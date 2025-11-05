# LLM Red Team Payloads - Claude Code Configuration

## Project Overview
This repository contains OWASP AI Testing Guide (AITG) payloads for defensive AI security research. The project provides sanitized red team scenarios, test datasets, and evaluation frameworks for assessing LLM security vulnerabilities in authorized testing environments.

### Tech Stack
- **Languages**: YAML (test configurations), Python (analysis scripts), JSON (results)
- **Frameworks**: OWASP AITG, MITRE ATLAS
- **Models Tested**: GPT-5, Gemini 2.5 Flash, Claude Sonnet 4, Llama 4 Maverick
- **Data Formats**: CSV (results), JSONL (detailed logs), YAML (test configs)

### Entry Points
- **AITG Test Files**: `OWASP AITG-APP/AITG-APP-*.yaml` (14 test categories)
- **Results Analysis**: `OWASP AITG-APP/RESULTS/` (model performance data)
- **Dataset Generation**: `CSVs/` (training datasets for ML)

### Run/Test Commands
```bash
# Validate YAML structure
python3 -c \"import yaml; yaml.safe_load(open('OWASP AITG-APP/AITG-APP-01.yaml'))\"

# Basic results analysis
head -5 \"OWASP AITG-APP/RESULTS/anthropic-claude-sonnet-4-results.csv\"

# Safety compliance check
grep -r \"<SECRET>\\|<REDACTED>\" --include=\"*.yaml\" .
```

## Imports
@README.md
@\"OWASP AITG-APP/README.md\"
@LICENSE

## Specialized Subagents

### Core Payload Generation
- **aitg-payload-generator** - Creates sanitized AITG test scenarios with MITRE mappings
  - *Triggers*: User requests payload generation, AITG creation, red team scenarios
  - *Tools*: Read, Write, Edit, MultiEdit, Glob, Grep, Bash
  - *Purpose*: Generate OWASP-compliant test payloads with safety controls
  - *File*: `.claude/agents/aitg-payload-generator.md`

- **dataset-generator** - Produces large-scale CSV datasets for ML training
  - *Triggers*: CSV dataset requests, bulk generation, training data needs
  - *Tools*: Write, MultiEdit, Bash
  - *Purpose*: Create 200+ row datasets (UserInfoLeak, DataLeak, PromptDisclosure, Exec)
  - *File*: `.claude/agents/dataset-generator.md`

### Security & Validation
- **security-reviewer** - Reviews content for safety compliance and ethical guidelines
  - *Triggers*: PROACTIVELY after payload generation, before commits
  - *Tools*: Read, Grep, Glob
  - *Purpose*: Ensure defensive-only usage, no real exploits
  - *File*: `.claude/agents/security-reviewer.md`

- **yaml-validator** - Validates AITG YAML structure and safety compliance
  - *Triggers*: PROACTIVELY on YAML modifications, structure validation
  - *Tools*: Read, Bash, Grep, Edit
  - *Purpose*: Ensure proper AITG format and judge prompt compliance
  - *File*: `.claude/agents/yaml-validator.md`

- **compliance-auditor** - Repository-wide ethical and regulatory compliance
  - *Triggers*: PROACTIVELY before commits, scheduled audits
  - *Tools*: Read, Glob, Grep, Bash
  - *Purpose*: OWASP adherence, safety standards, regulatory compliance
  - *File*: `.claude/agents/compliance-auditor.md`

### Analysis & Intelligence
- **aitg-results-analyzer** - Analyzes test results and generates performance reports
  - *Triggers*: Result analysis requests, model comparisons
  - *Tools*: Read, Bash, Glob, Grep
  - *Purpose*: Statistical analysis of AITG test outcomes
  - *MCP*: data-analysis
  - *File*: `.claude/agents/aitg-results-analyzer.md`

- **mitre-mapper** - Maps test scenarios to MITRE ATLAS techniques
  - *Triggers*: PROACTIVELY during payload creation, technique categorization
  - *Tools*: Read, WebFetch, Grep
  - *Purpose*: Provide threat intelligence context and proper categorization
  - *MCP*: threat-intelligence
  - *File*: `.claude/agents/mitre-mapper.md`

