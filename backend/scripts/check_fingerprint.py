"""Print the browser fingerprint that the fetcher's Playwright context exposes.

TEMP(反爬调试) helper: run alongside scripts/debug_fetcher.py to confirm the
UA / Sec-CH-UA brands / platform reported to websites are consistent with the
native Patchright Chromium instance used by the browser pool.

Usage:
  python scripts/check_fingerprint.py
"""

from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path

from dotenv import load_dotenv


BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

load_dotenv(BACKEND_DIR / ".env")

from utils.browser_manager import BrowserManager  # noqa: E402


PROBE_JS = """() => {
  const gl = document.createElement('canvas').getContext('webgl');
  const dbg = gl && gl.getExtension('WEBGL_debug_renderer_info');
  return {
    userAgent: navigator.userAgent,
    brands: (navigator.userAgentData && navigator.userAgentData.brands || [])
      .map(b => `${b.brand} v${b.version}`),
    platform: navigator.platform,
    mobile: navigator.userAgentData ? navigator.userAgentData.mobile : null,
    languages: navigator.languages,
    webdriver: navigator.webdriver,
    hardwareConcurrency: navigator.hardwareConcurrency,
    deviceMemory: navigator.deviceMemory || null,
    plugins: navigator.plugins.length,
    headlessHint: navigator.userAgent.toLowerCase().includes('headless'),
    // 无头经典破绽：无头模式没有窗口边框，outer 与 inner 尺寸相等
    windowSize: [window.outerWidth, window.innerWidth, window.outerHeight, window.innerHeight],
    screen: [screen.width, screen.height, screen.availWidth, screen.availHeight],
    hasWindowChrome: !!window.chrome,
    notificationPermission: (typeof Notification !== 'undefined') ? Notification.permission : null,
    webglVendor: dbg ? gl.getParameter(dbg.UNMASKED_VENDOR_WEBGL) : null,
    webglRenderer: dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : null,
  };
}"""


async def main() -> None:
    manager = BrowserManager(1, 1)
    try:
        async with manager.add_page() as page:
            # 需要_https_页面才会暴露 navigator.userAgentData（安全上下文专属）
            await page.goto("https://example.com", wait_until="domcontentloaded")
            info = await page.evaluate(PROBE_JS)
        print(json.dumps(info, ensure_ascii=False, indent=2))
    finally:
        await manager.close_all_browsers()


if __name__ == "__main__":
    asyncio.run(main())
