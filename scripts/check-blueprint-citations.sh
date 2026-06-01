#!/usr/bin/env bash
# check-blueprint-citations.sh
#
# Audits all file:line citations in docs/architecture/ to catch citation decay.
#
# Usage:
#   ./scripts/check-blueprint-citations.sh           # full audit
#   ./scripts/check-blueprint-citations.sh --quiet    # only print failures
#   ./scripts/check-blueprint-citations.sh --fix      # auto-repair drifted ANCHORED line numbers in place
#
# Exit codes:
#   0  all citations valid (or all repairable ones repaired under --fix)
#   1  one or more citations broken (file missing, line out of bounds, anchor
#      drifted [non-fix mode], or anchor missing entirely)
#
# ─────────────────────────────────────────────────────────────────────────
# TWO KINDS OF CITATION
#
# 1. PLAIN (legacy, bounds-only):
#      [GroupManagerView.swift:1207](../../Carry/Views/GroupManagerView.swift:1207)
#    Only checked for: file exists + line ≤ file length. CANNOT catch a line
#    that drifted but stayed in bounds (semantic drift). 183 of these exist.
#
# 2. ANCHORED (drift-proof — USE THESE for churning files like GroupManagerView):
#      [text](../../Carry/Views/GroupManagerView.swift:567 "func resolvedScorerIDs")
#    The link TITLE (the quoted string) is an ANCHOR: a substring that must
#    appear on (or within ANCHOR_WINDOW lines of) the cited line. The checker:
#      - anchor at the cited line (±window)  → PASS
#      - anchor found elsewhere in the file  → DRIFT: reports the correct line
#                                               (and rewrites it under --fix)
#      - anchor not found anywhere           → SEMANTIC BREAK (symbol renamed/
#                                               removed → the doc PROSE is now
#                                               wrong, code is truth: fix prose)
#
# WHY: line numbers into a 6,600-line churning file drift constantly and
# silently. Anchoring makes drift loud + self-healing. Migrate hot-file
# citations to anchored form as you touch them; `--fix` then keeps them honest
# automatically (the pre-push hook runs this checker).
#
# Intended to run in CI / pre-push on changes touching docs/architecture/,
# Carry/, or supabase/. When it fails, fix the docs — stale docs mislead.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_DIR="$REPO_ROOT/docs/architecture"
ANCHOR_WINDOW=4   # how many lines above/below the cited line the anchor may sit
QUIET=0
FIX=0

for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
    --fix)   FIX=1 ;;
  esac
done

if [[ ! -d "$DOCS_DIR" ]]; then
  echo "FAIL: $DOCS_DIR not found" >&2
  exit 1
fi

total=0
broken=0
repaired=0
broken_list=()
repaired_list=()

