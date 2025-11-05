# Link each global script file directly
MAIN_CC_SCRIPTS_DIR="$HOME/.claude/scripts/"
CUSTOM_CC_GLOBAL_SCRIPTS_DIR="$HOME/Professional/Code/ClaudeCode/scripts"

new_links=0
updated_links=0

cd "$MAIN_CC_SCRIPTS_DIR"

shopt -s nullglob
for script in "$CUSTOM_CC_GLOBAL_SCRIPTS_DIR"/*.sh; do
    script_name="$(basename "$script")"

    if [[ -L "$script_name" ]]; then
        current_target=$(readlink "$script_name")
        if [[ "$current_target" == "$script" ]]; then
            printf 'Already linked: %s -> %s\n' "$script" "$script_name"
            continue
        fi
        ln -snf "$script" "$script_name"
        printf 'Updated link: %s -> %s (was -> %s)\n' "$script" "$script_name" "$current_target"
        ((updated_links++))
        continue
    elif [[ -e "$script_name" ]]; then
        printf 'Skipping existing non-symlink (manual review needed): %s\n' "$script_name"
        continue
    fi

    ln -s "$script" "$script_name"
    printf 'Linking: %s -> %s\n' "$script" "$script_name"
    ((new_links++))
done

# Verify
ls -la ~/.claude/scripts/
echo ""
echo "✓ Global scripts linked (new: $new_links, updated: $updated_links)"
echo "NEW_COUNT=$new_links"
echo "UPDATED_COUNT=$updated_links"
