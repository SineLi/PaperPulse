from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import auth, journals, users, articles

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 允许所有来源，仅用于测试环境
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(journals.router)
app.include_router(users.router)
app.include_router(articles.router)

@app.get("/")
def root():
    return {"status": "ok"}