### Operations & Infrastructure
- **test-runner** - Executes AITG scenarios against target models
  - *Triggers*: Test execution requests, model evaluation
  - *Tools*: Bash, Read, Write
  - *Purpose*: Safe test execution with judge evaluation
  - *MCP*: llm-apis
  - *File*: `.claude/agents/test-runner.md`

- **documentation-manager** - Maintains README files and methodology docs
  - *Triggers*: PROACTIVELY on documentation updates, new content
  - *Tools*: Read, Write, Edit, MultiEdit
  - *Purpose*: Consistent, accurate, safety-focused documentation
  - *File*: `.claude/agents/documentation-manager.md`

- **performance-optimizer** - Optimizes test execution and processing performance
  - *Triggers*: PROACTIVELY on performance issues, scaling needs
  - *Tools*: Bash, Read, Edit
  - *Purpose*: Improve throughput and resource efficiency
  - *MCP*: performance-monitoring
  - *File*: `.claude/agents/performance-optimizer.md`

## MCP Server Dependencies

### Required MCP Servers
```bash
# Threat intelligence for MITRE ATLAS mapping
claude mcp add threat-intelligence --purpose \"MITRE ATLAS technique lookup and mapping\"

# Data analysis for statistical processing
claude mcp add data-analysis --purpose \"Statistical analysis and visualization for results\"

# LLM APIs for model testing
claude mcp add llm-apis --purpose \"Integration with target models for testing\"

# Performance monitoring for optimization
claude mcp add performance-monitoring --purpose \"Resource usage and optimization metrics\"
```

## Permissions & Modes

### Plan Mode Usage
- **Research Tasks**: Use Plan Mode for understanding codebase, analyzing existing content
- **Implementation Tasks**: Exit Plan Mode for payload generation, dataset creation, modifications

### Tool Permissions
```json
{
  \"permissions\": {
    \"allow\": [
      \"Bash(python3:*)\",
      \"Read\",
      \"Write\",
      \"Edit\",
      \"MultiEdit\",
      \"Glob\",
      \"Grep\"
    ],
    \"deny\": [
      \"Bash(rm -rf*)\",
      \"Bash(sudo*)\",
      \"Write(/etc/*)\",
      \"Edit(/etc/*)\"
    ],
    \"ask\": [
      \"Bash(*eval*)\",
      \"Bash(*exec*)\"
    ]
  }
}
```

### Disallowed Tools
- **System Commands**: No destructive system operations
- **Network Access**: Restricted to authorized APIs only
- **File System**: No access to system configuration files

## Verification Hooks

### PreToolUse Safety Validation
```bash
#!/bin/bash
# .claude/hooks/pre-tool-use.sh
TOOL=\"$1\"
CONTENT=\"$2\"

if [[ \"$TOOL\" == \"Write\" || \"$TOOL\" == \"Edit\" || \"$TOOL\" == \"MultiEdit\" ]]; then
    # Check for real credentials
    echo \"$CONTENT\" | grep -E \"password.*:.*[a-zA-Z0-9]\" && {
        echo \"ERROR: Real credentials detected\"
        exit 1
    }

    # Check for destructive commands
    echo \"$CONTENT\" | grep -E \"rm -rf|sudo|eval|exec\" && {
        echo \"ERROR: Destructive commands detected\"
        exit 1
    }

    # Ensure placeholders are used for sensitive content
    if [[ \"$TOOL\" == \"Write\" ]] && [[ \"$CONTENT\" =~ (password|api_key|token) ]]; then
        echo \"$CONTENT\" | grep -E \"<SECRET>|<REDACTED>|<.*_PLACEHOLDER>\" || {
            echo \"WARNING: Missing safety placeholders\"
            exit 1
        }
    fi
fi

echo \"Safety validation passed\"
exit 0
```

