import os
import redis
from redis import Redis
import json


class RedisClient:
    def __init__(self, redis_url: str, prefix: str = "paperpulse:"):
        self.redis_url = redis_url
        _redis: Redis = redis.from_url(self.redis_url, decode_responses=True)
        self.client = _redis
        self.prefix = prefix

    def _key(self, key: str) -> str:
        return f"{self.prefix}{key}"

    def ping(self) -> bool:
        try:
            return bool(self.client.ping())
        except redis.RedisError:
            return False

    def get_value(self, key: str) -> str | None:
        try:
            value = self.client.get(self._key(key))
            if value is not None:
                return str(value)
            return None

        except redis.RedisError:
            return None

    def set_value(self, key: str, value: str, ex: int | None = None, nx: bool = False) -> bool:
        key = self._key(key)
        try:
            return bool(self.client.set(key, value, ex=ex, nx=nx))

        except redis.RedisError:
            return False

    def delete_value(self, key: str) -> bool:
        try:
            return bool(self.client.delete(self._key(key)))
        except redis.RedisError:
            return False

    def get_json(self, key: str) -> dict | None:
        try:
            value = self.get_value(key)
            if value is not None:
                return json.loads(value)
            return None
        except redis.RedisError:
            return None
        except json.JSONDecodeError:
            return None

    def set_json(self, key: str, value: dict, ex: int | None = None) -> bool:
        try:
            return self.set_value(key, json.dumps(value), ex=ex)
        except redis.RedisError:
            return False
        except TypeError:
            return False
        except ValueError:
            return False

    def expire(self, key: str, ex: int) -> bool:
        try:
            return bool(self.client.expire(self._key(key), ex))
        except redis.RedisError:
            return False

    def ttl(self, key: str) -> int:
        try:
           
            return int(self.client.ttl(self._key(key)))     # ty:ignore[invalid-argument-type]
        except redis.RedisError:
            return -2

    def incr(self, key: str, amount: int = 1, ttl: int | None = None) -> int | None:
        try:
            
            result = int(self.client.incr(self._key(key), amount))      # ty:ignore[invalid-argument-type]
            if ttl is not None:
                self.expire(key, ttl)
            return result
        except redis.RedisError:
            return None


_client: RedisClient | None = None


def init_client() -> RedisClient:
    global _client
    if _client is None:
        try:
            _client = RedisClient(redis_url=str(os.getenv("REDIS_URL")))
        except Exception as e:
            raise RuntimeError(f"Failed to initialize Redis client: {e}")

        if not _client.ping():  # 确保连接可用
            _client = None
            raise RuntimeError("Failed to connect to Redis server")
    return _client


def get_client() -> RedisClient:
    if _client is None:
        raise RuntimeError(
            "Redis client not initialized. Call init_client() first.")
    return _client
