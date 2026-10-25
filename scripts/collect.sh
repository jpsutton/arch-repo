#!/usr/bin/env bash
# Downloads the Arch packages and their signatures from the releases listed in a
# state file (scripts/state.sh) into <dir>/<repo>/.
#   collect.sh <state file> <dir>
# A release without packages is an error: publishing without them would drop the
# project from the repository. Needs gh and GH_TOKEN.
set -euo pipefail
state=${1:?state file}
dir=${2:?download dir}

while read -r slug tag; do
  name=${slug#*/}
  mkdir -p "$dir/$name"
  gh release download "$tag" -R "$slug" -D "$dir/$name" --clobber \
    -p '*.pkg.tar.zst' -p '*.pkg.tar.zst.sig'
  ls -la "$dir/$name"
done < "$state"
