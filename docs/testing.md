# Testing

`bash doctor.sh` runs every suite in `tests/` and prints a `SUMMARY:` line in
the harness's format. `tests/skill-lint.test.sh` lints the skills beside the
harness's `bin/` at a fixed release, read from `$CCH_HARNESS_CLONE` or
`~/.claude/harness-src`; it skips without one, except in CI. CI
(`.github/workflows/ci.yml`) runs doctor on Linux and macOS with Python 3.12,
shellcheck, and compiles every Python file with macOS's `/usr/bin/python3`
(3.9). Each skill's mutation list (`skills/<name>/tests/run.py --mutate`)
runs weekly (`.github/workflows/mutations.yml`, Mondays 05:23 UTC); the comms
panel's tests run daily (`.github/workflows/panel.yml`, 06:41 UTC).
