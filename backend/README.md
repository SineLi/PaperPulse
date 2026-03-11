# Backend

本目录是 PaperPulse 的后端服务，包含 API、期刊抓取器、LLM 摘要任务和定时调度。

## 组成

- FastAPI API
- PostgreSQL 数据访问
- Redis 会话与验证码状态
- APScheduler 定时任务
- 多个期刊抓取器
- 基于 OpenAI 兼容接口的批量摘要任务

## 环境要求

- Python 3.10+
- PostgreSQL
- Redis

部分抓取器依赖 Playwright，首次安装后可能还需要执行:

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
```

说明:

- 缺少 `LM_API_KEY` 或 `Elsevier_KEY` 时，部分摘要/抓取能力会受限
- 缺少 SMTP 配置时，验证码邮件无法发送
- 当前代码里虽然读取了 `CORS_ORIGINS`，但还没有接入白名单逻辑，发布前需要补齐

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
- 执行 `alembic upgrade head`
- 启动 Redis 依赖的 FastAPI 应用
- 启动后台调度器

可选参数:

```powershell
python run.py --host 127.0.0.1 --port 9000
python run.py --no-scheduler
```

文档地址:

- 健康检查: `GET /`
- Redis 状态: `GET /status/redis`

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

## 期刊数据说明

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
