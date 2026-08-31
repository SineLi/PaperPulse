import sys
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
        scheduler._scheduler_work_lock.acquire()
        try:
            with patch.object(scheduler, "_run_cycle_job") as run_cycle:
                scheduler.cycle_job()
            run_cycle.assert_not_called()
        finally:
            scheduler._scheduler_work_lock.release()

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
