#!/bin/bash
# Post-tool-use compliance check hook
# This hook validates files after creation/modification for compliance

FILE="$1"
TOOL="$2"

echo "🔍 Running post-tool-use compliance check for: $FILE"

if [[ -f "$FILE" ]]; then
    # Run automated safety scan if available
    if [[ -f "./scripts/safety-scan.sh" ]]; then
        echo "🔧 Running automated safety scan..."
        bash ./scripts/safety-scan.sh "$FILE"
        if [[ $? -ne 0 ]]; then
            echo "❌ Safety scan failed for $FILE"
            exit 1
        fi
    fi

    # Validate YAML structure if applicable
    if [[ "$FILE" == *.yaml ]]; then
        echo "🔧 Validating YAML structure..."
        python3 -c "
import yaml
import sys
try:
    with open('$FILE', 'r') as f:
        yaml.safe_load(f)
    print('✅ YAML syntax valid')
except yaml.YAMLError as e:
    print(f'❌ ERROR: Invalid YAML syntax: {e}')
    sys.exit(1)
except Exception as e:
    print(f'❌ ERROR: Failed to read file: {e}')
    sys.exit(1)
"
        if [[ $? -ne 0 ]]; then
            echo "❌ YAML validation failed for $FILE"
            exit 1
        fi

        # Additional AITG-specific validation
        if [[ "$FILE" == *"AITG-APP"* ]]; then
            echo "🔧 Validating AITG compliance..."

            # Check for required fields
            if ! grep -q "^id:" "$FILE"; then
                echo "❌ ERROR: Missing 'id' field in AITG file"
                exit 1
            fi

            if ! grep -q "^judge:" "$FILE"; then
                echo "❌ ERROR: Missing 'judge' field in AITG file"
                exit 1
            fi

            if ! grep -q "^prompts:" "$FILE"; then
                echo "❌ ERROR: Missing 'prompts' field in AITG file"
                exit 1
            fi

            echo "✅ AITG structure validation passed"
        fi
    fi

    # Check for required safety documentation in CSV directory
    if [[ "$FILE" == CSVs/*.csv ]]; then
        echo "🔧 Checking CSV safety documentation..."

        if [[ ! -f "CSVs/README.md" ]]; then
            echo "⚠️  WARNING: Missing CSVs/README.md with rules of engagement"
            echo "   Consider creating safety documentation"
        fi

        if [[ ! -f "CSVs/manifest.json" ]]; then
            echo "⚠️  WARNING: Missing CSVs/manifest.json with dataset metadata"
            echo "   Consider creating dataset manifest"
        fi

        # Check CSV headers
        if head -1 "$FILE" | grep -q "prompt,category,example_id,obfuscated_prompt,mitre_id,risk_level,explanation,safe_test_instruction"; then
            echo "✅ CSV headers validation passed"
        else
            echo "❌ ERROR: Invalid CSV headers in $FILE"
            exit 1
        fi
    fi

    # Check for sensitive content that should be sanitized
    echo "🔧 Scanning for unsanitized sensitive content..."

    # Look for potential real credentials (excluding template examples)
    if grep -E "password.*:.*[a-zA-Z0-9]{8,}|api_key.*:.*[a-zA-Z0-9]{16,}" "$FILE" > /dev/null; then
        if ! grep -E "<SECRET>|<REDACTED>|<.*_PLACEHOLDER>" "$FILE" > /dev/null; then
            echo "❌ ERROR: Potential real credentials found without placeholders"
            exit 1
        fi
    fi

    # Check file permissions for security
    if [[ "$FILE" == *.sh ]]; then
        echo "🔧 Setting executable permissions for shell script..."
        chmod +x "$FILE"
    fi

    # Log successful compliance check
    echo "✅ Compliance check passed for $FILE"
    echo "📝 File validated: $(date '+%Y-%m-%d %H:%M:%S') - $FILE ($TOOL)" >> .claude/compliance.log

else
    echo "⚠️  WARNING: File $FILE does not exist after $TOOL operation"
fi

echo "🛡️  Post-tool-use compliance check completed"
exit 0