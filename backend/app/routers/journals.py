from fastapi import APIRouter, Depends, HTTPException
from app.core.auth_dependency import get_current_user_id

from app.schemas.articles import ItemJsonsResponse, ItemIDs

from services.user_services import UserService
user_service = UserService()

router = APIRouter(prefix="/journals", tags=["journals"])


@router.get("/status")
def get_journal_catalog_status(
    user_id: int = Depends(get_current_user_id),
):
    return user_service.get_journal_catalog_status()


@router.get("/")
def get_available_journals(
    limit: int = 50,
    offset: int = 0,
    user_id: int = Depends(get_current_user_id),
):
    journals = user_service.get_available_journals(
        limit=limit,
        offset=offset,
    )
    return ItemJsonsResponse(
        items=journals,
        limit=limit,
        offset=offset,
    )

@router.post("/{journal_id}/follow")
def follow_journal(
    journal_id: int,
    user_id: int = Depends(get_current_user_id),
):
    try:
        success = user_service.follow_journal(user_id, journal_id)
        if not success:
            raise HTTPException(status_code=409, detail="Already followed")
        return {"success": True}
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

@router.delete("/{journal_id}/follow")
def unfollow_journal(
    journal_id: int,
    user_id: int = Depends(get_current_user_id),
):
    success = user_service.unfollow_journal(user_id, journal_id)
    if not success:
        raise HTTPException(status_code=404, detail="Subscription not found")
    return {"success": True}

