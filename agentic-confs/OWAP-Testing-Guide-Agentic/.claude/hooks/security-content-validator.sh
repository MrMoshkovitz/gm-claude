#!/bin/bash
# Security Content Validator - PreToolUse Hook
# Prevents unsanitized security content from being committed

echo "🔍 Security Content Validation Running..."

# Check for potential real credentials
if grep -r -E "(password|secret|api_key|token)[:=]\s*['\"][^<]" Document/content/tests/ 2>/dev/null; then
    echo "🚫 BLOCKED: Potential real credentials detected in security content"
    echo ""
    echo "Found patterns that may contain real secrets:"
    grep -r -E "(password|secret|api_key|token)[:=]\s*['\"][^<]" Document/content/tests/ 2>/dev/null | head -3
    echo ""
    echo "✅ SOLUTION: Please sanitize using security-payload-sanitizer agent"
    echo "   Replace with: <SECRET>, <API_KEY>, <PASSWORD>, <TOKEN>"
    exit 1
fi

# Check for unsanitized exploit code
if grep -r -E "(rm -rf|DROP TABLE|exec\(|eval\(|system\()" Document/content/tests/ 2>/dev/null; then
    echo "🚫 BLOCKED: Potential executable exploit detected"
    echo ""
    echo "Found potentially dangerous commands:"
    grep -r -E "(rm -rf|DROP TABLE|exec\(|eval\(|system\()" Document/content/tests/ 2>/dev/null | head -3
    echo ""
    echo "✅ SOLUTION: Replace with placeholder or educational example"
    echo "   Use: <CMD_PLACEHOLDER>, <DESTRUCTIVE_CMD>, [REMOVE_EXEC]"
    exit 1
fi

# Check for real IP addresses (private ranges)
if grep -r -E "192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\." Document/content/tests/ 2>/dev/null; then
    echo "⚠️ WARNING: Potential real IP addresses detected"
    echo ""
    echo "Found IP addresses that may be real:"
    grep -r -E "192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\." Document/content/tests/ 2>/dev/null | head -3
    echo ""
    echo "💡 RECOMMENDATION: Consider replacing with:"
    echo "   • <IP_ADDR> for placeholders"
    echo "   • 192.0.2.x for example addresses (RFC 5737)"
    echo "   • example.com for domain examples"
    echo ""
fi

# Check for real domain names that might be problematic
if grep -r -E "(\.com|\.org|\.net)(?!\s*[/)])" Document/content/tests/ 2>/dev/null | grep -v -E "(example\.com|test\.local|localhost)" | head -1 >/dev/null; then
    echo "⚠️ WARNING: Real domain names detected"
    echo ""
    echo "💡 RECOMMENDATION: Use example domains:"
    echo "   • example.com, test.local for domain examples"
    echo "   • Replace real domains to avoid accidental targeting"
    echo ""
fi

# Check for missing educational disclaimers in new test files
find Document/content/tests/ -name "AITG-*.md" -newer .git/HEAD 2>/dev/null | while read testfile; do
    if ! grep -q "EDUCATIONAL" "$testfile" && ! grep -q "educational" "$testfile"; then
        echo "⚠️ WARNING: New test file missing educational disclaimer: $testfile"
        echo "💡 Add: ⚠️ EDUCATIONAL NOTICE: This example is for security testing education only."
    fi
done

echo "✅ Security content validation complete"