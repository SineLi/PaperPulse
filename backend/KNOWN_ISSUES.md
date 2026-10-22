# 暂挂事项

更新日期：2026-10-22。以下事项没有修复，不计为已验证通过。

- ACS 的 RSS DOI fixture 与现有提取规则不一致，详情 fixture 与页面选择器不一致。
  `tests/test_publisher_fetchers.py` 中对应两项测试明确跳过；恢复前需用有效页面核对
  DOI、摘要和图片解析，不能仅删除断言。ACS 图片相对地址也需要一并核对。
- RSC 专用 Edge 浏览器池、按站点隔离并持久保存会话尚未实现。
  当前 BROWSER_CHANNEL 作用于整个共享池；Docker 镜像只安装 Chromium，没有 Edge。
- RSC 仍默认固定等待 7 秒，尚未按 OIDC 完成或正文标记等待。
- 生产镜像尚未完成构建与运行验证；历史构建在基础镜像下载时失败。
- Cell/Elsevier 的 ScienceDirect 浏览器页及 Wiley 在上一轮实验中仍被拦截。
  Elsevier 官方 API 是不同路径。不能据此宣称浏览器迁移已解决所有出版社拦截。
- 真实站点 smoke test 仍需补强成功判据，当前详情为空字典也能通过类型断言。
  默认测试不访问外网；真实站点测试必须显式开启。

反拦截后续跟踪：[Issue #107](https://github.com/SineLi/PaperPulse/issues/107)。
调度阻塞跟踪：[Issue #108](https://github.com/SineLi/PaperPulse/issues/108)。

## 本轮优先修复后的剩余审查项

本轮优先处理调度活性、图片重试、队列公平性、浏览器恢复与取消收尾。
以下数据和解析问题仍待独立修复：解析异常沿用 ok、非空错误页/缺少摘要被误分类、
部分出版社图片 URL 归一化、Frontiers 全局 TLS 修改、LLM 完成批次中的残留失败条目、
不同 DOI 的同名文章被标题去重误排除。保留已有 non_article_entries 数据，不自动恢复或删除。

图片预算限制的是领取新任务；已经运行的同步下载仍需等待网络调用返回，
该预算不是强制终止线程的墙钟上限。队列轮转起点在进程内保存，服务重启后会重新开始。
