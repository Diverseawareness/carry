#!/usr/bin/env bash
# check-blueprint-citations.sh
#
# Audits all file:line citations in docs/architecture/ to catch citation
# decay (file renamed/deleted, line number drifted out of bounds).
#
# Usage:
#   ./scripts/check-blueprint-citations.sh           # full audit
#   ./scripts/check-blueprint-citations.sh --quiet   # only print failures
#
# Exit codes:
#   0  all citations valid
#   1  one or more citations broken (file missing or line out of bounds)
#
# What this catches:
#   - File renamed or deleted (broken path)
#   - Line number drifted past the file's end
#
# What it does NOT catch:
#   - Line number drifted within the file (cite still valid syntactically
#     but points at the wrong code). Catching that requires semantic
#     verification — out of scope for this script.
#
# Intended to run in CI on PRs touching docs/architecture/ OR Carry/ OR
# supabase/. When it fails, fix the doc — stale docs are worse than no docs.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCS_DIR="$REPO_ROOT/docs/architecture"
QUIET=0

for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
  esac
done

if [[ ! -d "$DOCS_DIR" ]]; then
  echo "FAIL: $DOCS_DIR not found" >&2
  exit 1
fi

# Citation pattern: markdown links of the form [text](relative/path:LINE)
# or [text](relative/path:LINE-LINE2). We extract the path and the first line.
# Examples:
#   [GroupManagerView.swift:1207](../../Carry/Views/GroupManagerView.swift:1207)
#   [:1037-1067](../../Carry/Views/GroupManagerView.swift:1037)

total=0
broken=0
broken_list=()

while IFS= read -r doc; do
  # Extract every citation. The link target is the second parenthesized group.
  while IFS= read -r citation; do
    # citation is something like "../../Carry/Views/GroupManagerView.swift:1207"
    # or "../../Carry/Views/GroupManagerView.swift:1037-1067" — grab first line.
    rel_path="${citation%%:*}"
    line_part="${citation#*:}"
    line_num="${line_part%%-*}"

    # Skip if no line number was captured (path has no colon)
    if [[ "$rel_path" == "$citation" ]]; then
      continue
    fi

    # Resolve relative to the doc's directory
    doc_dir="$(dirname "$doc")"
    abs_path="$doc_dir/$rel_path"

    # Normalize (resolve ../)
    if [[ ! -e "$abs_path" ]]; then
      # Try resolving as if path is relative to repo root (some docs do this)
      alt_path="$REPO_ROOT/$rel_path"
      if [[ -e "$alt_path" ]]; then
        abs_path="$alt_path"
      fi
    fi

    total=$((total + 1))

    if [[ ! -f "$abs_path" ]]; then
      broken=$((broken + 1))
      broken_list+=("$(basename "$doc"): file not found → $rel_path")
      continue
    fi

    # Verify line number is within bounds
    if ! [[ "$line_num" =~ ^[0-9]+$ ]]; then
      continue
    fi

    file_lines=$(wc -l < "$abs_path" | tr -d ' ')
    if (( line_num > file_lines )); then
      broken=$((broken + 1))
      broken_list+=("$(basename "$doc"): line $line_num exceeds $file_lines in $rel_path")
    fi
  # Extract URL part of every markdown link [text](url). The URL must
  # contain a path with one of the listed extensions and (optionally) a
  # `:line` suffix. We use perl for non-greedy matching so we don't grab
  # nested brackets in the link text.
  done < <(perl -ne 'while (/\]\((\.\.\/[^()]+\.(?:swift|sql|ts|md)(?::\d+(?:-\d+)?)?)\)/g) { print "$1\n" }' "$doc")
done < <(find "$DOCS_DIR" -name "*.md" -type f)

if (( QUIET == 0 )); then
  echo "Citation audit: $total cited, $broken broken"
fi

if (( broken > 0 )); then
  echo
  echo "BROKEN CITATIONS:"
  for item in "${broken_list[@]}"; do
    echo "  - $item"
  done
  echo
  echo "Fix the docs and re-run."
  exit 1
fi

if (( QUIET == 0 )); then
  echo "All citations valid."
fi
exit 0
