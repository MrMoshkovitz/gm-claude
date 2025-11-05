# OWASP AI Testing Guide - Claude Code Configuration

## Project Overview

This repository contains the OWASP AI Testing Guide, a comprehensive framework for testing AI systems across security, privacy, and responsible AI domains. The project is built using Jekyll/Ruby as a static documentation site with 32 structured test methodologies.

### Tech Stack
- **Framework**: Jekyll (Ruby-based static site generator)
- **Content**: Markdown files in `Document/content/`
- **Tests**: 32 AITG test methodologies in 4 categories (APP/MOD/INF/DAT)
- **Assets**: Images and documentation in `Document/images/` and `assets/`
- **Configuration**: Jekyll config in `_config.yml`, Ruby deps in `Gemfile`

### Entry Points
- **Main Documentation**: `Document/README.md` - Project table of contents
- **Test Methodologies**: `Document/content/tests/AITG-*.md` - Security test cases
- **Framework Overview**: `Document/content/3.0_OWASP_AI_Testing_Guide_Framework.md`
- **Site Configuration**: `_config.yml` - Jekyll settings

### Build & Test Commands
```bash
# Install dependencies
bundle install

# Development server with live reload
bundle exec jekyll serve --livereload

# Production build
bundle exec jekyll build

# Build validation (dry run)
bundle exec jekyll build --dry-run

# Update dependencies
bundle update

# Clean build cache
bundle exec jekyll clean
```

## Imports
```markdown
@README.md                                                           # Project overview
@CONTRIBUTING.md                                                     # Contribution guidelines
@Document/README.md                                                  # Documentation index
@Document/content/3.0_OWASP_AI_Testing_Guide_Framework.md          # Framework overview
@Document/content/3.0_Testing_Limitations_and_Requirements.md       # Testing constraints
```

## Specialized Subagents

### 🔒 Security & Content Validation Agents

#### aitg-content-reviewer
- **File**: `.claude/agents/aitg-content-reviewer.md`
- **Purpose**: Reviews AITG test methodology content for technical accuracy and security compliance
- **Triggers**: Editing files in `Document/content/tests/`, creating new AITG test cases
- **Tools**: Read, Grep, Edit, MultiEdit
- **Auto-invoked**: ✅ YES - When editing security test content
- **Key Function**: Ensures security payloads are sanitized and educational-only

#### security-payload-sanitizer
- **File**: `.claude/agents/security-payload-sanitizer.md`
- **Purpose**: Sanitizes security payloads and ensures ethical compliance
- **Triggers**: Before security content publication, editing payload sections
- **Tools**: Read, Edit, MultiEdit, Grep
- **Auto-invoked**: ✅ YES - Before commits to security content
- **Key Function**: Replaces real credentials with `<SECRET>`, commands with `<CMD_PLACEHOLDER>`

#### aitg-test-generator
- **File**: `.claude/agents/aitg-test-generator.md`
- **Purpose**: Generates new AITG test methodologies following OWASP standards
- **Triggers**: Creating new test cases, expanding methodologies
- **Tools**: Read, Write, Grep, Glob, WebFetch
- **Dependencies**: security-research MCP server
- **Key Function**: Creates structured test cases with sanitized payloads

### 🌐 Site Management Agents

#### jekyll-site-manager
- **File**: `.claude/agents/jekyll-site-manager.md`
- **Purpose**: Manages Jekyll site build, configuration, and deployment
- **Triggers**: Changes to `_config.yml`, navigation updates, new markdown files
- **Tools**: Read, Edit, Bash, Glob
- **Auto-invoked**: ✅ YES - For site structure changes
- **Key Function**: Ensures site builds successfully and navigation works

#### content-link-validator
- **File**: `.claude/agents/content-link-validator.md`
- **Purpose**: Validates internal and external links in documentation
- **Triggers**: Before commits, after content updates, weekly maintenance
- **Tools**: Read, Bash, Grep, Glob
- **Auto-invoked**: ✅ YES - Before publishing
- **Key Function**: Detects broken links and missing images

### 📋 Standards & Compliance Agents

#### aitg-taxonomy-maintainer
- **File**: `.claude/agents/aitg-taxonomy-maintainer.md`
- **Purpose**: Maintains AITG test categorization and OWASP framework mapping
- **Triggers**: Adding test categories, updating framework mappings
- **Tools**: Read, Edit, Grep, Glob
- **Key Function**: Ensures proper APP/MOD/INF/DAT classification

#### owasp-standards-validator
- **File**: `.claude/agents/owasp-standards-validator.md`
- **Purpose**: Validates content against OWASP standards and best practices
- **Triggers**: Reviewing security methodology content
- **Tools**: Read, WebFetch, Grep
- **Dependencies**: owasp-api MCP server
- **Key Function**: Ensures alignment with OWASP Top 10 LLM 2025

