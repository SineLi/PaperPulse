from contextlib import asynccontextmanager
from pathlib import Path
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from app.routers import auth, journals, users, articles, status

from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

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
class CachedStaticFiles(StaticFiles):
    def file_response(self, full_path, stat_result, scope, status_code=200):
        response = super().file_response(full_path, stat_result, scope, status_code)
        response.headers["Cache-Control"] = "public, max-age=31536000, immutable"
        return response

media_dir = Path(__file__).resolve().parents[1] / "media"
media_dir.mkdir(parents=True, exist_ok=True)

app.mount("/media", CachedStaticFiles(directory=str(media_dir)), name="media")

@app.get("/")
def root():
    return {"status": "ok"}

@app.get("/test", response_class=FileResponse)
def test_page():
    return os.path.join(os.path.dirname(__file__), "test.html")