#!/usr/bin/env bash
# Generate distribution README with dynamic version information

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
README_FILE="$PROJECT_DIR/README.md"
DIST_README_FILE="$PROJECT_DIR/README.dist.md"
UI_FILE="$PROJECT_DIR/ui.qml"
DIST_UI_FILE="$PROJECT_DIR/ui.dist.qml"

# Check if README exists
if [ ! -f "$README_FILE" ]; then
    echo "Error: README.md not found"
    exit 1
fi

# Extract base version from README.md (looks for line like "**Version:** 1.0.0")
BASE_VERSION=$(grep -E '^\*\*Version:\*\*' "$README_FILE" | sed -E 's/^\*\*Version:\*\* //' | tr -d '\n\r')

if [ -z "$BASE_VERSION" ]; then
    echo "Error: Could not extract version from README.md"
    echo "Please ensure README.md contains a line like: **Version:** 1.0.0"
    exit 1
fi

# Get git information
GIT_HASH=$(git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
BRANCH_RAW="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
# Normalize: lowercase, replace / and _ with -, strip illegal chars, collapse dashes, trim edges
GIT_BRANCH="$(printf '%s' "$BRANCH_RAW" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's@[/_]+@-@g; s/[^a-z0-9.-]//g; s/-{2,}/-/g; s/^-+//; s/-+$//')"
# Fallback for detached HEAD or empty after sanitization
if [ -z "$GIT_BRANCH" ] || [ "$GIT_BRANCH" = "head" ]; then
  GIT_BRANCH="unknown"
fi
BUILD_DATE=$(date +%Y%m%d)
BUILD_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Build version string based on branch
if [ "$GIT_BRANCH" = "main" ]; then
    FULL_VERSION="${BASE_VERSION}-${BUILD_DATE}-${GIT_HASH}"
else
    FULL_VERSION="${BASE_VERSION}-${GIT_BRANCH}-${GIT_HASH}"
fi

# Create distribution README by copying source and replacing version line
cp "$README_FILE" "$DIST_README_FILE"

# Replace version and add build timestamp
sed "s|^\*\*Version:\*\* .*$|**Version:** \`${FULL_VERSION}\`|" "$DIST_README_FILE" > "$DIST_README_FILE.tmp"
sed "/^\*\*Version:\*\*/a\\
\\
**Built:** ${BUILD_TIMESTAMP}" "$DIST_README_FILE.tmp" > "$DIST_README_FILE"
rm -f "$DIST_README_FILE.tmp"

echo "✓ Generated $DIST_README_FILE with version: $FULL_VERSION"

# Create distribution ui by copying source and replacing version line
cp "$UI_FILE" "$DIST_UI_FILE"

# Replace version and add build timestamp
sed "s/\(readonly property string const_BLACKTIP_DPV_VERSION: \"\)<unknown>\(\"\)/\1${FULL_VERSION}\2/" "$DIST_UI_FILE" > "$DIST_UI_FILE.tmp"
sed "s/\(readonly property string const_BLACKTIP_DPV_RELEASE_DATE: \"\)<unknown>\(\"\)/\1${BUILD_TIMESTAMP}\2/" "$DIST_UI_FILE.tmp" > "$DIST_UI_FILE"
rm -f "$DIST_UI_FILE.tmp"

echo "✓ Generated $DIST_UI_FILE with version: $FULL_VERSION"
