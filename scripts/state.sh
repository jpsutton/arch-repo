#!/usr/bin/env bash
# Prints one "<owner/repo> <tag>" line per source (sources.txt): its newest release.
# The publish workflow compares this with the published state.txt to tell whether
# anything changed. Needs gh and GH_TOKEN.
set -euo pipefail
cd "$(dirname "$0")/.."

while read -r slug _; do
  [[ -z $slug || $slug == \#* ]] && continue
  tag=$(gh release view -R "$slug" --json tagName -q .tagName)
  echo "$slug $tag"
done < sources.txt
