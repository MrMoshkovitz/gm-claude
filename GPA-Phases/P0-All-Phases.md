
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


### Phase 2: Iterative Deepening Pattern

**Objective**: Systematically evolve the initial vision through structured refinement cycles while maintaining architectural coherence.

**Process**:
- Present evolved concept based on initial vision
- Invite AI analysis and extensions
- **Critical**: Process AI feedback internally according to established principles
- Return with evolved but coherent vision
- Repeat cycle until architectural completeness achieved
- **Hard Blocking**: Never proceed to next phase until completely satisfied with current iteration

**Rationale**: This addresses the fundamental challenge of AI collaboration - leveraging comprehensive analytical capabilities while preventing vision dilution. Each cycle adds sophistication without losing the core insight.

**Implementation Rules**:
- **Message Editing Protocol**: Always edit and refine messages rather than continuing explanation in subsequent prompts
- **Phase Blocking**: Complete satisfaction with current phase is mandatory before progression
- **Token Economy**: Every word counts - think carefully about each response as you're dealing with "The Butterfly Effect"


**Prompt 2 (Phase 2: Iterative Deepening - Cycle 1):**
```
About queries, I will give you a vision example: compering the trace log of a failure to the graph to figure what is missing.
```


**Prompt 3 (Phase 2: Iterative Deepening - Cycle 2):**
```
Next, another scenario: the agent will create a vision graph (can have a implement flag), there will be a codebase graph (we scanned). And use this diff engine to know what is missing.
```

### Phase 3: Collaborative Stress Testing

**Objective**: Systematically surface concerns, edge cases, and implementation challenges through AI analysis.

**Process**:
- Explicitly invite AI to identify problems and limitations
- Resist immediate problem-solving; focus on problem collection
- Encourage exploration of failure modes and complexity sources
- Document all concerns without filtering
- **Critical**: Avoid arguing with AI to make it understand better - this causes faster vision loss

**Rationale**: Human architects often suffer from confirmation bias and blind spots. AI's pattern-matching capabilities can identify issues that human intuition misses. However, this phase must remain diagnostic rather than prescriptive.

**Key Principle**: Flood problems, don't fix them yet. Remember that instruction-tuned LLMs want to satisfy your latest prompt - maintain focus through consistent messaging.


**Prompt 4 (Phase 3: Collaborative Stress Testing):**
```
Anything else I am missing? not thinking far into the future of deterministic/vibing? pros/cons?
```


### Phase 4: Philosophical Grounding

**Objective**: Establish decision-making principles that filter subsequent choices and maintain architectural coherence.

**Process**:
- Identify core values and principles underlying the solution
- Connect technical choices to human-centered philosophy
- Establish clear boundaries and non-negotiables
- Create decision-making framework for future trade-offs
- **Critical**: Articulate philosophy clearly to provide consistent decision criteria

**Rationale**: This phase transforms scattered technical concerns into coherent worldview. Philosophical grounding prevents both human and AI from getting lost in infinite optimization cycles by providing consistent decision criteria.

**Example**: The "My Way" principle in our case study became a lens for every subsequent architectural decision.

**Prompt 5 (Phase 4: Philosophical Grounding):**
```
Version control and branches: we will use a graphs database, allow us to save for later sessions and collaborate teams. Plus efficient diffs. No need to reinvent the wheel. I think separate graphs will be easier to maintain/sync.
Team conflicts - our job is to flood problems, might suggest but not fix and replace the developer. Evolution problem: up to the developer to decide. Cognitive load: this system will reduce them.
Meta Challenge and Philosophy: no single point of truth(except one god), This is my vision, I did it my way...

Dynamic situation you described: off the scope of this project (vision<->codebase<->tracelog), It's complicated enough without them).
```


### Phase 5: Principled Boundary Setting

**Objective**: Use philosophical framework to make rapid, consistent scope decisions.

**Process**:
- Apply established principles to each identified concern
- Make decisive cuts to features that don't serve core vision
- Resist feature creep through principle-driven decisions
- Maintain focus on essential functionality
- **Final Implementation**: Create all deliverable files at once in a single prompt, not sequentially

**Rationale**: Without principled boundary setting, AI collaboration leads to scope explosion. Every AI-suggested improvement seems reasonable in isolation, but collectively they destroy focus and delay shipping.

**Decision Framework**: 
- Does this serve the core vision?
- Does this align with established principles?
- Is this essential for the primary use case?

**Implementation Principle**: The optimal process requires only 6-7 well-crafted prompts using message editing and phase blocking to achieve complete architectural specification.

**Prompt 6 (Phase 5: Principled Boundary Setting and Implementation):**
```
The system name will honor "Sinatra". Break it down to consice vision, prd and implementation md files. No over engendering.
```


**Prompt 7 (Phase 5: Final Documentation):**
```
Now a final document that explains the philosophy and the choices we did.
```

### Phase 6: Meta-Cognitive Review

**Objective**: Analyze and improve the design process itself.

**Process**:
- Examine decision patterns and methodology effectiveness
- Identify reusable principles and process improvements
- Document methodology evolution for future projects
- Build conscious competence in human-AI collaboration

**Rationale**: Continuous process improvement prevents methodology stagnation and builds systematic capability for future human-AI design collaboration.


**Prompt 8 (Phase 6: Meta-Cognitive Review):**
```
I want one last meta review document on how my (the user, Eliran) approach of designing to help my friends:
How I introduced you the problem, then we extended it, review it and I responded to your concerns, then to the vision, to the final plans. I might confused the order. Dig into my thinking process.
```
