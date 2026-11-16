#!/usr/bin/env bash
# install.sh into temp HOMEs: what lands under ~/.claude/skills and the data
# dir, with the source's bytes and modes; configs left alone; files replaced by
# rename; and a release that drops a file removes only what this installer
# wrote and nobody changed. claude-code-harness's handover test checks the tree
# against the one its v1.4.2 installed.
set -u
PASS=0; FAIL=0
# shellcheck source-path=SCRIPTDIR source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh" || exit 1
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/ccs.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P)
unset XDG_CONFIG_HOME XDG_DATA_HOME SKILL_FORGE_TEMPLATES
export HOME="$TMP/home"
mkdir -p "$HOME"
S="$HOME/.claude/skills"
mode() { ls -ld "$1" | cut -c1-10; }
inode() { ls -i "$1" | awk '{print $1}'; }

# A copy of the working tree to change, so the repo itself is never touched.
R="$TMP/repo"
mkdir -p "$R"
( cd "$REPO" && git ls-files -co --exclude-standard -z | tar -cf - --null -T - ) | tar -xf - -C "$R"
[[ -f "$R/install.sh" && -f "$R/skills/comms-hub/SKILL.md" ]] || { echo "  FAIL: fixture copy"; results; }

CH_SENTINEL='# my comms-hub config, names a workspace'
mkdir -p "$HOME/.config/comms-hub"
printf '%s\n' "$CH_SENTINEL" > "$HOME/.config/comms-hub/config.toml"

