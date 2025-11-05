#!/bin/bash
# Update Claude Code docs mirror and refresh local copies in the repo
set -euo pipefail

# Resolve directory even when invoked via symlink from ~/.claude/scripts
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

INSTALLER_URL="https://raw.githubusercontent.com/ericbuess/claude-code-docs/main/install.sh"
LOCAL_INSTALLER="$SCRIPT_DIR/cc_install_docs.sh"
LOCAL_INSTALLER_LINK="$HOME/.claude/scripts/cc_install_docs.sh"
DOCS_SOURCE="$HOME/.claude-code-docs/docs"
REPO_DOCS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/docs/git-docs"

echo "🔄 Fetching Claude Code docs installer..."
curl -fsSL "$INSTALLER_URL" -o "$LOCAL_INSTALLER"
chmod +x "$LOCAL_INSTALLER"

LOCAL_INSTALLER="$LOCAL_INSTALLER" python3 <<'PY'
import os
from pathlib import Path

installer_path = Path(os.environ["LOCAL_INSTALLER"])
text = installer_path.read_text()
marker = "# Guarded for empty arrays (ClaudeCode patch)"

if marker not in text:
    block1 = """    # Deduplicate and exclude new location
    printf '%s\\n' "${paths[@]}" | grep -v "^$INSTALL_DIR$" | sort -u
}"""
    block1_new = """    # Deduplicate and exclude new location
    if [[ ${#paths[@]} -gt 0 ]]; then  # Guarded for empty arrays (ClaudeCode patch)
        printf '%s\\n' "${paths[@]}" | grep -v "^$INSTALL_DIR$" | sort -u
    fi
}"""

    block2 = """existing_installs=()
while IFS= read -r line; do
    [[ -n "$line" ]] && existing_installs+=("$line")
done < <(find_existing_installations)
OLD_INSTALLATIONS=("${existing_installs[@]}")  # Save for later cleanup
"""

    block2_new = """existing_installs=()
while IFS= read -r line; do
    [[ -n "$line" ]] && existing_installs+=("$line")
done < <(find_existing_installations || true)

if [[ ${#existing_installs[@]} -gt 0 ]]; then  # Guarded for empty arrays (ClaudeCode patch)
    OLD_INSTALLATIONS=("${existing_installs[@]}")  # Save for later cleanup
else
    OLD_INSTALLATIONS=()
fi

"""

    changed = False
    if block1 in text:
        text = text.replace(block1, block1_new)
        changed = True
    if block2 in text:
        text = text.replace(block2, block2_new)
        changed = True

    if changed:
        installer_path.write_text(text)
PY

mkdir -p "$HOME/.claude/scripts"
if [[ -L "$LOCAL_INSTALLER_LINK" ]]; then
    current_target=$(readlink "$LOCAL_INSTALLER_LINK")
    if [[ "$current_target" != "$LOCAL_INSTALLER" ]]; then
        ln -sfn "$LOCAL_INSTALLER" "$LOCAL_INSTALLER_LINK"
    fi
elif [[ -e "$LOCAL_INSTALLER_LINK" ]]; then
    echo "⚠️ Existing non-symlink at $LOCAL_INSTALLER_LINK; please remove it manually." >&2
else
    ln -s "$LOCAL_INSTALLER" "$LOCAL_INSTALLER_LINK"
fi

echo "🚀 Running installer from $LOCAL_INSTALLER"
"$LOCAL_INSTALLER"

if [[ -d "$DOCS_SOURCE" ]]; then
    echo "📁 Syncing docs from $DOCS_SOURCE to $REPO_DOCS_DIR"
    mkdir -p "$REPO_DOCS_DIR"
    rsync -a --delete "$DOCS_SOURCE/" "$REPO_DOCS_DIR/"
else
    echo "⚠️ Docs source directory not found: $DOCS_SOURCE" >&2
    exit 1
fi

echo "✅ Claude Code docs update complete."
