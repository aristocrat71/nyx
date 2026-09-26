# Releasing Nyx

Releases are built by GitHub Actions and published to **GitHub Releases** as a
notarized DMG. There is no auto-updater yet: a new version is a new download, so
the release page is the whole distribution channel.

The pipeline is **tag-triggered**: pushing a tag matching `nyx-v*` builds a
universal `Nyx.app`, signs and notarizes it, wraps it in a DMG and publishes the
Release. Nothing else (branch pushes, PRs, the Actions UI) can start it.

---

## Does anything need setting up on GitHub?

A tag push works today with **nothing configured** — but the DMG comes out
ad-hoc signed, and macOS refuses to open it until each user overrides Gatekeeper
by hand. Three of the four items below are worth doing before the first real
release; only the first costs money.

### 1. Developer ID signing and notarization (the one that matters)

Nyx asks for Screen Recording, and macOS keys that grant to the app's code
signature. An ad-hoc signature is not a stable identity: it makes the first
launch a Gatekeeper fight, and it means an update cannot inherit the permission
the user already granted. A **Developer ID Application** certificate (Apple
Developer Program, $99/yr) fixes both.

With the five secrets below present the release signs, notarizes and staples; with
them absent it still publishes, warns in the job log, and says "not notarized" in
the release body. Add them under **Settings → Secrets and variables → Actions**:

| Secret | Value |
|--------|-------|
| `APPLE_CERTIFICATE_P12` | the Developer ID Application certificate and key, exported from Keychain Access as `.p12`, base64-encoded: `base64 -i cert.p12 \| pbcopy` |
| `APPLE_CERTIFICATE_PASSWORD` | the password set on that export |
| `APPLE_ID` | the Apple ID the certificate belongs to |
| `APPLE_TEAM_ID` | the 10-character team id from the developer portal (not secret, a secret is just the simplest home for it) |
| `APPLE_APP_PASSWORD` | an app-specific password from appleid.apple.com — notarization refuses the account password |

The workflow imports the certificate into a throwaway keychain, signs with the
hardened runtime and a secure timestamp, and asks Apple to notarize both the app
and the DMG. Gatekeeper's own verdict is asserted before anything is published,
so a mis-signed build fails the release instead of shipping.

### 2. The `release` environment

The build job runs under `environment: release`. Left unconfigured, GitHub
auto-creates it with no gate and the release proceeds unattended. To make a
release pause for approval before the signing key is exposed, set under
**Settings → Environments → release**:

- **Required reviewers** — `aristocrat71`.
- **Deployment branches and tags** — **Selected branches and tags** with a rule of
  type **Tag**, pattern `nyx-v*`.

That second one is not optional once the environment exists. If it is left on
**Protected branches only**, every release fails the moment the build job starts:

```
Tag 'nyx-v0.1.0' is not allowed to deploy to release due to environment protection rules.
```

A tag is not a branch, so "protected branches only" can never be satisfied by a
tag-triggered run. From the CLI it takes two calls — and the first is a `PUT`
that **replaces the whole environment**, so it must restate the reviewer rule or
that protection is silently dropped with it:

```bash
gh api -X PUT repos/aristocrat71/nyx/environments/release --input - <<'JSON'
{
  "wait_timer": 0,
  "prevent_self_review": false,
  "reviewers": [{ "type": "User", "id": 68835436 }],
  "deployment_branch_policy": {
    "protected_branches": false,
    "custom_branch_policies": true
  }
}
JSON

gh api -X POST repos/aristocrat71/nyx/environments/release/deployment-branch-policies \
  -f name='nyx-v*' -f type=tag
```

`68835436` is `aristocrat71`'s user id — re-check with `gh api users/<login> --jq .id`.

### 3. A ruleset that pins released tags

A tag someone may already have installed must never change meaning, so block
deleting and moving `nyx-v*`:

```bash
gh api -X POST repos/aristocrat71/nyx/rulesets --input - <<'JSON'
{
  "name": "Release tags",
  "target": "tag",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/tags/nyx-v*"], "exclude": [] } },
  "rules": [{ "type": "deletion" }, { "type": "update" }, { "type": "non_fast_forward" }]
}
JSON
```

This is separate from the environment policy above and satisfies neither.

### 4. Branch protection on `main`

The `guard` job refuses to release a tag whose commit isn't on `main`, which only
means something if `main` is reached through PRs. A pull-request ruleset with 0
required approvals keeps that true without slowing a solo repo down:

