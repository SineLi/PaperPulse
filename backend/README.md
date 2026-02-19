# Backend (FastAPI)

本目录是 `PaperPulse` 的后端服务，包含：

- REST API（FastAPI）
- 文章抓取器（Fetcher，按出版社/期刊适配）
- LLM 摘要批处理与轮询更新
- 定时任务调度（APScheduler）

## 1. 环境要求

- Python 3.10+

## 2. 安装依赖

```powershell
python -m pip install -r requirements.txt
playwright install chromium
```

## 3. 初始化数据库

后端使用 SQLite，数据库文件路径固定为 `backend/db/advNewsFeed.db`（见 `db/database.py`）。

首次运行前先建表：

```powershell
cd backend
python -c "from db.database import init_database; init_database()"
```

## 4. 启动 API 服务

```powershell
cd backend
fastapi dev app/main.py
```

启动后可访问：

- 健康检查：`GET /`
- OpenAPI 文档：`http://127.0.0.1:8000/docs`

## 5. 主要接口

- `POST /auth/register`
- `POST /auth/login`
- `GET /users/me`
- `GET /users/me/journals`
- `GET /journals/`
- `POST /journals/{journal_id}/follow`
- `DELETE /journals/{journal_id}/follow`
- `GET /articles/feed`
- `GET /articles/{article_id}`
- `POST /articles/read`
- `GET /articles/favorites`
- `GET /articles/read`
- `POST /articles/{article_id}/favorite`
- `DELETE /articles/{article_id}/favorite`

除 `/auth/*` 和 `/` 外，接口默认要求 `Authorization: Bearer <token>`。

## 6. 抓取与摘要调度

如果你希望在客户端里看到持续更新的论文流，通常需要同时运行两件事：

- API 服务：对外提供登录、订阅、文章流等接口（见第 4 节）。
- 调度器：负责抓取新文章并生成/更新摘要（本节）。

运行调度器：

```powershell
cd backend
python scheduler.py
```

建议在另一个终端窗口运行调度器（保持 API 服务仍在运行）。调度日志会写入 `backend/scheduler.log`，便于排查抓取/摘要是否正常执行。

调度器行为：

- 立即执行一次完整周期（检查批处理状态 -> 抓取新文章 -> 提交新批处理）
- 之后每小时整点执行一次

抓取器启用逻辑：

- 用户关注期刊后会将 `journals.crawler_enabled` 置为 `1`
- 取消关注且无人关注时置回 `0`

### 6.1 数据准备（期刊列表）

当前仓库没有内置期刊种子数据导入脚本，所以首次运行时你需要确保 `journals` 表里有数据，并且至少满足以下条件之一：

- `rss_url` 不为空，或
- `official_url` 不为空

否则：

- `GET /journals/` 不会返回任何可订阅期刊（后端会过滤掉 `rss_url` 和 `official_url` 都为空的期刊）。
- 调度器也无法抓取文章（抓取时需要用 `rss_url` 或 `official_url` 作为入口）。

### 6.2 为什么文章流为空

文章流（`GET /articles/feed`）为空通常由以下原因导致：

- 你还没有订阅任何期刊（需要在客户端关注期刊，或通过接口写入 `user_journal_subscriptions`）。
- 数据库里有文章，但 `llm_summary` 仍为空：当前实现只会返回 `llm_summary IS NOT NULL` 的文章。摘要生成依赖调度器 + LLM 配置，可能需要等待一段时间。

## 7. API 密钥文件（可选但建议）

仓库代码中以下模块依赖 `backend/API_KEYs.py`：

- `services/LLM_service.py`（`LM_API_KEY`）
- `utils/fetcher/Elsevier_fetcher.py`（`Elsevier_KEY`）

建议手动创建 `backend/API_KEYs.py`：

```python
Elsevier_KEY = "your_elsevier_key"
LM_API_KEY = "your_llm_api_key"
```

如果你只运行 API（不跑 `scheduler.py`），通常不需要这两个密钥。

## 8. 注意事项

- 当前 CORS 为全开放（`allow_origins=["*"]`），仅适合开发环境。
- JWT `SECRET_KEY` 当前写在代码中（`app/core/security.py`），生产环境建议改为环境变量。
- 仓库未附带期刊种子导入脚本；如果 `journals` 表为空，客户端将无可订阅期刊。

## 9. 常见问题

`sqlite3.OperationalError: no such table ...`

- 先执行数据库初始化命令（第 3 节）。

`No active journals found with crawler_enabled=1`

- 说明还没有用户订阅期刊，或 `journals` 表没有可抓取数据。

登录后看不到文章

- 文章流查询只返回 `llm_summary IS NOT NULL` 的数据；需要抓取并完成摘要处理后才会出现。
