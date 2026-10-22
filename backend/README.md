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

部分抓取器通过兼容 Playwright API 的 Patchright 驱动 Chromium，首次安装后可能还需要执行：

```powershell
patchright install chromium
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
DB_CONNECT_TIMEOUT_SECS=10
DB_POOL_TIMEOUT_SECS=10
DB_STATEMENT_TIMEOUT_MS=60000
DB_LOCK_TIMEOUT_MS=10000
ARTICLE_FETCH_EXECUTOR_WORKERS=8
ARTICLE_FETCH_EXECUTOR_TIMEOUT_SECS=1800
IMAGE_CACHE_EXECUTOR_WORKERS=2
IMAGE_CACHE_EXECUTOR_TIMEOUT_SECS=600
BROWSER_POOL_SIZE=2
BROWSER_MAX_PAGES=4
BROWSER_CHANNEL=
BROWSER_HEADLESS=1
RSC_POST_NAVIGATION_WAIT_MS=7000
```

说明:

- 缺少 `LM_API_KEY` 或 `Elsevier_KEY` 时，部分摘要/抓取能力会受限
- 缺少 SMTP 配置时，验证码邮件无法发送
- 当前代码里虽然读取了 `CORS_ORIGINS`，但还没有接入白名单逻辑，发布前需要补齐
- 数据库连接、连接池等待、SQL 执行和锁等待分别由 `DB_*_TIMEOUT_*` 配置限制，
  避免同步数据库线程使调度周期无限阻塞
- 文章详情的实际并发上限取 `ARTICLE_FETCH_EXECUTOR_WORKERS` 与
  `BROWSER_POOL_SIZE * BROWSER_MAX_PAGES` 中的较小值
- 文章执行器超时会取消尚未完成的详情任务，只入库已完成部分。详情按期刊轮转，
  每轮更换起始期刊；独立抓取器也复用同一队列来收口取消任务
- 图片执行器超时停止领取剩余任务，等待正在下载的线程安全收尾后记录真实结果。
  未启动任务保留原状态。失败图片持久保存重试次数，按 1、2、4 小时递增冷却，最长一天
- 浏览器替换失败会向上层报告，并将失败槽位冷却 30 秒，避免无上限启动重试
- RSS 和出版社 API 请求优先通过 `curl_cffi` 使用 Chrome 网络指纹；只有传输层失败时
  才回退到普通 `requests`。Patchright 浏览器上下文不覆盖 User-Agent，以保持 UA、
  Client Hints 和 Chromium 版本一致
- 直接运行且没有图形显示时保留 `BROWSER_HEADLESS=1`。需要降低无头浏览器特征时，
  应先提供 X11/Xvfb 显示，再设置 `BROWSER_HEADLESS=0`
- 安装了 Microsoft Edge 的主机可设置 `BROWSER_CHANNEL=msedge`，让 Patchright 使用
  真实 Edge 通道；留空时继续使用 Patchright 自带 Chromium。不要从个人 Edge 配置复制 Cookie

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
项目 Dockerfile 已将 Patchright 与 Xvfb 配套：容器由 `xvfb-run` 提供虚拟显示，并以
`BROWSER_HEADLESS=0` 启动 Chromium。这里的浏览器仍运行在没有物理屏幕的服务器中，
但 Chromium 使用有头渲染路径。

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
等待下一轮继续处理。主周期到达时若图片仍在执行，会等待当前批次收尾；等待期间
不再启动新的图片批次，主周期不会因此丢失。LLM 初始化失败也不会阻止文章抓取。

升级时需要运行 `alembic upgrade head`（统一入口 run.py 会自动执行），新增图片重试字段。
Compose 启用 init，新镜像使用 tini 回收浏览器孤儿进程；需要重建镜像并重新创建容器才能
应用启动配置。修复不会自动清理旧容器中已积累的僵尸进程，也不会修改 non_article_entries。

## 测试

后端调度和资源生命周期测试使用 Python 标准库 `unittest`，无需额外测试依赖:

```powershell
cd backend
python -m unittest discover -s tests -v
```

出版社抓取器测试位于 `tests/test_publisher_fetchers.py`。测试使用固定的 RSS、API XML
和文章 HTML fixture，并 mock 网络请求与 Patchright，因此不会访问真实出版社、启动浏览器
或连接数据库。只运行抓取器测试:

```powershell
cd backend
python -m unittest tests.test_publisher_fetchers -v
```

新增出版社抓取器时，请同时在该文件中覆盖列表解析和详情解析（如果该出版社需要详情页），
并将其加入 `utils/main_fetcher.py` 的 `PUBLISHER_FETCHER_MAP`。

如果需要访问真实出版社页面，可运行显式开启的集成 smoke test。它只抓每个出版社的一条列表项
和详情，不执行数据库过滤或入库；网络限流、验证码和页面改版都可能导致失败，因此不要在默认
测试命令中自动开启:

```powershell
cd backend
patchright install chromium       # 首次运行需要
$env:RUN_LIVE_FETCHER_TESTS = "1"
python -m unittest tests.test_publisher_fetchers_live -v
Remove-Item Env:RUN_LIVE_FETCHER_TESTS
```

Elsevier 的详情 API 还需要先设置 `$env:Elsevier_KEY`。可用
`$env:PLAYWRIGHT_ATTEMPTS = "1"` 和 `$env:PLAYWRIGHT_GOTO_TIMEOUT_MS = "30000"`
缩短单次联调等待时间。

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
