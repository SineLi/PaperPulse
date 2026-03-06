from pydantic import BaseModel, Field, EmailStr

class RegisterRequest(BaseModel):
    username: str = Field(..., min_length=1)
    password: str = Field(..., min_length=8)
    email: EmailStr
    verification_code: str = Field(..., min_length=6, max_length=6)


class LoginRequest(BaseModel):
    username: str = Field(..., min_length=1)
    password: str = Field(..., min_length=8)

class SendCodeRequest(BaseModel):
    email: EmailStr