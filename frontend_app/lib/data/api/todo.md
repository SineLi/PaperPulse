# Advanced News Feed 前端 API 通信待补全清单（对照表）

说明：
- ✅ 已完成：你目前已实现/验证过的能力
- 🟡 建议补：不阻塞 UI，但很快会需要
- 🔴 可能阻塞：如果你要做对应页面/体验，会卡住

## 1. 认证与会话 Auth

- ✅ POST /auth/login
  - 保存 access_token（flutter_secure_storage）
  - ApiClient 自动带 Authorization: Bearer <token>

- ✅ GET /users/me
  - AuthServices.tryGetCurrentUser(): 401/403 → deleteToken() → return null

- 🟡 POST /auth/logout（如果后端存在）
  - 如果后端需要 server-side session revoke，则补；否则前端删 token 即可

- 🔴 注册 Register（如果需要用户自助使用）
  - POST /auth/register 或 POST /users
  - 返回 token（直接登录）或返回 user（再走登录）
  - 失败场景：用户名已存在、邮箱已存在、弱密码、字段校验（422）

- 🟡 Token 刷新机制（如果后端支持 refresh token）
  - POST /auth/refresh
  - 前端：401 时尝试 refresh，再重试原请求
  - 若后端不支持，可忽略

## 2. 用户 User

- ✅ GET /users/me
  - 用于启动鉴权与展示用户名/邮箱

- 🟡 更新个人信息（如果后端存在）
  - PATCH /users/me
  - 字段：username/email 等
  - 注意：email 变更可能要验证

- 🟡 修改密码/找回密码（可选）
  - POST /auth/change-password
  - POST /auth/forgot-password / reset-password

## 3. Feed / Articles

- ✅ GET /articles/feed?limit&offset
  - 拉取文章列表（已做 Article.fromJson 转换）
  - FeedRepo.refreshArticles(): 使用 maxId 增量写库

- ✅ GET /articles/{id}
  - 用于补全收藏列表里本地缺失文章

- 🟡 总数/游标（如果你想更可靠的分页与增量）
  - 返回 total 或 next_cursor
  - 用于“客户端不知道总共有多少”时的完备分页

- 🟡 文章更新场景（目前后端无更新）
  - 若未来文章内容会更新：需要 updated_at 或版本号
  - 前端策略：按 updated_at 增量拉取并合并，不覆盖用户态字段

## 4. 用户态文章状态（收藏/已读）Status Sync

- ✅ 本地：articles.is_favorite / is_read
- ✅ 本地：sync_queue（read/favorite/unfavorite/unread）
- ✅ SyncService.flush()
  - read 批量 POST /articles/read
  - favorite POST /articles/{id}/favorite
  - unfavorite DELETE /articles/{id}/favorite
  - 409/404 幂等处理（不阻塞队列）
- ✅ pull favorites：
  - GET /articles/favorites → items:[id]
  - 对齐本地收藏集（补拉文章详情 + setFavorite true/false）

- 🔴 已读状态拉取（后端尚未实现）
  - GET /articles/read 或 GET /users/me/read-items
  - 用于多端一致：pull 后对齐本地 is_read

- 🟡 幂等与错误码规范化（后端可选优化）
  - 建议 favorite/unfavorite/read/unread 都做到幂等（重复操作返回 200/204）
  - 前端可减少 409/404 分支

- 🟡 队列折叠（客户端优化）
  - 同一 article_id 的多次操作可合并（例如 favorite→unfavorite→favorite 只留最后一次）
  - 防止队列膨胀

- 🟡 flush 触发策略（前端）
  - 启动后、下拉刷新后、网络恢复时、定时（如每 30-60s）或进入前台时

## 5. Journals（主数据）

- ✅ GET /journals?limit&offset
  - 首次空库同步：分页批量落库（3 万条）
  - 后续暂不更新（未来可加 updated_at 增量）

- 🟡 journals 更新（未来）
  - 后端：增加 updated_at 或版本号，并支持 updated_after 查询
  - 前端：增量 sync + 本地迁移加列

## 6. 用户订阅 Journals Subscription

- ✅ GET /users/me/journals
  - 拉取订阅 journal_id 集合
  - 本地存 user_subscriptions 表
- ✅ POST /journals/{journal_id}/follow
- ✅ DELETE /journals/{journal_id}/follow
  - 本地订阅表即时 add/remove（Repo 层）
  - 后续可触发 feed refresh（根据产品需要）

- 🟡 订阅列表展示所需 join/查询
  - 本地：根据 user_subscriptions 的 journal_id 到 journals 表取 name/abbreviation

## 7. 体验与健壮性（非接口，但很快会用到）

- 🟡 ApiClient 统一异常与重试策略
  - 401/403：触发登出流程（清 token）
  - 5xx/timeout：可重试（指数退避）
  - 422：表单校验错误展示

- 🟡 图片缓存（graphical_abstract）
  - 下载、缓存路径管理、失效/清理策略

- 🟡 多账号支持（如果未来需要）
  - user_subscriptions 与用户态状态表需要按 user_id 分区或加 user_id 列
