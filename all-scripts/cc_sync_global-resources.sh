#!/bin/bash
# Automatically syncs global Claude Code resources daily


LOG_FILE="$HOME/.claude/sync.log"
SCRIPTS_DIR="$HOME/Professional/Code/ClaudeCode/scripts"

echo "=== Sync started at $(date) ===" >> "$LOG_FILE"

total_new=0
agents_new=0
scripts_new=0
commands_new=0
docs_new=0

run_sync() {
    local script_name="$1"
    local label="$2"
    local __resultvar="$3"

    if [[ -f "$SCRIPTS_DIR/$script_name" ]]; then
        echo "Syncing $label..." >> "$LOG_FILE"
        local output
        output=$(bash "$SCRIPTS_DIR/$script_name" 2>&1)
        echo "$output" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"

        local count
        count=$(printf '%s\n' "$output" | awk -F= '/^NEW_COUNT=/{print $2}' | tail -1)
        if [[ -z "$count" ]]; then
            count=0
        fi

        printf -v "$__resultvar" '%s' "$count"
    else
        printf -v "$__resultvar" '0'
    fi
}

run_sync "cc_symlink_global_agents.sh" "global agents" agents_new
run_sync "cc_symlink_global_scripts.sh" "global scripts" scripts_new
run_sync "cc_symlink_global_commands.sh" "global commands" commands_new
if [[ -f "$SCRIPTS_DIR/cc_update_docs.sh" ]]; then
    echo "Updating Claude docs..." >> "$LOG_FILE"
    bash "$SCRIPTS_DIR/cc_update_docs.sh" >> "$LOG_FILE" 2>&1
    echo "" >> "$LOG_FILE"
fi
run_sync "cc_symlink_docs.sh" "Claude docs" docs_new

total_new=$((agents_new + scripts_new + commands_new + docs_new))

echo "New agents linked: $agents_new" >> "$LOG_FILE"
echo "New scripts linked: $scripts_new" >> "$LOG_FILE"
echo "New commands linked: $commands_new" >> "$LOG_FILE"
echo "New docs linked: $docs_new" >> "$LOG_FILE"
echo "Total new resources linked: $total_new" >> "$LOG_FILE"
echo "=== Sync completed at $(date) ===" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

cat "$LOG_FILE"

printf 'New items this run: %d (agents: %d, scripts: %d, commands: %d, docs: %d)\n' \
    "$total_new" "$agents_new" "$scripts_new" "$commands_new" "$docs_new"
