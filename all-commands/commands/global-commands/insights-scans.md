---
description: Static AST scan of Garak and Wuzzi, outputting ./Insights/*.md and JSON.
allowed-tools: Read, Grep, Glob, Bash(python3 *:*)
---
## Context
Roots:
- @"/Users/gmoshkov/Professional/Code/LLM-Red-Team/Garak/garak-repo/garak"
- @"/Users/gmoshkov/Professional/Code/LLM-Red-Team/Garak/wuzzi-chat-repo/wuzzi-chat"

## Task
1) Plan in read-only; show analyzer API + edits.
2) Write ./Insights/tools/analyze_ast.py
3) Run analyzer to produce JSON graphs + Markdown with Mermaid diagrams.
4) Save to:
   - Insights/Garak-Insights.md
   - Insights/Wuzzi-Insights.md
