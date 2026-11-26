# Releasing Nyx

Releases are built by GitHub Actions and published to **GitHub Releases**. Pushing a
tag that starts with `nyx-v` is the only thing that starts one: branch pushes, PRs and
the Actions UI never do.

---

## One-time setup (done)

### The `release` environment

The build job runs under the `release` environment, so every release pauses for your
approval. Under **Settings › Environments › release**:

- **Required reviewers**: `aristocrat71`.
- **Deployment branches and tags**: **Selected branches and tags**, with one rule of
  type **Tag**, pattern `nyx-v*`. A tag never satisfies "Protected branches only", so
  leaving that setting would fail every release the moment the build starts.

Check it from the terminal:

```bash
gh api repos/aristocrat71/nyx-app/environments/release --jq '.deployment_branch_policy'
# want: {"custom_branch_policies":true,"protected_branches":false}
gh api repos/aristocrat71/nyx-app/environments/release/deployment-branch-policies \
  --jq '.branch_policies[] | "\(.type) \(.name)"'
# want: tag nyx-v*
```

### Secrets

None. The workflow only uses the `GITHUB_TOKEN` every run gets. Builds are not
notarized: macOS apps are ad-hoc signed, which is why the site walks DMG users through
**Open Anyway** and why `install.sh` clears the quarantine flag itself.

---

## Cutting a release

**Starting point:** the changes are merged into `main`. `main` is protected: changes
go in through a pull request, which needs no approvals, so you can open and merge your
own.

### 1. Write the changelog as you merge

Each PR adds its user-facing changes under `## [Unreleased]` in `CHANGELOG.md`. At
release time that section becomes the GitHub Release body, word for word, so write it
for people downloading Nyx, not for the commit log. The heading and its date are never
published, only what sits below it.

### 2. Bump the version in a PR

Every release needs a new version, the same in all four files:

| File | Field |
|------|-------|
| `package.json` | `"version": "0.1.1"` |
| `src-tauri/tauri.conf.json` | `"version": "0.1.1"` |
| `src-tauri/Cargo.toml` | `version = "0.1.1"` |
| `src-tauri/Cargo.lock` | the `version` under `name = "nyx"` |

and turn `## [Unreleased]` into `## [0.1.1] - YYYY-MM-DD`. Then:

```bash
cargo check --manifest-path src-tauri/Cargo.toml   # updates Cargo.lock
git checkout -b release/v0.1.1
git commit -am "nyx: release v0.1.1"
git push origin release/v0.1.1
gh pr create --base main --fill && gh pr merge --merge
git checkout main && git pull origin main
```

### 3. Tag and push

Tag the bump commit **after** it is on `main`. Pushing the tag starts the build.

```bash
git tag nyx-v0.1.1
git push origin nyx-v0.1.1
```

### 4. Approve and watch

In the repo's **Actions** tab the run has two jobs:

1. **guard**, which fails within seconds and before asking for approval if:
   - the tag's commit is not on `main`,
   - any of `package.json`, `tauri.conf.json` or `Cargo.toml` disagrees with the tag, or
   - `CHANGELOG.md` has no `## [0.1.1]` section.
2. **release**, which waits until you click **Review deployments › release › Approve
   and deploy**, then builds and publishes.

---

## What a release publishes

- The installers, built by `tauri-action`. Today that is the universal macOS
  `Nyx_<version>_universal.dmg`.
- `Nyx.dmg`, a copy under a fixed name, so
  `https://github.com/aristocrat71/nyx-app/releases/latest/download/Nyx.dmg` (the
  site's download button) always serves the newest one.
- `Nyx-update.dmg`, the same file again, which only the in-app updater downloads, so
  updates are counted apart from new installs.
- A `<file>.sha256` beside each installer. `install.sh` refuses to install without a
  match.
- A build provenance attestation per installer, which ties the file to this repo and
  workflow run:

  ```bash
  gh attestation verify Nyx.dmg --repo aristocrat71/nyx-app
  ```

The install command fetches `install.sh` from `main`, so a change to the script
reaches users as soon as it is merged.

---

## Platforms

Only macOS is released for now, to save Actions minutes. To ship Windows and Linux,
add them to the `platform` list in `.github/workflows/release.yml`:

```yaml
platform: [macos-latest, ubuntu-22.04, windows-latest]
```

Everything else in the workflow already handles them. Then fill in the site's
Windows and Linux tabs, which say "Coming soon".

## Download stats

```bash
./scripts/release-stats.sh
```

Prints new installs per OS and updates for every release, from GitHub's download
counts. Nothing is sent from users' machines: an update is a download of
`Nyx-update.dmg`, a new install is a download of any other installer. The counts are
downloads, not people.

## Test builds

To try a branch on a real machine without releasing, run **test-build** by hand
(Actions › test-build › Run workflow, pick the branch). It builds unsigned installers
for all three platforms and attaches them to the run as artifacts: a `.dmg`, a `.deb`
and an AppImage, and an NSIS `-setup.exe`. Nothing is tagged or published.

## Redo a release

If a release failed or shipped wrong, fix it on `main`, then delete the release and its
tag and push the tag again:

```bash
gh release delete nyx-v0.1.1 --cleanup-tag --yes
git tag -d nyx-v0.1.1
git tag nyx-v0.1.1 && git push origin nyx-v0.1.1
```

Prefer a new patch version once anyone may have downloaded the old one.
