import unittest

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.routers.status import service_status
from app.routers.status import router as status_router
from app.version import APP_VERSION


class ServiceStatusTests(unittest.TestCase):
    def test_status_route_is_a_stable_client_handshake(self):
        app = FastAPI()
        app.include_router(status_router)
        response = TestClient(app).get("/status")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json(),
            {
                "status": "ok",
                "service": "paperpulse-backend",
                "version": APP_VERSION,
            },
        )

    def test_status_does_not_require_redis(self):
        self.assertEqual(service_status()["status"], "ok")


if __name__ == "__main__":
    unittest.main()
