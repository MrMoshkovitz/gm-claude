#!/bin/bash
# Setup daily cron job to sync global Claude Code resources
# Run this once to install the cron job

CLAUDECODE_SCRIPTS="$HOME/Professional/Code/ClaudeCode/scripts/cc_sync_global-resources.sh"

# Create a wrapper script that runs all three sync scripts
SYNC_SCRIPT="$HOME/.claude/scripts/cc_sync_global-resources.sh"

# Add to crontab (runs daily at 3 AM)
CRON_LINE="0 8 * * * $SYNC_SCRIPT"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "$SYNC_SCRIPT"; then
    echo "✓ Cron job already exists"
else
    # Add to existing crontab
    (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
    echo "✓ Cron job installed: Daily sync at 8 AM"
fi

echo ""
echo "Sync script original path: $CLAUDECODE_SCRIPTS"
echo "Sync script path: $SYNC_SCRIPT"
echo "Logs will be written to: $HOME/.claude/sync.log"
echo ""
echo "Running initial docs update and symlink..."
bash "$HOME/Professional/Code/ClaudeCode/scripts/cc_update_docs.sh"
bash "$HOME/Professional/Code/ClaudeCode/scripts/cc_symlink_docs.sh"
echo ""
echo "Initial docs sync complete."
echo ""
echo "To test the full sync now, run:"
echo "  $SYNC_SCRIPT"
echo ""
echo "To view cron jobs:"
echo "  crontab -l"
echo ""
echo "To remove the cron job:"
echo "  crontab -e  # Then delete the line with sync-global-resources.sh"