#### academic-reference-manager
- **File**: `.claude/agents/academic-reference-manager.md`
- **Purpose**: Manages academic citations and reference accuracy
- **Triggers**: Citation updates, reference management
- **Tools**: Read, Edit, WebFetch
- **Key Function**: Maintains consistent citation format and validates links

## MCP Server Dependencies

### Required MCP Servers

#### security-research
- **Purpose**: Access to current vulnerability databases and security research
- **Used by**: aitg-test-generator, aitg-content-reviewer
- **Add command**: `claude mcp add security-research`
- **Function**: Provides current threat intelligence and vulnerability data

#### owasp-api
- **Purpose**: Current OWASP standards and documentation access
- **Used by**: owasp-standards-validator, aitg-taxonomy-maintainer
- **Add command**: `claude mcp add owasp-api`
- **Function**: Validates against current OWASP Top 10 and framework updates

## Permissions & Modes

### Preferred Operating Modes
- **Plan Mode**: Use for security content review and methodology development
- **Accept-Edits Mode**: Use for routine documentation updates and formatting
- **Read-Only Mode**: Use for initial codebase analysis and research

### Tool Restrictions
- **Write/Edit Tools**: Restricted when handling security payloads - must use sanitizer agent first
- **Bash Execution**: Limited to build/validation commands for security
- **WebFetch**: Allowed for research and validation, not for content modification

### Security Constraints
- ⚠️ Never commit unsanitized security content
- ⚠️ Always use placeholder data in examples (`<SECRET>`, `<REDACTED>`)
- ⚠️ Require sanitization review before publication
- ⚠️ Follow responsible disclosure principles
- ⚠️ Block working exploits or real credentials

## Verification Hooks

### PreToolUse Hook: Security Content Validator
```bash
#!/bin/bash
# .claude/hooks/security-content-validator.sh
if grep -r -E "(password|secret|api_key)[:=]\s*['\"][^<]" Document/content/tests/ 2>/dev/null; then
    echo "🚫 BLOCKED: Potential real credentials detected in security content"
    echo "Please sanitize using security-payload-sanitizer agent"
    exit 1
fi

# Check for unsanitized exploit code
if grep -r -E "(rm -rf|DROP TABLE|exec\(|eval\()" Document/content/tests/ 2>/dev/null; then
    echo "🚫 BLOCKED: Potential executable exploit detected"
    echo "Please replace with placeholder or educational example"
    exit 1
fi

# Check for real system information
if grep -r -E "192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[01])\." Document/content/tests/ 2>/dev/null; then
    echo "⚠️ WARNING: Potential real IP addresses detected"
    echo "Consider replacing with <IP_ADDR> or example addresses"
fi
```

### PostToolUse Hook: Jekyll Build Validator
```bash
#!/bin/bash
# .claude/hooks/jekyll-build-validator.sh
if [[ "$CLAUDE_TOOL" == "Edit" || "$CLAUDE_TOOL" == "Write" || "$CLAUDE_TOOL" == "MultiEdit" ]]; then
    # Validate Jekyll build after content changes
    if command -v bundle >/dev/null 2>&1; then
        bundle exec jekyll build --dry-run >/dev/null 2>&1 || {
            echo "⚠️ ALERT: Jekyll build validation failed after changes"
            echo "Site may have syntax errors or broken references"
            echo "Run: bundle exec jekyll build --verbose"
            exit 1
        }
    fi

    # Quick internal link validation
    find Document/content -name "*.md" -exec grep -l "](\.\./" {} \; 2>/dev/null | head -5 | while read file; do
        grep -o "](\.\.\/[^)]*)" "$file" 2>/dev/null | while read link; do
            target=$(echo "$link" | sed 's/](\.\.\///' | sed 's/)$//')
            if [[ ! -f "Document/content/$target" && ! -f "Document/$target" ]]; then
                echo "⚠️ WARNING: Potential broken internal link in $file: $target"
            fi
        done
    done
fi
```

### SessionStart Hook: AITG Session Initialization
```bash
#!/bin/bash
# .claude/hooks/aitg-session-init.sh
echo "🔒 OWASP AI Testing Guide - Security-First Session"
echo ""
echo "📋 Active Security Constraints:"
echo "   • Payload sanitization required for all security content"
echo "   • No real credentials/exploits permitted in examples"
echo "   • Responsible disclosure principles must be followed"
echo "   • Educational disclaimers required for security tests"
echo ""
echo "🤖 Available Specialized Agents:"
echo "   • aitg-content-reviewer (auto-triggered for test content)"
echo "   • security-payload-sanitizer (auto-triggered before commits)"
echo "   • jekyll-site-manager (auto-triggered for site changes)"
echo "   • content-link-validator (auto-triggered before publishing)"
echo ""
echo "📖 Quick Commands:"
echo "   • bundle exec jekyll serve --livereload  # Development server"
echo "   • bundle exec jekyll build --dry-run     # Validate build"
echo "   • find Document/content/tests -name '*.md' | wc -l  # Count tests"
echo ""
```

