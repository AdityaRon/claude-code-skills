r"""pr_transcript.py: the conversation in time order, bodies shown or named empty, nothing partial.

Mutations (run.py --mutate applies each and expects this file to fail):
  unordered: pr_transcript.py: `for at, label, body in sorted(events):` => `for at, label, body in events:`
  empty-body-silent: pr_transcript.py: `(body or "").strip() or "(no body)"` => `(body or "").strip()`
  inline-dropped: pr_transcript.py: `for i, c in enumerate(t["comments"]["nodes"]):` => `for i, c in ():`
  partial-ok: pr_transcript.py: `if pr[k]["pageInfo"].get("hasNextPage"):` => `if False:`
  no-head-line: pr_transcript.py: `lines = [f"head: {pr['headRefOid']}",` => `lines = [`
  no-cap-line: pr_transcript.py: `f"review-cap: {cap} characters for the review's body (github.review_max_chars); the lint refuses more",` => ``
  cap-not-printed: pr_transcript.py: `print("\n".join(text.splitlines()[:2]))` => `print(text.splitlines()[0])`
  checklist-from-head: pr_transcript.py: `at = f"refs/heads/{base}:{CHECKLIST}"` => `at = f"{pr['headRefOid']}:{CHECKLIST}"`
  checklist-all-rows: pr_transcript.py: `hit = [r for r in rows if any(glob(r[1]).fullmatch(p) for p in paths)]` => `hit = rows`
  checklist-star-crosses-dirs: pr_transcript.py: `out, i = out + "[^/]*", i + 1` => `out, i = out + ".*", i + 1`
  checklist-anchored-basename: pr_transcript.py: `out, i = "" if "/" in g else "(?:.*/)?", 0` => `out, i = "", 0`
  checklist-partial-ok: pr_transcript.py: `if pr["files"]["pageInfo"].get("hasNextPage"):` => `if False:`
  checklist-unreadable-silent: pr_transcript.py: `bad.append(str(n))` => `pass`
  checklist-truncated-ok: pr_transcript.py: `if blob.get("text") is None or blob.get("isTruncated"):` => `if blob.get("text") is None:`
"""
import contextlib
import io
import unittest

from fakes import Env, Fail, FakeGh, actor, page

import hub
import pr_transcript as pt

T1, T2, T3, T4 = "2026-10-20T10:00:00Z", "2026-10-20T11:00:00Z", "2026-10-20T12:00:00Z", "2026-10-20T13:00:00Z"


def pr(more=None, more_thread=False, files=("src/retry/loop.py", "docs/retry.md"), more_files=False):
    return {"number": 7, "url": "https://github.com/acme/app/pull/7", "title": "retry with backoff", "state": "OPEN",
            "isDraft": False, "headRefOid": "abcdef1234567890", "baseRefName": "main", "createdAt": T1,
            "body": "Adds backoff.", "files": page([{"path": f} for f in files], more=more_files),
            "author": actor("teammate"),
            "comments": page([{"author": actor("bob"), "createdAt": T4, "body": "ping"}], more=more == "comments"),
            "reviews": page([{"author": actor("carol"), "state": "APPROVED", "submittedAt": T2, "body": "",
                              "commit": {"oid": "abcdef1234567890"}}], more=more == "reviews"),
            "reviewThreads": page([{"isResolved": False, "path": "src/a.py", "line": 3, "comments": page(
                [{"author": actor("carol"), "createdAt": T2, "body": "off by one?"},
                 {"author": actor("teammate"), "createdAt": T3, "body": "fixed in the next push"}], more=more_thread)}],
                more=more == "reviewThreads")}


BASE = "refs/heads/main:.claude/review-checklist.tsv"
TSV = ("id\tpath glob\tdiff regex\tcheck\tincident\n"
       "# rows a reviewer checks when the PR touches their paths\n"
       "retry-cap\tsrc/**/*.py\tretry|backoff\tEvery retry loop caps its attempts.\tA retry storm, 2026-03\n"
       "\n"
       "docs-only\t*.md\t\tThe page's examples still run.\t\n"
       "top-level\tsrc/*.py\t\tA top-level module keeps its public names.\tA rename broke importers\n"
       "schema\tdb/**\t\tA migration has its down step.\tA rollback that could not\n"
       "half a row\n")


def checklists(files):
    """Answers ReviewChecklist as GitHub would: the blob at the expression asked
    for, from `files` (expression to text), null for a path not there."""
    def answer(v):
        text = files.get(v["at"])
        return {"repository": {"object": text if not isinstance(text, str) else {"text": text, "isTruncated": False}}}
    return answer


def run(env, handler, *argv, checklist=None):
    runner = FakeGh(graphql={"CommsTranscript": handler, "ReviewChecklist": checklists(checklist or {})})
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        rc = pt.main(["acme/app#7", *argv], gh=hub.Gh(runner=runner, pause=0))
    run.runner = runner
    return rc, out.getvalue()


