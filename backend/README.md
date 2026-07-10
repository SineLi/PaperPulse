# Backend
<img alt="Backend Licence" src="https://img.shields.io/badge/Licence-AGPLv3-orange?logo=gnu  "/>

本目录是 PaperPulse 的后端服务，包含 API、期刊抓取器、LLM 摘要任务和定时调度。

## 组成

- FastAPI API
- PostgreSQL 数据访问
- Redis 会话与验证码状态
- APScheduler 定时任务
- 多个期刊抓取器
- 基于 OpenAI 兼容接口的批量摘要任务
- 自动缓存文章图片

## 环境要求

- Python 3.10+
- PostgreSQL
- Redis

部分抓取器依赖 Playwright，首次安装后可能还需要执行：

```powershell
playwright install chromium
```

## 安装依赖

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\activate
python -m pip install -r requirements.txt
```

## 环境变量

`run.py` 会自动加载同目录下的 `.env` 文件。 你可以复制 `.env.example` 并修改其中的值来配置环境。

必需变量:

```env
DATABASE_URL=postgresql+psycopg://paperpulse:paperpulse@127.0.0.1:5432/paperpulse
REDIS_URL=redis://127.0.0.1:6379/0
JWT_SECRET=replace-with-a-random-secret
```

可选变量:

```env
LLM_BASE_URL=https://your-openai-compatible-endpoint
LM_API_KEY=your-llm-key
Elsevier_KEY=your-elsevier-key
SMTP_SERVER=smtp.example.com
SMTP_PORT=587
SMTP_USERNAME=your-smtp-user
SMTP_KEY=your-smtp-password
SOURCE_EMAIL=donotreply@example.com
CORS_ORIGINS=https://app.example.com,https://admin.example.com
ARTICLE_FETCH_EXECUTOR_WORKERS=8
ARTICLE_FETCH_EXECUTOR_TIMEOUT_SECS=1800
IMAGE_CACHE_EXECUTOR_WORKERS=2
IMAGE_CACHE_EXECUTOR_TIMEOUT_SECS=600
BROWSER_POOL_SIZE=2
BROWSER_MAX_PAGES=4
```

说明:

- 缺少 `LM_API_KEY` 或 `Elsevier_KEY` 时，部分摘要/抓取能力会受限
- 缺少 SMTP 配置时，验证码邮件无法发送
- 当前代码里虽然读取了 `CORS_ORIGINS`，但还没有接入白名单逻辑，发布前需要补齐
- 文章详情的实际并发上限取 `ARTICLE_FETCH_EXECUTOR_WORKERS` 与
  `BROWSER_POOL_SIZE * BROWSER_MAX_PAGES` 中的较小值
- 执行器超时会取消尚未开始或尚未完成的任务；文章只入库已完成部分，图片保持
  `pending` 并等待下一轮回填

## 本地依赖服务

仓库提供了 PostgreSQL 和 Redis 的本地 compose 配置:

```powershell
cd backend
docker compose up -d postgres redis
```

默认 compose 参数:

- PostgreSQL: `paperpulse/paperpulse`, 端口 `5432`
- Redis: 端口 `6379`

## 启动方式

### 1. 推荐：使用docker compose

```powershell
cd backend
Copy-Item .env.example .env
docker compose up -d
```
注意：启动前请在 `.env` 文件中配置好环境变量。
默认会拉取 `docker-compose.yml` 中配置的后端镜像；如需覆盖镜像版本，可设置 `BACKEND_IMAGE` 环境变量。

### 2. 直接运行统一入口

```powershell
cd backend
python run.py
```

默认行为:

- 加载 `.env`
- 检查必需环境变量
- 探测 PostgreSQL 连通性
- 探测 Redis 连通性
- 执行 `alembic upgrade head`
- 启动 FastAPI 应用
- 启动后台调度器
- 输出结构化日志；调度器额外写入 `scheduler.log`

可选参数:

```powershell
python run.py --host 127.0.0.1 --port 9000
python run.py --no-scheduler
```

默认地址:

- 健康检查 `GET /`
- Redis 状态 `GET /status/redis`
- 媒体静态文件 `GET /media/...`

## API 概览

公开接口:

- `POST /auth/login`
- `POST /auth/register`
- `POST /auth/send_verification_code`
- `POST /auth/refresh`
- `GET /`

鉴权接口:

- `POST /auth/logout`
- `GET /users/me`
- `GET /users/me/journals`
- `GET /journals/`
- `POST /journals/{journal_id}/follow`
- `DELETE /journals/{journal_id}/follow`
- `GET /articles/feed`
- `GET /articles/{article_id}`
- `POST /articles/read`
- `GET /articles/read`
- `GET /articles/favorites`
- `POST /articles/{article_id}/favorite`
- `DELETE /articles/{article_id}/favorite`

除 `/auth/*` 和 `/` 外，其余业务接口都要求 `Authorization: Bearer <access_token>`。

## 数据与业务行为

- `run.py` 会在每次启动时执行 Alembic 迁移
- 用户关注期刊时，会将对应期刊的 `crawler_enabled` 置为 `TRUE`
- 最后一个用户取消关注后，会把 `crawler_enabled` 置回 `FALSE`
- 文章流只返回 `llm_summary IS NOT NULL` 的文章
- 令牌体系为 `access token + refresh token`
- refresh token 会存到 Redis，中途清 Redis 会导致会话失效

## 调度与摘要

默认调度逻辑在 `scheduler.py` 中:

- 进程启动时立即执行一轮任务
- 之后每小时整点执行一轮

单轮任务顺序:

1. 检查并拉取已完成的 LLM 批处理结果
2. 抓取当前启用期刊的新文章
3. 提交新的摘要批处理任务

文章抓取分为三个阶段:

1. 依次收集各期刊 RSS/列表并过滤数据库中已有文章
2. 将所有期刊的文章详情任务交给同一个限流执行器
3. 执行器结束或超时后，按期刊将已完成任务统一写入数据库

图形摘要不会在文章插入事务中同步下载。新记录先标记为 `pending`，图片回填任务在
每小时的第 15、30、45 分钟运行；如果主调度周期仍在执行，本轮图片回填会跳过，
等待下一轮继续处理。

## 测试

后端调度和资源生命周期测试使用 Python 标准库 `unittest`，无需额外测试依赖:

```powershell
cd backend
python -m unittest discover -s tests -v
```

## 期刊数据说明

仓库提交中包含 `backend/journals.csv`。初始化数据库后，用户需要自行将该文件导入 `journals` 表；后端启动和迁移过程不会自动执行这一步。

后端不会自动导入完整的期刊主数据。要让前端“期刊列表”可用，`journals` 表里至少需要有可抓取的期刊记录，并满足以下条件之一:

- `rss_url` 非空
- `official_url` 非空

否则:

- `GET /journals/` 会返回空列表
- 调度器也没有抓取入口

## 常见问题

### 启动时报 `DATABASE_URL is not set`

先配置 `DATABASE_URL`，再执行 `python run.py`。

### 启动时报 Redis 初始化失败

检查 `REDIS_URL` 是否正确，并确认 Redis 已经启动。

### 登录后没有文章

通常有三种原因:

- 还没有关注任何期刊
- `journals` 表里没有可抓取的数据
- 新文章还没完成摘要生成

### 验证码邮件发不出去

检查 `SMTP_SERVER`、`SMTP_USERNAME`、`SMTP_KEY` 和 `SOURCE_EMAIL`。
