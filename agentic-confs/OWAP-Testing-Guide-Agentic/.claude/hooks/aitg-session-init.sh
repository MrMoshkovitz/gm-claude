#!/bin/bash
# AITG Session Initialization - SessionStart Hook
# Provides context and guidance for working with OWASP AI Testing Guide

echo "🔒 OWASP AI Testing Guide - Security-First Claude Code Session"
echo "=================================================================="
echo ""

# Display current repository status
if [[ -d .git ]]; then
    current_branch=$(git branch --show-current 2>/dev/null || echo "unknown")
    echo "📁 Repository: OWASP AI Testing Guide (Branch: $current_branch)"
else
    echo "📁 Repository: OWASP AI Testing Guide"
fi

# Count current test methodologies
test_count=$(find Document/content/tests -name "AITG-*.md" 2>/dev/null | wc -l | tr -d ' ')
echo "📊 Current AITG Tests: $test_count methodologies across 4 categories"

echo ""
echo "📋 Active Security Constraints:"
echo "   🚫 No real credentials/exploits permitted in examples"
echo "   🔄 Payload sanitization required for all security content"
echo "   📚 Educational disclaimers mandatory for security tests"
echo "   ✅ Responsible disclosure principles must be followed"
echo "   🎯 Content must be educational, not actionable for malicious use"

echo ""
echo "🤖 Available Specialized Agents:"
echo "   🔍 aitg-content-reviewer     → Auto-triggered for security test content"
echo "   🛡️ security-payload-sanitizer → Auto-triggered before security commits"
echo "   🌐 jekyll-site-manager       → Auto-triggered for site structure changes"
echo "   🔗 content-link-validator    → Auto-triggered before publishing"
echo "   📋 aitg-taxonomy-maintainer  → Manual: test categorization management"
echo "   ✅ owasp-standards-validator → Manual: OWASP compliance validation"
echo "   📚 academic-reference-manager → Manual: citation and reference management"
echo "   📝 aitg-test-generator       → Manual: create new test methodologies"

echo ""
echo "📖 Quick Development Commands:"
echo "   bundle exec jekyll serve --livereload    # Development server with auto-reload"
echo "   bundle exec jekyll build --dry-run       # Validate site build without output"
echo "   bundle exec jekyll clean && jekyll build # Clean build from scratch"

echo ""
echo "🔍 Repository Navigation:"
echo "   📄 Document/README.md                    # Main documentation index"
echo "   🧪 Document/content/tests/               # 32 AITG test methodologies"
echo "   🎯 Document/content/3.0_*                # Framework and methodology docs"
echo "   ⚙️ _config.yml                          # Jekyll site configuration"

echo ""
echo "📊 Test Categories (Current Distribution):"

# Count tests by category
app_count=$(find Document/content/tests -name "AITG-APP-*.md" 2>/dev/null | wc -l | tr -d ' ')
mod_count=$(find Document/content/tests -name "AITG-MOD-*.md" 2>/dev/null | wc -l | tr -d ' ')
inf_count=$(find Document/content/tests -name "AITG-INF-*.md" 2>/dev/null | wc -l | tr -d ' ')
dat_count=$(find Document/content/tests -name "AITG-DAT-*.md" 2>/dev/null | wc -l | tr -d ' ')

echo "   🟦 APP (Application Testing):    $app_count tests"
echo "   🟪 MOD (Model Testing):          $mod_count tests"
echo "   🟩 INF (Infrastructure Testing): $inf_count tests"
echo "   🟨 DAT (Data Testing):           $dat_count tests"

echo ""
echo "⚠️ Common Workflow Reminders:"
echo "   1. Use aitg-test-generator for new security test methodologies"
echo "   2. Security content will be auto-reviewed by aitg-content-reviewer"
echo "   3. All security payloads will be auto-sanitized before commits"
echo "   4. Site builds are validated automatically after content changes"
echo "   5. Links are checked before publishing to prevent broken references"

echo ""
echo "🆘 Emergency Procedures:"
echo "   • Unsanitized content detected → Use security-payload-sanitizer agent"
echo "   • Build failures → Run: bundle exec jekyll build --verbose"
echo "   • Broken links → Run content-link-validator agent"
echo "   • OWASP compliance → Run owasp-standards-validator agent"

echo ""
echo "🎯 Mission: Maintain the highest standards of AI security testing"
echo "   documentation while ensuring ethical, responsible, and educational"
echo "   content that advances the field of AI security."
echo ""
echo "Ready to contribute to AI security! 🚀"
echo "=================================================================="