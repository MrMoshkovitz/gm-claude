<!-- Usage: claude_search "<search_string>" -->

claude_search() {
    local query="$1"
    [[ -z "$query" ]] && echo "Usage: claude_search <search_string>" && return 1
    
    grep -r "$query" ~/.claude/projects --include="*.jsonl" -l | while read file; do
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        head -1 "$file" | jq -r '"SessionID: \(.sessionId)\nCWD:       \(.cwd)\nBranch:    \(.gitBranch)\nTimestamp: \(.timestamp)\nFile:      " + "'"$file"'"'
        echo ""
    done
}


