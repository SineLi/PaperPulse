from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass, field
from typing import Any, Literal, Protocol, Sequence

from utils.logging_utils import log_event

logger = logging.getLogger(__name__)

TaskType = Literal["article_fetch", "image_cache"]


class DetailFetcher(Protocol):
    journal_name: str

    async def fetch_detail_at_index(self, papers_to_fetch: list[dict], idx: int) -> None: ...


class ImageCacheService(Protocol):
    def cache_image(self, url: str, article_id: int) -> dict[str, Any]: ...


@dataclass
class TaskResult:
    """保存单个任务的执行结果，供业务层在整批结束后统一处理。"""

    success: bool
    task_type: TaskType
    data: dict[str, Any] | None = None
    error: str | None = None
    cancelled: bool = False


@dataclass
class QueueTask:
    """所有可执行任务的公共状态，result 由执行器完成或取消时回填。"""

    task_type: TaskType = field(init=False)
    result: TaskResult | None = field(default=None, init=False)


@dataclass
class ArticleFetchTask(QueueTask):
    """文章详情抓取任务。

    任务保留原文章批次和下标，worker 会直接更新 collect() 返回的文章字典。
    执行结束后无需合并副本，所属 fetcher 可以直接 finalize() 已完成的文章。
    """

    fetcher: DetailFetcher
    papers_to_fetch: list[dict]
    index: int
    task_type: TaskType = field(default="article_fetch", init=False)

    @property
    def article(self) -> dict:
        return self.papers_to_fetch[self.index]

    @property
    def journal_name(self) -> str | None:
        return getattr(self.fetcher, "journal_name", None)

    @property
    def url(self) -> str | None:
        return self.article.get("link")


@dataclass
class ImageCacheTask(QueueTask):
    """图片下载及本地缓存任务，article_id 用于缓存归属和数据库状态更新。"""

    article_id: int
    url: str
    task_type: TaskType = field(default="image_cache", init=False)


