# jpsutton Arch Linux repository

One signed pacman repository for my projects' Arch Linux packages:

| Package | Project |
| --- | --- |
| `patchbay`, `patchbayd` | [Patchbay](https://github.com/jpsutton/patchbay) |
| `omnimark` | [Omnimark](https://github.com/jpsutton/omnimark) |
| `nulamp` | [nulamp](https://github.com/jpsutton/nulamp) |

It always carries each project's newest release.

## Setup

The setup script adds `[jpsutton]` to `/etc/pacman.conf` and adds the repository key to the pacman keyring. If the downloaded key's fingerprint doesn't match, the script refuses it. It also removes the old per-project repositories (`[patchbay]`, `[omnimark]`, `[nulamp]` served from GitHub releases), which no longer get updates. You can run it again safely.

```bash
curl -fsSLO https://jpsutton.github.io/arch-repo/setup.sh
bash setup.sh --install patchbay
```

Without `--install` it only adds the repository. `--remove` removes the repository and the key.

To set it up by hand, add this to `/etc/pacman.conf`:

```ini
[jpsutton]
Server = https://jpsutton.github.io/arch-repo/$arch
```

Then trust the key and install:

```bash
curl -fsSLO https://jpsutton.github.io/arch-repo/jpsutton-signing-key.asc
sudo pacman-key --add jpsutton-signing-key.asc
sudo pacman-key --lsign-key 8476350364502FEDD331B66BEDB90079E3C73E41
sudo pacman -Sy patchbay
```

## How it works

Nothing is built here. The [publish workflow](.github/workflows/publish.yml) runs every hour and when a project's release workflow sends a `package-released` dispatch. It:

1. Finds each project's newest release ([sources.txt](sources.txt)). If none changed since the last publish, it stops.
2. Downloads the release's `*.pkg.tar.zst` and checks each one's signature against that project's release key ([keys/sources](keys/sources), pinned by fingerprint in `sources.txt`).
3. Signs every package and the database with the repository key and runs `repo-add` ([scripts/build-repo.sh](scripts/build-repo.sh)).
4. Deploys the result to GitHub Pages: `<arch>/jpsutton.db`, the packages and their signatures, the public key and the setup script.

The repository key's public half is [keys/jpsutton-signing-key.asc](keys/jpsutton-signing-key.asc). Its private half is the `ARCH_REPO_GPG_KEY` repository secret.

### Adding a project

1. Have its release workflow attach `*.pkg.tar.zst` files to the GitHub Release, each with a detached `.sig` from the project's release key.
2. Add its public key as `keys/sources/<repo>.asc` and a line to `sources.txt`.
3. Optionally, have its release workflow send a dispatch so the repository updates at once instead of within the hour:

   ```bash
   gh api repos/jpsutton/arch-repo/dispatches -f event_type=package-released
   ```

   That needs a token that can write to this repository (a fine-grained token with Contents: read and write), stored in the project as the `ARCH_REPO_DISPATCH_TOKEN` secret.
