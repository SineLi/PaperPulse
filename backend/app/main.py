from contextlib import asynccontextmanager
import logging
import os
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from app.routers import auth, journals, users, articles, status

logger = logging.getLogger(__name__)

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


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    logger.warning(
        "event=request_validation_failed method=%s path=%s errors=%s",
        request.method,
        request.url.path,
        exc.errors(),
    )
    return JSONResponse(status_code=422, content={"detail": exc.errors()})


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    logger.exception(
        "event=unhandled_request_exception method=%s path=%s detail=%s",
        request.method,
        request.url.path,
        exc,
    )
    return JSONResponse(status_code=500, content={"detail": "Internal Server Error"})

@app.get("/")
def root():
    return {"status": "ok"}

@app.get("/test", response_class=FileResponse)
def test_page():
    return os.path.join(os.path.dirname(__file__), "test.html")
