---
allowed-tools: Bash(pwd:*), Bash(ls:*), Bash(du:*), Bash(rm:*)
description: Clear Claude Code session cache to remove sensitive data
argument-hint: [confirm]
---

# Clear Claude Code Cache

This command clears the Claude Code session cache for the CURRENT PROJECT ONLY to remove potentially sensitive data like API keys, tokens, or other credentials that may have been logged.

**WARNING**: This will remove conversation history for the current project only but will NOT affect your actual code files or other projects' caches.

## What gets cleared:
- Session logs (.jsonl files) containing conversation history for current project
- Current project's cached data only
- Current project's temporary conversation context

## What's preserved:
- Your actual code and project files
- Global Claude Code settings
- Claude Code installation
- Other projects' conversation history and caches

## Usage:
- `/clear-cache confirm` - Actually perform the cache clearing
- `/clear-cache` - Show what would be cleared (dry run)

---

Current working directory: !`pwd`

## Your task:

Argument provided: "$1"

If the argument is "confirm":
- First determine the current project's cache directory name using pwd
- List all session files in the cache directory BEFORE clearing
- Clear ONLY current project cache files (remove individual .jsonl files, not the directory)
- IMPORTANT: The current active session file may reappear immediately - this is normal behavior
- Show confirmation of what was cleared (list the files that were removed)
- Explain the security benefit of removing potentially leaked API keys and sensitive data from current project
- Confirm that code files remain untouched
- Confirm that other projects' caches remain untouched
- Note that a new session file for the current conversation is normal and expected

If no argument or argument is not "confirm":
- Show what would be cleared (dry run mode) - ONLY for current project
- Determine current project's cache directory using pwd
- List the cache files that exist for current project only
- Show the total size of data that would be cleared for current project
- Explain that user needs to run `/clear-cache confirm` to actually clear
- Warn about conversation history loss for CURRENT PROJECT only

Steps to determine current project cache directory:
1. Get current working directory with pwd
2. Extract the directory path and convert it to cache directory name format
3. Cache directory format: ~/.claude/projects/- + directory_path_with_slashes_replaced_by_dashes
4. Example: /data/eliran/.claude becomes ~/.claude/projects/-data-eliran--claude
5. Example: /data/eliran/WhatsApp_Organized becomes ~/.claude/projects/-data-eliran-WhatsApp-Organized

Important notes about clearing:
- Remove individual .jsonl files, not the entire directory
- The current active session file will be recreated immediately - this is expected behavior
- Focus on removing PREVIOUS session files to clear sensitive data from past conversations
- A new session file appearing after clearing indicates the command is working correctly