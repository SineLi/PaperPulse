from fastapi import APIRouter, Depends, HTTPException
from app.core.auth_dependency import get_current_user_id

from app.schemas.users import UserInfoResponse
from app.schemas.articles import ItemIDs

from services.user_services import UserService
user_service = UserService()

router = APIRouter(prefix="/users", tags=["users"])

@router.get("/me", response_model=UserInfoResponse)
def get_current_user(
    user_id: int = Depends(get_current_user_id),
):
    user = user_service.get_user_by_id(user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return UserInfoResponse(**user)

@router.get("/me/journals", response_model=ItemIDs)
def get_followed_journals(
    user_id: int = Depends(get_current_user_id),
):
    journal_ids = user_service.get_followed_journals(
        user_id=user_id,
    )
    return ItemIDs(
        items=journal_ids,
    )