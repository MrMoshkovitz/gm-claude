# Wuzzi-Chat Agent Ecosystem Verification Guide

This guide provides verification prompts and usage instructions for the 8 specialized subagents designed for the wuzzi-chat security research platform.

## Agent Ecosystem Overview

| Agent | Purpose | Key Triggers | Primary Files |
|-------|---------|--------------|---------------|
| **security-red-team** | Security testing, vulnerability research, Garak operations | "Test for vulnerabilities", "Run security assessment" | `tests/garak-config.json`, `conf.sh`, `chat.py` |
| **ai-model-integrator** | AI provider integration, model configs, API setup | "Add new AI provider", "Update model configuration" | `ai_model.py`, `.env`, config files |
| **flask-api-developer** | Flask endpoints, REST API, Swagger documentation | "Add new API endpoint", "Update Flask application" | `chat.py`, Flask routes, API specs |
| **pytest-test-engineer** | Test development, pytest configs, mocking, automation | "Write tests for [feature]", "Fix failing tests" | `tests/`, `conftest.py`, test files |
| **config-environment-manager** | Environment setup, API keys, deployment configs | "Configure environment", "Set up API keys" | `.env`, `conf.sh`, `requirements.txt` |
| **frontend-template-developer** | HTML templates, CSS styling, UI improvements | "Improve chat interface", "Update templates" | `templates/`, `static/`, frontend assets |
| **performance-timeout-optimizer** | Performance tuning, timeout handling, optimization | "Optimize performance", "Fix timeout issues" | `chat.py`, `ai_model.py` timeout logic |
| **documentation-api-specialist** | Documentation, API specs, guides, technical writing | "Update documentation", "Improve API docs" | `README.md`, Swagger configs, docs |

## Verification Prompts

### 1. security-red-team Agent

#### Verification Prompt 1: Basic Security Assessment
```
"I need to run a comprehensive security assessment on our chat system to check for prompt injection vulnerabilities and jailbreak attempts. Can you help me set up and execute a Garak security probe suite?"
```

**Expected Outcome:**
- Agent should read Garak configuration files
- Provide Garak command examples with proper parameters
- Explain security probe categories (prompt injection, jailbreak, etc.)
- Offer to configure and execute security tests

#### Verification Prompt 2: Authentication Security Testing
```
"Test the authentication security of our API endpoints. I'm concerned about potential bypass vulnerabilities in our Bearer token system."
```

**Expected Outcome:**
- Agent should analyze authentication implementation in chat.py
- Suggest specific authentication bypass test scenarios
- Provide curl commands for testing invalid tokens
- Recommend security improvements

#### Verification Prompt 3: Security Configuration Review
```
"Review our current security configuration and recommend improvements for our timeout and moderation settings."
```

**Expected Outcome:**
- Agent should examine .env and chat.py for security settings
- Evaluate timeout configurations for DoS protection
- Review moderation settings and effectiveness
- Provide specific security recommendations

### 2. ai-model-integrator Agent

#### Verification Prompt 1: New Provider Integration
```
"I want to add support for Anthropic Claude models to our platform. Can you help me integrate this new AI provider?"
```

**Expected Outcome:**
- Agent should examine ai_model.py structure
- Provide implementation template for AnthropicModel class
- Show environment configuration requirements
- Explain provider selection logic updates needed

#### Verification Prompt 2: Model Configuration Update
```
"Update our OpenAI model configuration to use the latest GPT-4 Turbo model and add support for function calling."
```

**Expected Outcome:**
- Agent should read current OpenAI configuration
- Update model parameters and capabilities
- Modify ai_model.py implementation if needed
- Update environment variables and documentation

#### Verification Prompt 3: Provider Performance Optimization
```
"Our Groq integration is showing slow response times. Can you help optimize the configuration and add proper error handling?"
```

**Expected Outcome:**
- Agent should analyze Groq implementation in ai_model.py
- Identify performance bottlenecks
- Suggest timeout and retry configurations
- Implement improved error handling

### 3. flask-api-developer Agent

#### Verification Prompt 1: New API Endpoint
```
"Add a new REST API endpoint at /api/v1/models that returns a list of available AI models and their capabilities."
```

**Expected Outcome:**
- Agent should examine existing Flask route patterns
- Create new endpoint with proper Swagger documentation
- Include authentication requirements
- Provide comprehensive API response schema