while IFS= read -r doc; do
  doc_dir="$(dirname "$doc")"

  # Each emitted record: "<path:line(-range)?>\t<anchor or empty>"
  while IFS=$'\t' read -r citation anchor; do
    [[ -z "$citation" ]] && continue

    rel_path="${citation%%:*}"
    line_part="${citation#*:}"
    line_num="${line_part%%-*}"

    # No colon → no line number; skip (bare file links are fine).
    [[ "$rel_path" == "$citation" ]] && continue

    abs_path="$doc_dir/$rel_path"
    if [[ ! -e "$abs_path" ]]; then
      alt_path="$REPO_ROOT/$rel_path"
      [[ -e "$alt_path" ]] && abs_path="$alt_path"
    fi

    total=$((total + 1))

    if [[ ! -f "$abs_path" ]]; then
      broken=$((broken + 1))
      broken_list+=("$(basename "$doc"): file not found → $rel_path")
      continue
    fi

    [[ "$line_num" =~ ^[0-9]+$ ]] || continue

    file_lines=$(wc -l < "$abs_path" | tr -d ' ')
    if (( line_num > file_lines )); then
      broken=$((broken + 1))
      broken_list+=("$(basename "$doc"): line $line_num exceeds $file_lines in $rel_path")
      continue
    fi

    # ── Plain citation (no anchor): bounds check already passed. Done. ──
    [[ -z "$anchor" ]] && continue

    # ── Anchored citation: verify the anchor sits at/near the cited line. ──
    # Find all 1-based line numbers whose content contains the anchor (literal).
    # Portable (no `mapfile` — this runs under bash via the shebang, but stay
    # POSIX-friendly in case it's sourced elsewhere).
    hits=()
    while IFS= read -r hn; do
      [[ -n "$hn" ]] && hits+=("$hn")
    done < <(grep -nF -- "$anchor" "$abs_path" | cut -d: -f1)

    if (( ${#hits[@]} == 0 )); then
      # Anchor gone entirely → the code the doc describes was renamed/removed.
      broken=$((broken + 1))
      broken_list+=("$(basename "$doc"): ANCHOR MISSING \"$anchor\" not found in $rel_path (semantic break — code changed, fix the prose; cited :$line_num)")
      continue
    fi

    # Already correct? (anchor within window of the cited line)
    within=0
    nearest="${hits[0]}"
    for h in "${hits[@]}"; do
      (( h >= line_num - ANCHOR_WINDOW && h <= line_num + ANCHOR_WINDOW )) && within=1
      # track the hit nearest the cited line for the self-heal suggestion
      local_d=$(( h > line_num ? h - line_num : line_num - h ))
      near_d=$(( nearest > line_num ? nearest - line_num : line_num - nearest ))
      (( local_d < near_d )) && nearest="$h"
    done

    if (( within == 1 )); then
      continue  # PASS
    fi

    # Drifted: anchor lives at `nearest`, not near `line_num`.
    if (( FIX == 1 )); then
      # Rewrite ONLY this citation's line number, on lines that carry this exact
      # anchor, swapping the precise `path:oldline` token for `path:newline`.
      # Pass values via ENV (single-quoted perl) to dodge all the shell/regex
      # quoting hazards of interpolating a path with `/` and `:` into -e.
      CIT_PATH="$rel_path" CIT_OLD="$line_num" CIT_NEW="$nearest" CIT_ANCHOR="$anchor" \
        perl -i -pe '
          my $a = quotemeta($ENV{CIT_ANCHOR});
          if (/"$a"/) {
            my $find = quotemeta("$ENV{CIT_PATH}:$ENV{CIT_OLD}");
            my $repl = "$ENV{CIT_PATH}:$ENV{CIT_NEW}";
            s/$find/$repl/g;
          }
        ' "$doc"
      repaired=$((repaired + 1))
      repaired_list+=("$(basename "$doc"): $rel_path :$line_num → :$nearest  (anchor \"$anchor\")")
    else
      broken=$((broken + 1))
      broken_list+=("$(basename "$doc"): DRIFTED $rel_path cited :$line_num but anchor \"$anchor\" is at :$nearest  (run --fix)")
    fi

  done < <(perl -ne '
    while (/\]\((\.\.\/[^()"]+\.(?:swift|sql|ts|md)(?::\d+(?:-\d+)?)?)(?:\s+"([^"]+)")?\)/g) {
      my $path = $1; my $anchor = defined($2) ? $2 : "";
      print "$path\t$anchor\n";
    }' "$doc")
done < <(find "$DOCS_DIR" -name "*.md" -type f)

if (( FIX == 1 && repaired > 0 )); then
  echo "Repaired $repaired drifted anchored citation(s):"
  for item in "${repaired_list[@]}"; do echo "  ✓ $item"; done
  echo
fi

if (( QUIET == 0 )); then
  summary="Citation audit: $total cited, $broken broken"
  (( FIX == 1 )) && summary="$summary, $repaired repaired"
  echo "$summary"
fi

if (( broken > 0 )); then
  echo
  echo "BROKEN CITATIONS:"
  for item in "${broken_list[@]}"; do
    echo "  - $item"
  done
  echo
  echo "Fix the docs and re-run. (Anchored drift: re-run with --fix to auto-repair.)"
  exit 1
fi

if (( QUIET == 0 )); then
  echo "All citations valid."
fi
exit 0
