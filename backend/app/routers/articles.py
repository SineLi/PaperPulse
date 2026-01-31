from fastapi import APIRouter, Depends, HTTPException
from app.core.auth_dependency import get_current_user_id

from app.schemas.articles import ItemJsonsResponse, ItemIDs

from services.user_services import UserService
user_service = UserService()


router = APIRouter(prefix="/articles", tags=["articles"])

@router.get("/feed", response_model=ItemJsonsResponse)
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
    return ItemJsonsResponse(
        items=articles,
        limit=limit,
        offset=offset,
    )

@router.post("/read")
def mark_articles_read(
    request: ItemIDs,
    user_id: int = Depends(get_current_user_id),
):
    try:
        user_service.mark_as_read(user_id, request.items)
        return {"success": True}
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

@router.post("/{article_id}/favorite")
def add_favorite(
    article_id: int,
    user_id: int = Depends(get_current_user_id),
):
    try:
        success = user_service.add_favorite(user_id, article_id)
        if not success:
            raise HTTPException(status_code=409, detail="Already favorited")
        return {"success": True}
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

@router.delete("/{article_id}/favorite")
def del_favorite(
    article_id: int,
    user_id: int = Depends(get_current_user_id),
):
    success = user_service.del_favorite(user_id, article_id)
    if not success:
        raise HTTPException(status_code=404, detail="Favorite not found")
    return {"success": True}

@router.get("/favorites", response_model=ItemIDs)
def get_favorite_articles(
    user_id: int = Depends(get_current_user_id),
):
    article_ids = user_service.get_favorite_articles(
        user_id=user_id,
    )
    return ItemIDs(
        items=article_ids,
    )

@router.get("/read", response_model=ItemIDs)
def get_read_articles(
    user_id: int = Depends(get_current_user_id),
):
    article_ids = user_service.get_read_articles(
        user_id=user_id,
    )
    return ItemIDs(
        items=article_ids,
    )

@router.get("/{article_id}")
def get_article_detail(
    article_id: int,
    user_id: int = Depends(get_current_user_id),
):
    article = user_service.get_article_by_id(
        user_id=user_id,
        article_id=article_id,
    )
    if not article:
        raise HTTPException(status_code=404, detail="Article not found")
    return article