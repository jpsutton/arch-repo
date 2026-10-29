#!/usr/bin/env bash
# Adds the jpsutton pacman repository (Patchbay, Omnimark, nulamp, FreeCell) to this Arch
# Linux system.
#
#   setup.sh                    add the repo, trust the key, sync
#   setup.sh --install PKG...   ...and install those packages
#   setup.sh --remove           undo: drop the repo and the key
#
# It also removes the old per-project repositories ([patchbay], [omnimark],
# [nulamp] served from GitHub releases), which no longer publish a database.
# Safe to run again: it only adds what's missing. Re-runs itself with sudo.
set -euo pipefail

REPO_NAME=jpsutton
BASE_URL=https://jpsutton.github.io/arch-repo
# pacman expands $arch itself.
SERVER="$BASE_URL/\$arch"
KEY_URL=$BASE_URL/jpsutton-signing-key.asc
# The repository key; a downloaded key is only trusted if it matches this.
FINGERPRINT=8476350364502FEDD331B66BEDB90079E3C73E41
LEGACY_REPOS=(patchbay omnimark nulamp)
PACMAN_CONF=${PACMAN_CONF:-/etc/pacman.conf}

action=add
packages=()
case ${1:-} in
  '') ;;
  --install)
    action=install
    shift
    packages=("$@")
    ((${#packages[@]})) || { echo "error: --install needs package names" >&2; exit 2; }
    ;;
  --remove) action=remove ;;
  -h | --help)
    sed -n '2,11s/^# \{0,1\}//p' "$0"
    exit 0
    ;;
  *)
    echo "unknown option: $1 (try --help)" >&2
    exit 2
    ;;
esac

if [[ $EUID -ne 0 ]]; then
  # Through bash, so it also works when run as `bash setup.sh`.
  exec sudo --preserve-env=PACMAN_CONF bash "$0" "$@"
fi

log() { printf '==> %s\n' "$*"; }

has_section() { grep -q "^\[$1\]" "$PACMAN_CONF"; }

# One backup per run, of the file as it was before this run touched it.
backed_up=0
backup() {
  ((backed_up)) || cp -a "$PACMAN_CONF" "$PACMAN_CONF.$REPO_NAME.bak"
  backed_up=1
}

# Deletes a section header and its lines up to the next section.
remove_section() {
  log "Removing [$1] from $PACMAN_CONF (backup: $PACMAN_CONF.$REPO_NAME.bak)"
  backup
  local tmp
  tmp=$(mktemp)
  awk -v name="[$1]" '
    $0 == name { skip = 1; next }
    /^\[/ { skip = 0 }
    !skip
  ' "$PACMAN_CONF" > "$tmp"
  cat "$tmp" > "$PACMAN_CONF"
  rm -f "$tmp"
}

# Only the old GitHub-release repositories: a [patchbay] section pointing anywhere
# else is someone's own and stays.
remove_legacy() {
  local name
  for name in "${LEGACY_REPOS[@]}"; do
    if awk -v name="[$name]" -v url="github.com/jpsutton/$name/releases/" '
         $0 == name { in_section = 1; next }
         /^\[/ { in_section = 0 }
         in_section && index($0, url) { found = 1 }
         END { exit !found }
       ' "$PACMAN_CONF"; then
      remove_section "$name"
    fi
  done
}

remove_repo() {
  has_section "$REPO_NAME" && remove_section "$REPO_NAME"
  if pacman-key --list-keys "$FINGERPRINT" >/dev/null 2>&1; then
    log "Removing key $FINGERPRINT from the pacman keyring"
    pacman-key --delete "$FINGERPRINT"
  fi
  log "Done. Installed packages are untouched: pacman -Rns <package> to remove them."
}

trust_key() {
  if pacman-key --list-keys "$FINGERPRINT" >/dev/null 2>&1; then
    log "Repository key $FINGERPRINT is already in the pacman keyring"
  else
    local tmp
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' RETURN
    log "Downloading the repository key"
    curl -fsSL --retry 3 -o "$tmp/key.asc" "$KEY_URL"
    local got
    got=$(gpg --batch --with-colons --show-keys "$tmp/key.asc" 2>/dev/null | awk -F: '/^fpr/ {print $10; exit}')
    if [[ $got != "$FINGERPRINT" ]]; then
      echo "error: downloaded key has fingerprint '${got:-none}', expected $FINGERPRINT; not trusting it" >&2
      exit 1
    fi
    pacman-key --add "$tmp/key.asc" >/dev/null
  fi
  # Locally sign it so pacman trusts packages signed with it.
  pacman-key --lsign-key "$FINGERPRINT" >/dev/null
  log "Repository key trusted"
}

add_repo() {
  if has_section "$REPO_NAME"; then
    log "[$REPO_NAME] is already in $PACMAN_CONF"
    return
  fi
  log "Adding [$REPO_NAME] to $PACMAN_CONF (backup: $PACMAN_CONF.$REPO_NAME.bak)"
  backup
  printf '\n[%s]\nServer = %s\n' "$REPO_NAME" "$SERVER" >> "$PACMAN_CONF"
}

if [[ $action == remove ]]; then
  remove_repo
  exit 0
fi

command -v pacman-key >/dev/null || { echo "error: this is not an Arch-based system (no pacman-key)" >&2; exit 1; }
trust_key
remove_legacy
add_repo
log "Syncing package databases"
pacman -Sy
if [[ $action == install ]]; then
  log "Installing ${packages[*]}"
  pacman -S --needed --noconfirm "${packages[@]}"
else
  pacman -Sl "$REPO_NAME"
  log "Ready. Install with: sudo pacman -S <package>"
fi
