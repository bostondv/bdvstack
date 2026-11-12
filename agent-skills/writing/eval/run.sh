#!/usr/bin/env bash
# Score a rules version against the committed fixtures.
#   ./run.sh current            # score fixtures vs rewrites/current, compare to the last run
#   ./run.sh candidate --rewrite  # also regenerate rewrites/candidate with the current SKILL.md
set -euo pipefail
cd "$(dirname "$0")"
V="${1:-}"
if [ -z "$V" ]; then
  echo "usage: ./run.sh <rules-version> [--rewrite]"; exit 1
fi
if [ "${2:-}" = "--rewrite" ]; then
  mkdir -p "rewrites/$V"
  for f in fixtures/*.md; do
    out="rewrites/$V/$(basename "$f")"
    echo "rewriting $f -> $out"
    codex exec --skip-git-repo-check \
      "Rewrite the document on stdin following ../SKILL.md exactly. Keep every fact. Output markdown only." \
      < "$f" > "$out"
  done
fi
python3 score.py run "$V"
python3 report.py
