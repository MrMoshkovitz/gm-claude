# CLAUDE.md

**Garak LLM Vulnerability Scanner** - Configuration & Development Guide

## Project Overview

Garak is a generative AI red-teaming and assessment kit that probes Large Language Models (LLMs) for security vulnerabilities. It functions similarly to `nmap` or Metasploit Framework for traditional security, but focuses on LLM-specific weaknesses including hallucination, data leakage, prompt injection, misinformation, toxicity generation, and jailbreaks.

**Project Import References:**
- @README.md - Complete project overview and usage examples
- @FAQ.md - Frequently asked questions and conceptual guidance
- @CONTRIBUTING.md - Development guidelines and contribution process
- @pyproject.toml - Build configuration, dependencies, and development tools

## Architecture

Garak follows a modular plugin architecture with clear separation of concerns:

- **Core Components:**
  - `garak/cli.py` - Command-line interface and main orchestration
  - `garak/command.py` - Command processing and execution logic
  - `garak/_config.py` - Configuration management system
  - `garak/_plugins.py` - Plugin discovery and loading mechanisms

- **Plugin Categories:**
  - `garak/probes/` - Generate interactions with LLMs to test vulnerabilities
  - `garak/detectors/` - Analyze LLM outputs for specific failure modes
  - `garak/generators/` - Interface adapters for different LLM providers
  - `garak/evaluators/` - Assessment reporting and analysis schemes
  - `garak/harnesses/` - Structure and orchestrate testing workflows

- **Supporting Systems:**
  - `garak/resources/` - Static assets, configurations, and data files
  - `garak/data/` - Test datasets and reference materials
  - `garak/configs/` - Pre-defined scan configuration templates

## Key Patterns

- **Plugin Inheritance:** All plugins inherit from base classes in `*/base.py` files - override minimal methods while leveraging shared functionality
- **Configuration Management:** Uses `Configurable` mixin for consistent parameter handling across all components
- **Stochastic Testing:** Multiple generations per prompt due to LLM output variability
- **Modular Detection:** Probes specify recommended detectors; harnesses coordinate execution
- **Exception Handling:** Custom `GarakException` hierarchy for structured error management
- **Parallel Execution:** Configurable parallelization for both generation and evaluation phases

## Common Workflows

- **Development Testing:** `pytest` with coverage analysis and mock frameworks
- **Code Quality:** `black` formatting, `pylint` linting, pre-commit hooks
- **Plugin Development:** Create new modules inheriting from base classes, test with blank generators/detectors
- **Security Scanning:** Configure probes and detectors, execute via CLI, analyze JSONL reports
- **Research Integration:** Add new vulnerability categories, implement detection algorithms

## Commands

```bash
# Installation & Setup
python -m pip install -e .                    # Development install
python -m pip install garak[tests,lint]       # With optional dependencies

# Development
pytest                                         # Run test suite
pytest --cov=garak tests/                     # Run with coverage
black .                                        # Format code
pylint garak/                                  # Lint codebase
pre-commit run --all-files                    # Run pre-commit hooks

# Core Usage
python -m garak --list_probes                 # List available vulnerability probes
python -m garak --list_generators             # List supported LLM providers
python -m garak --list_detectors              # List vulnerability detectors
python -m garak --model_type openai --model_name gpt-3.5-turbo --probes encoding
```

## Subagents

| Name | Purpose | When to Use | Tools |
|------|---------|-------------|-------|
| agent-router | Intelligent task routing to specialized agents | Primary entry point for unclear tasks, complex multi-domain requests | Read, Grep, Glob, WebSearch, Task |
| config-manager | Manage LLM provider credentials and scan configurations | Configure scan parameters, setup multi-environment deployments | Read, Write, Edit, Grep, Glob |
| detector-developer | Create and enhance vulnerability detection algorithms | Develop new detection methods, enhance pattern-based/ML detection | Read, Write, Edit, Grep, Glob, Bash |
| generator-integrator | Add and maintain LLM provider integrations | Integrate new LLM providers, maintain API connections | Read, Write, Edit, Grep, Glob, Bash, WebFetch |
| plugin-architect | Manage plugin system architecture and loading | Maintain plugin discovery, design plugin interfaces | Read, Edit, Grep, Glob, Bash |
| probe-developer | Create vulnerability probe modules and attack vectors | Develop new vulnerability probes, implement jailbreaking tests | Read, Write, Edit, Grep, Glob, Bash |
| quality-enforcer | Maintain code quality and style consistency | Enforce code standards, run linting checks, fix formatting | Read, Edit, Bash, Grep, Glob |
| report-analyzer | Process scan results and generate security insights | Analyze JSONL results, generate executive summaries | Read, Write, Edit, Grep, Glob, Bash |
| security-scanner | Execute comprehensive vulnerability assessments | Run security scans, interpret results, perform model comparisons | Read, Edit, Bash, Grep |
| test-runner | Execute test suites and manage CI/CD workflows | Run test suites, manage CI/CD, monitor coverage | Read, Edit, Bash, Grep, Glob |
| vuln-researcher | Research emerging AI vulnerabilities and implement novel attacks | Research threats, analyze academic papers, implement attack vectors | Read, Write, Edit, WebFetch, Grep, Glob |

## MCP Integrations (Optional)

Potential MCP servers that could enhance Garak development:

- **Security Research APIs** - Integrate CVE databases, threat intelligence feeds for vulnerability context
- **Academic Paper Search** - Automated monitoring of AI security research publications
- **Model Registry APIs** - Streamlined access to emerging LLM providers and model variants
- **Reporting Platforms** - Export scan results to security dashboards and compliance systems

*Note: Specific MCP server configuration should be coordinated with the development team based on operational requirements.*

## Hooks & Guardrails

Garak implements security-focused pre-commit hooks via `.pre-commit-config.yaml` that may block risky actions including mixed line endings, trailing whitespace, and code formatting violations. When hooks return exit code 2, they actively prevent commits to maintain code quality and security standards. This protective behavior ensures defensive security practices are consistently applied across all contributions.

## Maintenance

- **Memory Management:** Use `/memory` command to access project-specific memories and configuration guidance
- **Agent Updates:** Project agents in `.claude/agents/` take precedence over user-level agents in `~/.claude/agents/`
- **Configuration Updates:** Edit `@pyproject.toml` for dependencies, use `#` shortcut for quick memory access
- **Documentation Sync:** Keep `@README.md` and `@FAQ.md` current with feature additions and usage patterns

---

*This configuration complements the system prompt Layer 2 configuration without overriding core functionality. For detailed API documentation, see [reference.garak.ai](https://reference.garak.ai/)*