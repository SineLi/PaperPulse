# ACS RSS 优先抓取

ACS 详情页仍可能触发人机验证，而 [官方 RSS](https://pubs.acs.org/pages/rss) 已在本次样本中
提供正式摘要与 TOC 图片地址。因此默认直接使用 RSS 中明确标为 Abstract 的内容，
缺少有效摘要时继续访问详情页。

## 配置和行为

- `ACS_PREFER_RSS=1`（默认）：优先使用 RSS 的摘要、DOI 与图片地址，避免重复请求详情页。
- `ACS_PREFER_RSS=0`：浏览器优先；页面失败或没有摘要时仍保留有效的 RSS 摘要。
- 未标为 Abstract 的短介绍，以及空摘要标题，不会跳过详情页。
- DOI 优先使用 feed 元数据；兼容当前及旧版页面选择器，并解析相对图片地址。
- TOC 图片保留完整签名查询参数；完成日志中的 `fetch_source=acs_rss/acs_page` 标明来源。

## 2026-10-25 实测

| ASAP feed | 条目数 |
|---|---:|
| Journal of the American Chemical Society | 7 |
| Analytical Chemistry | 9 |
| Chemical Reviews | 3 |
| ACS Nano | 8 |
| Journal of Agricultural and Food Chemistry | 7 |
| 合计 | 34 |

34 条通过实际详情任务入口，全部为 `ok`，浏览器请求为 0。
按 DOI 查询的 34 条 Crossref 摘要与 RSS 文本全部一致（移除 Abstract 标题并忽略空白）；
另有 4 篇与成功保存的文章页 Abstract 正文一致。这批样本没有进一步缩写为短简介。

图片测试使用部署依赖镜像中的原有 `ImageService.cache_image`，在本地 Linux 容器运行。
34 个 RSS 原始图片地址全部 HTTP 200，并验证为有效图片；没有使用登录 Cookie、授权头、
文章页预加载或浏览器回退。31 个 PNG 全部转为 WebP 缓存；3 个 SVG 下载成功，
但现有 Pillow 转换阶段报 `invalid_image_data`。本分支保留这一限制，没有引入新的图片转换依赖。

## 验证方式与范围

新增 `tests/test_acs_rss_details.py` 覆盖 RSS 优先、短介绍回退、空摘要、浏览器失败回退、
开关、公式文本、签名参数、DOI 与图片地址；恢复原先跳过的两项 ACS 解析测试。

```sh
cd backend
python -B -m unittest tests.test_acs_rss_details tests.test_publisher_fetchers -v
python -B -m unittest discover -s tests -v
```

默认单元测试不访问外网。实际 RSS、图片下载与跨来源摘要比较是另行完成的验证，
不代表全部历史文章或未来所有 ACS feed 都具有相同结构。本次未从远程生产主机重复图片测试。
当前 feed 窗口以外的历史漏文、SVG 转换及生产部署仍需后续处理。
