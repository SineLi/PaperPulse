import unittest

from utils.challenge_detection import detect_block_reason


class ChallengeDetectionTests(unittest.TestCase):
    def test_detects_akamai_bm_verify_meta_refresh(self):
        content = """
        <html><head><title>&nbsp;</title>
        <meta http-equiv="refresh" content="0;url=/article?bm-verify=token">
        </head></html>
        """

        self.assertEqual(detect_block_reason(content), "content:bm-verify")

    def test_detects_bm_verify_in_redirect_url(self):
        self.assertEqual(
            detect_block_reason("", "https://example.com/article?bm-verify=token"),
            "url:bm-verify",
        )

    def test_does_not_match_incidental_cloudflare_text(self):
        content = "<html><title>Research article</title><script>const provider='cloudflare';</script></html>"

        self.assertIsNone(detect_block_reason(content))

    def test_detects_cloudflare_challenge_title(self):
        self.assertEqual(
            detect_block_reason("<title>Just a moment...</title>"),
            "title:just a moment",
        )

    def test_detects_short_cloudflare_challenge_structure(self):
        self.assertEqual(
            detect_block_reason("<script src='/challenge-platform/h/g/orchestrate'></script>"),
            "content:challenge-platform",
        )

    def test_ignores_challenge_script_inside_large_article(self):
        content = (
            "<title>Research article</title>"
            + "x" * 100_000
            + "<script src='/challenge-platform/scripts/jsd/main.js'></script>"
        )

        self.assertIsNone(detect_block_reason(content))


if __name__ == "__main__":
    unittest.main()
