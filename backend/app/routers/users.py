from fastapi import APIRouter, HTTPException
from app.core.security import create_access_token

from app.schemas import LoginRequest, RegisterRequest

from services.user_services import UserService
user_service = UserService()

router = APIRouter(prefix="/users", tags=["users"])

@router.post("/login")
def login(req: LoginRequest):
    try:
        user = user_service.login(req.username, req.password)
        access_token = create_access_token({"sub": str(user["id"])})
        return {"access_token": access_token, "token_type": "bearer"}
    except ValueError as e:
        raise HTTPException(status_code=401, detail=str(e))
    
@router.post("/register")
def register(req: RegisterRequest):
    try:
        user = user_service.register(req.username, req.email, req.password)
        access_token = create_access_token({"sub": str(user["id"])})
        return {"access_token": access_token, "token_type": "bearer"}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))