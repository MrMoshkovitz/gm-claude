#!/bin/bash
# Pre-tool-use safety validation hook
# This hook validates content before any write operations to ensure safety compliance

TOOL="$1"
CONTENT="$2"
FILE="$3"

# Safety validation for write operations
if [[ "$TOOL" == "Write" || "$TOOL" == "Edit" || "$TOOL" == "MultiEdit" ]]; then
    echo "🔍 Running safety validation for $TOOL operation..."

    # Check for real credentials
    if echo "$CONTENT" | grep -E "password.*:.*[a-zA-Z0-9]|api_key.*:.*[a-zA-Z0-9]|token.*:.*[a-zA-Z0-9]" > /dev/null; then
        echo "❌ ERROR: Real credentials detected in content"
        echo "   Use placeholders like <SECRET>, <API_KEY>, <TOKEN> instead"
        exit 1
    fi

    # Check for destructive commands
    if echo "$CONTENT" | grep -E "rm -rf|sudo.*rm|eval.*rm|exec.*rm" > /dev/null; then
        echo "❌ ERROR: Destructive commands detected"
        echo "   Remove or replace with <CMD_PLACEHOLDER>"
        exit 1
    fi

    # Check for real URLs and IPs (in payload context)
    if [[ "$FILE" == *".yaml" || "$FILE" == *".csv" ]] && echo "$CONTENT" | grep -E "https?://[a-zA-Z0-9.-]+|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" > /dev/null; then
        echo "⚠️  WARNING: Real URLs or IPs detected"
        echo "   Consider using <URL_PLACEHOLDER> or <IP_ADDR> for safety"
        # Warning only, don't exit
    fi

    # Ensure placeholders are used for AITG files
    if [[ "$FILE" == *"AITG-APP"* ]] || [[ "$FILE" == *"payload"* ]]; then
        if echo "$CONTENT" | grep -E "(password|api_key|token|secret).*:" > /dev/null; then
            if ! echo "$CONTENT" | grep -E "<SECRET>|<REDACTED>|<.*_PLACEHOLDER>" > /dev/null; then
                echo "❌ ERROR: Missing safety placeholders in payload content"
                echo "   Use <SECRET>, <REDACTED>, or appropriate placeholders"
                exit 1
            fi
        fi
    fi

    # Check for proper AITG structure if YAML
    if [[ "$FILE" == *"AITG-APP"*.yaml ]]; then
        if ! echo "$CONTENT" | grep -E "^(id|name|topics|judge|prompts):" > /dev/null; then
            echo "⚠️  WARNING: AITG YAML may be missing required fields"
            echo "   Ensure id, name, topics, judge, and prompts are present"
        fi
    fi

    echo "✅ Safety validation passed for $TOOL"
fi

# Special validation for CSV dataset files
if [[ "$TOOL" == "Write" && "$FILE" == CSVs/*.csv ]]; then
    echo "🔍 Validating CSV dataset content..."

    # Check for required CSV headers
    if ! echo "$CONTENT" | head -1 | grep -E "prompt,category,example_id,obfuscated_prompt,mitre_id,risk_level,explanation,safe_test_instruction" > /dev/null; then
        echo "❌ ERROR: CSV missing required headers"
        echo "   Required: prompt,category,example_id,obfuscated_prompt,mitre_id,risk_level,explanation,safe_test_instruction"
        exit 1
    fi

    # Ensure obfuscated prompts are present
    if echo "$CONTENT" | tail -n +2 | cut -d',' -f4 | grep -E "^$|^\"\"$" > /dev/null; then
        echo "❌ ERROR: Empty obfuscated_prompt fields detected"
        echo "   All CSV rows must have obfuscated versions with placeholders"
        exit 1
    fi

    echo "✅ CSV dataset validation passed"
fi

echo "🛡️  Pre-tool-use validation completed successfully"
exit 0