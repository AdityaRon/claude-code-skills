#!/usr/bin/env python3
"""The conversation on a PR in time order, for a reviewer: the description,
every comment, every review with its body (an empty one says so) and every
inline thread with its path and line. The transcript half of reading a PR;
the diff is `gh pr diff`.

  pr_transcript.py owner/repo#N [-o FILE]

The first line is `head: <sha>`, the commit the review is of: pass it to
review_lint.py --head. The second is `review-cap:`, the body's character limit
the lint holds it to: 3 of 9 reviewers wrote past it on one day, each trimmed
by hand once the lint refused it. A PR with more than one page of comments,
reviews or threads is refused: a partial transcript reads as complete.

Opt-in: when the PR's base branch holds .claude/review-checklist.tsv (read
from the base on GitHub, never the head, which the PR's author controls), a
Checklist section lists its rows whose path glob matches a changed file. Tab
separated: id, path glob, diff regex (may be empty), check, incident; `#` lines
and a header row starting `id` are skipped. In a glob `*` and `?` stop at `/`,
`**` crosses it, and a glob with no `/` matches at any depth. The diff regex
is printed with its row for the reviewer to apply. No file, no section: one
small query finds that out.
Exit 0, or 3 when the PR, or a checklist it has, could not be read in full.
"""
from __future__ import annotations

import argparse
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hub  # noqa: E402

TRANSCRIPT = """query CommsTranscript($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){
 pullRequest(number:$number){number url title state isDraft headRefOid baseRefName createdAt body author{login}
  """ + hub.PR_FILES + """
  comments(first:100){pageInfo{hasNextPage} nodes{author{login} createdAt body}}
  reviews(first:100){pageInfo{hasNextPage} nodes{author{login} state submittedAt body commit{oid}}}
  reviewThreads(first:100){pageInfo{hasNextPage} nodes{isResolved path line
   comments(first:50){pageInfo{hasNextPage} nodes{author{login} createdAt body}}}}}}}"""


CHECKLIST = ".claude/review-checklist.tsv"
CHECKLIST_QUERY = """query ReviewChecklist($owner:String!,$name:String!,$at:String!){repository(owner:$owner,name:$name){
 object(expression:$at){... on Blob{text isTruncated}}}}"""


def glob(g: str) -> re.Pattern:
    """A checklist path glob: `*` and `?` stop at `/`, `**` crosses it, no `/` matches at any depth."""
    g = g.lstrip("/")
    out, i = "" if "/" in g else "(?:.*/)?", 0
    while i < len(g):
        if g.startswith("**/", i):
            out, i = out + "(?:.*/)?", i + 3
        elif g.startswith("**", i):
            out, i = out + ".*", i + 2
        elif g[i] == "*":
            out, i = out + "[^/]*", i + 1
        elif g[i] == "?":
            out, i = out + "[^/]", i + 1
        else:
            out, i = out + re.escape(g[i]), i + 1
    return re.compile(out)


def checklist(gh: hub.Gh, owner: str, name: str, pr: dict) -> list[str]:
    """The Checklist section: the base's rows whose glob matches a changed file,
    or nothing when the base has no checklist. Raises GhError when it has one
    that cannot be read or matched in full."""
    base = pr["baseRefName"]
    at = f"refs/heads/{base}:{CHECKLIST}"
    blob = gh.graphql(CHECKLIST_QUERY, owner=owner, name=name, at=at)["repository"]["object"]
    if blob is None:
        return []
    if blob.get("text") is None or blob.get("isTruncated"):
        raise hub.GhError(f"{CHECKLIST} on {base} is binary or too large to read")
    if pr["files"]["pageInfo"].get("hasNextPage"):
        raise hub.GhError(f"more than 100 changed files, so {CHECKLIST} cannot be matched against them all")
    paths = [f["path"] for f in pr["files"]["nodes"]]
    rows, bad = [], []
    for n, line in enumerate(blob["text"].splitlines(), 1):
        cells = [c.strip() for c in line.split("\t")] + [""] * 4
        if not line.strip() or line.lstrip().startswith("#") or cells[0].lower() == "id":
            continue
        if not (cells[1] and cells[3]):
            bad.append(str(n))
            continue
        rows.append(cells[:5])
    hit = [r for r in rows if any(glob(r[1]).fullmatch(p) for p in paths)]
    top = (f"checklist: {len(hit)} of {len(rows)} rows of {CHECKLIST} on {base} match the changed files; check each"
           + (f". Unreadable line(s) {', '.join(bad)}: id, path glob, diff regex, check, incident, by tabs" if bad else ""))
    return ["## Checklist", top] + [f"- {i} `{g}`" + (f" (diff `{rx}`)" if rx else "") + f": {check}"
                                     + (f" Incident: {inc}" if inc else "") for i, g, rx, check, inc in hit] + [""]


