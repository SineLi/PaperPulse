from fastapi import APIRouter
from utils.redis_client import get_client

router = APIRouter(prefix="/status", tags=["status"])

@router.get("/redis")
def redis_status():
    redis_client = get_client()
    if (redis_client and redis_client.ping()):
        return {"status": "ok"}
    return {"status": "error"}