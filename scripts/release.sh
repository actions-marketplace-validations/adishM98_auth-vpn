#!/usr/bin/env bash
set -euo pipefail

# ── helpers ───────────────────────────────────────────────────────────────────

red()   { printf "\033[0;31m%s\033[0m\n" "$*"; }
green() { printf "\033[0;32m%s\033[0m\n" "$*"; }
bold()  { printf "\033[1m%s\033[0m\n" "$*"; }

# ── repo root ─────────────────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# ── pre-flight checks ─────────────────────────────────────────────────────────

if ! git diff --quiet || ! git diff --cached --quiet; then
  red "Working tree has uncommitted changes. Commit or stash them first."
  exit 1
fi

#── detect current version ────────────────────────────────────────────────────

CURRENT=$(git tag --sort=-version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)
if [[ -z "$CURRENT" ]]; then
  CURRENT="v0.0.0"
  echo "No existing tags found — starting from $CURRENT"
else
  echo "Current version: $(bold "$CURRENT")"
fi

# Strip leading 'v'
VERSION="${CURRENT#v}"
MAJOR=$(echo "$VERSION" | cut -d. -f1)
MINOR=$(echo "$VERSION" | cut -d. -f2)
PATCH=$(echo "$VERSION" | cut -d. -f3)

# ── choose bump type ──────────────────────────────────────────────────────────

echo ""
echo "Bump type:"
echo "  1) patch  → v$MAJOR.$MINOR.$((PATCH+1))"
echo "  2) minor  → v$MAJOR.$((MINOR+1)).0"
echo "  3) major  → v$((MAJOR+1)).0.0"
echo "  4) custom"
echo ""
read -rp "Choose [1]: " CHOICE
CHOICE="${CHOICE:-1}"

case "$CHOICE" in
  1) NEW_VERSION="$MAJOR.$MINOR.$((PATCH+1))" ;;
  2) NEW_VERSION="$MAJOR.$((MINOR+1)).0" ;;
  3) NEW_VERSION="$((MAJOR+1)).0.0" ;;
  4)
    read -rp "Enter version (without v): " NEW_VERSION
    if ! echo "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      red "Invalid version format. Use X.Y.Z"
      exit 1
    fi
    ;;
  *)
    red "Invalid choice"
    exit 1
    ;;
esac

NEW_TAG="v$NEW_VERSION"

echo ""
bold "Releasing $NEW_TAG"
echo ""
read -rp "Continue? [y/N]: " CONFIRM
if [[ "$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')" != "y" ]]; then
  echo "Aborted."
  exit 0
fi

# ── update Makefile version ───────────────────────────────────────────────────

sed -i.bak "s/^VERSION ?= .*/VERSION ?= $NEW_VERSION/" Makefile
rm -f Makefile.bak

# ── commit + tag + push ───────────────────────────────────────────────────────

git add Makefile
if ! git diff --cached --quiet; then
  git commit -m "chore: release $NEW_TAG"
fi

git tag -a "$NEW_TAG" -m "Release $NEW_TAG"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
git push origin "$BRANCH"
git push origin "$NEW_TAG"

# ── done ──────────────────────────────────────────────────────────────────────

echo ""
green "✓ Tagged and pushed $NEW_TAG"
echo ""

# ── build + publish via gh CLI ────────────────────────────────────────────────

if ! command -v gh >/dev/null 2>&1; then
  red "gh CLI not found (https://cli.github.com) — tag is pushed, but the release wasn't published."
  echo "Once gh is installed and authenticated (gh auth login), run:"
  echo ""
  echo "       make release VERSION=$NEW_VERSION"
  echo ""
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  red "gh CLI isn't authenticated — tag is pushed, but the release wasn't published."
  echo "Run 'gh auth login', then:"
  echo ""
  echo "       make release VERSION=$NEW_VERSION"
  echo ""
  exit 1
fi

echo "This will build all platform binaries and publish the GitHub release"
echo "for $NEW_TAG with gh, attaching:"
echo "  auth-vpn-linux-amd64, auth-vpn-darwin-amd64, auth-vpn-darwin-arm64, install.sh"
echo ""
read -rp "Build and publish now? [y/N]: " PUBLISH
if [[ "$(echo "$PUBLISH" | tr '[:upper:]' '[:lower:]')" != "y" ]]; then
  echo ""
  echo "Tag pushed, release not published. Run this when ready:"
  echo ""
  echo "       make release VERSION=$NEW_VERSION"
  echo ""
  exit 0
fi

echo ""
bold "Building all platforms and publishing release..."
echo ""
make release VERSION="$NEW_VERSION"

bold "Cleaning up build artifacts..."
make clean

echo ""
green "✓ Released $NEW_TAG"
echo "  GitHub → https://github.com/adishM98/auth-vpn/releases/tag/$NEW_TAG"
echo ""