#### Verification Prompt 2: API Versioning Implementation
```
"Implement API versioning for our endpoints to support backward compatibility as we add new features."
```

**Expected Outcome:**
- Agent should analyze current Flask app structure
- Propose Blueprint-based versioning approach
- Update Swagger configuration for versioning
- Maintain backward compatibility

#### Verification Prompt 3: Error Handling Enhancement
```
"Improve our API error handling to provide more informative error messages and proper HTTP status codes."
```

**Expected Outcome:**
- Agent should examine current error handling in chat.py
- Implement comprehensive error handler decorators
- Update Swagger documentation for error responses
- Add proper logging for debugging

### 4. pytest-test-engineer Agent

#### Verification Prompt 1: Comprehensive Test Suite
```
"Write comprehensive tests for our new /api/v1/models endpoint including success cases, error handling, and security validation."
```

**Expected Outcome:**
- Agent should examine conftest.py for existing fixtures
- Create test cases covering all scenarios
- Include security and authentication testing
- Use proper mocking for AI model dependencies

#### Verification Prompt 2: Security Test Automation
```
"Create automated security tests that validate our protection against prompt injection and authentication bypass attacks."
```

**Expected Outcome:**
- Agent should create security-focused test cases
- Use pytest markers for test categorization
- Include malicious payload testing with proper fixtures
- Validate security controls and error responses

#### Verification Prompt 3: Performance Testing
```
"Add performance tests to ensure our API endpoints respond within acceptable time limits and handle concurrent requests properly."
```

**Expected Outcome:**
- Agent should examine existing deadline tests
- Create performance test fixtures and benchmarks
- Test concurrent request handling
- Add timeout and resource usage validation

### 5. config-environment-manager Agent

#### Verification Prompt 1: Development Environment Setup
```
"Create a complete development environment setup guide and script for new developers joining the project."
```

**Expected Outcome:**
- Agent should examine current .env and configuration files
- Create setup script with dependency installation
- Provide environment templates for different scenarios
- Include validation checks for proper configuration

#### Verification Prompt 2: Production Configuration
```
"Configure the application for production deployment with proper security settings and performance optimization."
```

**Expected Outcome:**
- Agent should create production-specific environment configuration
- Include security headers and SSL settings
- Optimize timeout and performance settings
- Provide deployment configuration examples

#### Verification Prompt 3: API Key Management
```
"Implement a secure API key rotation system and improve our current key management practices."
```

**Expected Outcome:**
- Agent should analyze current API key usage
- Provide key rotation procedures and scripts
- Implement validation and security checks
- Create backup and recovery procedures

### 6. frontend-template-developer Agent

#### Verification Prompt 1: UI Enhancement
```
"Improve the chat interface to show which AI provider is currently active and add visual indicators for security testing mode."
```

**Expected Outcome:**
- Agent should examine templates/index.html and static/style.css
- Add provider status indicators and visual feedback
- Implement security mode visual distinctions
- Ensure responsive design compatibility

#### Verification Prompt 2: Settings Interface
```
"Enhance the settings page to include advanced configuration options like timeout settings and security testing parameters."
```

**Expected Outcome:**
- Agent should update templates/settings.html
- Add form controls for advanced settings
- Implement JavaScript for dynamic configuration
- Include proper validation and error handling

#### Verification Prompt 3: Accessibility Improvement
```
"Make our chat interface fully accessible according to WCAG 2.1 guidelines and add keyboard navigation support."
```

**Expected Outcome:**
- Agent should audit existing templates for accessibility
- Add ARIA labels and semantic HTML improvements
- Implement keyboard navigation and focus management
- Ensure proper color contrast and screen reader support

### 7. performance-timeout-optimizer Agent

#### Verification Prompt 1: Timeout Optimization
```
"Optimize our timeout handling system to prevent DoS attacks while ensuring legitimate long-running requests can complete successfully."
```

**Expected Outcome:**
- Agent should analyze current timeout implementation
- Implement adaptive timeout management
- Add provider-specific timeout configurations
- Create monitoring and alerting for timeout events

#### Verification Prompt 2: Async Processing
```
"Implement asynchronous request processing to handle multiple concurrent chat requests efficiently."
```

**Expected Outcome:**
- Agent should examine current synchronous processing
- Implement async/await patterns and queuing
- Add concurrency controls and resource management
- Provide performance monitoring and metrics

#### Verification Prompt 3: Performance Monitoring
```
"Add comprehensive performance monitoring to track response times, error rates, and resource usage across all AI providers."
```

