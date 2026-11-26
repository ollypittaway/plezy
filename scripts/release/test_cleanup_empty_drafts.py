import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("cleanup-empty-drafts.sh").resolve()


class CleanupDraftsTest(unittest.TestCase):
    def test_deletes_only_empty_workflow_drafts_after_uploads_stop(self):
        with tempfile.TemporaryDirectory() as path:
            root = Path(path)
            drafts = [
                {"id": i, "draft": True, "tag_name": f"v0.0.{i}", "assets": [],
                 "author": {"login": "github-actions[bot]"},
                 "body": f"Release notes\n\n<!-- offstage-release-run:{100 + i} -->"}
                for i in range(1, 10)
            ]
            drafts[2]["draft"] = False
            drafts[3]["assets"] = [{"name": "partial.apk", "state": "starter"}]
            drafts[4]["author"] = {"login": "maintainer"}
            drafts[5]["body"] = "Manually prepared"
            (root / "list").write_text(json.dumps(drafts))
            # Two candidates changed since the list was fetched.
            drafts[7]["assets"] = [{"name": "ready.ipa"}]
            drafts[8]["draft"] = False
            for draft in drafts:
                (root / str(draft["id"])).write_text(json.dumps(draft))
            gh = root / "gh"
            gh.write_text("""#!/usr/bin/env bash
set -eu
case "$*" in
  'api --paginate repos/test/offstage/releases?per_page=100') cat list ;;
  'api repos/test/offstage/actions/runs/107 --jq .status') echo in_progress ;;
  'api repos/test/offstage/actions/runs/'*' --jq .status') echo completed ;;
  'api repos/test/offstage/releases/'*) cat "${2##*/}" ;;
  'api --method DELETE repos/test/offstage/releases/'*) echo "${4##*/}" >> deleted ;;
  *) exit 1 ;;
esac
""")
            gh.chmod(0o755)
            env = {**os.environ, "PATH": path + os.pathsep + os.environ["PATH"],
                   "GITHUB_REPOSITORY": "test/offstage", "GITHUB_RUN_ID": "101"}
            subprocess.run(["bash", str(SCRIPT)], cwd=root, env=env, check=True)
            self.assertEqual((root / "deleted").read_text().splitlines(), ["1", "2"])


if __name__ == "__main__":
    unittest.main()
