from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest


ROOT = Path(__file__).resolve().parents[2]


class MissingAsset(BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.send_response(404)
        self.end_headers()

    def log_message(self, format, *args):
        pass


class PreCommitHookTests(unittest.TestCase):
    def test_unpublished_pin_warns_without_blocking_the_commit(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), MissingAsset)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        with tempfile.TemporaryDirectory() as raw:
            repo = Path(raw)
            (repo / "Scripts").mkdir()
            shutil.copy2(ROOT / "Scripts/check-pinned-downloads.py", repo / "Scripts")
            shutil.copytree(ROOT / ".githooks", repo / ".githooks")
            url = f"http://127.0.0.1:{server.server_port}/v9.9.9/GhosttyKit.zip"
            (repo / "Scripts/dev-tools.env").write_text(f"OMNIWM_GHOSTTY_DOWNLOAD_URL={url}\n")
            env = {**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}

            def git(*args):
                return subprocess.run(["git", *args], cwd=repo, env=env, capture_output=True, text=True, check=False)

            git("init", "-q")
            git("config", "core.hooksPath", ".githooks")
            git("add", "Scripts/dev-tools.env")
            result = git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "pin")

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("OMNIWM_GHOSTTY_DOWNLOAD_URL is not downloadable (HTTP 404)", result.stderr)
            self.assertIn("pre-commit: warning", result.stderr)
            self.assertEqual(git("rev-list", "--count", "HEAD").stdout.strip(), "1")


if __name__ == "__main__":
    unittest.main()
