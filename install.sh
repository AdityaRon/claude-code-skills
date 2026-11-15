#!/usr/bin/env bash
# Installs the skills into ~/.claude/skills as claude-code-harness's install.sh
# did before the split: same paths, files and modes. Safe to re-run.
# Removes only files its own record (~/.claude/skills.manifest) says it wrote.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS="$HOME/.claude/skills"
MANIFEST="$HOME/.claude/skills.manifest"

# Live sessions read these while this runs: comms-hub's tick runs its bin/ every
# few minutes. cp rewrites a file in place, so a reader can catch it half written;
# place copies beside the target and renames it over. MODE, if given, is chmod's.
place() {  # SRC DEST [MODE]
  local tmp
  tmp=$(mktemp "$(dirname "$2")/.$(basename "$2").XXXXXX")
  if cp -p "$1" "$tmp" && { [[ -z "${3:-}" ]] || chmod "$3" "$tmp"; } && mv -f "$tmp" "$2"; then return 0; fi
  rm -f "$tmp"
  return 1
}

mkdir -p "$SKILLS"
WROTE=$(mktemp "$HOME/.claude/.skills.wrote.XXXXXX")
trap 'rm -f "$WROTE" "$WROTE.next"' EXIT
put() {  # SRC DEST: place it, and record DEST as written by this install
  place "$1" "$2"
  printf '%s\n' "${2#"$SKILLS"/}" >> "$WROTE"
}

