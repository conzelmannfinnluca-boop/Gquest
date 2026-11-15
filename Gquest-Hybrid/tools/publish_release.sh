#!/usr/bin/env bash
# Publish the built APK as a GitHub release.
#
# Needs an authenticated GitHub CLI on the machine that runs it: `gh auth login` once, or a
# GH_TOKEN in the environment with contents:write on the repository. The APK is far beyond the
# 100 MB single-file limit for the repository itself, so it can only go out as a release asset.
#
#   bash Gquest-Hybrid/tools/publish_release.sh
#
# Override with TAG=..., REPO=..., APK=... when publishing another build.
set -euo pipefail

REPO="${REPO:-conzelmannfinnluca-boop/Gquest}"
TAG="${TAG:-v0.1.30-gquest.2}"
TITLE="${TITLE:-Gquest 0.1.30-gquest.2}"
APK="${APK:-outputs/Gquest.apk}"
NOTES="${NOTES:-docs/RELEASE-v0.1.30-gquest.2.md}"

command -v gh >/dev/null || { echo "gh fehlt: https://cli.github.com/"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh ist nicht angemeldet: einmal 'gh auth login'"; exit 1; }
[ -f "$APK" ] || { echo "APK fehlt: $APK (erst bauen)"; exit 1; }
[ -f "$NOTES" ] || { echo "Release-Text fehlt: $NOTES"; exit 1; }

# The tag is created by the release itself, so no separate tag push is needed.
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "Release $TAG existiert, Assets werden ersetzt"
else
    gh release create "$TAG" --repo "$REPO" --title "$TITLE" --notes-file "$NOTES" --target main
fi
gh release upload "$TAG" "$APK#Gquest.apk" --repo "$REPO" --clobber
gh release view "$TAG" --repo "$REPO" --json url,assets --template '{{.url}}{{"\n"}}{{range .assets}}{{.name}} {{.size}} Bytes{{"\n"}}{{end}}'