echo "=== a first install: the harness's copy rules, the source's bytes and modes ==="
OUT=$(bash "$R/install.sh" 2>&1); RC=$?
[[ $RC == 0 ]] && pass "install exits 0" || fail "install exits 0" "rc=$RC $(tail -5 <<<"$OUT")"
# What the harness's install.sh copied, read from the tree: SKILL.md, *.example.toml
# and bin/* of each skill, and of a panel its manifest, hooks/ and types/.
EXPECT=$( cd "$R/skills" && for f in */SKILL.md */*.example.toml */bin/* */panel/.claude-plugin/plugin.json */panel/hooks/* */panel/types/*; do
            [[ -f "$f" ]] && printf '%s\n' "$f"; done | LC_ALL=C sort )
GOT=$(cd "$S" && find . -type f | sed 's|^\./||' | LC_ALL=C sort)
[[ -n "$EXPECT" && "$GOT" == "$EXPECT" ]] && pass "$(wc -l <<<"$GOT" | tr -d ' ') files, exactly the harness's set" \
  || fail "the installed set" "$(diff <(printf '%s\n' "$EXPECT") <(printf '%s\n' "$GOT") | head -8)"
BAD=""
while IFS= read -r f; do
  cmp -s "$R/skills/$f" "$S/$f" || BAD="$BAD bytes:$f"
  [[ "$(mode "$R/skills/$f")" == "$(mode "$S/$f")" ]] || BAD="$BAD mode:$f"
done <<<"$EXPECT"
[[ -z "$BAD" ]] && pass "each file holds the source's bytes and mode" || fail "bytes and modes" "$BAD"
[[ -x "$S/comms-hub/bin/check_draft.py" && ! -x "$S/comms-hub/bin/hub.py" ]] && pass "an executable script stays one, a 644 one stays 644" || fail "modes" "$(ls -l "$S/comms-hub/bin" | head -4)"
[[ -z "$(find "$S" \( -name tests -o -name 'test_*' -o -name '*.test.tsx' -o -name forge.toml -o -name lint-waivers.toml -o -name '*.tmpl' -o -name templates \))" ]] \
  && pass "no tests, manifests, waivers or templates under ~/.claude/skills" || fail "not installed" "$(find "$S" -name tests -o -name forge.toml | head -3)"
T="$HOME/.local/share/skill-forge/templates"
diff -r "$R/skills/skill-forge/templates" "$T" >/dev/null && pass "skill-forge's templates are in ~/.local/share/skill-forge/templates" \
  || fail "templates in the data dir" "$(diff -r "$R/skills/skill-forge/templates" "$T" 2>&1 | head -3)"
for n in comms-hub memory-archive memory-audit pr-review skill-forge slack-draft; do
  grep -qxF "  ✓ skills/$n" <<<"$OUT" || BAD="$BAD $n"
done
[[ -z "$BAD" ]] && pass "names each of the six skills" || fail "names each skill" "$BAD"
[[ "$(cat "$HOME/.config/comms-hub/config.toml")" == "$CH_SENTINEL" && "$(ls -A "$HOME/.config/comms-hub" | wc -l | tr -d ' ')" == 1 ]] \
  && ! grep -qF 'comms-hub is not configured' <<<"$OUT" \
  && pass "an existing comms-hub config is left byte for byte, and no hint" || fail "comms-hub config" "$(ls -A "$HOME/.config/comms-hub")"
[[ ! -e "$HOME/.config/skill-forge" ]] && grep -qF 'skill-forge is not configured' <<<"$OUT" \
  && pass "skill-forge's config is not created; a hint says how" || fail "skill-forge config" "$OUT"
[[ -f "$HOME/.claude/skills.manifest" && "$(wc -l < "$HOME/.claude/skills.manifest" | tr -d ' ')" == "$(wc -l <<<"$EXPECT" | tr -d ' ')" ]] \
  && pass "the record lists each file written, outside ~/.claude/skills" || fail "the record" "$(head -3 "$HOME/.claude/skills.manifest" 2>&1)"
grep -q '^version=' "$HOME/.claude/skills.version" && pass "skills.version written" || fail "skills.version" "$(cat "$HOME/.claude/skills.version" 2>&1)"
LEFT=$(find "$HOME/.claude" -name '.*' -type f | head -3)
[[ -z "$LEFT" ]] && pass "no temp file left behind" || fail "temp files" "$LEFT"

echo ""
echo "=== the installed skill-forge drafts from the installed templates ==="
SF="$S/skill-forge"
SF_PY=$(bash "$SF/bin/python.sh" 2>/dev/null)
F_OUT=$(SKILL_FORGE_STATE="$TMP/sf-state" "${SF_PY:-python3}" -B "$SF/bin/forge.py" list 2>&1)
grep -q '^sql-readonly ' <<<"$F_OUT" \
  && pass "the installed forge.py finds the installed templates" || fail "installed forge.py lists archetypes" "$(printf '%s' "$F_OUT" | head -3)"
SF_ENV=(SKILL_FORGE_STATE="$TMP/sf-state" SKILL_FORGE_CONFIG="$TMP/none.toml")
env "${SF_ENV[@]}" "${SF_PY:-python3}" -B "$SF/bin/forge.py" draft metrics-query job-latency --question "why is this job slow" >/dev/null 2>&1
V_OUT=$(env "${SF_ENV[@]}" "${SF_PY:-python3}" -B "$SF/bin/forge.py" verify "$TMP/sf-state/drafts/job-latency" --no-mutate 2>&1); V_RC=$?
[[ "$V_RC" == 0 ]] && grep -q '^skill_lint: PASS' <<<"$V_OUT" && grep -q '^tests: exit 0' <<<"$V_OUT" \
  && pass "the installed forge.py drafts a skill whose tests and lint pass" || fail "installed draft verifies" "$(printf '%s' "$V_OUT" | tail -5)"

echo ""
echo "=== a re-install replaces by rename and reports nothing changed ==="
I1=$(inode "$S/comms-hub/bin/hub.py")
exec 3< "$S/comms-hub/bin/hub.py"
OUT=$(bash "$R/install.sh" 2>&1)
[[ "$(inode "$S/comms-hub/bin/hub.py")" != "$I1" ]] && pass "hub.py replaced by rename (new inode)" || fail "rename" "same inode $I1"
cmp -s <(cat <&3) "$R/skills/comms-hub/bin/hub.py" && pass "a reader that opened the old hub.py reads it whole" || fail "old reader" ""
exec 3<&-
! grep -qE 'changed|Dropped' <<<"$OUT" && pass "nothing reported as changed or dropped" || fail "quiet re-install" "$OUT"

echo ""
echo "=== a release that drops files: only this installer's, unchanged, go ==="
mkdir -p "$S/mine" "$TMP/outside"
echo 'my own skill' > "$S/mine/SKILL.md"
echo 'my notes' > "$S/comms-hub/notes.md"
echo 'edited' >> "$S/slack-draft/SKILL.md"
mv "$S/memory-audit" "$TMP/outside/memory-audit" && ln -s "$TMP/outside/memory-audit" "$S/memory-audit"
rm -r "$R/skills/pr-review" "$R/skills/slack-draft" "$R/skills/memory-audit" "$R/skills/comms-hub/bin/slack_diff.py"
echo '// changed' >> "$R/skills/comms-hub/panel/hooks/register.tsx"
OUT=$(bash "$R/install.sh" 2>&1); RC=$?
[[ $RC == 0 ]] && pass "install exits 0" || fail "install exits 0" "rc=$RC"
[[ ! -e "$S/pr-review" && ! -e "$S/comms-hub/bin/slack_diff.py" ]] \
  && pass "a dropped skill and a dropped script go, and the emptied folder" || fail "dropped files removed" "$(ls -A "$S/pr-review" "$S/comms-hub/bin" 2>&1 | head -5)"
grep -qF "$S/comms-hub/bin/slack_diff.py" <<<"$OUT" && pass "the removal is named" || fail "removal named" "$OUT"
[[ -f "$S/mine/SKILL.md" && -f "$S/comms-hub/notes.md" ]] && pass "a skill of the user's own and a file added to comms-hub stay" || fail "foreign files" "$(ls -A "$S")"
[[ "$(tail -1 "$S/slack-draft/SKILL.md")" == edited ]] && grep -qF "slack-draft/SKILL.md (edited since install)" <<<"$OUT" \
  && pass "an edited file stays, and says why" || fail "edited file" "$OUT"
[[ -f "$TMP/outside/memory-audit/SKILL.md" ]] && grep -qF "outside ~/.claude/skills through a symlink" <<<"$OUT" \
  && pass "a file reached through a symlinked skill stays" || fail "symlinked skill" "$OUT"
grep -qF 'Skills changed' <<<"$OUT" && grep -qF "claude respawn <job>" <<<"$OUT" && grep -qF "$S/comms-hub/panel/hooks/register.tsx" <<<"$OUT" \
  && pass "a changed panel names the respawn" || fail "panel change" "$OUT"
! grep -qE 'again:.*/memory-archive' <<<"$OUT" && pass "an unchanged skill is not named" || fail "unchanged skill named" "$OUT"

echo ""
echo "=== the first install over a tree the harness installed: nothing removed, changes named ==="
# The harness's tree: this release's files, no record of this installer's, an
# older panel hook and a script an older harness shipped.
export HOME="$TMP/home2"; S="$HOME/.claude/skills"
bash "$REPO/install.sh" >/dev/null 2>&1; rm -f "$HOME/.claude/skills.manifest"
echo 'a script an older harness shipped' > "$S/comms-hub/bin/old_tool.py"
echo '// an older panel' > "$S/comms-hub/panel/hooks/register.tsx"
OUT=$(bash "$REPO/install.sh" 2>&1)
[[ -f "$S/comms-hub/bin/old_tool.py" ]] && ! grep -qF 'Dropped' <<<"$OUT" \
  && pass "no record of its own yet: nothing removed" || fail "first install over the harness's tree" "$OUT"
grep -qF "again: /comms-hub"$'\n' <<<"$OUT" && grep -qF "claude respawn <job>" <<<"$OUT" && grep -qF "$S/comms-hub/panel/hooks/register.tsx" <<<"$OUT" \
  && pass "the panel that differs from the harness's copy is named, and only its skill" || fail "first-run panel change" "$OUT"
! grep -qF 'old_tool.py' "$HOME/.claude/skills.manifest" && pass "and the record holds only what it wrote" || fail "record" ""

echo ""
echo "=== a first install into an empty tree reports no change ==="
export HOME="$TMP/home3"; S="$HOME/.claude/skills"
OUT=$(bash "$REPO/install.sh" 2>&1); RC=$?
[[ $RC == 0 ]] && ! grep -qE 'changed|Dropped' <<<"$OUT" && pass "nothing reported" || fail "empty first install" "rc=$RC $OUT"

results
