#!/usr/bin/env bash
# Branch preview: builds the web app for the site root and deploys it to a
# Firebase Hosting preview channel named after the current git branch.
#
#   scripts/preview.sh            # channel = current branch
#   scripts/preview.sh my-name    # channel = my-name
#
# The preview is a separate URL (https://tsevet-shir-shavtzak--<channel>-<hash>.web.app)
# and expires after 7 days. It talks to the SAME Firebase project as the real
# site (production data, the deployed `api` function): open it, do not test
# writes on it carelessly. It never touches GitHub Pages, which stays the
# production site and deploys only from `main` (.github/workflows/web.yml).
#
# sw.js is left unpinned on purpose (inert), so a preview is never cached on
# the device and every reload shows the newest deploy of the channel.
set -euo pipefail
# Git Bash on Windows would rewrite "/" into a Windows path.
export MSYS_NO_PATHCONV=1

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

raw="${1:-$(git rev-parse --abbrev-ref HEAD)}"
# Channel ids: lowercase letters, digits and '-', at most 63 characters.
channel="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//' | cut -c1-40)"
if [ -z "$channel" ] || [ "$channel" = "head" ] || [ "$channel" = "live" ]; then
  echo "Cannot derive a channel name from '$raw'; pass one: scripts/preview.sh <name>" >&2
  exit 1
fi

echo "==> Building web (base href /) ..."
(cd shavtzak && flutter build web --release --base-href /)

echo "==> Deploying to preview channel '$channel' (expires in 7 days) ..."
out="$(firebase hosting:channel:deploy "$channel" --expires 7d --json)"
url="$(printf '%s' "$out" | node -e '
  let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
    const j = JSON.parse(s);
    if (j.status !== "success") { console.error(s); process.exit(1); }
    const site = Object.values(j.result)[0];
    process.stdout.write(site.url);
  });')"

echo
echo "Preview: $url/#/whoami"
