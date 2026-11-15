#!/usr/bin/env bash
# Runs every test in tests/ and reports totals, in claude-code-harness's format.
# Exit code = number of suites that failed (at most 100).
#   bash doctor.sh --skill comms-hub   that skill's prerequisites instead
set -u
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

if [[ "${1:-}" == "--skill" ]]; then
  [[ -f "skills/${2:-}/bin/prereqs.sh" ]] || { echo "no prerequisite check for skill '${2:-}'" >&2; exit 2; }
  exec bash "skills/$2/bin/prereqs.sh"
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/ccs.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
TOTAL_SUITES=0 FAILED_SUITES=0 TOTAL_PASS=0 TOTAL_FAIL=0 UNCOUNTED="" TIMES=""
for f in tests/*.test.sh; do
  [[ -f "$f" ]] || continue
  TOTAL_SUITES=$((TOTAL_SUITES+1))
  echo ""
  echo "▶ $f"
  T0=$SECONDS
  bash "$f" > "$TMP/suite.out" 2>&1 < /dev/null
  STATUS=$?
  TIMES="$TIMES$((SECONDS - T0)) $f"$'\n'
  cat "$TMP/suite.out"
  line=$(grep -E '^-+ Results:' "$TMP/suite.out" | tail -1)
  p=$(printf '%s\n' "$line" | sed -nE 's/.* Results: ([0-9]+) passed.*/\1/p')
  ff=$(printf '%s\n' "$line" | sed -nE 's/.*passed, ([0-9]+) failed.*/\1/p')
  # A suite whose tally does not match counts 0 both ways; name it, so that
  # does not read as "ran and had nothing to report".
  [[ -n "$p" ]] || UNCOUNTED="$UNCOUNTED $f"
  TOTAL_PASS=$((TOTAL_PASS + ${p:-0}))
  TOTAL_FAIL=$((TOTAL_FAIL + ${ff:-0}))
  [[ "$STATUS" -eq 0 ]] || FAILED_SUITES=$((FAILED_SUITES+1))
done

echo ""
echo "SUMMARY: $TOTAL_SUITES suites │ $TOTAL_PASS passed │ $TOTAL_FAIL failed │ $FAILED_SUITES suite(s) failed"
if [[ -n "$UNCOUNTED" ]]; then
  echo "NOT COUNTED in the totals above (no '--- Results: N passed, M failed ---' line):$UNCOUNTED"
fi
echo "Slowest suites (wall seconds): $(printf '%s' "$TIMES" | sort -rn | head -5 | awk '{ sub("tests/", "", $2); sub(".test.sh", "", $2); printf "%s%s %s", (NR > 1 ? ", " : ""), $2, $1 }')"
N=$FAILED_SUITES; [[ $N -gt 100 ]] && N=100
exit "$N"
