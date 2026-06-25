#!/usr/bin/env bash
# Push standalone_audiobook_app/ from PlayTorrioV2 to https://github.com/killamfkr/Stories
set -euo pipefail

STORIES_REPO="${STORIES_REPO:-https://github.com/killamfkr/Stories.git}"
BRANCH="${STORIES_BRANCH:-stories-publish-main}"
PLAYTORRIO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$PLAYTORRIO_ROOT/standalone_audiobook_app"

if [[ ! -d "$SRC" ]]; then
  echo "Run from PlayTorrioV2 (standalone_audiobook_app/ not found under $PLAYTORRIO_ROOT)"
  exit 1
fi

has_subtree() {
  git subtree 2>&1 | grep -q 'usage: git subtree'
}

publish_with_subtree() {
  cd "$PLAYTORRIO_ROOT"
  echo "Using git subtree → branch $BRANCH"
  git subtree split --prefix=standalone_audiobook_app -b "$BRANCH"
  echo "Pushing to $STORIES_REPO (main)"
  git push "$STORIES_REPO" "$BRANCH:main"
}

publish_with_copy() {
  echo "git subtree not available — copying folder to a temp repo instead"
  echo "(Install optional: sudo apt install git-subtree  # Debian/Ubuntu)"

  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT

  rsync -a \
    --exclude='.dart_tool/' \
    --exclude='build/' \
    --exclude='android/' \
    --exclude='ios/' \
    --exclude='.flutter-plugins-dependencies' \
    "$SRC/" "$TMP/"

  cd "$TMP"
  if [[ ! -d .git ]]; then
    git init -b main
  fi

  git add -A
  if git diff --cached --quiet; then
    echo "No changes to publish."
  else
    git commit -m "Publish Stories from PlayTorrioV2"
  fi

  if git remote get-url origin &>/dev/null; then
    git remote set-url origin "$STORIES_REPO"
  else
    git remote add origin "$STORIES_REPO"
  fi

  echo "Pushing to $STORIES_REPO (main)"
  git push -u origin main
}

if has_subtree; then
  publish_with_subtree
else
  publish_with_copy
fi

echo "Done: https://github.com/killamfkr/Stories"
