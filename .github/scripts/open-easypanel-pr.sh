#!/bin/bash
# Opens a PR on Easypanel's templates repo that points the osTicket template
# at the image tag for $VERSION. Run by the publish workflow after a new
# osTicket version is published.
#
# Needs: GH_TOKEN (classic token with public_repo), VERSION, OWNER.
# Optional: UPSTREAM, UPSTREAM_BRANCH (for testing), DRY_RUN=1 (show the
# change without pushing or opening a PR).
set -euo pipefail

UPSTREAM="${UPSTREAM:-easypanel-io/templates}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
FORK="${OWNER}/templates"
BRANCH="osticket-${VERSION}"
FILE=templates/osticket/meta.yaml
IMAGE="ghcr.io/${OWNER}/osticket"

if [ -z "${GH_TOKEN:-}" ] && [ -z "${DRY_RUN:-}" ]; then
    echo "::notice::TEMPLATES_PR_TOKEN is not set, so no Easypanel PR was opened"
    exit 0
fi

if [ -z "${DRY_RUN:-}" ] && [ -n "$(gh pr list --repo "$UPSTREAM" --head "$BRANCH" --state all --json number --jq '.[].number')" ]; then
    echo "A PR for $BRANCH already exists on $UPSTREAM"
    exit 0
fi

workdir=$(mktemp -d)
git clone -q --depth 1 --branch "$UPSTREAM_BRANCH" "https://github.com/${UPSTREAM}.git" "$workdir"
cd "$workdir"

if ! grep -q "default: ${IMAGE}:" "$FILE"; then
    echo "::notice::$UPSTREAM's osticket template doesn't use $IMAGE, so there is nothing to bump"
    exit 0
fi
if grep -q "default: ${IMAGE}:${VERSION}\$" "$FILE"; then
    echo "$UPSTREAM's template already uses ${IMAGE}:${VERSION}"
    exit 0
fi

sed -i "s|default: ${IMAGE}:[0-9.]*|default: ${IMAGE}:${VERSION}|" "$FILE"
python3 - "$FILE" "$VERSION" <<'EOF'
import datetime, sys
path, version = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
entry = (f"  - date: {datetime.date.today().isoformat()}\n"
         f"    description: Update to osTicket {version}\n")
if "\n\nlinks:" in text:
    text = text.replace("\n\nlinks:", "\n" + entry + "\nlinks:", 1)
open(path, "w", encoding="utf-8", newline="\n").write(text)
EOF

git --no-pager diff
if [ -n "${DRY_RUN:-}" ]; then
    exit 0
fi

login=$(gh api user --jq .login)
id=$(gh api user --jq .id)
git config user.name "$login"
git config user.email "${id}+${login}@users.noreply.github.com"
git checkout -q -b "$BRANCH"
git commit -q -am "osticket: update to osTicket ${VERSION}"

gh repo fork "$UPSTREAM" --clone=false >/dev/null 2>&1 || true
git push -q --force "https://x-access-token:${GH_TOKEN}@github.com/${FORK}.git" "$BRANCH"

gh pr create --repo "$UPSTREAM" --base "$UPSTREAM_BRANCH" --head "${OWNER}:${BRANCH}" \
    --title "osticket: update to osTicket ${VERSION}" \
    --body "Updates the osTicket template image to \`${IMAGE}:${VERSION}\`, built from the official osTicket ${VERSION} release: https://github.com/osTicket/osTicket/releases/tag/v${VERSION}

The image's build and changelog are at https://github.com/${OWNER}/osticket. This PR was opened automatically when the new version was published."