### PostToolUse Compliance Check
```bash
#!/bin/bash
# .claude/hooks/post-tool-use.sh
FILE=\"$1\"

if [[ -f \"$FILE\" ]]; then
    # Run automated safety scan
    if command -v ./scripts/safety-scan.sh &> /dev/null; then
        ./scripts/safety-scan.sh \"$FILE\"
    fi

    # Validate YAML structure if applicable
    if [[ \"$FILE\" == *.yaml ]]; then
        python3 -c \"import yaml; yaml.safe_load(open('$FILE'))\" || {
            echo \"ERROR: Invalid YAML syntax\"
            exit 1
        }
    fi

    # Check for required safety documentation
    if [[ \"$FILE\" == CSVs/*.csv ]]; then
        [[ -f \"CSVs/README.md\" ]] || {
            echo \"WARNING: Missing CSVs/README.md\"
        }
    fi
fi

echo \"Compliance check completed\"
exit 0
```

### SessionStart Safety Briefing
```bash
#!/bin/bash
# .claude/hooks/session-start.sh
echo \"🔒 SAFETY REMINDER: This repository contains red team payloads for defensive security research only.\"
echo \"📋 REQUIREMENTS: All generated content must use placeholders and be non-actionable.\"
echo \"⚖️ ETHICS: Ensure proper authorization and ethical compliance for all activities.\"
echo \"📞 ESCALATION: Contact repository maintainers for safety concerns.\"
```

## Output Styles

### Safety-First Response Style
```yaml
name: safety-first
description: Emphasizes safety warnings and ethical considerations in all responses
prompt_append: |
  IMPORTANT: Always prioritize safety in your responses. When generating any red team content:
  1. Lead with safety warnings and ethical considerations
  2. Use clear placeholders for any sensitive information
  3. Emphasize defensive research purposes only
  4. Include proper attribution and compliance notes
  5. Provide escalation contacts for safety concerns
```

### Technical Precision Style
```yaml
name: technical-precision
description: Focuses on technical accuracy and detailed explanations for complex topics
prompt_append: |
  Provide technically precise and detailed responses. Include:
  1. Specific technique references (MITRE ATLAS IDs)
  2. Clear methodology explanations
  3. Proper categorization and risk assessments
  4. Quantitative metrics where applicable
  5. References to relevant standards and frameworks
```

## Default Agent Delegation Rules

### Automatic Triggers
- **security-reviewer**: MUST BE USED after any payload generation or content modification
- **yaml-validator**: MUST BE USED when AITG YAML files are created or modified
- **compliance-auditor**: MUST BE USED before any commits or releases
- **mitre-mapper**: PROACTIVELY used when creating new attack vectors
- **documentation-manager**: PROACTIVELY used when documentation needs updates

### Manual Delegation Commands
```bash
# Generate sanitized payloads
/agents aitg-payload-generator \"Create AITG test for prompt injection\"

# Analyze test results
/agents aitg-results-analyzer \"Compare model performance across AITG categories\"

# Validate repository compliance
/agents compliance-auditor \"Audit entire repository for safety compliance\"

# Generate training datasets
/agents dataset-generator \"Create CSV datasets for UserInfoLeak category\"
```

## Safety & Ethics Framework

### Core Principles
1. **Defensive Only**: All content for authorized defensive research
2. **Safety First**: Mandatory sanitization and placeholder usage
3. **Ethical Compliance**: Adherence to OWASP and academic standards
4. **Transparency**: Clear methodology and purpose documentation
5. **Accountability**: Proper authorization and escalation procedures

### Escalation Contacts
- **Security Issues**: security-team@organization.com
- **Ethical Concerns**: ethics-board@organization.com
- **Technical Support**: maintainers@organization.com
- **Emergency**: security-incident@organization.com

### Compliance Requirements
- All payloads must use placeholders for sensitive content
- Clear documentation of defensive research purpose
- Proper authorization and approval documentation
- Regular safety audits and compliance reviews
- Immediate escalation of safety violations

---

*This configuration enables safe, ethical, and effective red team security research using Claude Code's specialized agent framework.*