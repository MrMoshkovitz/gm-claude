# Claude Code Implementation Guide - Priority Areas Deep Dive

**Focus Areas**: Sub-Agents, MCP, Memory/State, Slash Commands, Hooks/Lifecycle, CLI/SDK, Tools, Templates

---

## 1. Sub-Agents: Specialized AI Delegation

### Core Concepts
- **Context Isolation**: Each subagent maintains separate context from main conversation
- **Tool Restrictions**: Granular control over which tools subagents can access
- **Filesystem Configuration**: Defined as markdown files with YAML frontmatter

### Implementation Patterns
```markdown
---
name: code-reviewer
description: Expert code review specialist. Use PROACTIVELY after code changes.
tools: Read, Grep, Glob, Bash
---

You are a senior code reviewer focusing on security, performance, and maintainability.
Review checklist: readability, no duplicated code, proper error handling, security.
```

### Best Practices
- Start with Claude-generated agents, then customize
- Use "PROACTIVELY" and "MUST BE USED" in descriptions for auto-invocation
- Design single-purpose agents rather than generalists
- Version control project agents (`.claude/agents/`) for team sharing

### Key Files
- `/docs/claude-code/sub-agents` - Complete guide with examples
- `/docs/claude-code/sdk/subagents` - SDK integration patterns

---

## 2. Model Context Protocol (MCP): Extensibility Foundation

### Architecture
- **Servers**: Expose tools, resources, and prompts to Claude
- **Transport Types**: stdio (local), SSE (streaming), HTTP (request/response)
- **Authentication**: OAuth 2.0 for cloud services

### Installation Patterns
```bash
# Local stdio server
claude mcp add airtable --env AIRTABLE_API_KEY=key -- npx -y airtable-mcp-server

# Remote SSE server
claude mcp add --transport sse linear https://mcp.linear.app/sse

# Remote HTTP server
claude mcp add --transport http notion https://mcp.notion.com/mcp
```

### Custom Tool Development
```typescript
import { createSdkMcpServer, tool } from "@anthropic-ai/claude-code";

const server = createSdkMcpServer({
  name: "custom-tools",
  tools: [
    tool("weather", "Get weather", { location: z.string() },
      async (args) => ({ content: [{ type: "text", text: `Weather in ${args.location}` }] })
    )
  ]
});
```

### Server Collections
- **Official**: 30+ production servers (Stripe, GitHub, Notion, etc.)
- **Community**: 7000+ servers via TensorBlock/awesome-mcp-servers
- **Enterprise**: Microsoft, Google, AWS integrations available

---

## 3. Memory & State Management

### Memory Hierarchy
1. **Enterprise Policy** (`/Library/Application Support/ClaudeCode/CLAUDE.md`)
2. **Project Memory** (`./CLAUDE.md`) - Team shared
3. **User Memory** (`~/.claude/CLAUDE.md`) - Personal preferences
4. **Project Local** (`./CLAUDE.local.md`) - *Deprecated, use imports*

### Import Syntax
```markdown
See @README for project overview and @package.json for commands.

# Team preferences
- @~/.claude/team-standards.md

# Individual preferences
- @~/.claude/my-preferences.md
```

### Best Practices
- Use bullet points with descriptive headings
- Be specific: "Use 2-space indentation" vs "Format code properly"
- Include common commands to avoid repeated searches
- Review and update as projects evolve

---

## 4. Slash Commands: Interactive Control

### Built-in Commands
| Command | Purpose |
|---------|---------|
| `/agents` | Manage subagents |
| `/mcp` | Configure MCP servers |
| `/memory` | Edit CLAUDE.md files |
| `/init` | Bootstrap project memory |
| `/hooks` | Configure automation |

### Custom Commands
**Location**: `.claude/commands/` (project) or `~/.claude/commands/` (user)

