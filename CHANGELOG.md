# Changelog

## v1.0.0 (2026-11-15)

Split out of claude-code-harness at 6699a5c (issue #237 there, step 5).

- `skills/` is the harness's `skills/` at that commit, file for file: comms-hub
  (with its panel mod), slack-draft, skill-forge, pr-review, memory-audit and
  memory-archive.
- `install.sh` installs them as the harness's `install.sh` did: same paths,
  files and modes. It records what it wrote in `~/.claude/skills.manifest` and
  removes only those files, unchanged, that a later release drops.
- The skills' suites moved here: comms-hub, comms-hub-prereqs, skill-forge and
  skill-lint, plus install and repo-layout. The comms panel's tests run daily
  on the newest Claude Code; each skill's mutation list runs weekly.
- The harness installs this repo at the release `config/skills.pin` names, from
  its `install.sh` and `harness-update.sh`.
