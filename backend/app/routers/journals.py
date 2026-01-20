from fastapi import APIRouter, Depends, HTTPException
from app.core.auth_dependency import get_current_user_id

from services.user_services import UserService
user_service = UserService()

router = APIRouter(prefix="/journals", tags=["journals"])

@router.post("/{journal_id}/follow")
def follow_journal(
    journal_id: int,
    user_id: int = Depends(get_current_user_id),
):
    success = user_service.follow_journal(user_id, journal_id)
    if not success:
        raise HTTPException(status_code=409, detail="Already followed")
    return {"success": True}

@router.delete("/{journal_id}/follow")
def unfollow_journal(
    journal_id: int,
    user_id: int = Depends(get_current_user_id),
):
    success = user_service.unfollow_journal(user_id, journal_id)
    if not success:
        raise HTTPException(status_code=404, detail="Subscription not found")
    return {"success": True}

@router.get("/available")
def get_available_journals(
    limit: int = 50,
    offset: int = 0,
    user_id: int = Depends(get_current_user_id),
):
    journals = user_service.get_available_journals(
        limit=limit,
        offset=offset,
    )
    return {
        "items": journals,
        "limit": limit,
        "offset": offset,
    }