class Transcript(unittest.TestCase):
    def test_time_order_with_empty_bodies_named(self):
        with Env() as env:
            rc, out = run(env, {"repository": {"pullRequest": pr()}})
        self.assertEqual(rc, 0, out)
        lines = out.splitlines()
        self.assertEqual(lines[0], "head: abcdef1234567890")
        # 3 of 9 reviewers wrote past the cap in one day; the reviewer now reads it here.
        self.assertTrue(lines[1].startswith("review-cap: 2500 characters for the review's body"), lines[1])
        self.assertIn("# acme/app#7: retry with backoff", lines)
        self.assertIn("Adds backoff.", lines)
        heads = [l for l in lines if l.startswith("### ")]
        self.assertEqual(heads, [f"### {T2} carol inline src/a.py:3", f"### {T2} carol review APPROVED at abcdef1",
                                 f"### {T3} teammate inline src/a.py:3 reply", f"### {T4} bob comment"])
        self.assertEqual(lines[lines.index(heads[1]) + 1], "(no body)")
        self.assertEqual(lines[lines.index(heads[0]) + 1], "off by one?")
        self.assertNotIn("## Checklist", out, "no checklist on the base, no section")
        self.assertEqual(run.runner.count("ReviewChecklist"), 1, "one small query finds that out")

    def test_writes_a_file_and_prints_the_head(self):
        with Env() as env:
            rc, out = run(env, {"repository": {"pullRequest": pr()}}, "-o", str(env.dir / "pr-7.md"))
            self.assertEqual(rc, 0, out)
            self.assertEqual(out.splitlines()[0], "head: abcdef1234567890")
            self.assertTrue(out.splitlines()[1].startswith("review-cap: 2500 characters"), out)
            self.assertIn("### ", (env.dir / "pr-7.md").read_text())

    def test_the_checklist_lists_the_base_rows_whose_glob_matches_a_changed_file(self):
        # A checklist on the head is the PR author's to edit: dropping a row there must not drop the check.
        head = "abcdef1234567890:.claude/review-checklist.tsv"
        planted = "harmless\t**\t\tNothing to check here.\t\n"
        with Env() as env:
            rc, out = run(env, {"repository": {"pullRequest": pr()}}, checklist={BASE: TSV, head: planted})
        self.assertEqual(rc, 0, out)
        lines = out.splitlines()
        sec = lines[lines.index("## Checklist"):lines.index("## Conversation, oldest first")]
        self.assertEqual(sec, [
            "## Checklist",
            "checklist: 2 of 4 rows of .claude/review-checklist.tsv on main match the changed files; check each. "
            "Unreadable line(s) 8: id, path glob, diff regex, check, incident, by tabs",
            "- retry-cap `src/**/*.py` (diff `retry|backoff`): Every retry loop caps its attempts. "
            "Incident: A retry storm, 2026-03",
            "- docs-only `*.md`: The page's examples still run.",
            ""])
        self.assertEqual(lines[:2][0], "head: abcdef1234567890", "head: and review-cap: stay the first two lines")
        self.assertLess(lines.index("## Description"), lines.index("## Checklist"))

    def test_a_top_level_glob_stays_at_the_top(self):
        with Env() as env:
            rc, out = run(env, {"repository": {"pullRequest": pr(files=("src/b.py",))}}, checklist={BASE: TSV})
        self.assertEqual(rc, 0, out)
        self.assertIn("checklist: 2 of 4 rows", out)
        self.assertIn("- top-level `src/*.py`: A top-level module keeps its public names.", out)
        self.assertNotIn("docs-only", out)

    def test_a_checklist_that_cannot_be_read_or_matched_in_full_blocks(self):
        with Env() as env:
            for p, lists, why in ((pr(more_files=True), {BASE: TSV}, "more than 100 changed files"),
                                  (pr(), {BASE: {"text": TSV[:40], "isTruncated": True}}, "binary or too large"),
                                  (pr(), {BASE: {"text": None, "isTruncated": False}}, "binary or too large")):
                rc, out = run(env, {"repository": {"pullRequest": p}}, checklist=lists)
                self.assertEqual(rc, 3, out)
                self.assertIn(f"BLOCKED: acme/app#7 has a review checklist that could not be read in full", out)
                self.assertIn(why, out)
            rc, out = run(env, {"repository": {"pullRequest": pr(more_files=True)}})
            self.assertEqual(rc, 0, "a long file list matters only to a checklist")

    def test_more_than_one_page_or_an_unreadable_pr_blocks(self):
        with Env() as env:
            for more in ("comments", "reviews", "reviewThreads"):
                rc, out = run(env, {"repository": {"pullRequest": pr(more=more)}})
                self.assertEqual(rc, 3, more)
                self.assertIn(f"more than one page of {more}", out)
            rc, out = run(env, {"repository": {"pullRequest": pr(more_thread=True)}})
            self.assertEqual(rc, 3)
            self.assertIn("a thread at src/a.py:3", out)
            rc, out = run(env, [Fail(), Fail()])
            self.assertEqual(rc, 3)
            self.assertIn("BLOCKED", out)


if __name__ == "__main__":
    unittest.main()
