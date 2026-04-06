# Changelog

## 0.0.4
`2026-04-05`

### Added
- Flutter Web 本地数据库支持，补充 `sqflite_common_ffi_web`、`sqlite3.wasm`、Web 图标与 manifest 资源
- 前端图片缓存多平台实现，以及后端 `/media` 静态媒体服务
- 文章详情错误页，不存在或无效的文章链接会显示提示页
- Tab 双击回到顶部能力和对应设置项
- GitHub Pages Web 部署工作流

### Changed
- 前端导航切换为 `go_router`，登录、注册、主 Tab、设置子页和文章详情支持 URL 直达
- 文章详情改为基于 `articleId + source` 从本地数据库重建内容和上下篇关系
- 设置相关模型、存储与控制器从页面文件中拆出
- 后端运行入口、调度器和关键服务改为结构化日志输出

### Fixed
- 修复登录后回到 feed 时文章不显示的问题
- 修复文章列表已读状态与详情页切换后的同步问题
- 修复文章详情切换动画、滑动手势和出版商颜色映射问题
- 修复 Web 端字体 fallback、图片缓存策略和本地数据库适配问题
- 去除预测性返回相关逻辑，避免与当前路由和切换行为冲突

### Notes
- Web 端现在依赖浏览器路由与后端 CORS 配置；本地调试时需要确认后端允许当前前端 origin 访问
- GitHub Release 仍负责构建 APK；GitHub Pages 工作流负责构建并部署 Web 产物

## 0.0.3
`2026-03-11`

### Added
- 首个公开发布版本
- Flutter 客户端基础功能
- FastAPI 后端、PostgreSQL、Redis、定时抓取与摘要流程
- GitHub Actions 自动构建 APK 与 Docker 镜像

### Notes
- 首次部署后需要用户自行导入 `backend/journals.csv` 到 `journals` 表
