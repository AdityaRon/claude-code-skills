# Claude Code Skills

Skills for Claude Code, installed into `~/.claude/skills` once per machine, so
they load in every project without touching repo files: `comms-hub` and
`slack-draft` (one session speaks on Slack for all of them), `skill-forge` (one
skill per recurring question in a new job), `pr-review`, `memory-audit` and
`memory-archive`.

Split out of [claude-code-harness](https://github.com/AdityaRon/claude-code-harness)
at [6699a5c](https://github.com/AdityaRon/claude-code-harness/commit/6699a5c6432d3ebcdff63052d32e95a4ef314ada).
`skills/` here is that commit's `skills/`, file for file, and `install.sh` puts
the same files in the same places with the same modes as the harness's
`install.sh` did. The history before the split is in the harness repo.

## Install and update

Needs macOS or Linux with bash and `git`; Python 3.10 or newer with a TOML
reader for comms-hub and skill-forge and their tests; `jq` and `gh` for comms-hub.

**With the harness**, nothing to do: the harness pins a release of this repo
(`config/skills.pin` there), and its `install.sh` and scheduled
`harness-update.sh` clone this repo into `~/.claude/skills-src`, check the
pinned tag out, verify its commit and run its `install.sh`. A machine that
points `HARNESS_UPDATE_URL` at another clone of the harness points
`HARNESS_SKILLS_URL` at a clone of this repo.

**Alone:**

```bash
git clone https://github.com/AdityaRon/claude-code-skills.git
cd claude-code-skills
bash install.sh
```

- Each skill's `SKILL.md`, `*.example.toml`, `bin/`, and a panel's manifest,
  `hooks/` and `types/` go to `~/.claude/skills/<name>/`; tests, `forge.toml`
  and `lint-waivers.toml` stay in the clone.
- skill-forge's `templates/` go to `~/.local/share/skill-forge/templates/`
  (`$XDG_DATA_HOME`), never under `~/.claude/skills`.
- Every file is written beside its target and renamed over it, so a session
  reading one mid-install gets the old file or the new one.
- No config is created or touched: `~/.config/comms-hub/config.toml` and
  `~/.config/skill-forge/config.toml` are yours.
- `~/.claude/skills.manifest` records each file it wrote, with its git blob.
  A later release that drops a file removes it only when unchanged since; a
  skill of your own, a file you added, or one you edited stays.
  `~/.claude/skills.version` records the release.

Several skills run scripts the harness installs in `~/.claude`
(`memory-verify.sh`, `memory-index.sh`, `session-route.sh`, `spend-report.py`);
each skill's `forge.toml` lists them under `uses`.

## comms-hub: one session speaks on Slack for all of them

A skill for running several sessions at once. One long-lived session, the comms
session, runs a tick on a `/loop` cron trigger: it reads GitHub for your PRs and
review requests and Slack for replies, and routes each event to the peer session
that owns the PR or ticket. It is the only session that sends Slack. A peer hands
it a draft and a target with SendMessage; it checks every claim against its
source, runs the draft through a gate (every PR a link, no em or en dash, no `>`
quote, no token-shaped string, a length cap, the linked PRs' live state, no
review ask to someone who already reviewed that head, and no reply that only
restates your own posted review, which goes as a reaction instead), then sends,
or schedules for the morning in quiet hours. It resolves a review thread on your own PR only
once you answered it and that reviewer approved after. It reviews a PR asked of
you as a comment only. It never approves a PR or merges someone else's.

- Needs `gh`, Python 3.10+ with a TOML reader, `jq`, a Slack MCP server (any,
  registered with `claude mcp add` or `/mcp`, with read channel, read thread,
  search, send and schedule tools), ListAgents and SendMessage, and the `/loop`
  trigger. `bash doctor.sh --skill comms-hub` checks each and says how to fix it
  (the harness's `doctor.sh --skill comms-hub` runs the same check from `~/.claude/skills-src`).
- Config in `~/.config/comms-hub/config.toml`, written by the skill's
  `hub.py init` from its `config.example.toml` with your GitHub login and time
  zone filled in; state in `~/.local/state/comms-hub/`. `install.sh` creates
  neither, and neither belongs in a repo.
- The protocol the comms session follows: [skills/comms-hub/SKILL.md](skills/comms-hub/SKILL.md).
  A peer's side, the draft it hands over, is the separate [slack-draft](skills/slack-draft/SKILL.md)
  skill, so a session that only sends Slack does not load the tick.
- A panel beside the comms session's chat (`skills/comms-hub/panel/`, a mod
  `hub.py launch` loads into that session alone): what needs you, what goes
  out and when, what is with other sessions, and what changed since you last
  looked, one line each, from `hub.py panel` as each turn ends and each minute
  while it is drawn, so it calls no model. `claude plugin test skills/comms-hub/panel`
  runs its tests; `.github/workflows/panel.yml` runs them daily on the newest Claude Code.

## skill-forge: one skill per recurring question

A skill for a new job's environment. It inventories, read-only, the systems
that answer operational questions (access and how to re-login, metrics, logs,
databases, schedulers, deploy tools, the repos that hold configs), mines
transcripts and shell history for the questions that keep coming up, and
drafts one skill per question from an archetype: sql-readonly, metrics-query,
logs-fetch, cluster-probe, job-run, api-readonly, runbook or local-repro. A
drafted skill is read-only by default, opens every output with where its
answer came from, masks identifiers that name customers, and tells an empty
answer from a missing metric, a partial one and an expired login.

- `skills/skill-forge/bin/skill_lint.py` checks any skill against the ten
  conventions. `tests/skill-lint.test.sh` runs it over every skill here; a
  finding is fixed, or waived in that skill's `lint-waivers.toml` with its reason.
- Config in `~/.config/skill-forge/config.toml`, from the skill's
  `config.example.toml`; state in `~/.local/state/skill-forge/`. A drafted
  skill installs to `~/.claude/skills` or a work repo, never into this one,
  which is public.
- The protocol: [skills/skill-forge/SKILL.md](skills/skill-forge/SKILL.md).
  `skills/skill-forge/tests/live_acceptance.py` runs the acceptance checks
  against Postgres and Prometheus in Docker.

## The other skills

- `pr-review`: writing, answering and requesting a review.
- `slack-draft`: how a session other than the comms session sends Slack.
- `memory-audit`: check memories against GitHub and Jira; runs the harness's `memory-verify.sh`.
- `memory-archive`: relieve an over-limit memory index; proposes, never deletes; runs `memory-index.sh`.

## Testing

`bash doctor.sh` runs every suite in `tests/` and prints a `SUMMARY:` line in
the harness's format. `tests/skill-lint.test.sh` lints the skills beside the
harness's `bin/` at a fixed release, read from `$CCH_HARNESS_CLONE` or
`~/.claude/harness-src`; it skips without one, except in CI. CI runs doctor on
Linux and macOS, shellcheck, and compiles every Python file with macOS's
`/usr/bin/python3` (3.9). Each skill's mutation list (`skills/<name>/tests/run.py --mutate`)
runs weekly (`.github/workflows/mutations.yml`).

## Repo layout

```
install.sh  doctor.sh    ← install into ~/.claude/skills; run every suite in tests/
CHANGELOG.md  LICENSE    ← one entry per release; MIT
skills/                  ← memory-audit/, memory-archive/, pr-review/, slack-draft/
  comms-hub/             ← SKILL.md, config.example.toml, bin/, panel/ (the comms panel mod),
                           tests/ (Python), forge.toml, lint-waivers.toml (not installed)
  skill-forge/           ← SKILL.md, config.example.toml, bin/, templates/ (installed to ~/.local/share),
                           tests/, forge.toml (not installed)
tests/                   ← install, repo-layout, and the skills' suites: comms-hub, comms-hub-prereqs,
                           skill-forge and skill-lint; lib.sh is their shared pass/fail
```

## License

MIT, in [LICENSE](LICENSE).
