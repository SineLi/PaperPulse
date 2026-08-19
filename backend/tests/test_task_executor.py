import asyncio
import threading
import unittest

from utils.task_executor import ArticleFetchTask, ImageCacheTask, TaskExecutor


class FakeFetcher:
    def __init__(self, statuses: list[str], delay: float = 0):
        self.journal_name = "Test Journal"
        self.statuses = statuses
        self.delay = delay
        self.active = 0
        self.max_active = 0

    async def fetch_detail_at_index(self, papers_to_fetch: list[dict], idx: int) -> None:
        self.active += 1
        self.max_active = max(self.max_active, self.active)
        try:
            if self.delay:
                await asyncio.sleep(self.delay)
            papers_to_fetch[idx]["_fetch_status"] = self.statuses[idx]
            if self.statuses[idx] != "ok":
                papers_to_fetch[idx]["_fetch_fail_reason"] = "fetch_failed"
        finally:
            self.active -= 1


class FakeImageService:
    def __init__(self, succeeds: bool):
        self.succeeds = succeeds

    def cache_image(self, url: str, article_id: int) -> dict:
        if self.succeeds:
            return {"url": url, "path": f"{article_id}.webp", "status": "cached", "error": None}
        return {"url": url, "path": None, "status": "failed", "error": "download_failed"}


class BlockingImageService:
    def __init__(self):
        self.started = threading.Event()
        self.release = threading.Event()

    def cache_image(self, url: str, article_id: int) -> dict:
        self.started.set()
        self.release.wait()
        return {"url": url, "path": f"{article_id}.webp", "status": "cached", "error": None}


class TaskExecutorTests(unittest.IsolatedAsyncioTestCase):
    async def test_limits_article_concurrency(self):
        papers = [{"link": f"https://example.com/{index}"} for index in range(6)]
        fetcher = FakeFetcher(["ok"] * len(papers), delay=0.01)
        tasks = [ArticleFetchTask(fetcher, papers, index) for index in range(len(papers))]

        stats = await TaskExecutor(max_workers=2).run(tasks)

        self.assertEqual(fetcher.max_active, 2)
        self.assertEqual(stats["succeeded"], 6)
        self.assertTrue(all(task.result and task.result.success for task in tasks))

    async def test_treats_non_ok_article_status_as_failure(self):
        papers = [{"link": "ok"}, {"link": "blocked"}, {"link": "unknown"}]
        fetcher = FakeFetcher(["ok", "blocked", "unknown"])
        tasks = [ArticleFetchTask(fetcher, papers, index) for index in range(len(papers))]

        stats = await TaskExecutor(max_workers=3).run(tasks)

        self.assertEqual(stats["succeeded"], 1)
        self.assertEqual(stats["failed"], 2)
        self.assertTrue(tasks[0].result and tasks[0].result.success)
        self.assertFalse(tasks[1].result and tasks[1].result.success)

    async def test_uses_image_cache_return_value_as_task_result(self):
        success_task = ImageCacheTask(article_id=1, url="https://example.com/1.png")
        failed_task = ImageCacheTask(article_id=2, url="https://example.com/2.png")

        success_stats = await TaskExecutor(
            max_workers=1,
            image_service=FakeImageService(succeeds=True),
        ).run([success_task])
        failed_stats = await TaskExecutor(
            max_workers=1,
            image_service=FakeImageService(succeeds=False),
        ).run([failed_task])

        self.assertEqual(success_stats["succeeded"], 1)
        self.assertTrue(success_task.result and success_task.result.success)
        self.assertEqual(failed_stats["failed"], 1)
        self.assertEqual(failed_task.result.error, "download_failed")

    async def test_cancellation_waits_for_image_thread_and_records_result(self):
        service = BlockingImageService()
        task = ImageCacheTask(article_id=1, url="https://example.com/1.png")
        runner = asyncio.create_task(TaskExecutor(max_workers=1, image_service=service).run([task]))

        await asyncio.to_thread(service.started.wait)
        runner.cancel()
        await asyncio.sleep(0)
        self.assertFalse(runner.done())

        service.release.set()
        with self.assertRaises(asyncio.CancelledError):
            await runner

        self.assertTrue(task.result and task.result.success)
        self.assertFalse(task.result.cancelled)

    async def test_soft_timeout_keeps_image_task_running_until_real_result(self):
        service = BlockingImageService()
        task = ImageCacheTask(article_id=1, url="https://example.com/1.png")
        execution = asyncio.create_task(TaskExecutor(max_workers=1, image_service=service).run([task]))

        await asyncio.to_thread(service.started.wait)
        with self.assertRaises(asyncio.TimeoutError):
            await asyncio.wait_for(asyncio.shield(execution), timeout=0.01)

        self.assertFalse(execution.done())
        self.assertIsNone(task.result)
        service.release.set()
        await execution

        self.assertTrue(task.result and task.result.success)
        self.assertFalse(task.result.cancelled)

    async def test_marks_unfinished_tasks_cancelled(self):
        papers = [{"link": f"https://example.com/{index}"} for index in range(3)]
        fetcher = FakeFetcher(["ok"] * len(papers), delay=1)
        tasks = [ArticleFetchTask(fetcher, papers, index) for index in range(len(papers))]

        with self.assertRaises(asyncio.TimeoutError):
            await asyncio.wait_for(TaskExecutor(max_workers=1).run(tasks), timeout=0.01)

        self.assertTrue(all(task.result and task.result.cancelled for task in tasks))
        self.assertTrue(all(paper["_fetch_fail_reason"] == "task_cancelled" for paper in papers))


if __name__ == "__main__":
    unittest.main()
