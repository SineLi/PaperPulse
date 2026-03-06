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
            return self._incr_value(key, amount=amount, ttl=ttl)
        except redis.RedisError:
            return None

    def get_value_or_raise(self, key: str) -> str | None:
        try:
            value = self.client.get(self._key(key))
            if value is not None:
                return str(value)
            return None
        except redis.RedisError as exc:
            raise RuntimeError("Failed to read from Redis") from exc

    def set_value_or_raise(self, key: str, value: str, ex: int | None = None, nx: bool = False) -> bool:
        try:
            key = self._key(key)
            return bool(self.client.set(key, value, ex=ex, nx=nx))
        except redis.RedisError as exc:
            raise RuntimeError("Failed to write to Redis") from exc

    def delete_value_or_raise(self, key: str) -> bool:
        try:
            return bool(self.client.delete(self._key(key)))
        except redis.RedisError as exc:
            raise RuntimeError("Failed to delete from Redis") from exc

    def ttl_or_raise(self, key: str) -> int:
        try:
            return int(self.client.ttl(self._key(key)))     # ty:ignore[invalid-argument-type]
        except redis.RedisError as exc:
            raise RuntimeError("Failed to read TTL from Redis") from exc

    def incr_or_raise(self, key: str, amount: int = 1, ttl: int | None = None) -> int:
        try:
            return self._incr_value(key, amount=amount, ttl=ttl)
        except redis.RedisError as exc:
            raise RuntimeError("Failed to increment Redis counter") from exc

    def _incr_value(self, key: str, amount: int = 1, ttl: int | None = None) -> int:
        redis_key = self._key(key)
        if ttl is None:
            return int(self.client.incr(redis_key, amount))      # ty:ignore[invalid-argument-type]

        # Keep the original TTL once the counter is created.
        result = self.client.eval(
            """
            local current = redis.call('INCRBY', KEYS[1], ARGV[1])
            if redis.call('TTL', KEYS[1]) == -1 then
                redis.call('EXPIRE', KEYS[1], tonumber(ARGV[2]))
            end
            return current
            """,
            1,
            redis_key,
            amount,
            ttl,
        )
        return int(result)  # ty:ignore[invalid-argument-type]


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
