#!/usr/bin/env bash
# The repo's shape: entry points executable, every skill on the README's layout
# lines, every repo path the README cites present, and each skill's tests/run.py
# skill-forge's own.
set -u
PASS=0; FAIL=0
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

echo "=== the entry points are executable ==="
for f in install.sh doctor.sh .github/install-apt-deps.sh; do
  [[ -x "$f" ]] && pass "$f" || fail "$f is not executable" "chmod +x $f"
done

echo ""
echo "=== every skill is on the README's layout lines ==="
BLOCK=$(cat docs/layout.md)
N=0
for d in skills/*/; do
  n=$(basename "$d"); N=$((N+1))
  grep -qE "(^|[ ,])$n/" <<<"$BLOCK" && pass "$n/" || fail "$n/ is not on the layout lines" ""
done
[[ "$N" -ge 6 ]] && pass "read $N skills" || fail "read $N skills" "expected six or more"

echo ""
echo "=== every repo path the README cites exists ==="
BROKEN="" CHECKED=0
while read -r ref; do
  case "$ref" in *'<'*|*'*'*|*'$'*) continue ;; esac
  CHECKED=$((CHECKED+1))
  [[ -e "$ref" ]] || BROKEN="$BROKEN $ref"
done < <(for f in README.md docs/*.md; do sed 's|~/\.[A-Za-z0-9._/-]*||g' "$f"; done \
         | sed 's|\.\./||g' \
         | grep -oE '(^|[^A-Za-z0-9._/-])(skills|tests|docs|\.github)/[A-Za-z0-9._/-]+' \
         | sed -E 's|^[^A-Za-z0-9._/-]||; s|[.,;:)]+$||' | sort -u)
[[ "$CHECKED" -ge 8 ]] && pass "checked $CHECKED references" || fail "checked $CHECKED references" "the extractor found almost nothing"
[[ -z "$BROKEN" ]] && pass "each resolves" || fail "references that resolve to nothing" "$BROKEN"

echo ""
echo "=== the README's skills table matches the tree ==="
# ROOT is overridable so a mutation can run against a scratch copy.
ROOT="${README_ROOT:-.}"
TBL=$(grep -E '^\| \[' "$ROOT/README.md")
cell() { awk -F'|' -v n="$2" '{gsub(/^ +| +$/,"",$n); print $n}' <<<"$1"; }  # cell 5 = Needs
for d in "$ROOT"/skills/*/; do
  n=$(basename "$d")
  row=$(grep -F "](skills/$n/SKILL.md)" <<<"$TBL" | head -1)
  if [[ -z "$row" ]]; then fail "$n has no table row linking its SKILL.md" ""; continue; fi
  pass "$n has a table row"
  needs=$(cell "$row" 5)
  uses=$(grep -E '^uses *= *\[' "$d/forge.toml" 2>/dev/null | grep -vE '\[ *\]' || true)
  if [[ -n "$uses" ]]; then want=harness; else want="-"; fi
  [[ "$needs" == "$want" ]] && pass "$n Needs is '$want'" || fail "$n Needs is '$needs', its forge.toml uses say '$want'" ""
done

echo ""
echo "=== the README's skill-forge counts match the tree ==="
SF=$(sed -n '/^## skill-forge/,/^## /p' "$ROOT/README.md")
NCHECK=$(grep -c '^def check_' "$ROOT/skills/skill-forge/bin/skill_lint.py")
NARCH=$(find "$ROOT/skills/skill-forge/templates" -mindepth 1 -maxdepth 1 -type d ! -name _shared | wc -l | tr -d ' ')
word() { case "$1" in 8) echo eight;; 9) echo nine;; 10) echo ten;; 11) echo eleven;; 12) echo twelve;; *) echo "$1";; esac; }
grep -qiE "\b$(word "$NCHECK") conventions" <<<"$SF" && pass "README says $(word "$NCHECK") conventions ($NCHECK def check_)" || fail "README does not say $(word "$NCHECK") conventions" "skill_lint.py has $NCHECK def check_"
grep -qiE "^$(word "$NARCH") archetypes:" <<<"$SF" && pass "README says $(word "$NARCH") archetypes" || fail "README does not say $(word "$NARCH") archetypes" ""
HAVE=$(grep -iE '^[A-Za-z]+ archetypes:' <<<"$SF" | sed 's/^[^:]*: *//; s/\.$//' | tr ',' '\n' | sed 's/^ *//; s/ *$//' | sort | tr '\n' ' ')
WANT=$(find "$ROOT/skills/skill-forge/templates" -mindepth 1 -maxdepth 1 -type d ! -name _shared -exec basename {} \; | sort | tr '\n' ' ')
[[ "$HAVE" == "$WANT" ]] && pass "archetype names equal templates/ dirs" || fail "archetype names differ from templates/" "README: $HAVE; tree: $WANT"

echo ""
echo "=== every skill's tests/run.py is skill-forge's, byte for byte ==="
# comms-hub's was an older copy (111 lines of diff): it copied only bin/ and
# tests/, so a mutation could not name a file elsewhere in the skill.
for f in skills/*/tests/run.py; do
  [[ "$f" == skills/skill-forge/tests/run.py ]] && continue
  cmp -s "$f" skills/skill-forge/tests/run.py && pass "$f is skill-forge's" || fail "$f differs from skill-forge's" "copy skills/skill-forge/tests/run.py over it"
done

results
