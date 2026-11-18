---
name: memory-archive
description: Relieve a MEMORY.md index that Claude Code reports as over or approaching its read limit (200 lines, 25,000 bytes), by proposing index lines to archive or lessons to group, never deletions. Use when Claude Code reports that error, and only then, or when asked to clean up, archive or merge the memory index. Never as routine maintenance.
---

# Relieving a memory index that is over its read limit

`MEMORY.md` loads into every session and holds one line per memory. Past 200
lines or 25,000 bytes the tail is dropped at session start, silently.

**What already happens without you.** Claude Code checks the index on every
write: over the limit it returns an error to the writer (`Error: this write
left the` index `over its` cap `read limit`), near it a reminder to compact
(`approaching the` cap `read limit. Compact it`). Where auto-dream is
enabled it also prunes and reindexes in the background. And `memory-index.sh`
keeps the index in tier order (ACTIVE, `feedback`, `reference`, `project`,
newest first inside the last two) so that whatever truncation takes is the
cheapest line. Your job starts only when those have run and the index is still
over: deciding *which* lines leave, which a tool cannot judge.

Two things are settled; do not re-derive them:

1. **The size problem is not solvable.** Bounded index, unbounded corpus.
   Archiving and grouping are constant-factor moves against linear growth;
   they buy months. Merging DUPLICATES reclaims nothing (measured: 6 of 1,328
   claims appeared twice). Grouping instances of one *principle* does (76
   `feedback_` lines became 12), and it is the only lever that reaches
   `feedback_`.
2. **The harm was never the limit; it was the ordering.** An append-ordered
   index drops its newest entries, and `feedback_` entries only work when
   loaded. Run `memory-index.sh` first; if ordering alone puts every
   `feedback_` above the cut, the index may not need relieving at all.

## The safety property that makes this delegable

**Never delete. Move the index line and leave a pointer.** The memory file
stays on disk, its line moves to `MEMORY_ARCHIVE.md`, and `MEMORY.md` keeps one
line saying the archive exists and when to read it. A wrong archive costs one
retrieval, not lost knowledge, which is why the judgment does not have to be
reliable.

This skill proposes; `bin/memory-index.sh` performs, and it refuses to write
anything that is not a pure permutation of the existing lines. Keep that split.

## Procedure

**1. Establish there is pressure.** `--status` prints lines, bytes, both limits
and `pressure: yes|no`, judged as memory-lint and session-start judge it (180
lines or 20,000 bytes). On `pressure: no`, stop: say so with the numbers and
change nothing.

```bash
bash ~/.claude/memory-index.sh --store <slug> --status
```

**2. Fix ordering first, then re-measure the harm, not the total.** `--diff`
lists each entry the reorder would move; judge any hand-placed line there
before `--write` moves it.

```bash
bash ~/.claude/memory-index.sh --store <slug> --diff     # dry run, with the moves
bash ~/.claude/memory-index.sh --store <slug> --write    # if out of order
grep -n '^- \[' MEMORY.md | awk -F: '$1>200' | grep -c 'feedback_'
```

Zero means the tail holds only the least costly entries. That may be enough.

**3. Relieve the byte limit first; it needs no archiving.** Index hooks drift
long and the detail stays in the memory file, so trimming them loses nothing.
`--long-hooks` lists lines over 110 characters, counted as memory-lint counts
them, with the room each hook has after its title and filename:

```bash
bash ~/.claude/memory-index.sh --store <slug> --long-hooks
```

Trimming the 13 worst hooks on a real store cleared the limit outright.

**4. Archive the cheapest end.** `--archive-overflow` moves the oldest
`project` lines, then the oldest `reference`, draining to a margin below the
cap. It never peels ACTIVE, `feedback`, untyped entries, or anything modified
in the last 2 days (`--min-age-days`). For lines you judged, `--archive` moves
exactly those under a new `## TEXT` block; it is a dry run until `--write`,
and `--write` also reorders:

```bash
bash ~/.claude/memory-index.sh --store <slug> --archive-overflow
bash ~/.claude/memory-index.sh --store <slug> --archive project_a.md project_b.md --heading "<why these>"
```

Spend your judgment on what deserves promoting UP into the ACTIVE block, and on
`project_` lines whose work is finished. A hook is not evidence; the body is,
and where a claim's truth lives on GitHub or Jira either check it or say you
did not.

**5. Group instances of one principle under a hub; this is the only lever that
reaches `feedback_`.** When several lessons each record a different way of the
same failure (a tool's output describing the lookup rather than the world, say),
propose one `feedback_hub_<slug>` memory stating the rule with one bullet per
instance (wikilink, trigger, tell). Instance files stay on disk unedited; the
hub's own line stays in the index, and `--archive <instances> --heading
feedback_hub_<slug>` moves the instances' lines under `## feedback_hub_<slug>`
(it refuses an instance the hub does not link). Say what it costs: a situation
the index used to name directly is now one hop away. Hub only what truly shares
a principle.

**6. Hand back a proposal, not a change.** For each candidate: name, type, why
it qualifies, what a wrong call would cost. Then lines now, lines after, limit.
A human approves; `memory-index.sh` writes.

## The aggressive tier: only when asked for it

Steps 1 to 6 are the default and usually enough. Only when the user asks for
more, and step 1 said `pressure: yes`, a line may also move with **evidence
per line**:

- **Finished work**: the tracker or GitHub state was checked, not inferred
  from the hook. `bash ~/.claude/memory-verify.sh --jira-keys` prints the
  stored Jira keys as `key in (...)` lines, one JQL search per 50 keys.
- **A duplicated reference**: a skill or rule line already says the same
  thing and always loads. Quote that line and name its file.

One `--archive` run per reason, its heading naming the reason and the date
(`--heading "Tracker Done, checked 2026-11-18"`). Which session wrote a memory
is no evidence: sessions started in one directory share one index.

## Rules

- **`feedback_` is never archived on its own.** Its line may move only under a
  hub whose own line IS loaded. If you cannot name that line, it is a deletion
  wearing a different word.
- **`reference_` is rarely archivable.** A fact does not become false because
  its project ended. The aggressive tier's duplicate is the one exception.
- **Finished is not worthless.** Archive the lifecycle, keep the lesson; if the
  lesson is buried in a `project_` memory, propose extracting it first.
- **Do not re-propose "retire settled memories with no lesson-shaped wording".**
  It was built, tried and withdrawn: it flagged a real pipeline mismatch and a
  real blocker. No wordlist separates a status record from a durable fact. See
  `docs/history/memory-hygiene-problems.md`.
- **"Do less" is usually the right answer.** On the run this was written
  against: trim hooks, archive two, merge none, and stay ~8 entries over the
  line limit rather than archive live work. An index over its limit with no
  `feedback_` or `reference_` past the cut is working as intended; report the
  overage and why you are leaving it. The aggressive tier is for when the user
  asks for more than that.