```bash
gh api -X POST repos/aristocrat71/nyx/rulesets --input - <<'JSON'
{
  "name": "Protect main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": {
      "required_approving_review_count": 0,
      "dismiss_stale_reviews_on_push": false,
      "require_code_owner_review": false,
      "require_last_push_approval": false,
      "required_review_thread_resolution": false,
      "allowed_merge_methods": ["merge", "squash", "rebase"]
    }}
  ]
}
JSON
```

---

## Cutting a release

**Starting point:** your changes are committed on a feature branch.

### 1. Get the changes onto `main`

The release **must** be built from `main` — the `guard` job refuses a tag whose
commit isn't on it.

```bash
git push origin feat/your-branch
gh pr create --base main --head feat/your-branch --fill
gh pr merge --merge
git checkout main && git pull origin main
```

### 2. Bump the version and write the changelog

Two edits, and the release fails without either:

| File | What |
|------|------|
| `assets/Info.plist` | `CFBundleShortVersionString` — must equal the tag's version, or `guard` stops the release |
| `CHANGELOG.md` | a `## [X.Y.Z]` section — its body becomes the release notes |

The heading's date is never published, so `## [0.2.0] - Unreleased` is fine to
merge and tidy up later. Write the body for users, not for the commit log, and
lead with anything that changes behaviour by default.

```bash
git checkout -b release/v0.2.0
git add assets/Info.plist CHANGELOG.md
git commit -m "release: v0.2.0"
git push origin release/v0.2.0
gh pr create --base main --fill && gh pr merge --merge
git checkout main && git pull origin main
```

### 3. Tag and push

Tag the bump commit **after** it's on `main`. This is what triggers the build.

```bash
git tag nyx-v0.2.0
git push origin nyx-v0.2.0
```

### 4. Approve the deployment, then watch the build

The run has two stages:

1. **guard** — fails in seconds if the tag isn't on `main`, the plist version
   disagrees with the tag, or the changelog has no matching section.
2. **release** — sits in **Waiting** if you configured a reviewer. Click
   **Review deployments → release → Approve and deploy**; nothing builds until you
   do, and an unapproved run eventually expires.

### 5. Verify

The Releases page should carry `Nyx-X.Y.Z.dmg` and `Nyx-X.Y.Z.dmg.sha256`, and
the body should not say "not notarized". Then, on a Mac that has never run Nyx:

```bash
shasum -a 256 -c Nyx-X.Y.Z.dmg.sha256
spctl --assess --type open --context context:primary-signature -vv Nyx-X.Y.Z.dmg
gh attestation verify Nyx-X.Y.Z.dmg --repo aristocrat71/nyx
```

Open it, drag Nyx to Applications, launch it, and grant Screen Recording — a
notarized build should do all of that without a Gatekeeper detour.

---

## Redo a release (bad build / wrong commit)

With the tag ruleset in place **you can't re-tag** — deleting or moving `nyx-v*`
is rejected. A botched release is fixed forwards:

1. Delete the bad GitHub *Release* (`gh release delete nyx-v0.2.0 --yes`). The
   tag stays behind; that's expected.
2. Fix the problem and PR it to `main`.
3. Bump to the next patch (`0.2.1`) and tag that.

The exception is a run that failed *before* publishing anything (guard failed, or
the deployment was never approved): the tag exists but no Release does, so re-run
the workflow from the Actions tab.

---

## Testing the pipeline without cutting a release

`ci` runs on every PR and every push to `main`: tests, the universal bundle, and
the DMG — unsigned, since the signing key lives behind the `release`
environment. Dispatch it by hand (**Actions → ci → Run workflow**) on any branch
and it uploads `nyx-unsigned-dmg` as a run artifact to sideload.

Locally, the same two steps the release runs:

```bash
NYX_UNIVERSAL=1 NYX_VERSION=0.2.0 make app
make dmg
```

---

## Reference

- Workflows: `.github/workflows/release.yml`, `.github/workflows/ci.yml`
- Packaging: `scripts/make-app.sh`, `scripts/make-dmg.sh`, `scripts/notarize.sh`
- Version: `assets/Info.plist` → `CFBundleShortVersionString`
- Release notes: `CHANGELOG.md`
- Repo settings: Settings → Environments → `release`, Settings → Rules
