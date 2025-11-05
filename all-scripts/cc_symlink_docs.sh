#!/bin/bash
set -euo pipefail

# Resolve script directory even when invoked via symlink
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
    DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
    TARGET="$(readlink "$SOURCE")"
    if [[ "$TARGET" == /* ]]; then
        SOURCE="$TARGET"
    else
        SOURCE="$DIR/$TARGET"
    fi
done
SCRIPT_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"

REPO_DOCS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/docs/git-docs"
TARGET_ROOT="$HOME/.claude/docs"

if [[ ! -d "$REPO_DOCS_DIR" ]]; then
    echo "❌ Repo docs directory not found: $REPO_DOCS_DIR" >&2
    exit 1
fi

mkdir -p "$TARGET_ROOT"

new_links=0
updated_links=0

while IFS= read -r -d '' file; do
    relative_path="${file#$REPO_DOCS_DIR/}"
    dest_path="$TARGET_ROOT/$relative_path"
    dest_dir="$(dirname "$dest_path")"
    mkdir -p "$dest_dir"

    if [[ -L "$dest_path" ]]; then
        current_target=$(readlink "$dest_path")
        if [[ "$current_target" == "$file" ]]; then
            printf 'Already linked: %s -> %s\n' "$file" "$dest_path"
            continue
        fi
        ln -snf "$file" "$dest_path"
        printf 'Updated link: %s -> %s (was -> %s)\n' "$file" "$dest_path" "$current_target"
        ((updated_links++))
        continue
    elif [[ -e "$dest_path" ]]; then
        printf 'Skipping existing non-symlink (manual review needed): %s\n' "$dest_path"
        continue
    fi

    ln -s "$file" "$dest_path"
    printf 'Linking: %s -> %s\n' "$file" "$dest_path"
    ((new_links++))
done < <(find "$REPO_DOCS_DIR" -type f -print0)

echo ""
echo "✓ Docs symlinked (new: $new_links, updated: $updated_links)"
echo "NEW_COUNT=$new_links"
echo "UPDATED_COUNT=$updated_links"
