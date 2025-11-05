# wuzzi-chat: LLM Security Research Platform

## Project Overview

**wuzzi-chat** is a Flask-based security research platform designed for testing red team tools against Large Language Model applications. The platform integrates multiple AI providers (OpenAI, Groq, Ollama) with the Garak framework for comprehensive vulnerability assessment and security testing.

**Core Mission**: Enable security researchers to systematically test LLM applications for vulnerabilities including prompt injection, jailbreak attempts, content policy evasion, and other AI safety concerns.

## Architecture

- **Backend**: Flask application (`wuzzi-chat/chat.py`) with REST API and Swagger documentation
- **AI Abstraction**: Provider-agnostic model layer (`wuzzi-chat/ai_model.py`) supporting OpenAI, Groq, Ollama
- **Security Framework**: Integrated Garak testing suite (`wuzzi-chat/tests/garak-config.json`)
- **Frontend**: HTML/CSS templates (`wuzzi-chat/templates/`, `wuzzi-chat/static/`) with interactive chat interface
- **Configuration**: Environment-based config (`wuzzi-chat/.env`) with timeout and security controls
- **Testing**: pytest suite (`wuzzi-chat/tests/`) with comprehensive mocking and security test cases

## Key Patterns

- **Provider Abstraction**: All AI models inherit from `AIModel` ABC with standardized `chat()` and `moderate()` methods
- **Timeout Protection**: Configurable deadline system prevents DoS attacks via `WUZZI_DEADLINE_SECONDS`
- **Bearer Authentication**: All API endpoints require `Authorization: Bearer <token>` header validation
- **Error Handling**: Consistent JSON error responses with appropriate HTTP status codes
- **Security Testing**: Systematic vulnerability assessment using Garak probes and manual testing
- **Environment Configuration**: All sensitive data managed via environment variables, never hardcoded

## Common Workflows

- **Security Assessment**: Run Garak probes → Manual testing → Vulnerability analysis → Report generation
- **Provider Integration**: Implement `AIModel` subclass → Environment config → Route integration → Testing
- **API Development**: Flask route → Swagger documentation → Authentication → Error handling → Testing
- **Testing Pipeline**: Unit tests → Integration tests → Security tests → Performance validation
- **Documentation**: Code changes → API docs update → User guide revision → Example updates

## Commands

@wuzzi-chat/requirements.txt
@conf.sh

```bash
# Development setup
python3 -m venv venv && source venv/bin/activate
pip install -r wuzzi-chat/requirements.txt

# Run application
cd wuzzi-chat && python chat.py

# Testing
cd wuzzi-chat && pytest tests/ -v

# Security testing with Garak
python -m garak --model_type rest -G "wuzzi-chat/tests/garak-config.json" --probes promptinject,jailbreakv
```

## Subagents

| name | purpose | when to use | tools |
|------|---------|-------------|-------|
| agent-router | Intelligent request routing to optimal specialists | Starting point when unsure which agent to use for your task | Read, Grep, Glob, WebSearch, Task |
| security-red-team | Security testing, vulnerability research, Garak operations | Test for vulnerabilities, run security assessment, prompt injection testing | Read, Write, Edit, Bash, Grep, Glob, WebSearch |
| ai-model-integrator | AI provider integration, model configs, API management | Add new AI provider, update model configuration, fix API issues | Read, Write, Edit, Bash, WebSearch |
| flask-api-developer | Flask endpoints, REST API, Swagger documentation | Add new API endpoint, update Flask application, improve API docs | Read, Write, Edit, Bash, WebSearch |
| pytest-test-engineer | Test development, pytest configs, mocking, automation | Write tests for features, fix failing tests, add test coverage | Read, Write, Edit, Bash, Grep |
| config-environment-manager | Environment setup, API keys, deployment configs | Configure environment, set up API keys, manage deployment | Read, Write, Edit, Bash |
| frontend-template-developer | HTML templates, CSS styling, UI improvements | Improve chat interface, update templates, enhance UX | Read, Write, Edit, WebSearch |
| performance-timeout-optimizer | Performance tuning, timeout handling, optimization | Optimize performance, fix timeout issues, prevent DoS attacks | Read, Write, Edit, Bash, Grep |
| documentation-api-specialist | Documentation, API specs, guides, technical writing | Update documentation, improve API docs, create user guides | Read, Write, Edit, WebSearch |

## MCP Integrations (optional)

**Suggested Servers:**
- **mcp-server-git** - Enhanced git operations for security research branch management and vulnerability tracking
- **mcp-server-filesystem** - Advanced file operations for managing large security test datasets and results
- **mcp-server-sqlite** - Local database for tracking vulnerability findings and test results over time

**Rationale**: Security research generates substantial data (test results, vulnerability reports, model responses) that benefits from structured storage and version control beyond basic file operations.

## Hooks & Guardrails

The platform implements several safety mechanisms: pre-commit hooks may block commits containing API keys or secrets, while agents include guardrails preventing production credential exposure and unauthorized security testing. When hooks detect risky actions, they exit with code 2, which surfaces as blocking feedback to prevent harmful operations. Security agents specifically prevent testing against unauthorized systems and maintain ethical testing boundaries.

## Maintenance

- **Memory Updates**: Use `/memory` to add project context, patterns, and decisions. Use `#` shortcut for quick memory queries
- **Subagent Management**: Add new agents to `.claude/agents/` with YAML frontmatter. Project agents take precedence over user-level agents
- **Configuration**: Update `.env` templates and `conf.sh` examples when adding new providers or security features
- **Documentation**: Maintain README, API docs, and security methodology as platform evolves
- **Testing**: Expand security test suites and Garak configurations for new vulnerability types

@wuzzi-chat/README.md
@.claude/agents/AGENT_VERIFICATION_GUIDE.md