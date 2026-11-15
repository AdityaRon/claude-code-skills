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
BLOCK=$(sed -n '/^## Repo layout/,/^## /p' README.md)
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
done < <(sed 's|~/\.[A-Za-z0-9._/-]*||g' README.md \
         | grep -oE '(^|[^A-Za-z0-9._/-])(skills|tests|\.github)/[A-Za-z0-9._/-]+' \
         | sed -E 's|^[^A-Za-z0-9._/-]||; s|[.,;:)]+$||' | sort -u)
[[ "$CHECKED" -ge 8 ]] && pass "checked $CHECKED references" || fail "checked $CHECKED references" "the extractor found almost nothing"
[[ -z "$BROKEN" ]] && pass "each resolves" || fail "references that resolve to nothing" "$BROKEN"

echo ""
echo "=== every skill's tests/run.py is skill-forge's, byte for byte ==="
# comms-hub's was an older copy (111 lines of diff): it copied only bin/ and
# tests/, so a mutation could not name a file elsewhere in the skill.
for f in skills/*/tests/run.py; do
  [[ "$f" == skills/skill-forge/tests/run.py ]] && continue
  cmp -s "$f" skills/skill-forge/tests/run.py && pass "$f is skill-forge's" || fail "$f differs from skill-forge's" "copy skills/skill-forge/tests/run.py over it"
done

results
