from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routers import auth, journals, users, articles, status

from fastapi.responses import FileResponse

import os

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Redis client is already initialised by run.py (check_redis).
    # Nothing else to set up; just yield for the app lifetime.
    yield

app = FastAPI(
    lifespan=lifespan,
    docs_url=None,
    redoc_url=None,
    openapi_url=None 
    )

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(users.router)
app.include_router(journals.router)
app.include_router(articles.router)
app.include_router(status.router)

@app.get("/")
def root():
    return {"status": "ok"}

@app.get("/test", response_class=FileResponse)
def test_page():
    return os.path.join(os.path.dirname(__file__), "test.html")