class TaskExecutor:
    """使用固定数量 worker 执行单轮内存任务。

    任务容器使用局部的 asyncio.Queue，执行器负责消费、限流、结果回填和 worker
    清理，不负责持久化、业务重试或数据库写入。不同业务可以创建独立执行器，
    分别设置文章详情抓取和图片缓存的并发上限。
    """

    def __init__(self, max_workers: int = 8, image_service: ImageCacheService | None = None):
        if max_workers <= 0:
            raise ValueError("max_workers must be positive")
        self.max_workers = max_workers
        self.image_service = image_service

    async def run(self, tasks: Sequence[QueueTask]) -> dict[str, int]:
        """等待一批任务全部结束，并将结果写回各任务的 result 字段。"""

        task_list = list(tasks)
        unsupported_task = next(
            (
                task
                for task in task_list
                if not isinstance(task, (ArticleFetchTask, ImageCacheTask))
            ),
            None,
        )
        if unsupported_task is not None:
            raise TypeError(
                f"Unsupported queue task type: {type(unsupported_task).__name__}"
            )

        stats = {
            "queued": len(task_list),
            "succeeded": 0,
            "failed": 0,
            "article_fetch": 0,
            "image_cache": 0,
        }
        if not task_list:
            return stats

        queue: asyncio.Queue[QueueTask] = asyncio.Queue()
        for task in task_list:
            task.result = None
            queue.put_nowait(task)

        # worker 数量固定，因此任务来源再多也不会扩大本轮实际并发。
        workers = [
            asyncio.create_task(self._worker(queue, stats))
            for _ in range(min(self.max_workers, len(task_list)))
        ]
        try:
            await queue.join()
        finally:
            # 取消时同步收口 worker；图片 worker 会先等其同步下载线程结束再退出。
            for worker in workers:
                worker.cancel()
            await asyncio.gather(*workers, return_exceptions=True)
            self._mark_unfinished_tasks_cancelled(task_list, stats)

        log_event(logger, logging.INFO, "task_executor_completed", **stats)
        return stats

    async def _worker(self, queue: asyncio.Queue[QueueTask], stats: dict[str, int]) -> None:
        while True:
            task = await queue.get()
            try:
                await self._run_task(task, stats)
            finally:
                # 无论任务成功、失败还是被取消，都必须释放 join() 的计数。
                queue.task_done()

    async def _run_task(self, task: QueueTask, stats: dict[str, int]) -> None:
        try:
            if isinstance(task, ArticleFetchTask):
                await task.fetcher.fetch_detail_at_index(task.papers_to_fetch, task.index)
                status = task.article.get("_fetch_status", "unknown")
                data = {
                    "journal": task.journal_name,
                    "url": task.url,
                    "status": status,
                }
                if status != "ok":
                    self._record_result(
                        task,
                        stats,
                        success=False,
                        data=data,
                        error=task.article.get("_fetch_fail_reason") or f"fetch_status:{status}",
                    )
                    return
            elif isinstance(task, ImageCacheTask):
                if self.image_service is None:
                    raise RuntimeError("image_service is required for image cache tasks")

                cache_result, image_error, cancelled_while_waiting = await self._cache_image(task)
                if image_error is not None:
                    self._record_result(task, stats, success=False, error=str(image_error))
                    logger.error(
                        "event=task_executor_image_cache_exception article_id=%s detail=%s",
                        task.article_id,
                        image_error,
                    )
                    if cancelled_while_waiting:
                        raise asyncio.CancelledError
                    return

                if cache_result is None:
                    raise RuntimeError("image cache task returned no result")
                data = dict(cache_result)
                if not cache_result.get("path"):
                    # ImageService 用返回值表达可预期失败，需要显式转换成失败结果。
                    self._record_result(
                        task,
                        stats,
                        success=False,
                        data=data,
                        error=cache_result.get("error") or f"cache_status:{cache_result.get('status', 'unknown')}",
                    )
                    log_event(
                        logger,
                        logging.WARNING,
                        "task_executor_image_cache_failed",
                        article_id=task.article_id,
                        status=cache_result.get("status"),
                        error=cache_result.get("error"),
                    )
                    if cancelled_while_waiting:
                        raise asyncio.CancelledError
                    return
            else:
                raise TypeError(f"Unsupported queue task type: {type(task).__name__}")
        except Exception as exc:
            # 单个任务失败不终止整批任务，错误留在 result 中供业务层汇总。
            self._record_result(task, stats, success=False, error=str(exc))
            logger.exception("event=task_executor_task_failed task_type=%s detail=%s", task.task_type, exc)
            return

        self._record_result(task, stats, success=True, data=data)
        if isinstance(task, ImageCacheTask) and cancelled_while_waiting:
            raise asyncio.CancelledError

    async def _cache_image(
        self,
        task: ImageCacheTask,
    ) -> tuple[dict[str, Any] | None, Exception | None, bool]:
        """等待同步下载线程结束，避免取消协程后把仍在运行的任务误标为 cancelled。"""

        if self.image_service is None:
            raise RuntimeError("image_service is required for image cache tasks")

        work = asyncio.create_task(
            asyncio.to_thread(self.image_service.cache_image, task.url, task.article_id)
        )
        try:
            return await asyncio.shield(work), None, False
        except asyncio.CancelledError:
            # shield 保留底层线程任务；收到取消后仍必须等待其真实结果再结束 worker。
            try:
                return await asyncio.shield(work), None, True
            except Exception as exc:
                return None, exc, True
        except Exception as exc:
            return None, exc, False

    def _record_result(
        self,
        task: QueueTask,
        stats: dict[str, int],
        *,
        success: bool,
        data: dict[str, Any] | None = None,
        error: str | None = None,
        cancelled: bool = False,
    ) -> None:
        task.result = TaskResult(
            success=success,
            task_type=task.task_type,
            data=data,
            error=error,
            cancelled=cancelled,
        )
        stats["succeeded" if success else "failed"] += 1
        stats[task.task_type] += 1

    def _mark_unfinished_tasks_cancelled(
        self,
        tasks: Sequence[QueueTask],
        stats: dict[str, int],
    ) -> None:
        for task in tasks:
            if task.result is not None:
                continue
            if isinstance(task, ArticleFetchTask):
                task.article.setdefault("_fetch_status", "error")
                task.article.setdefault("_fetch_fail_reason", "task_cancelled")
            self._record_result(
                task,
                stats,
                success=False,
                error="task_cancelled",
                cancelled=True,
            )
