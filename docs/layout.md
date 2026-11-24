# Repo layout

```
install.sh  doctor.sh    ← install into ~/.claude/skills; run every suite in tests/
CHANGELOG.md  LICENSE    ← one entry per release; MIT
docs/                    ← install, panel, testing and layout notes
skills/                  ← memory-audit/, memory-archive/, harness-checkup/, pr-review/, slack-draft/
  comms-hub/             ← SKILL.md, config.example.toml, bin/, panel/ (the comms panel mod),
                           tests/ (Python), forge.toml, lint-waivers.toml (not installed)
  skill-forge/           ← SKILL.md, config.example.toml, bin/, templates/ (installed to ~/.local/share),
                           tests/, forge.toml (not installed)
tests/                   ← install, repo-layout, and the skills' suites: comms-hub, comms-hub-prereqs,
                           skill-forge, skill-lint and harness-checkup; lib.sh is their shared pass/fail
```
