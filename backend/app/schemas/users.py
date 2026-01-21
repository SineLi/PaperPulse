from pydantic import BaseModel, Field

class UserInfoResponse(BaseModel):
    id: int = Field(..., description="用户ID")
    username: str = Field(..., description="用户名")
    email: str = Field(..., description="用户邮箱")
