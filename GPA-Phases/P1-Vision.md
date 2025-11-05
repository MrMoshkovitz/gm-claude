### Phase 1: Concrete Vision Casting

**Objective**: Establish a tangible, implementable solution sketch before engaging AI assistance.

**Process**:
- Define specific problem with concrete solution outline
- Avoid abstract goals or open-ended problem statements  
- Present AI with structured, examnable proposition
- Explicitly defer implementation details
- **Critical**: Use strategic naming that focuses AI attention on mission

**Rationale**: AI systems excel at analysis and extension but struggle with vision generation from abstract requirements. Starting with concrete vision gives AI productive analytical targets while preserving human creative authority.

**Anti-patterns**: 
- "How should I build X?" (too open-ended)
- "What's the best way to solve Y?" (invites generic solutions)

**Preferred pattern**: "I want to build X that does A, B, C. Don't code anything, think about it."

**Key Principle**: Naming matters profoundly. The project name becomes a cognitive anchor that keeps AI focused on the core mission throughout all subsequent interactions.

**Prompt 1 (Phase 1: Concrete Vision Casting):**
```
I want to design a mcp "memory" server and agent. Once he scan a project (suppose python/JS/Typescript) he will make a networkx graph mapping all the project classes and modules (imported builtin and externals can be ignored unless important). Connecting the nodes with their relationships as edges).

Later when we built a project from md files we will be able to update and query it.

While testing, we can compare implementation to actually state.

This leverage deterministic knowledge with code agents statistics behavior.

Don't code nothing, think about it.
```
