import json
import os
import hashlib
import hmac
from datetime import datetime, timedelta

import pytz
import redis
import secrets
from jose import JWTError, jwt

from utils.redis_client import get_client

ALGORITHM = "HS256"
ACCESS_TOKEN_TYPE = "access"
ACCESS_TOKEN_EXPIRE_SECONDS = 3600  # 1 hour
REFRESH_TOKEN_EXPIRE_SECONDS = 7 * 24 * 3600  # 7 days
JWT_SECRET = os.getenv("JWT_SECRET")


def _get_jwt_secret() -> str:
    if not JWT_SECRET:
        raise RuntimeError("JWT_SECRET is not configured")
    return JWT_SECRET


def _refresh_session_key(session_id: str) -> str:
    return f"refresh:{session_id}"


def create_access_token(user_id: int, session_id: str) -> str:
    expire = datetime.now(pytz.utc) + timedelta(seconds=ACCESS_TOKEN_EXPIRE_SECONDS)
    data = {
        "sub": str(user_id),
        "session_id": session_id,
        "type": ACCESS_TOKEN_TYPE,
        "exp": expire,
    }
    return jwt.encode(data, _get_jwt_secret(), algorithm=ALGORITHM)


def create_refresh_token(session_id: str) -> str:
    rand = secrets.token_urlsafe(32)
    return f"{session_id}.{rand}"


def parse_refresh_token(refresh_token: str) -> str:
    try:
        session_id, _ = refresh_token.split(".", 1)
    except ValueError as exc:
        raise JWTError("Invalid refresh token format") from exc

    if not session_id:
        raise JWTError("Invalid refresh token format")
    return session_id


def hash_refresh_token(refresh_token: str) -> str:
    return hashlib.sha256(refresh_token.encode("utf-8")).hexdigest()


def store_refresh_token(session_id: str, user_id: int, refresh_token: str) -> None:
    redis_client = get_client()
    hashed_token = hash_refresh_token(refresh_token)
    session_data = {
        "user_id": str(user_id),
        "token_hash": hashed_token,
    }
    stored = redis_client.set_json(
        _refresh_session_key(session_id),
        session_data,
        ex=int(REFRESH_TOKEN_EXPIRE_SECONDS),
    )
    if not stored:
        raise RuntimeError("Failed to persist refresh token")


def _build_refresh_session_data(user_id: int | str, refresh_token: str) -> str:
    return json.dumps(
        {
            "user_id": str(user_id),
            "token_hash": hash_refresh_token(refresh_token),
        }
    )


def get_refresh_session(session_id: str) -> dict | None:
    redis_client = get_client()
    try:
        raw_value = redis_client.get_value_or_raise(_refresh_session_key(session_id))
    except RuntimeError as exc:
        raise RuntimeError("Failed to load refresh session") from exc

    if raw_value is None:
        return None

    try:
        session = json.loads(raw_value)
    except json.JSONDecodeError as exc:
        raise JWTError("Invalid refresh session") from exc

    if not isinstance(session, dict):
        raise JWTError("Invalid refresh session")
    return session


def revoke_refresh_session(session_id: str) -> bool:
    redis_client = get_client()
    try:
        return redis_client.delete_value_or_raise(_refresh_session_key(session_id))
    except RuntimeError as exc:
        raise RuntimeError("Failed to revoke refresh session") from exc


def verify_refresh_token(refresh_token: str) -> tuple[int, str]:
    session_id = parse_refresh_token(refresh_token)
    session = get_refresh_session(session_id)
    if session is None:
        raise JWTError("Refresh session not found")

    stored_hashed_token = session.get("token_hash")
    user_id = session.get("user_id")
    if not stored_hashed_token or not user_id:
        raise JWTError("Invalid refresh session")

    if not hmac.compare_digest(hash_refresh_token(refresh_token), str(stored_hashed_token)):
        raise JWTError("Invalid refresh token")

    return int(user_id), session_id


def consume_refresh_token(refresh_token: str, next_refresh_token: str | None = None) -> tuple[int, str]:
    session_id = parse_refresh_token(refresh_token)
    redis_client = get_client()
    redis_key = redis_client._key(_refresh_session_key(session_id))

    try:
        with redis_client.client.pipeline() as pipe:
            pipe.watch(redis_key)
            raw_value = pipe.get(redis_key)
            if raw_value is None:
                raise JWTError("Refresh session not found")

            try:
                session = json.loads(raw_value)  # ty:ignore[invalid-argument-type]
            except json.JSONDecodeError as exc:
                raise JWTError("Invalid refresh session") from exc

            if not isinstance(session, dict):
                raise JWTError("Invalid refresh session")

            stored_hashed_token = session.get("token_hash")
            user_id = session.get("user_id")
            if not stored_hashed_token or not user_id:
                raise JWTError("Invalid refresh session")

            if not hmac.compare_digest(hash_refresh_token(refresh_token), str(stored_hashed_token)):
                raise JWTError("Invalid refresh token")

            pipe.multi()
            if next_refresh_token is None:
                pipe.delete(redis_key)
            else:
                pipe.set(
                    redis_key,
                    _build_refresh_session_data(user_id, next_refresh_token),
                    ex=int(REFRESH_TOKEN_EXPIRE_SECONDS),
                )
            result = pipe.execute()
    except redis.WatchError as exc:
        raise JWTError("Refresh token already used") from exc
    except RuntimeError:
        raise
    except JWTError:
        raise
    except Exception as exc:
        raise RuntimeError("Failed to consume refresh token") from exc

    if not result:
        raise JWTError("Refresh token already used")

    first_result = result[0]
    if isinstance(first_result, int) and first_result <= 0:
        raise JWTError("Refresh token already used")

    return int(user_id), session_id


def decode_access_token(token: str) -> dict:
    payload = jwt.decode(token, _get_jwt_secret(), algorithms=[ALGORITHM])
    if payload.get("type") != ACCESS_TOKEN_TYPE:
        raise JWTError("Invalid token type")

    if not payload.get("sub") or not payload.get("session_id"):
        raise JWTError("Invalid token payload")

    return payload
