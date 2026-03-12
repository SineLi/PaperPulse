# Frontend App
  <img alt="Frontend Licence" src="https://img.shields.io/badge/Licence-Apache_2.0-blue?logo=apache
    "/>
  
本目录是 PaperPulse 的 Flutter 客户端，负责登录、期刊浏览、文章流展示、收藏/已读、本地缓存和离线同步。

## 当前功能

- 登录、注册、验证码发送
- Access Token / Refresh Token 管理
- 期刊列表浏览、搜索、筛选、关注/取关
- 文章流分页、搜索、筛选、下拉刷新
- 收藏和已读状态同步
- SQLite 本地缓存
- 图形摘要图片缓存
- 设置页:
  - 主题模式
  - AMOLED 模式
  - API 地址
  - 字体大小
  - Wi-Fi 下才下载图片
  - 手势和返回行为

## 环境要求

- Flutter SDK
- Dart SDK `^3.10.7`
- Android Studio / VS Code + Flutter 插件

依赖版本以 `pubspec.yaml` 和 `pubspec.lock` 为准。

## 安装与运行

```powershell
cd frontend_app
flutter pub get
flutter run
```

如果你要跑 Web:

```powershell
flutter run -d chrome
```

## 首次启动说明

应用初始 API 地址为空，不会默认连到任何后端。首次启动后需要进入 `设置 -> 网络` 填写 API Base URL。

常见本地调试地址:

- Windows / 桌面调试: `http://127.0.0.1:8000`
- Android 模拟器访问宿主机: `http://10.0.2.2:8000`
- 真机调试: `http://你的局域网IP:8000`

设置保存后，`ApiClient` 会在应用生命周期内实时切换到新的地址，不需要改代码重新编译。

## 主要页面

- `BootstrapPage`: 应用启动与会话恢复
- `AppShellPage`: 底部导航壳
- `JournalPage`: 期刊列表与关注状态
- `FeedPage`: 首页文章流
- `FavPage`: 收藏文章
- `ArticleDetailPage`: 文章详情、收藏、分享、上下篇切换
- `SettingPage`: 设置和账号页
- `LoginPage` / `RegisterPage`: 认证流程

未登录时，期刊、首页和收藏页会显示登录提示，但仍可进入设置页配置 API 地址。

## 数据与同步

本地数据包括:

- 文章表
- 期刊表
- 订阅表
- 同步队列表
- 元数据表

同步逻辑:

- 收藏/取消收藏/已读先记录到本地
- `SyncService.flush()` 把队列里的操作推到后端
- `SyncService.pullStatus()` 拉取远端收藏状态并修正本地
- 登录后会自动做一次启动同步

## 认证与存储

- token 存储使用 `flutter_secure_storage`
- 主题和 API 地址等设置存储在 `shared_preferences`
- 前端会在遇到 `401` 时尝试调用 `/auth/refresh`

## 目录结构

- `lib/main.dart`: 应用入口和依赖装配
- `lib/pages/`: 页面
- `lib/widgets/`: 通用组件
- `lib/data/api/`: HTTP 客户端
- `lib/data/auth/`: 认证逻辑和安全存储
- `lib/data/db/`: SQLite 访问层
- `lib/data/service/`: 面向接口的服务层
- `lib/data/repositories/`: 业务组合层
- `assets/`: 图片和 SVG 资源

## 与后端的对接

当前客户端依赖这些主要接口:

- `/auth/login`
- `/auth/register`
- `/auth/send_verification_code`
- `/auth/refresh`
- `/auth/logout`
- `/users/me`
- `/users/me/journals`
- `/journals/`
- `/journals/{journal_id}/follow`
- `/articles/feed`
- `/articles/{article_id}`
- `/articles/read`
- `/articles/favorites`
- `/articles/{article_id}/favorite`

详细后端说明见 `../backend/README.md`。

## 开发注意事项

- Android 或真机联调时，确认后端地址不是 `127.0.0.1`
- 如果后端使用 HTTP，目标平台需要允许明文请求
- API 地址为空时，登录和数据请求都会失败，这是预期行为
- 本地数据库和同步逻辑依赖真实设备存储，调试时建议关注卸载重装对数据的影响

## 已知限制

- 当前客户端默认不内置后端地址，需要用户首次手动配置
- 未登录时不显示业务数据，但设置页仍可访问
- 文章流依赖后端已生成摘要；后端尚未处理完成时，前端不会显示对应文章
