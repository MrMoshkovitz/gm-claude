# Link each global agent file directly
# Link each global agent file directly
MAIN_CC_AGENTS_DIR="$HOME/.claude/agents/"
CUSTOM_CC_GLOBAL_AGENTS_DIR="$HOME/Professional/Code/ClaudeCode/agents/global-agents"

new_links=0
updated_links=0

cd "$MAIN_CC_AGENTS_DIR"

shopt -s nullglob
for agent in "$CUSTOM_CC_GLOBAL_AGENTS_DIR"/*.md; do
    agent_name="$(basename "$agent")"

    if [[ -L "$agent_name" ]]; then
        current_target=$(readlink "$agent_name")
        if [[ "$current_target" == "$agent" ]]; then
            printf 'Already linked: %s -> %s\n' "$agent" "$agent_name"
            continue
        fi
        ln -snf "$agent" "$agent_name"
        printf 'Updated link: %s -> %s (was -> %s)\n' "$agent" "$agent_name" "$current_target"
        ((updated_links++))
        continue
    elif [[ -e "$agent_name" ]]; then
        printf 'Skipping existing non-symlink (manual review needed): %s\n' "$agent_name"
        continue
    fi

    ln -s "$agent" "$agent_name"
    printf 'Linking: %s -> %s\n' "$agent" "$agent_name"
    ((new_links++))
done

# Verify
ls -la ~/.claude/agents/
echo ""
echo "✓ Global agents linked (new: $new_links, updated: $updated_links)"
echo "NEW_COUNT=$new_links"
echo "UPDATED_COUNT=$updated_links"
