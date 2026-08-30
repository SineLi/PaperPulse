from fastapi import APIRouter

from app.version import APP_VERSION

router = APIRouter(prefix="/status", tags=["status"])


@router.get("")
def service_status():
    """Lightweight, dependency-free handshake for PaperPulse clients."""
    return {
        "status": "ok",
        "service": "paperpulse-backend",
        "version": APP_VERSION,
    }


@router.get("/redis")
def redis_status():
    from utils.redis_client import get_client

    redis_client = get_client()
    if (redis_client and redis_client.ping()):
        return {"status": "ok"}
    return {"status": "error"}
