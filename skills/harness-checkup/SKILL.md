---
name: harness-checkup
description: Run the harness's own checkup and relay what it finds. Use when asked what is costing the most on this machine, to check my setup, or why sessions are slow or expensive. Not for general advice about Claude Code.
---

# Harness checkup

The harness measures its own costs. This skill runs that and relays it; it adds
no measurement of its own.

1. Run `python3 ~/.claude/harness-checkup.py` (`--days N` for another window,
   `--json` for data). It takes up to about 30 s and is offline. If the file is
   missing, say the harness is not installed and stop.
2. Relay the three costs as printed: the value, its n, its window, and the line
   it is measured against (the multiple is value / line). Say in a clause what
   each line means. Then the "Below these" line.
3. Give each cost its fix, from the harness docs:

| Cost | Fix |
|---|---|
| cache rewrites after a lapsed TTL | restart from a handoff (docs/long-running-sessions.md); for a loop or cron, `python3 ~/.claude/spend-report.py --tick-prompt '<words from the tick prompt>'` says which ticks' first call rewrote after the TTL lapsed |
| calls held by prompts then approved | docs/permission-friction.md: which guard asked, and which asks are policy calls for the owner |
| slowest Bash guard p95 | `bash doctor.sh --latency`, in the harness clone |
| job folders on disk | `python3 ~/.claude/disk-space.py prune` (a listing; only `--apply` deletes) |
| memory index | the memory-archive skill |

4. Say what it could not tell: a tool it names as failed (with its exit
   status) leaves that cost out of the ranking, so the ranking is of what ran.

## Rules

- Never read raw transcripts or chat text to add to the script's numbers.
- Never print a dollar amount; the script shows spend as a share, so relay that.
- Never clone, install, or use the network. Offer a fix; do not run it.
- Keep the reply to one screen.
