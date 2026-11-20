#!/usr/bin/env bash
# skill_lint (skills/skill-forge/bin/skill_lint.py) over every skill this repo
# ships. A finding is fixed, or waived in that skill's lint-waivers.toml with
# its reason; the lint fails a waiver with no reason, or one whose check now
# passes, so a waiver cannot outlive its finding. One result per skill.
# C10 needs the harness's bin/ (forge.toml uses), so the lint runs on a copy
# beside it; CI clones the harness and sets CCH_HARNESS_CLONE.
set -u
PASS=0; FAIL=0
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
fail(){ echo "  FAIL: $1"; printf '%s\n' "$2" | sed 's/^/        /'; FAIL=$((FAIL+1)); }
HARNESS_TAG=v1.4.19

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! PY=$(bash "$REPO/skills/skill-forge/bin/python.sh" 2>&1); then
  echo "  FAIL: $PY"
  echo "--- Results: 0 passed, 1 failed ---"
  exit 1
fi
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ccs.XXXXXX"); trap 'rm -rf "$TMP"' EXIT

H=""
for c in "${CCH_HARNESS_CLONE:-}" "$HOME/.claude/harness-src"; do
  [[ -n "$c" ]] && git -C "$c" cat-file -e "$HARNESS_TAG^{commit}" 2>/dev/null && { H=$c; break; }
done
if [[ -z "$H" ]]; then
  # A skip in CI would leave C10 unable to fail.
  if [[ -n "${CI:-}" ]]; then fail "a harness clone at $HARNESS_TAG" "set CCH_HARNESS_CLONE"
  else echo "  SKIP: no claude-code-harness clone holding $HARNESS_TAG; set CCH_HARNESS_CLONE to one"; fi
  echo "--- Results: $PASS passed, $FAIL failed ---"
  exit "$FAIL"
fi
C="$TMP/combo"
mkdir -p "$C"
cp -R "$REPO/skills" "$REPO/tests" "$C/"
git -C "$H" archive "$HARNESS_TAG" bin hooks | tar -x -C "$C"
git -C "$C" init -q

N=0
for s in "$C"/skills/*/; do
  [[ -f "$s/SKILL.md" ]] || continue
  N=$((N+1))
  name=$(basename "$s")
  # A config of the machine's own (its line_budget) must not change the verdict.
  if OUT=$(PYTHONDONTWRITEBYTECODE=1 SKILL_FORGE_CONFIG="$TMP/none.toml" "$PY" -B "$C/skills/skill-forge/bin/skill_lint.py" "$s" 2>&1); then
    # The verdict line, e.g. "PASS (0 FAIL, 3 WAIVED, 3 N/A)"; WARN is no failure but is shown.
    pass "$name: $(printf '%s\n' "$OUT" | grep -oE ': (PASS|WARN) \([^)]*\)$' | head -1 | cut -c3-)"
  else
    fail "$name" "$(printf '%s\n' "$OUT" | grep -E '^  C[0-9]+ +FAIL')"
  fi
done
[[ "$N" -ge 6 ]] && pass "linted $N skills beside the harness's bin/ at $HARNESS_TAG" || fail "linted $N skills" "expected every skill under skills/"

echo "--- Results: $PASS passed, $FAIL failed ---"
exit "$FAIL"
