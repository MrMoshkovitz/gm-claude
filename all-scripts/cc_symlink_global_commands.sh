#!/bin/bash
# Link each global command file directly to the ~/.claude/commands/ folder

MAIN_CC_COMMANDS_DIR="$HOME/.claude/commands"
CUSTOM_CC_GLOBAL_COMMANDS_DIR="$HOME/Professional/Code/ClaudeCode/commands/global-commands"

new_links=0
updated_links=0

# Create commands directory if it doesn't exist
mkdir -p "$MAIN_CC_COMMANDS_DIR"

cd "$MAIN_CC_COMMANDS_DIR" || exit 1

shopt -s nullglob
for command in "$CUSTOM_CC_GLOBAL_COMMANDS_DIR"/*.md; do
    command_name="$(basename "$command")"

    if [[ -L "$command_name" ]]; then
        current_target=$(readlink "$command_name")
        if [[ "$current_target" == "$command" ]]; then
            printf 'Already linked: %s -> %s\n' "$command" "$command_name"
            continue
        fi
        ln -snf "$command" "$command_name"
        printf 'Updated link: %s -> %s (was -> %s)\n' "$command" "$command_name" "$current_target"
        ((updated_links++))
        continue
    elif [[ -e "$command_name" ]]; then
        printf 'Skipping existing non-symlink (manual review needed): %s\n' "$command_name"
        continue
    fi

    ln -s "$command" "$command_name"
    printf 'Linking: %s -> %s\n' "$command" "$command_name"
    ((new_links++))
done

echo ""
ls -la "$MAIN_CC_COMMANDS_DIR"
echo "✓ Global commands linked (new: $new_links, updated: $updated_links)"
echo "NEW_COUNT=$new_links"
echo "UPDATED_COUNT=$updated_links"
