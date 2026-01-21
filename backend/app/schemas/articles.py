from pydantic import BaseModel, Field
from typing import Optional

class ItemJsonsResponse(BaseModel):
    items: list[dict] = Field(..., description="文章列表")
    limit: int = Field(..., description="每页限制数量")
    offset: int = Field(..., description="偏移量")

class ItemIDs(BaseModel):
    items: list[int] = Field(..., description="文章id列表")
    limit: Optional[int] = Field(None, description="每页限制数量")
    offset: Optional[int] = Field(None, description="偏移量")