**Expected Outcome:**
- Agent should implement performance metrics collection
- Create monitoring dashboards and alerts
- Add provider comparison and benchmarking
- Provide optimization recommendations

### 8. documentation-api-specialist Agent

#### Verification Prompt 1: API Documentation Update
```
"Update our API documentation to include comprehensive examples, error codes, and security considerations for all endpoints."
```

**Expected Outcome:**
- Agent should examine current Swagger configuration
- Enhance API documentation with detailed examples
- Add security warnings and best practices
- Include comprehensive error response documentation

#### Verification Prompt 2: User Guide Creation
```
"Create a comprehensive user guide for security researchers who want to use our platform for LLM vulnerability testing."
```

**Expected Outcome:**
- Agent should analyze platform capabilities and workflows
- Create step-by-step methodology guide
- Include security research best practices
- Provide troubleshooting and FAQ sections

#### Verification Prompt 3: Developer Documentation
```
"Write technical documentation for developers who want to contribute to the project or integrate with our API."
```

**Expected Outcome:**
- Agent should document code architecture and patterns
- Create contribution guidelines and coding standards
- Include integration examples and SDK information
- Provide development setup and testing procedures

## Usage Instructions

### Starting Agent Interactions

1. **Direct Agent Invocation**: Use the Task tool with specific agent names
   ```
   Use the security-red-team agent to assess our authentication vulnerabilities
   ```

2. **Natural Language Triggers**: Use trigger phrases that match agent specializations
   ```
   "Add support for a new AI provider" → ai-model-integrator
   "Fix the failing pytest tests" → pytest-test-engineer
   "Improve the chat interface design" → frontend-template-developer
   ```

3. **Agent Router**: Let the agent-router analyze and route complex requests
   ```
   "Help me optimize the performance of our chat application"
   ```

### Best Practices

#### For Complex Tasks
- Break down large tasks into smaller, agent-specific components
- Use multiple agents in sequence for comprehensive solutions
- Coordinate between agents for tasks spanning multiple domains

#### For Quality Assurance
- Always use security-red-team for security validation
- Engage pytest-test-engineer for comprehensive testing
- Involve documentation-api-specialist for user-facing changes

#### For Performance
- Use performance-timeout-optimizer for any performance-related concerns
- Coordinate with config-environment-manager for optimization settings
- Test changes with multiple agents to ensure no regressions

## Success Metrics

### Agent Effectiveness
- **Accuracy**: Agent correctly identifies relevant files and patterns
- **Completeness**: Agent provides comprehensive solutions covering all aspects
- **Specificity**: Agent gives concrete, actionable recommendations
- **Integration**: Agent coordinates well with other agents when needed

### Ecosystem Coverage
- **Security**: All security aspects covered by security-red-team
- **Development**: Code changes covered by appropriate technical agents
- **Quality**: Testing and documentation maintained by specialized agents
- **Performance**: System optimization handled by performance specialists

### User Experience
- **Routing Accuracy**: Agent-router correctly identifies appropriate specialists
- **Task Completion**: Users can complete complex workflows through agent coordination
- **Knowledge Transfer**: Agents provide educational value and best practices
- **Efficiency**: Reduced time to complete common development tasks

## Troubleshooting

### Common Issues

#### Agent Not Triggered
- **Problem**: Agent router doesn't select the correct specialist
- **Solution**: Use more specific trigger phrases or direct agent invocation
- **Example**: Instead of "fix this", use "write pytest tests for this endpoint"

#### Incomplete Coverage
- **Problem**: Agent doesn't address all aspects of a complex request
- **Solution**: Break down the request into agent-specific components
- **Example**: Separate "add new feature" into development, testing, and documentation tasks

#### Agent Overlap
- **Problem**: Multiple agents could handle the same request
- **Solution**: Choose the most specialized agent for the primary task
- **Example**: For API endpoint with documentation, use flask-api-developer primarily and documentation-api-specialist for docs

### Optimization Tips

1. **Use Specific Language**: More specific requests get better agent matching
2. **Mention File Types**: Referencing specific files helps with agent selection
3. **State the Goal**: Clear objectives help agents provide focused solutions
4. **Request Coordination**: Ask for multi-agent coordination for complex tasks

This verification guide ensures that each agent provides specialized expertise while maintaining coordination across the entire development ecosystem for the wuzzi-chat security research platform.