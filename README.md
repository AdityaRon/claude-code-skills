# Claude Code Skills

Skills for Claude Code, one folder each under `skills/`. They install once per
machine into `~/.claude/skills`, so they load in every project without touching
repo files.

## The skills

| Skill | Use when | Not for | Needs |
|---|---|---|---|
| [comms-hub](skills/comms-hub/SKILL.md) | Running the recurring tick in the one long-lived comms session: GitHub queue, Slack replies, routing, gating and sending peers' drafts. | Any other session. | harness |
| [harness-checkup](skills/harness-checkup/SKILL.md) | Asked what costs the most on this machine, to check the setup, or why sessions are slow or expensive; relays the three largest costs. | General advice about Claude Code. | harness |
| [memory-archive](skills/memory-archive/SKILL.md) | Claude Code reports a MEMORY.md index over or near its read limit; proposes lines to archive, never deletions. | Routine maintenance. | harness |
| [memory-audit](skills/memory-audit/SKILL.md) | `memory-verify.sh` reports STALE or TRIAGE, or a memory's claim about a PR or ticket looks out of date. | Tidying or index size. | harness |
| [pr-review](skills/pr-review/SKILL.md) | Writing a PR review, answering review comments, deferring or asking for a review. | - | - |
| [skill-forge](skills/skill-forge/SKILL.md) | Starting in a new job's environment, finding the questions that keep coming up, turning one into a skill, or linting a skill. | A skill per database or tool; answering the question itself. | - |
| [slack-draft](skills/slack-draft/SKILL.md) | A session other than the comms session is about to send, answer, schedule or react to Slack; the draft goes to the comms session. | The comms session itself. | - |

## Check a skill of your own

```bash
python3 skills/skill-forge/bin/skill_lint.py SKILL_DIR
```

It checks the folder against skill-forge's ten conventions and exits 1 on a
FAIL. One caveat: the convention on `uses` needs the harness scripts on the
machine (see the docstring in `skill_lint.py`).

## Install

```bash
git clone https://github.com/AdityaRon/claude-code-skills.git
cd claude-code-skills
bash install.sh
```

With [claude-code-harness](https://github.com/AdityaRon/claude-code-harness), nothing to do: it pins a release of this repo and installs it. Needs macOS or Linux with bash and `git`; Python 3.10 or newer, `jq` and `gh` for comms-hub. Detail: [docs/install.md](docs/install.md).

## comms-hub

One long-lived session, the comms session, runs a tick on a `/loop` cron: it
reads GitHub and Slack and routes each event to the peer session that owns it.
It is the only session that sends Slack; a peer hands it a draft, and it checks
the draft before sending. It never approves a PR or merges someone else's.
Protocol, prerequisites and config: [SKILL.md](skills/comms-hub/SKILL.md).

## skill-forge

Drafts one skill per recurring question in a new job's environment, read-only, and every output opens with where its answer came from.
Eight archetypes: api-readonly, cluster-probe, job-run, local-repro, logs-fetch, metrics-query, runbook, sql-readonly.
`skill_lint.py` checks any skill against ten conventions; a finding is fixed, or waived with its reason.
Protocol and config: [SKILL.md](skills/skill-forge/SKILL.md).

## Limits and not measured

- Four of the seven skills (comms-hub, harness-checkup, memory-archive, memory-audit) do nothing useful without the harness.
- The Slack connector is your own; comms-hub and slack-draft need one registered.
- The skill lint skips locally when no harness clone is present; CI always runs it.
- No skill's effect has been measured: not time saved, not drafts stopped by the gate.

## Docs

[Install](docs/install.md) | [Panel](docs/panel.md) | [Testing](docs/testing.md) | [Repo layout](docs/layout.md) | [Changelog](CHANGELOG.md)

## License

MIT, in [LICENSE](LICENSE).