## Output Styles

### Security Content Style
```yaml
# .claude/styles/aitg-security-content.yaml
name: aitg-security-content
description: "For reviewing and creating AI security test methodologies"
style: |
  When working with AITG security content:

  📋 STRUCTURE REQUIREMENTS:
  - Always use the standard AITG format: Summary → Test Objectives → Test/Payloads → Attended Output → Remediation → Suggested Tools → References
  - Include proper AITG-[CAT]-[NUM] test ID format
  - Use clear section headers and consistent markdown formatting

  🔒 SECURITY REQUIREMENTS:
  - Prioritize ethical compliance and responsible disclosure
  - Use sanitization markers: <SECRET>, <REDACTED>, <CMD_PLACEHOLDER>
  - Include educational disclaimers: "⚠️ EDUCATIONAL NOTICE: This example is for security testing education only"
  - Reference current OWASP standards (Top 10 LLM 2025, AI Exchange)

  📚 CONTENT GUIDELINES:
  - Provide educational context without enabling malicious use
  - Use placeholder data: example.com, 192.0.2.x, <IP_ADDR>
  - Reference peer-reviewed academic sources
  - Recommend actively maintained security tools
  - Include clear remediation strategies
```

### Documentation Style
```yaml
# .claude/styles/aitg-documentation.yaml
name: aitg-documentation
description: "For general documentation and content management"
style: |
  When editing AITG documentation:

  📖 FORMATTING STANDARDS:
  - Maintain consistent markdown formatting and structure
  - Use descriptive headings with proper hierarchy (##, ###, ####)
  - Include clear table of contents for longer documents
  - Use proper internal linking: [Text](../section/file.md)

  🔗 LINKING REQUIREMENTS:
  - Ensure accessibility and readability for all audiences
  - Follow Jekyll/markdown best practices
  - Use relative paths for internal links
  - Validate image references: ![Alt](../images/file.png)

  📋 CONTENT ORGANIZATION:
  - Organize content logically by threat category
  - Cross-reference related AITG test cases
  - Include navigation aids and breadcrumbs
  - Maintain consistency with OWASP documentation standards
```

---

## Quick Start Guide

### Initial Setup
1. **Initialize agent system**: Run `/agents` command in Claude Code
2. **Create directory structure**: Ensure `.claude/agents/`, `.claude/hooks/`, `.claude/styles/` exist
3. **Add MCP servers**:
   ```bash
   claude mcp add security-research
   claude mcp add owasp-api
   ```
4. **Enable verification hooks**:
   ```bash
   claude hooks enable
   claude hooks install .claude/hooks/
   ```
5. **Set default output style**:
   ```bash
   claude style set aitg-security-content
   ```

### Development Workflow
1. **Start development server**: `bundle exec jekyll serve --livereload`
2. **Create new test**: Use `aitg-test-generator` agent
3. **Review security content**: Auto-triggered `aitg-content-reviewer` and `security-payload-sanitizer`
4. **Validate build**: Auto-triggered `jekyll-site-manager` ensures site builds
5. **Check links**: Auto-triggered `content-link-validator` before publishing

### Common Operations
- **New AITG test methodology**: Invoke `aitg-test-generator` agent with test requirements
- **Security content review**: Automatically handled by `aitg-content-reviewer` when editing test files
- **Site maintenance**: Automatically managed by `jekyll-site-manager` for structure changes
- **Standards compliance**: Use `owasp-standards-validator` for OWASP alignment checks
- **Reference management**: Use `academic-reference-manager` for citation updates

### Emergency Procedures
- **Unsanitized content detected**: Security hooks will block - use `security-payload-sanitizer` agent
- **Build failures**: Check Jekyll validation with `bundle exec jekyll build --verbose`
- **Broken links**: Run `content-link-validator` agent for comprehensive link checking
- **OWASP compliance issues**: Use `owasp-standards-validator` for standards alignment

## Project Structure Reference

```
www-project-ai-testing-guide/
├── .claude/
│   ├── agents/           # 8 specialized agent specifications
│   ├── hooks/            # Security and validation hooks
│   └── styles/           # Output style configurations
├── Document/
│   ├── content/
│   │   ├── tests/        # 32 AITG test methodologies
│   │   └── *.md          # Framework documentation
│   └── images/           # Documentation images
├── assets/               # Jekyll site assets
├── _config.yml           # Jekyll configuration
├── Gemfile               # Ruby dependencies
├── CLAUDE.md             # This configuration file
└── README.md             # Project overview
```

**🎯 Mission**: Maintain the highest standards of AI security testing documentation while ensuring ethical, responsible, and educational content that advances the field of AI security.