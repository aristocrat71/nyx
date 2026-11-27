#!/usr/bin/env bash
# New installs vs updates per release and per OS, from GitHub's download counts.
# Updates are the updater's own Nyx-update.dmg; every other installer is a new install.
set -euo pipefail

REPO="${1:-unravel-team/nyx}"
for bin in gh jq column; do
  command -v "$bin" >/dev/null || { echo "release-stats: needs $bin" >&2; exit 1; }
done

raw=$(gh api "repos/$REPO/releases?per_page=100" --paginate | jq -s 'add')

read -r -d '' DEFS <<'JQ' || true
def update: . == "Nyx-update.dmg";
def mac:    test("\\.dmg$") and (update | not);
def win:    test("\\.(exe|msi)$");
def linux:  test("\\.(AppImage|deb|rpm)$");
def n(f):   [.assets[] | select(.name | f) | .download_count] | add // 0;
JQ

echo
echo "Nyx downloads, $REPO, $(date -u '+%Y-%m-%d %H:%M UTC')"
echo
{
  printf 'RELEASE\tPUBLISHED\tNEW MACOS\tNEW WINDOWS\tNEW LINUX\tUPDATES\n'
  jq -r "$DEFS"'.[] | [.tag_name, .published_at[:10], n(mac), n(win), n(linux), n(update)] | @tsv' <<<"$raw"
  jq -r "$DEFS"'["TOTAL", "-", ([.[] | n(mac)] | add), ([.[] | n(win)] | add), ([.[] | n(linux)] | add), ([.[] | n(update)] | add)] | @tsv' <<<"$raw"
} | column -t -s$'\t'

cat <<'NOTE'

  These count downloads, not people: a retried or abandoned download counts too.
  Only macOS updates itself so far, so Windows and Linux numbers are all new installs.
NOTE
