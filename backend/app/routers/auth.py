import secrets
import time

from fastapi import APIRouter, Depends, HTTPException, status
from jose.exceptions import JWTError

from app.core.auth_dependency import get_current_token_payload
from app.core.security import (
    consume_refresh_token,
    create_access_token,
    create_refresh_token,
    parse_refresh_token,
    revoke_refresh_session,
    store_refresh_token,
)
from app.schemas.auth import LoginRequest, RefreshRequest, RegisterRequest, SendCodeRequest, TokenResponse
from services.mail_service import send_verification_email
from services.user_services import UserService
from utils.redis_client import get_client

user_service = UserService()

router = APIRouter(prefix="/auth", tags=["auth"])

VERIFICATION_CODE_TTL = 30 * 60
VERIFICATION_FAIL_LIMIT = 5
VERIFICATION_SEND_LIMIT_24H = 5
VERIFICATION_MIN_INTERVAL = 60


def _verification_service_unavailable() -> HTTPException:
    return HTTPException(status_code=503, detail="Verification service unavailable")


def _normalize_retry_after(ttl: int) -> int | None:
    return ttl if ttl >= 0 else None


def _issue_tokens(user_id: int, session_id: str | None = None) -> TokenResponse:
    if session_id is None:
        session_id = secrets.token_urlsafe(32)
    access_token = create_access_token(user_id, session_id)
    refresh_token = create_refresh_token(session_id)
    store_refresh_token(session_id, user_id, refresh_token)
    return TokenResponse(access_token=access_token, refresh_token=refresh_token)


@router.post("/login", response_model=TokenResponse)
def login(req: LoginRequest):
    try:
        user = user_service.login(req.username.strip(), req.password)
        return _issue_tokens(user["id"])
    except ValueError as e:
        raise HTTPException(status_code=401, detail=str(e))
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail="Authentication service unavailable") from exc


@router.post("/refresh", response_model=TokenResponse)
def refresh_token(req: RefreshRequest):
    try:
        session_id = parse_refresh_token(req.refresh_token)
        next_refresh_token = create_refresh_token(session_id)
        user_id, _ = consume_refresh_token(req.refresh_token, next_refresh_token=next_refresh_token)
        access_token = create_access_token(user_id, session_id)
        return TokenResponse(access_token=access_token, refresh_token=next_refresh_token)
    except JWTError as exc:
        raise HTTPException(status_code=401, detail="Invalid refresh token") from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail="Authentication service unavailable") from exc


@router.post("/logout")
def logout(payload: dict = Depends(get_current_token_payload)):
    session_id = payload.get("session_id")
    if session_id is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token payload")

    try:
        revoke_refresh_session(session_id)
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail="Authentication service unavailable") from exc

    return {"message": "Logged out"}


@router.post("/register", response_model=TokenResponse)
def register(req: RegisterRequest):
    redis_client = get_client()

    username = req.username.strip()
    email = req.email.lower().strip()
    code_key = f"vr_code:{email}"
    fail_key = f"vr_fail:{email}"

    try:
        stored_code = redis_client.get_value_or_raise(code_key)
    except RuntimeError as exc:
        raise _verification_service_unavailable() from exc

    if stored_code is None:
        raise HTTPException(status_code=400, detail="Verification code expired or not found")

    if stored_code != req.verification_code:
        try:
            fail_count = redis_client.incr_or_raise(fail_key, ttl=VERIFICATION_CODE_TTL)
        except RuntimeError as exc:
            raise _verification_service_unavailable() from exc

        if fail_count >= VERIFICATION_FAIL_LIMIT:
            try:
                retry_after = _normalize_retry_after(redis_client.ttl_or_raise(fail_key))
            except RuntimeError as exc:
                raise _verification_service_unavailable() from exc
            raise HTTPException(status_code=429, detail={"msg": "Too many failed attempts", "retry_after": retry_after})
        raise HTTPException(status_code=400, detail="Invalid verification code")

    try:
        user = user_service.register(username, email, req.password)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    redis_client.delete_value(code_key)
    redis_client.delete_value(fail_key)

    try:
        return _issue_tokens(user["id"])
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail="Authentication service unavailable") from exc


@router.post("/send_verification_code")
def send_verification_code(req: SendCodeRequest):
    redis_client = get_client()

    email = req.email.lower().strip()
    send_count_key = f"vr_send_count:{email}"
    last_key = f"vr_send_last:{email}"
    code_key = f"vr_code:{email}"
    fail_key = f"vr_fail:{email}"
    now = int(time.time())

    try:
        last_ts = redis_client.get_value_or_raise(last_key)
        if last_ts is not None:
            try:
                elapsed = now - int(last_ts)
                if elapsed < VERIFICATION_MIN_INTERVAL:
                    raise HTTPException(
                        status_code=429,
                        detail={"msg": "Too many requests", "retry_after": VERIFICATION_MIN_INTERVAL - elapsed},
                    )
            except ValueError:
                pass

        current_send_count = redis_client.get_value_or_raise(send_count_key)
        if current_send_count is not None:
            try:
                current_send_count_value = int(current_send_count)
            except ValueError as exc:
                raise RuntimeError("Invalid verification counter state") from exc
        else:
            current_send_count_value = 0

        if current_send_count_value >= VERIFICATION_SEND_LIMIT_24H:
            retry_after = _normalize_retry_after(redis_client.ttl_or_raise(send_count_key))
            raise HTTPException(status_code=429, detail={"msg": "Daily limit reached", "retry_after": retry_after})

        send_count = redis_client.incr_or_raise(send_count_key, ttl=24 * 3600)
        if send_count > VERIFICATION_SEND_LIMIT_24H:
            redis_client.incr_or_raise(send_count_key, amount=-1)
            retry_after = _normalize_retry_after(redis_client.ttl_or_raise(send_count_key))
            raise HTTPException(status_code=429, detail={"msg": "Daily limit reached", "retry_after": retry_after})

        code = f"{secrets.randbelow(900000) + 100000}"
        redis_client.set_value_or_raise(code_key, code, ex=VERIFICATION_CODE_TTL)
        redis_client.set_value_or_raise(last_key, str(now), ex=VERIFICATION_MIN_INTERVAL)
    except HTTPException:
        raise
    except RuntimeError as exc:
        raise _verification_service_unavailable() from exc

    try:
        send_verification_email(email, code)
    except RuntimeError as exc:
        redis_client.delete_value(code_key)
        redis_client.delete_value(last_key)
        redis_client.incr(send_count_key, amount=-1)
        raise HTTPException(status_code=503, detail="Verification email delivery failed") from exc

    redis_client.delete_value(fail_key)

    return {"message": "Verification code sent to email"}
