# VoicePrep: Standard Prompt Template

## MANDATORY PREFIX (Add to ALL prompts)

```
## PROTOCOLS

1. **ULTRATHINK** - Deep reasoning before action
2. **READ FIRST**: Start by reading @CLAUDE.md instruction file
3. **AGENT ROUTER**: Use @agent-router to identify best agent for task
4. **SUBAGENTS**: Use ALL relevant agents from ./.claude/agents/*
5. **SKILLS**: Use ALL relevant skills from ./.claude/skills/*
6. **ACCURACY**: Read source code + docs. Validate yourself. Accuracy is critical.
7. **COMMITS**: Never write "Claude" - User is always the author
8. **TASKGUARD**: All work through `taskguard add/start/done`
9. **TESTING**: No delivery without E2E verification

---
```

## MANDATORY SUFFIX (Add to ALL prompts)

```
---

## EXECUTION PROTOCOL

1. Read CLAUDE.md
2. Run agent-router → identify best agent
3. Create taskguard task before work
4. Use relevant subagents + skills
5. Validate against source code
6. Test E2E before delivery
7. Commit with user as author (no "Claude")

## VERIFICATION CHECKLIST

Before saying "done":
- [ ] Source code read and understood
- [ ] Subagents/skills used where relevant
- [ ] Taskguard task created and tracked
- [ ] E2E test passed
- [ ] No errors in logs
- [ ] Commit message has no "Claude"
```

---

## EXAMPLE: Complete Prompt with Prefix/Suffix

```markdown
## PROTOCOLS

1. **ULTRATHINK** - Deep reasoning before action
2. **READ FIRST**: Start by reading @CLAUDE.md instruction file
3. **AGENT ROUTER**: Use @agent-router to identify best agent for task
4. **SUBAGENTS**: Use ALL relevant agents from ./.claude/agents/*
5. **SKILLS**: Use ALL relevant skills from ./.claude/skills/*
6. **ACCURACY**: Read source code + docs. Validate yourself. Accuracy is critical.
7. **COMMITS**: Never write "Claude" - User is always the author
8. **TASKGUARD**: All work through `taskguard add/start/done`
9. **TESTING**: No delivery without E2E verification

---

# [ACTUAL TASK TITLE]

[Task content here...]

---

## EXECUTION PROTOCOL

1. Read CLAUDE.md
2. Run agent-router → identify best agent
3. Create taskguard task before work
4. Use relevant subagents + skills
5. Validate against source code
6. Test E2E before delivery
7. Commit with user as author (no "Claude")

## VERIFICATION CHECKLIST

Before saying "done":
- [ ] Source code read and understood
- [ ] Subagents/skills used where relevant
- [ ] Taskguard task created and tracked
- [ ] E2E test passed
- [ ] No errors in logs
- [ ] Commit message has no "Claude"
```

---

## APPLYING TO CURRENT TASK

Now applying to the start button + audio fix:

---

## PROTOCOLS

1. **ULTRATHINK** - Deep reasoning before action
2. **READ FIRST**: Start by reading @CLAUDE.md instruction file
3. **AGENT ROUTER**: Use @agent-router to identify best agent for task
4. **SUBAGENTS**: Use ALL relevant agents from ./.claude/agents/*
5. **SKILLS**: Use ALL relevant skills from ./.claude/skills/*
6. **ACCURACY**: Read source code + docs. Validate yourself. Accuracy is critical.
7. **COMMITS**: Never write "Claude" - User is always the author
8. **TASKGUARD**: All work through `taskguard add/start/done`
9. **TESTING**: No delivery without E2E verification

---

# VoicePrep: Missing Start Button + No Audio

## PROBLEM
- No "התחל ראיון" button visible
- Audio not playing even with "מוכן" status

## ROOT CAUSE ANALYSIS
1. Start button never added to HTML
2. AudioContext requires user gesture (browser security)
3. Audio playback handler missing or not wired

## FIX

### 1. Add Start Button
```html
<button id="startBtn" onclick="startInterview()">התחל ראיון</button>
```

### 2. Initialize AudioContext on Click
```javascript
let audioContext;

async function startInterview() {
    audioContext = new AudioContext();
    await navigator.mediaDevices.getUserMedia({ audio: true });
    ws.send(JSON.stringify({ type: 'start' }));
    document.getElementById('startBtn').style.display = 'none';
}
```

### 3. Wire Audio Playback
```javascript
ws.onmessage = async (event) => {
    if (event.data instanceof Blob) {
        const arrayBuffer = await event.data.arrayBuffer();
        const audioBuffer = await audioContext.decodeAudioData(arrayBuffer);
        const source = audioContext.createBufferSource();
        source.buffer = audioBuffer;
        source.connect(audioContext.destination);
        source.start();
    }
};
```

---

## EXECUTION PROTOCOL

1. Read CLAUDE.md
2. Run agent-router → identify best agent
3. Create taskguard task before work
4. Use relevant subagents + skills
5. Validate against source code
6. Test E2E before delivery
7. Commit with user as author (no "Claude")

## VERIFICATION CHECKLIST

Before saying "done":
- [ ] Source code read and understood
- [ ] Subagents/skills used where relevant
- [ ] Taskguard task created and tracked
- [ ] E2E test passed
- [ ] No errors in logs
- [ ] Commit message has no "Claude"

---

**BEGIN: Read CLAUDE.md → agent-router → taskguard add → implement → test → commit.**
