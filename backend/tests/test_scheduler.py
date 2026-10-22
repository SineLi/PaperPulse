import sys
import threading
import types
import unittest
from unittest.mock import patch


class FakeScheduler:
    pass


class FakeCronTrigger:
    def __init__(self, **kwargs):
        self.kwargs = kwargs


apscheduler = types.ModuleType("apscheduler")
schedulers = types.ModuleType("apscheduler.schedulers")
blocking = types.ModuleType("apscheduler.schedulers.blocking")
background = types.ModuleType("apscheduler.schedulers.background")
triggers = types.ModuleType("apscheduler.triggers")
cron = types.ModuleType("apscheduler.triggers.cron")
blocking.BlockingScheduler = FakeScheduler
background.BackgroundScheduler = FakeScheduler
cron.CronTrigger = FakeCronTrigger
sys.modules.setdefault("apscheduler", apscheduler)
sys.modules.setdefault("apscheduler.schedulers", schedulers)
sys.modules.setdefault("apscheduler.schedulers.blocking", blocking)
sys.modules.setdefault("apscheduler.schedulers.background", background)
sys.modules.setdefault("apscheduler.triggers", triggers)
sys.modules.setdefault("apscheduler.triggers.cron", cron)

main_fetcher = types.ModuleType("utils.main_fetcher")
main_fetcher.run_enabled_fetchers = lambda **kwargs: None
article_services = types.ModuleType("services.article_services")
article_services.ArticleService = type("ArticleService", (), {})
llm_service = types.ModuleType("services.LLM_service")
llm_service.LLMService = type("LLMService", (), {})
sys.modules.setdefault("utils.main_fetcher", main_fetcher)
sys.modules.setdefault("services.article_services", article_services)
sys.modules.setdefault("services.LLM_service", llm_service)

import scheduler


class SchedulerCycleTests(unittest.TestCase):
    def test_skips_reentrant_cycle(self):
        scheduler._cycle_run_lock.acquire()
        try:
            with patch.object(scheduler, "_run_cycle_job") as run_cycle:
                scheduler.cycle_job()
            run_cycle.assert_not_called()
        finally:
            scheduler._cycle_run_lock.release()

    def test_cycle_waits_for_active_images_and_prevents_another_batch(self):
        scheduler._scheduler_work_lock.acquire()
        ran = threading.Event()
        worker = threading.Thread(target=scheduler.cycle_job)
        with patch.object(scheduler, "_run_cycle_job", side_effect=ran.set), patch.object(scheduler, "ArticleService") as service:
            worker.start()
            try:
                self.assertTrue(scheduler._cycle_requested.wait(timeout=1))
                self.assertFalse(ran.is_set())
                scheduler.image_cache_backfill_job()
                service.assert_not_called()
            finally:
                scheduler._scheduler_work_lock.release()
                worker.join(timeout=2)
        self.assertFalse(worker.is_alive())
        self.assertTrue(ran.is_set())
        self.assertFalse(scheduler._scheduler_work_lock.locked())
        self.assertFalse(scheduler._cycle_requested.is_set())

    def test_llm_initialization_failure_still_runs_fetchers(self):
        with patch.object(scheduler, "LLMService", side_effect=RuntimeError("missing_key")), patch.object(scheduler, "run_enabled_fetchers") as fetch:
            scheduler.cycle_job()
        fetch.assert_called_once_with(journal_timeout_secs=600)
        self.assertFalse(scheduler._cycle_requested.is_set())
        self.assertFalse(scheduler._scheduler_work_lock.locked())

    def test_cycle_exception_releases_priority_and_locks(self):
        with patch.object(scheduler, "_run_cycle_job", side_effect=ValueError("cycle_error")):
            with self.assertRaises(ValueError):
                scheduler.cycle_job()
        self.assertFalse(scheduler._cycle_requested.is_set())
        self.assertFalse(scheduler._cycle_run_lock.locked())
        self.assertFalse(scheduler._scheduler_work_lock.locked())

    def test_cycle_holds_shared_lock_for_full_execution(self):
        observed_states = []

        def observe_cycle():
            observed_states.append(scheduler._scheduler_work_lock.locked())

        with patch.object(scheduler, "_run_cycle_job", side_effect=observe_cycle):
            scheduler.cycle_job()

        self.assertEqual(observed_states, [True])
        self.assertFalse(scheduler._scheduler_work_lock.locked())

    def test_skips_image_backfill_while_scheduler_work_is_active(self):
        scheduler._scheduler_work_lock.acquire()
        try:
            with patch.object(scheduler, "ArticleService") as article_service:
                scheduler.image_cache_backfill_job()
            article_service.assert_not_called()
        finally:
            scheduler._scheduler_work_lock.release()

    def test_image_backfill_holds_shared_lock_for_full_execution(self):
        observed_states = []

        class FakeArticleService:
            async def cache_missing_article_images_async(self, **kwargs):
                observed_states.append(scheduler._scheduler_work_lock.locked())
                return {}

        with patch.object(scheduler, "ArticleService", FakeArticleService):
            scheduler.image_cache_backfill_job()

        self.assertEqual(observed_states, [True])
        self.assertFalse(scheduler._scheduler_work_lock.locked())


if __name__ == "__main__":
    unittest.main()
