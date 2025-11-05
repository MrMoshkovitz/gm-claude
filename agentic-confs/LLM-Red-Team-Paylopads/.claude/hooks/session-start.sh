#!/bin/bash
# Session start safety briefing and environment setup

echo "════════════════════════════════════════════════════════════════"
echo "🔒 LLM RED TEAM PAYLOADS - SAFETY BRIEFING"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "📋 IMPORTANT SAFETY REQUIREMENTS:"
echo "   • This repository contains SANITIZED red team payloads for DEFENSIVE security research ONLY"
echo "   • All generated content MUST use placeholders (<SECRET>, <REDACTED>, etc.)"
echo "   • NO real credentials, exploits, or actionable malicious content allowed"
echo "   • Ensure proper authorization before conducting any security testing"
echo ""
echo "⚖️  ETHICAL COMPLIANCE:"
echo "   • Follow OWASP AI Testing Guide ethical standards"
echo "   • Maintain defensive research purpose at all times"
echo "   • Respect privacy and data protection requirements"
echo "   • Use only in authorized testing environments"
echo ""
echo "🛡️  SAFETY FEATURES ACTIVE:"
echo "   • Pre-tool-use validation hooks enabled"
echo "   • Post-tool-use compliance checks enabled"
echo "   • Automated safety scanning configured"
echo "   • Specialized security agents available"
echo ""
echo "📞 ESCALATION CONTACTS:"
echo "   • Security Issues: Contact repository maintainers"
echo "   • Ethical Concerns: Follow institutional ethics procedures"
echo "   • Technical Support: See CLAUDE.md for guidance"
echo ""
echo "🤖 AVAILABLE SPECIALIZED AGENTS:"
echo "   • aitg-payload-generator: Create sanitized AITG test scenarios"
echo "   • security-reviewer: Validate content safety compliance"
echo "   • yaml-validator: Ensure AITG structure compliance"
echo "   • dataset-generator: Create training datasets with safety controls"
echo "   • compliance-auditor: Repository-wide ethical compliance"
echo "   • And 5 additional specialized agents (see CLAUDE.md)"
echo ""
echo "🎯 QUICK START:"
echo "   • Review CLAUDE.md for complete configuration"
echo "   • Use specialized agents for red team tasks"
echo "   • Always prioritize safety and ethical compliance"
echo "   • Run compliance checks before committing changes"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "✅ Safety briefing completed. Proceed with defensive security research."
echo "════════════════════════════════════════════════════════════════"
echo ""

# Create compliance log if it doesn't exist
if [[ ! -f ".claude/compliance.log" ]]; then
    echo "# Claude Code Compliance Log" > .claude/compliance.log
    echo "# Tracks safety validation and compliance checks" >> .claude/compliance.log
    echo "" >> .claude/compliance.log
fi

# Log session start
echo "SESSION_START: $(date '+%Y-%m-%d %H:%M:%S') - Safety briefing completed" >> .claude/compliance.log

# Check for required safety documentation
echo "🔍 Checking repository safety documentation..."

if [[ ! -f "README.md" ]]; then
    echo "⚠️  WARNING: Missing main README.md - consider creating project documentation"
fi

if [[ ! -f "CSVs/README.md" ]]; then
    echo "⚠️  WARNING: Missing CSVs/README.md - required for dataset safety documentation"
fi

if [[ ! -f "LICENSE" ]]; then
    echo "⚠️  WARNING: Missing LICENSE file - consider adding appropriate license"
fi

# Verify hook permissions
chmod +x .claude/hooks/*.sh 2>/dev/null

echo "🛡️  Environment safety check completed"
echo ""