## TaskGuard Integration
This project uses TaskGuard for AI-ready task management.

**Essential Reference**: See `AGENTIC_AI_TASKGUARD_GUIDE.md` for complete AI collaboration guide.

### Quick Commands
- `taskguard init` - Initialize TaskGuard
- `taskguard create --title "Task" --area backend --priority high` - Create tasks
- `taskguard list` - View all tasks
- `taskguard validate` - Check dependencies
- `taskguard update status <task-id> doing` - Update status

### Workflow
1. Use CLI commands for ALL task metadata updates
2. Create tasks across different areas (setup, backend, api, frontend, etc.)
3. Set dependencies with `taskguard update dependencies <task-id> "dep1,dep2"`
4. Validate frequently with `taskguard validate`