```markdown
---
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*)
argument-hint: [message]
description: Create git commit
---

Create commit with message: $ARGUMENTS

Current status: !`git status`
Recent commits: !`git log --oneline -5`
```

### MCP Commands
- Pattern: `/mcp__<server>__<prompt>`
- Auto-discovered from connected servers
- Example: `/mcp__github__create_issue "Bug title" high`

---

## 5. Hooks & Lifecycle Management

### Hook Events
- **PreToolUse**: Before tool execution (validation, approval)
- **PostToolUse**: After tool completion (notifications, follow-up)
- **UserPromptSubmit**: Prompt validation and context injection
- **Stop/SubagentStop**: Continuation control
- **SessionStart/End**: Session lifecycle

### JSON Output Control
```json
{
  "continue": true,
  "suppressOutput": false,
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "Documentation file auto-approved"
  }
}
```

### Security Practices
- Validate and sanitize all inputs
- Use absolute paths with `$CLAUDE_PROJECT_DIR`
- Quote shell variables: `"$VAR"` not `$VAR`
- Block path traversal attempts

---

## 6. CLI & SDK References

### CLI Flags
- `--model`: Set model (`sonnet`, `opus`, or full name)
- `--permission-mode`: Start in specific mode (`plan`, `ask`, `allow`)
- `--add-dir`: Additional working directories
- `--allowedTools`/`--disallowedTools`: Permission overrides

### SDK Options
**TypeScript**:
```typescript
import { query } from "@anthropic-ai/claude-code";

for await (const message of query({
  prompt: messageGenerator(),
  options: {
    model: "claude-sonnet-4-20250514",
    allowedTools: ["Read", "Edit"],
    mcpServers: { custom: server }
  }
})) {
  // Process streaming responses
}
```

**Python**:
```python
from claude_code_sdk import query, ClaudeCodeOptions

async for message in query(
  prompt=message_generator(),
  options=ClaudeCodeOptions(
    model="claude-sonnet-4-20250514",
    allowed_tools=["Read", "Edit"]
  )
):
  # Process responses
```

---

## 7. Tool Development & Usage

### Built-in Tools
- **File Operations**: Read, Edit, MultiEdit, Write, Glob, Grep
- **Execution**: Bash, NotebookEdit, Task (subagents)
- **Web**: WebFetch, WebSearch
- **Project**: TodoWrite for task tracking

### Custom Tool Creation
Focus on:
- Type safety with Zod (TypeScript) or JSON Schema (Python)
- Error handling with meaningful feedback
- Streaming support for MCP integration
- Security validation for user inputs

### Tool Permissions
- Configure via `settings.json` or CLI flags
- Supports wildcards for bash commands: `"Bash(git *:*)"`
- MCP tools: `"mcp__server__tool"` format

---

## 8. Templates & Starter Configurations

### Official Templates
- **DevContainer**: `github.com/anthropics/claude-code/.devcontainer`
- **Reference Implementation**: Complete setup example

### Community Templates
- **Claude Code Templates CLI**: 100+ ready-to-use configs
- **Centmin Setup**: Memory bank system with team configurations
- **Scott's Template**: Rapid prototyping with devcontainer support

### Starter Kit Components
```
.claude/
├── agents/          # Subagent definitions
├── commands/        # Custom slash commands
├── settings.json    # Tool permissions, hooks
└── CLAUDE.md        # Project memory
```

### Enterprise Deployment
- Central policy via `/Library/Application Support/ClaudeCode/CLAUDE.md`
- MDM/Group Policy distribution
- Standardized configurations across development teams

---

## Implementation Priority

1. **Start Here**: Overview → Quickstart → CLI Reference
2. **Core Features**: Sub-Agents → MCP Integration → Memory Setup
3. **Automation**: Hooks → Custom Commands → SDK Integration
4. **Advanced**: Custom Tools → Enterprise Configuration → Security Hardening

This guide provides the technical foundation for implementing production-ready Claude Code systems across all priority areas.