def partial(pr: dict) -> str | None:
    """Which list has more than one page, or None."""
    for k in ("comments", "reviews", "reviewThreads"):
        if pr[k]["pageInfo"].get("hasNextPage"):
            return k
    for t in pr["reviewThreads"]["nodes"]:
        if t["comments"]["pageInfo"].get("hasNextPage"):
            return f"a thread at {t.get('path')}:{t.get('line')}"
    return None


def render(ref: str, pr: dict, cap: int, checks: list[str] = ()) -> str:
    who = lambda x: hub.login(x.get("author")) or "a deleted account"  # noqa: E731
    lines = [f"head: {pr['headRefOid']}",
             f"review-cap: {cap} characters for the review's body (github.review_max_chars); the lint refuses more",
             f"# {ref}: {pr['title']}",
             f"{pr['url']} {pr['state']}{' draft' if pr.get('isDraft') else ''} by {who(pr)} opened {pr['createdAt']}",
             "", "## Description", (pr.get("body") or "").strip() or "(no description)", "",
             *checks, "## Conversation, oldest first"]
    events = [(c["createdAt"], f"{who(c)} comment", c.get("body")) for c in pr["comments"]["nodes"]]
    for r in pr["reviews"]["nodes"]:
        if r.get("state") == "PENDING":
            continue
        oid = ((r.get("commit") or {}).get("oid") or "?")[:7]
        events.append((r["submittedAt"], f"{who(r)} review {r['state']} at {oid}", r.get("body")))
    for t in pr["reviewThreads"]["nodes"]:
        where = f"{t.get('path')}:{t.get('line') or '?'}" + (" (resolved)" if t.get("isResolved") else "")
        for i, c in enumerate(t["comments"]["nodes"]):
            events.append((c["createdAt"], f"{who(c)} inline {where}" + (" reply" if i else ""), c.get("body")))
    for at, label, body in sorted(events):
        lines += [f"### {at} {label}", (body or "").strip() or "(no body)", ""]
    return "\n".join(lines) + "\n"


def main(argv=None, gh=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("pr", metavar="owner/repo#N")
    ap.add_argument("-o", "--out")
    ap.add_argument("--config")
    args = ap.parse_args(argv)
    try:
        cfg = hub.load_config(args.config)
        owner, name, number = hub.split_pr(args.pr)
    except (hub.ConfigError, ValueError) as e:
        print(f"config: {e}")
        return 2
    gh = gh or hub.Gh()
    try:
        pr = gh.graphql(TRANSCRIPT, owner=owner, name=name, number=number)["repository"]["pullRequest"]
    except hub.GhError as e:
        print(f"BLOCKED: {args.pr} could not be read: {e}")
        return 3
    if pr is None:
        print(f"BLOCKED: {args.pr} not found")
        return 3
    more = partial(pr)
    if more:
        print(f"BLOCKED: {args.pr} has more than one page of {more}; a partial transcript reads as complete")
        return 3
    try:
        checks = checklist(gh, owner, name, pr)
    except hub.GhError as e:
        print(f"BLOCKED: {args.pr} has a review checklist that could not be read in full: {e}")
        return 3
    text = render(args.pr, pr, int(cfg["github"]["review_max_chars"]), checks)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text)
        print("\n".join(text.splitlines()[:2]))
        print(f"{len(text.splitlines())} lines -> {args.out}")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
