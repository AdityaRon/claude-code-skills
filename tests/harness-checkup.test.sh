#!/usr/bin/env bash
# skills/harness-checkup/SKILL.md against the script it relays. The command it
# runs is taken from the SKILL.md and run against a fake harness-checkup.py in
# a temp HOME; the flags, scripts and fixes it names are checked against the
# harness at the commit skill-lint pins; its three rules must be present. Each
# check is then run on a mutated copy of the SKILL.md, and must go red.
set -u
PASS=0; FAIL=0
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SK="$REPO/skills/harness-checkup/SKILL.md"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ccs-hc.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
HARNESS_REF=$(sed -n 's/^HARNESS_TAG=//p' "$REPO/tests/skill-lint.test.sh")

H=""
for c in "${CCH_HARNESS_CLONE:-}" "$HOME/.claude/harness-src"; do
  [[ -n "$c" ]] && git -C "$c" cat-file -e "$HARNESS_REF^{commit}" 2>/dev/null && { H=$c; break; }
done

mkdir -p "$TMP/home/.claude"
cat > "$TMP/home/.claude/harness-checkup.py" <<'PY'
import sys
print("harness-checkup, fake: " + " ".join(sys.argv[1:]))
PY

# check SKILL_MD: prints one line per failed check
check() {
  local f=$1 cmd out
  cmd=$(grep -oE 'python3 ~/\.claude/harness-checkup\.py' "$f" | head -1)
  if [[ -z "$cmd" ]]; then echo "no harness-checkup.py command"; else
    out=$(cd "$TMP" && HOME="$TMP/home" bash -c "${cmd/\~/$TMP/home} --days 3" 2>&1) \
      && [[ "$out" == "harness-checkup, fake: --days 3" ]] || echo "the command does not run against the fake: $out"
  fi
  grep -qiE 'missing.*not installed.*stop' <(tr '\n' ' ' < "$f") || echo "no stop when the script is missing"
  grep -qE 'Never read raw transcripts' "$f" || echo "rule: no raw transcripts"
  grep -qE 'Never print a dollar amount' "$f" || echo "rule: no dollar amounts"
  grep -qE 'Never clone, install, or use the network' "$f" || echo "rule: no clone, install or network"
  grep -qE 'doctor\.sh --latency' "$f" || echo "no guard fix (doctor.sh --latency)"
  grep -qE 'disk-space\.py prune' "$f" || echo "no job folder fix (disk-space.py prune)"
  grep -qE 'memory-archive' "$f" || echo "no memory fix (memory-archive)"
  grep -qE 'docs/long-running-sessions\.md' "$f" || echo "no ttl-gap doc"
  grep -qE 'docs/permission-friction\.md' "$f" || echo "no permission-friction doc"
  grep -qE '\$[0-9]' "$f" && echo "a dollar amount in the text"
  grep -qE '(^|[^a-z-])(curl|wget|git clone|pip install|brew install)([^a-z-]|$)' "$f" && echo "a network or install command in the text"
  return 0
}

echo "=== SKILL.md runs the fake and carries its rules ==="
R=$(check "$SK")
[[ -z "$R" ]] && pass "no findings" || fail "findings" "$R"

echo ""
echo "=== what it names exists in the harness at $HARNESS_REF ==="
if [[ -z "$H" ]]; then
  if [[ -n "${CI:-}" ]]; then fail "a harness clone holding $HARNESS_REF" "set CCH_HARNESS_CLONE"
  else echo "  SKIP: no harness clone holding $HARNESS_REF; set CCH_HARNESS_CLONE to one"; fi
else
  DOC=$(git -C "$H" show "$HARNESS_REF:bin/harness-checkup.py" 2>&1 | sed -n '1,25p')
  for flag in --days --json; do
    grep -qF -- "$flag" "$SK" && grep -qF -- "$flag" <<<"$DOC" && pass "$flag is in the SKILL.md and the script's docstring" || fail "$flag" "missing from one of them"
  done
  for d in docs/long-running-sessions.md docs/permission-friction.md bin/disk-space.py; do
    git -C "$H" cat-file -e "$HARNESS_REF:$d" 2>/dev/null && pass "$d exists" || fail "$d" "not in the harness at $HARNESS_REF"
  done
  git -C "$H" show "$HARNESS_REF:doctor.sh" | grep -qE -- '--latency\)' && pass "doctor.sh takes --latency" || fail "doctor.sh --latency" "no such option"
fi

echo ""
echo "=== a mutated SKILL.md goes red ==="
mut() {  # NAME SED-EXPR
  sed "$2" "$SK" > "$TMP/mut.md"
  cmp -s "$SK" "$TMP/mut.md" && { fail "mutation $1" "did not change the file"; return; }
  [[ -n "$(check "$TMP/mut.md")" ]] && pass "mutation $1 is caught" || fail "mutation $1 survives" ""
}
mut "script renamed" 's/harness-checkup\.py`/harness-check.py`/'
mut "dollar rule dropped" 's/Never print a dollar amount/Print what you like/'
mut "network rule dropped" 's/Never clone, install, or use the network/Clone if needed/'
mut "transcript rule dropped" 's/Never read raw transcripts/Read transcripts/'
mut "guard fix dropped" 's/doctor\.sh --latency/doctor.sh/'
mut "a dollar amount added" 's/^# Harness checkup$/# Harness checkup ($12)/'
mut "an install command added" 's/^# Harness checkup$/# Harness checkup (pip install x)/'
mut "no stop when missing" 's/say the harness is not installed and stop/carry on/'

results