# A skill's bin/ and *.example.toml go with its SKILL.md, by glob; its tests/
# stay in the clone. comms-hub reads ~/.config/comms-hub/config.toml, which
# this installer never creates or touches: it holds names a public repo cannot.
for skill in "$REPO"/skills/*/; do
  [[ -d "$skill" ]] || continue
  name=$(basename "$skill")
  mkdir -p "$SKILLS/$name"
  put "$skill"SKILL.md "$SKILLS/$name/SKILL.md"
  for f in "$skill"*.example.toml; do
    if [[ -f "$f" ]]; then put "$f" "$SKILLS/$name/$(basename "$f")"; fi
  done
  if [[ -d "$skill"bin ]]; then
    mkdir -p "$SKILLS/$name/bin"
    for f in "$skill"bin/*; do
      if [[ -f "$f" ]]; then put "$f" "$SKILLS/$name/bin/$(basename "$f")"; fi
    done
  fi
  # A skill's panel/ is a mod its own session loads (comms-hub's: hub.py launch
  # passes --plugin-dir); its tests stay, as do the types the engine writes.
  if [[ -d "$skill"panel ]]; then
    for f in "$skill"panel/.claude-plugin/plugin.json "$skill"panel/hooks/* "$skill"panel/types/*; do
      if [[ -f "$f" ]]; then
        rel=${f#"$skill"}
        mkdir -p "$SKILLS/$name/$(dirname "$rel")"
        put "$f" "$SKILLS/$name/$rel"
      fi
    done
  fi
  # A skill's templates/ (skill-forge's archetypes) go to the data dir, never
  # under ~/.claude/skills, so no template can be read as a skill. Copied whole
  # beside the old set and swapped in, so a removed template does not linger.
  if [[ -d "$skill"templates ]]; then
    data="${XDG_DATA_HOME:-$HOME/.local/share}/$name"
    mkdir -p "$data"
    rm -rf "$data/templates.new"
    cp -R "$skill"templates "$data/templates.new" && rm -rf "$data/templates" && mv "$data/templates.new" "$data/templates"
  fi
  echo "  ✓ skills/$name"
done
if [[ -d "$REPO/skills/comms-hub" && ! -f "${XDG_CONFIG_HOME:-$HOME/.config}/comms-hub/config.toml" ]]; then
  echo "  ℹ comms-hub is not configured (optional): the Setup section of ~/.claude/skills/comms-hub/SKILL.md"
  echo "     starts with hub.py init, which writes ~/.config/comms-hub/config.toml; then: bash $REPO/doctor.sh --skill comms-hub"
fi
# skill-forge reads ~/.config/skill-forge/config.toml (its mask patterns can name
# customers), which this installer never creates or touches either.
if [[ -d "$REPO/skills/skill-forge" && ! -f "${XDG_CONFIG_HOME:-$HOME/.config}/skill-forge/config.toml" ]]; then
  echo "  ℹ skill-forge is not configured (optional): copy ~/.claude/skills/skill-forge/config.example.toml"
  echo "     to ~/.config/skill-forge/config.toml and add your mask patterns"
fi

# ---- The record: "<blob> <path under ~/.claude/skills>", one per file written --
# The blob is git's hash of the installed bytes, so a later run can tell a file
# it wrote from one edited since.
LC_ALL=C sort -u "$WROTE" -o "$WROTE"
( cd "$SKILLS" && git hash-object --no-filters --stdin-paths < "$WROTE" ) | paste -d' ' - "$WROTE" > "$WROTE.next"

# ---- What changed, and what a release dropped --------------------------------
# Only against an earlier record of this script's own. The first run over a tree
# claude-code-harness installed has none, so it removes nothing: the harness's
# copies are this release's files, byte for byte, and the record starts here.
CHANGED="" PANEL="" REMOVED="" KEPT=""
if [[ -f "$MANIFEST" ]]; then
  REAL=$(cd "$SKILLS" && pwd -P)
  while read -r rel; do
    [[ -n "$rel" ]] || continue
    s=${rel%%/*}
    case " $CHANGED " in *" /$s "*) ;; *) CHANGED="$CHANGED /$s" ;; esac
    [[ "$rel" == */panel/* ]] && PANEL="$PANEL  $SKILLS/$rel"
  done < <(awk 'NR == FNR { old[$2] = $1; next } old[$2] != $1 { print $2 }' "$MANIFEST" "$WROTE.next")
  while read -r blob rel; do
    [[ -n "${rel:-}" && "$rel" != *..* && "$rel" != /* ]] || continue
    dest="$SKILLS/$rel"
    # Renamed only in case: on a disk that ignores case it is the file just written.
    w=$(grep -ixF -- "$rel" "$WROTE" | head -1) || w=""
    [[ -n "$w" && "$dest" -ef "$SKILLS/$w" ]] && continue
    [[ -e "$dest" || -L "$dest" ]] || continue
    dir=$(cd "$(dirname "$dest")" 2>/dev/null && pwd -P) || dir=""
    if [[ -z "$dir" || ( "$dir" != "$REAL" && "$dir" != "$REAL"/* ) ]]; then KEPT="$KEPT  $dest (outside ~/.claude/skills through a symlink)"
    elif [[ ! -f "$dest" || -L "$dest" ]]; then KEPT="$KEPT  $dest (not the plain file this wrote)"
    elif [[ "$(git hash-object --no-filters -- "$dest")" != "$blob" ]]; then KEPT="$KEPT  $dest (edited since install)"
    elif rm -f -- "$dest"; then
      REMOVED="$REMOVED  $dest"
      # Its folders too, once empty; rmdir never removes one that is not.
      d=$(dirname "$dest")
      while [[ "$d" == "$SKILLS"/?* ]] && rmdir "$d" 2>/dev/null; do d=$(dirname "$d"); done
    else KEPT="$KEPT  $dest (could not remove)"
    fi
  done < <(awk 'NR == FNR { new[$2] = 1; next } !($2 in new)' "$WROTE.next" "$MANIFEST")
fi
mv -f "$WROTE.next" "$MANIFEST"
[[ -n "$CHANGED" ]] && echo "  Skills changed, picked up when a running session calls them again:$CHANGED"
[[ -n "$PANEL" ]] && echo "  A panel changed, picked up when the session that shows it restarts: type \`! claude respawn <job>\` at your own prompt (from another session the auto-mode classifier denies it):$PANEL"
[[ -n "$REMOVED" ]] && echo "  Dropped by this release, and removed because this installer wrote it and nothing changed it:$REMOVED"
[[ -n "$KEPT" ]] && echo "  Dropped by this release; the earlier copy stays until removed by hand:$KEPT"

# ---- Installed version: written last ------------------------------------------
# claude-code-harness's skills-sync.sh compares commit= with the commit it pins.
VER=$(git -C "$REPO" describe --tags --match 'v[0-9]*' --always --dirty 2>/dev/null || echo unknown)
ORIGIN=$(git -C "$REPO" remote get-url origin 2>/dev/null || true)
{
  echo "version=$VER"
  echo "commit=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "repo=$REPO"
  if [[ -n "$ORIGIN" ]]; then echo "origin=$ORIGIN"; fi
  echo "installed=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$HOME/.claude/skills.version"
echo "  ✓ skills.version ($VER)"
