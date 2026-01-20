from fastapi import APIRouter, Depends, HTTPException
from app.core.auth_dependency import get_current_user_id

from services.user_services import UserService
user_service = UserService()


router = APIRouter(prefix="/articles", tags=["articles"])

@router.get("/feed")
def get_feed(
    limit: int = 50,
    offset: int = 0,
    user_id: int = Depends(get_current_user_id),
):
    articles = user_service.get_articles_feed(
        user_id=user_id,
        limit=limit,
        offset=offset,
    )
    return {
        "items": articles,
        "limit": limit,
        "offset": offset,
    }

@router.post("/read")
def mark_articles_read(
    article_ids: list[int],
    user_id: int = Depends(get_current_user_id),
):
    user_service.mark_as_read(user_id, article_ids)
    return {"success": True}

@router.post("/{article_id}/favorite")
def add_favorite(
    article_id: int,
    user_id: int = Depends(get_current_user_id),
):
    success = user_service.add_favorite(user_id, article_id)
    if not success:
        raise HTTPException(status_code=409, detail="Already favorited")
    return {"success": True}

@router.delete("/{article_id}/favorite")
def del_favorite(
    article_id: int,
    user_id: int = Depends(get_current_user_id),
):
    success = user_service.del_favorite(user_id, article_id)
    if not success:
        raise HTTPException(status_code=404, detail="Favorite not found")
    return {"success": True}

@router.get("/favorites")
def get_favorite_articles(
    limit: int = 50,
    offset: int = 0,
    user_id: int = Depends(get_current_user_id),
):
    article_ids = user_service.get_favorite_articles(
        user_id=user_id,
    )
    return article_ids