# Frontend App (Flutter)

本目录是 `PaperPulse` 移动端客户端代码，主要用于论文流浏览、订阅管理与收藏/已读同步等功能。

它依赖后端 API（见 `backend/README.md`），且当前版本需要在代码中手动配置 API 地址。

主要职责包括：

- 登录状态管理（Token 存储）
- 期刊订阅与文章流展示
- 文章详情阅读、收藏、已读标记
- 本地 SQLite 缓存与离线同步队列
- 图片缓存与按网络策略下载

## 1. 环境要求

- Flutter SDK（与 `pubspec.yaml` 对应，Dart `^3.10.7`）
- Android Studio / VS Code + Flutter 插件

## 2. 安装与运行

```powershell
cd frontend_app
flutter pub get
flutter run
```

## 3. 后端地址配置（当前版本重点）

`ApiClient` 目前在 `lib/main.dart` 通过常量初始化：

```dart
final apiClient = ApiClient(baseUrl: '', authStorage: authStorage);
```

你需要先把 `baseUrl` 改成后端地址，例如：

- 本机调试（桌面）：`http://127.0.0.1:8000`
- Android 模拟器访问宿主机：`http://10.0.2.2:8000`

示例：

```dart
final apiClient = ApiClient(
  baseUrl: 'http://10.0.2.2:8000',
  authStorage: authStorage,
);
```

## 4. Android 网络限制

`android/app/src/main/AndroidManifest.xml` 当前配置了：

- `android:usesCleartextTraffic="false"`

这意味着默认不允许 `http` 明文流量。若你使用本地 HTTP 后端，需要改为 HTTPS，或按项目注释调整 `network_security_config.xml`。

如果你只是本地联调，常见做法是仅在 Debug 环境允许 cleartext（避免影响正式发布版本）。

## 5. 主要页面与行为

- `FeedPage`：本地文章流，支持分页、搜索、下拉刷新
- `JournalPage`：期刊列表与关注/取关
- `FavPage`：收藏列表
- `ArticleDetailPage`：详情阅读、收藏、分享 DOI、滑动切换文章
- `SettingPage`：主题、字体、网络、手势等设置

## 6. 数据与同步机制

本地数据库表（`lib/data/db/schema.dart`）：

- `articles`
- `journals`
- `user_subscriptions`
- `sync_queue`
- `metadata`

同步流程（`SyncService`）：

- 本地收藏/已读先写本地库与 `sync_queue`
- `flush()` 将待同步操作推送到后端
- `pullStatus()` 拉取远端收藏状态并回写本地

## 7. 目录结构（核心）

- `lib/pages/`：页面
- `lib/widgets/`：复用组件与列表骨架
- `lib/data/api/`：HTTP 客户端
- `lib/data/auth/`：登录与 token 存储
- `lib/data/db/`：SQLite 访问层
- `lib/data/service/`：API 服务与同步服务
- `lib/data/repositories/`：业务仓储层
- `assets/`：资源（logo 等）

## 8. 当前已知限制

- `/signup` 路由未在 `MaterialApp.routes` 中注册，登录页“立即注册”会跳转失败。
- 设置页保存的 `baseURL` 尚未驱动真实请求地址（实际请求仍使用 `main.dart` 初始化时传入的 `baseUrl`）。
