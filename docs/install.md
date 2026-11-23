# Install and update, in detail

Python 3.10 or newer with a TOML reader runs comms-hub and skill-forge and their tests; `skills/comms-hub/bin/python.sh` and `skills/skill-forge/bin/python.sh` pick the interpreter.

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
(`memory-verify.sh`, `memory-index.sh`, `session-route.sh`, `spend-report.py`, `harness-checkup.py`);
each skill's `forge.toml` lists them under `uses`.
