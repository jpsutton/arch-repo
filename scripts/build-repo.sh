#!/usr/bin/env bash
# CI (publish): builds the signed pacman repository "jpsutton" from collected packages.
#   build-repo.sh <collected dir> <site dir>
# <collected dir>/<repo>/ holds each source's packages and their .sig (collect.sh).
# Every package must verify against its project's pinned release key (sources.txt,
# keys/sources/); it's then re-signed with the repository key, so pacman needs to
# trust only that one. Writes <site dir>/<arch>/ with the packages, signatures and
# jpsutton.db/.files ("any" packages go into every architecture), plus the public key.
# Needs ARCH_REPO_GPG_KEY (the armored private key; the workflow passes the repo
# secret). Runs in an archlinux container (repo-add).
set -euo pipefail
src=$(realpath "${1:?collected dir}")
mkdir -p "${2:?site dir}"
site=$(realpath "$2")
: "${ARCH_REPO_GPG_KEY:?ARCH_REPO_GPG_KEY is not set}"
repo=jpsutton
cd "$(dirname "$0")/.."

pacman -Sy --noconfirm --needed gnupg >/dev/null
export GNUPGHOME
GNUPGHOME=$(mktemp -d)
trap 'gpgconf --kill all; rm -rf "$GNUPGHOME"' EXIT

fingerprint() { gpg --batch --with-colons --show-keys "$1" | awk -F: '/^fpr/ {print $10; exit}'; }

# Check every package against its project's release key.
pkgs=()
while read -r slug fpr; do
  [[ -z $slug || $slug == \#* ]] && continue
  name=${slug#*/}
  key=keys/sources/$name.asc
  got=$(fingerprint "$key")
  [[ $got == "$fpr" ]] || { echo "error: $key is $got, sources.txt pins $fpr" >&2; exit 1; }
  gpg --batch --dearmor <"$key" >"$GNUPGHOME/$name.gpg"
  found=0
  for pkg in "$src/$name"/*.pkg.tar.zst; do
    [[ -e $pkg ]] || continue
    gpgv --quiet --keyring "$GNUPGHOME/$name.gpg" "$pkg.sig" "$pkg"
    pkgs+=("$pkg")
    found=1
  done
  ((found)) || { echo "error: no packages from $slug" >&2; exit 1; }
done < sources.txt

gpg --batch --quiet --import <<<"$ARCH_REPO_GPG_KEY"
fpr=$(gpg --batch --with-colons --list-secret-keys | awk -F: '/^fpr/ {print $10; exit}')
want=$(fingerprint "keys/$repo-signing-key.asc")
[[ $fpr == "$want" ]] || { echo "error: ARCH_REPO_GPG_KEY is $fpr, keys/$repo-signing-key.asc is $want" >&2; exit 1; }
echo "signing with $fpr"

# <name>-<version>-<rel>-<arch>.pkg.tar.zst
arch_of() { local base=${1##*/}; base=${base%.pkg.tar.zst}; echo "${base##*-}"; }
arches=()
for pkg in "${pkgs[@]}"; do
  a=$(arch_of "$pkg")
  [[ $a == any || " ${arches[*]} " == *" $a "* ]] || arches+=("$a")
done
((${#arches[@]})) || arches=(x86_64)

for a in "${arches[@]}"; do
  mkdir -p "$site/$a"
  for pkg in "${pkgs[@]}"; do
    pa=$(arch_of "$pkg")
    [[ $pa == "$a" || $pa == any ]] || continue
    out=$site/$a/${pkg##*/}
    [[ ! -e $out ]] || { echo "error: two sources ship ${pkg##*/}" >&2; exit 1; }
    cp "$pkg" "$out"
    gpg --batch --yes --detach-sign --no-armor "$out"
  done
  (
    cd "$site/$a"
    repo-add --sign --key "$fpr" "$repo.db.tar.zst" ./*.pkg.tar.zst
    # GitHub Pages serves symlinks badly; pacman fetches jpsutton.db and jpsutton.files.
    for link in "$repo.db" "$repo.db.sig" "$repo.files" "$repo.files.sig"; do
      [[ -L $link ]] && cp --remove-destination "$(readlink -f "$link")" "$link"
    done
    rm -f ./*.old ./*.old.sig
    # Prove it: every signature verifies against the repository key.
    for sig in ./*.sig; do
      gpg --batch --quiet --verify "$sig" "${sig%.sig}"
    done
    ls -la
  )
done

cp "keys/$repo-signing-key.asc" scripts/setup.sh "$site/"
