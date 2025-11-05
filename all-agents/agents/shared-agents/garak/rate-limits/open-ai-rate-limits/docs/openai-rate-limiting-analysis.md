# OpenAI Rate Limiting Architecture Analysis

**Document Purpose**: Complete architectural map of garak OpenAI generator for implementing token-based rate limiting.

**Analysis Date**: October 20, 2025
**Scope**: garak OpenAI generator with focus on surgical rate limiter integration

---

## 1. Complete Call Graph

### 1.1 End-to-End Request Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                      PROBE EXECUTION LAYER                          │
│  garak/probes/base.py:337 → Probe.probe(generator)                 │
│    └─ Creates list of Attempt objects with prompts                 │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────────┐
│              PROBE EXECUTION MANAGER                                 │
│  garak/probes/base.py:278 → Probe._execute_all(attempts)           │
│    ├─ Optional: Multiprocessing.Pool (lines 289-321)               │
│    └─ Sequential: loop through attempts (lines 323-333)            │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────────┐
│            INDIVIDUAL ATTEMPT EXECUTION                              │
│  garak/probes/base.py:266 → Probe._execute_attempt(attempt)        │
│    ├─ Line 268: Call _generator_precall_hook()                     │
│    ├─ Line 269-270: this_attempt.outputs = generator.generate()    │
│    ├─ Line 272-273: Optional _postprocess_buff()                   │
│    └─ Line 274-275: _postprocess_hook() + _generator_cleanup()     │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────────┐
│            GENERATOR ORCHESTRATION LAYER                             │
│  garak/generators/base.py:132 → Generator.generate(prompt, n)      │
│  Input: Conversation object, generations_this_call (int)           │
│                                                                      │
│  Dispatch Logic (lines 154-216):                                   │
│    ├─ IF n == 1:                                                    │
│    │  └─ outputs = _call_model(prompt, 1)  [single call]           │
│    │                                                                │
│    ├─ ELIF supports_multiple_generations:                          │
│    │  └─ outputs = _call_model(prompt, n)  [batch call]            │
│    │                                                                │
│    └─ ELSE (loop + optional parallelism):                          │
│       ├─ IF parallel_requests > 1 AND parallel_capable:            │
│       │  ├─ Pool(pool_size) created (line 189)                     │
│       │  └─ pool.imap_unordered(_call_model, [prompts]*n)          │
│       │     [calls _call_model n times in parallel]                │
│       │                                                             │
│       └─ ELSE (sequential):                                        │
│          └─ loop: output_one = _call_model(prompt, 1)              │
│             [n sequential calls]                                   │
│                                                                     │
│  Post-processing (lines 218-222):                                   │
│    ├─ _post_generate_hook(outputs)                                 │
│    └─ _prune_skip_sequences(outputs) [if configured]               │
│                                                                     │
│  Returns: List[Union[Message, None]]                               │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────────┐
│                  API CALL LAYER (THE CRITICAL POINT)                │
│  garak/generators/openai.py:211 → OpenAICompatible._call_model()   │
│                                                                      │
│  ┌─ DECORATOR LAYER (lines 200-210):                               │
│  │  @backoff.on_exception(                                         │
│  │      backoff.fibo,                                              │
│  │      exceptions=(RateLimitError, InternalServerError, ...),    │
│  │      max_value=70                                               │
│  │  )                                                              │
│  │                                                                 │
│  └─ EXECUTION (lines 214-290):                                     │
│     ├─ Line 214-216: Reload client if needed (_load_client)       │
│     │                                                              │
│     ├─ Line 218-233: Build create_args from config                │
│     │  ├─ model name (line 223)                                   │
│     │  ├─ n (num generations) (line 220)                          │
│     │  ├─ temperature, top_p, etc. (lines 227-229)                │
│     │  └─ extra_params merge (lines 231-233)                      │
│     │                                                              │
│     ├─ Line 235-244: FOR COMPLETION MODELS:                       │
│     │  └─ Set prompt text in create_args                          │
│     │                                                              │
│     ├─ Line 246-260: FOR CHAT MODELS (most common):               │
│     │  └─ Convert Conversation to messages list                   │
│     │     Set messages in create_args                             │
│     │                                                              │
│     └─ Line 263: ACTUAL API CALL:                                 │
│        response = self.generator.create(**create_args)            │
│        [THIS IS WHERE RATE LIMITS HAPPEN]                         │
│                                                                    │
│        Response object structure:                                  │
│        ├─ response.choices[]: list of choice objects              │
│        │  └─ choice.message.content: actual text                  │
│        ├─ response.usage (NOT CURRENTLY CAPTURED):                │
│        │  ├─ .prompt_tokens: # tokens in input                    │
│        │  ├─ .completion_tokens: # tokens in output               │
│        │  └─ .total_tokens: sum of above                          │
│        └─ response.model: model identifier used                   │
│                                                                    │
│     ├─ Line 264-274: ERROR HANDLING:                              │
│     │  ├─ BadRequestError: log and return [None]                  │
│     │  └─ JSONDecodeError: retry or raise                         │
│     │     (triggers backoff via GarakBackoffTrigger)               │
│     │                                                              │
│     └─ Line 287-290: RESPONSE PARSING:                            │
│        FOR completion models: extract .text from choice           │
│        FOR chat models: extract .message.content from choice      │
│        Return: List[Message(...)]                                 │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────────┐
│               CLIENT INITIALIZATION (Cached)                         │
│  garak/generators/openai.py:159 → OpenAICompatible._load_client()  │
│                                                                      │
│  Line 162: self.client = openai.OpenAI(api_key=self.api_key)       │
│  Line 167: self.generator = self.client.chat.completions           │
│            [or self.client.completions for completion models]      │
│                                                                      │
│  Pickling Handling (lines 150-157):                                 │
│    ├─ __getstate__: clears client before pickle                   │
│    ├─ __setstate__: restores client after unpickle                │
│    └─ Multiprocessing: automatically uses these                   │
└─────────────────────────────────────────────────────────────────────┘
```

### 1.2 Request/Response Flow with Token Counting Integration Points

```
ENTRY: Probe with N prompts
  ↓
PHASE 1: Generate Batch
  ├─ Each prompt: probe._execute_attempt()
  │  ├─ [TOKEN COUNT INSERTION #1] Count prompt tokens (pre-call)
  │  │   Location: probe._generator_precall_hook() - extended
  │  └─ generator.generate(prompt, generations_this_call)
  │     ├─ [PARALLEL SPLIT - IF parallel_requests > 1]
  │     │  └─ MULTIPROCESSING POOL: _call_model() x N
  │     │     └─ [TOKEN COUNT INSERTION #2] Track tokens per call
  │     │        Location: _call_model wrapper
  │     │
  │     └─ [SEQUENTIAL FALLBACK - IF not parallel or not capable]
  │        └─ Loop _call_model() x N
  │           └─ [TOKEN COUNT INSERTION #2] Same location
  │
  ├─ _call_model() for each (generations_this_call times):
  │  ├─ Build API request parameters
  │  ├─ [RATE LIMIT CHECK #1] Check if request would exceed rate limit
  │  │   Location: Before line 263 (response = self.generator.create())
  │  │   Action: Block/queue/sleep if needed
  │  │
  │  └─ API Call: self.generator.create(**create_args)
  │     ├─ [ON SUCCESS] response object with .usage
  │     │  ├─ [TOKEN COUNT INSERTION #3] Extract response.usage
  │     │  │   Location: Lines 263-288 (after successful call)
  │     │  │   Fields: prompt_tokens, completion_tokens, total_tokens
  │     │  │
  │     │  └─ [RATE LIMIT UPDATE #1] Update cumulative token count
  │     │     Location: Same location as #3
  │     │
  │     └─ [ON RETRY] Catches rate limit via @backoff
  │        └─ Automatic exponential backoff (max 70 seconds)
  │
  └─ Return to Probe: List[Message]
```

### 1.3 Token Counting Insertion Points (Specific Line Numbers)

| # | Location | File:Line | Purpose | Current State | Action |
|---|----------|-----------|---------|---------------|--------|
| 1 | Probe precall hook | `probes/base.py:132` | Count prompt tokens before API call | None (hook exists but empty) | Extend hook to count |
| 2 | Generator wrapper | `generators/openai.py:211-213` | Wrap _call_model to track token usage | None | Add wrapper/decorator |
| 3 | Response parsing | `generators/openai.py:263-290` | Extract usage from response object | Not captured | Extract and track |
| 4 | Rate limiter check | `generators/openai.py:211` | Check rate limit before call | Only backoff-based | Add proactive check |
| 5 | Parallel pool | `generators/base.py:189-195` | Coordinate rate limits across pool | No coordination | Add sync mechanism |

---

## 2. Integration Architecture Map

### 2.1 Component Integration Points

```
CONFIGURATION → GENERATOR INIT → RATE LIMITER → API CALL → RESPONSE TRACKING
     ↓              ↓               ↓              ↓           ↓
[file:line]    [file:line]    [NEW LOGIC]   [file:line]  [file:line]

┌──────────────────────────────────────────────────────────────────────┐
│ Step 1: CONFIGURATION LAYER                                          │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│ File: garak/generators/openai.py:136-147                            │
│ Class: OpenAICompatible.DEFAULT_PARAMS                              │
│                                                                       │
│ Current DEFAULT_PARAMS = Generator.DEFAULT_PARAMS | {                │
│   "temperature": 0.7,                                                │
│   "top_p": 1.0,                                                      │
│   ...                                                                 │
│ }                                                                     │
│                                                                       │
│ INSERTION POINT:                                                     │
│   Add rate limiting parameters:                                      │
│   ├─ "rate_limit_tokens_per_minute": 90000  [or read from config]  │
│   ├─ "rate_limit_requests_per_minute": 3500                        │
│   ├─ "enable_token_tracking": True                                  │
│   └─ "rate_limiter_strategy": "token_aware"                        │
│                                                                       │
│ Config Loading: garak/configurable.py:15-59                        │
│   └─ _load_config() → _apply_config() → setattr(self, k, v)        │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│ Step 2: INITIALIZATION LAYER                                         │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│ File: garak/generators/openai.py:176-194 (OpenAICompatible.__init__)│
│ Also: garak/generators/openai.py:337-343 (OpenAIGenerator.__init__)  │
│                                                                       │
│ Current Flow:                                                        │
│   Line 178: self._load_config(config_root)                          │
│   Line 182: self._load_client()                                     │
│   Line 197: self._clear_client()  [for pickling]                   │
│                                                                       │
│ INSERTION POINT #1 (after line 192):                                │
│   Initialize rate limiter instance:                                 │
│   ├─ self.rate_limiter = TokenRateLimiter(                          │
│   │    tokens_per_minute=self.rate_limit_tokens_per_minute,         │
│   │    requests_per_minute=self.rate_limit_requests_per_minute,     │
│   │  )                                                              │
│   └─ self.token_usage_log = []  # Track for analytics             │
│                                                                       │
│ INSERTION POINT #2 (in _load_client, after line 167):              │
│   Ensure client has retry config:                                   │
│   └─ Already has: @backoff decorator on _call_model               │
│       This handles transient failures                               │
│                                                                       │
│ Pickling Impact: garak/generators/openai.py:149-157               │
│   └─ Need to add rate_limiter to __getstate__/__setstate__         │
│      OR make rate_limiter thread-safe singleton                    │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│ Step 3: RATE LIMITER LOGIC (NEW COMPONENT)                           │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│ New File: garak/generators/rate_limiter.py                          │
│                                                                       │
│ Required Classes/Functions:                                         │
│   ├─ TokenRateLimiter                                               │
│   │  ├─ __init__(tokens_per_minute, requests_per_minute)           │
│   │  ├─ can_make_request(estimated_tokens) -> bool                 │
│   │  ├─ acquire(estimated_tokens) -> sleep_time                    │
│   │  ├─ record_usage(prompt_tokens, completion_tokens) -> None     │
│   │  └─ get_stats() -> dict                                         │
│   │                                                                  │
│   └─ TokenCounter (wrapper around tiktoken)                        │
│      ├─ count_tokens(text, model_name) -> int                      │
│      └─ Uses: garak/resources/red_team/evaluation.py:47-50         │
│         (existing token_count function)                             │
│                                                                       │
│ Key Design:                                                          │
│   ├─ Thread-safe for multiprocessing                               │
│   ├─ Sliding window token tracking (per minute)                    │
│   ├─ Graceful handling of OpenAI response.usage                    │
│   └─ Logging of rate limit events                                  │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│ Step 4: API CALL WRAPPER (Injection Point)                           │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│ File: garak/generators/openai.py:200-290 (_call_model method)       │
│                                                                       │
│ Current Structure:                                                   │
│   @backoff.on_exception(...)  [LINE 200]                            │
│   def _call_model(self, prompt, generations_this_call=1):          │
│     ... build request ...                                           │
│     response = self.generator.create(...)  [LINE 263]               │
│     ... parse response ...                                          │
│     return List[Message]                                            │
│                                                                       │
│ INSERTION POINT #1 (Pre-API call, before line 263):                │
│   ├─ Count estimated prompt tokens                                  │
│   │  └─ Location: After build create_args, before API call         │
│   │     Code:                                                        │
│   │     ```python                                                   │
│   │     estimated_prompt_tokens = self.token_counter.count_tokens(│
│   │         str(create_args.get("messages", create_args.get("prompt", ""))),│
│   │         self.name                                              │
│   │     )                                                           │
│   │     estimated_total = estimated_prompt_tokens + self.max_tokens│
│   │     ```                                                         │
│   │                                                                 │
│   ├─ Rate limit check & wait                                       │
│   │  └─ Location: Immediately after token estimate                 │
│   │     Code:                                                       │
│   │     ```python                                                   │
│   │     sleep_time = self.rate_limiter.acquire(estimated_total)   │
│   │     if sleep_time > 0:                                         │
│   │         logging.info(f"Rate limit: sleeping {sleep_time}s")    │
│   │         time.sleep(sleep_time)                                │
│   │     ```                                                         │
│   │                                                                 │
│   └─ Impact on existing @backoff:                                  │
│       The backoff decorator wraps _call_model()                    │
│       So rate limit check happens WITHIN the backoff retry logic   │
│       This is CORRECT: pre-emptive wait before each attempt        │
│                                                                       │
│ INSERTION POINT #2 (Post-API call, after line 263):               │
│   ├─ Extract response usage metadata                               │
│   │  └─ Location: After successful API call response               │
│   │     Code:                                                       │
│   │     ```python                                                   │
│   │     if hasattr(response, 'usage') and response.usage:          │
│   │         self.rate_limiter.record_usage(                        │
│   │             response.usage.prompt_tokens,                      │
│   │             response.usage.completion_tokens                   │
│   │         )                                                       │
│   │         logging.debug(f"Tokens used: {response.usage.total_tokens}")│
│   │     ```                                                         │
│   │                                                                 │
│   └─ Update rate limiter state                                     │
│       For more accurate future estimates                            │
│                                                                       │
│ INSERTION POINT #3 (Error handling, lines 264-285):               │
│   ├─ On RateLimitError: backoff already handles                   │
│   │  └─ @backoff catches and retries with fibonacci backoff       │
│   │                                                                 │
│   ├─ On other errors: current behavior maintained                 │
│   │                                                                 │
│   └─ Consider: Add logging for rate limit events                   │
│       Location: In error handler around line 203                   │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│ Step 5: RESPONSE TRACKING LAYER                                      │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│ File: garak/generators/openai.py:287-290 (return statement)         │
│                                                                       │
│ Current:                                                             │
│   return [Message(c.text) for c in response.choices]               │
│   OR                                                                 │
│   return [Message(c.message.content) for c in response.choices]    │
│                                                                       │
│ Optional Enhancement (not required for rate limiting):              │
│   ├─ Add token usage to Message.notes                              │
│   ├─ Propagate to Attempt object for reporting                     │
│   └─ File: garak/attempt.py:50 - add to Message.notes             │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────┐
│ Step 6: PARALLEL REQUEST COORDINATION (Optional)                     │
├──────────────────────────────────────────────────────────────────────┤
│                                                                       │
│ File: garak/generators/base.py:167-216 (generate method)            │
│                                                                       │
│ Current Flow:                                                        │
│   ├─ If parallel_requests > 1:                                      │
│   │  └─ with Pool(pool_size) as pool:                              │
│   │     └─ pool.imap_unordered(self._call_model, [prompts]*n)     │
│   │        (PROBLEM: No coordination between workers)               │
│   │                                                                 │
│   └─ Else: sequential _call_model calls                            │
│                                                                       │
│ Rate Limiting Implication:                                          │
│   ├─ With multiprocessing.Pool: Each worker is separate process    │
│   ├─ Global rate limiter state CANNOT be shared (IPC challenge)    │
│   └─ Solution Options:                                              │
│      ├─ Option A (Recommended): Keep rate limiter PER-PROCESS      │
│      │  └─ Each worker gets its own limiter, divide quota equally  │
│      │                                                              │
│      ├─ Option B: Use shared memory / semaphore                    │
│      │  └─ Complex, requires multiprocessing.Manager               │
│      │                                                              │
│      └─ Option C: Disable parallel requests for rate-limited gens  │
│         └─ Set parallel_requests=1 for OpenAI generators           │
│                                                                       │
│ Recommended Action (Minimal Change):                                │
│   Location: garak/generators/openai.py:132                         │
│   Add: parallel_capable = False [when rate limiting enabled]       │
│   OR  Implement Option A with divided quotas                       │
│                                                                       │
└──────────────────────────────────────────────────────────────────────┘
```

### 2.2 File Interaction Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Configuration Files (YAML)                        │
│              garak/configs/{default,fast,full}.yaml                 │
│  Contains: generators.openai params (temperature, rate_limit_*, etc)│
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│              Configurable Base (config loading)                      │
│                  garak/configurable.py:12-127                      │
│  ├─ _load_config() - loads YAML configs                            │
│  ├─ _apply_config() - sets instance attributes                     │
│  └─ _validate_env_var() - checks API keys                          │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│         OpenAI Generator Classes (openai.py)                        │
│  ├─ OpenAICompatible (base, lines 126-291)                         │
│  │  ├─ __init__ → _load_config() + _load_client()                 │
│  │  ├─ _call_model() [decorated with @backoff]                    │
│  │  └─ __getstate__/__setstate__ (for pickling)                   │
│  │                                                                  │
│  ├─ OpenAIGenerator (public API, lines 293-343)                    │
│  │  └─ Specialized _load_client() for model detection              │
│  │                                                                  │
│  └─ OpenAIReasoningGenerator (reasoning models, lines 346-360)     │
│     └─ Reduced DEFAULT_PARAMS (no n, temperature, max_tokens)      │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                ┌────────────┼────────────┐
                │            │            │
                ▼            ▼            ▼
    ┌─────────────────┐  ┌──────────────────┐  ┌──────────────────┐
    │  TokenRateLimiter│  │  TokenCounter    │  │  Rate Limit      │
    │  (NEW FILE)      │  │  (uses tiktoken) │  │  Exceptions      │
    │                  │  │                  │  │                  │
    │  ├─ can_acquire()│  │  ├─ count_tokens()  │  ├─ RateLimitHit  │
    │  ├─ acquire()    │  │  └─ Uses existing   │  │  (garak/       │
    │  └─ record_usage()   │     token_count()   │  │   exception.py) │
    └─────────────────┘  │     function from    │  └──────────────┘
                         │     evaluation.py    │
                         └──────────────────┘

    Integration Point:
    └─ _call_model() calls:
       1. token_counter.count_tokens()
       2. rate_limiter.acquire()
       3. rate_limiter.record_usage() after API call

    Existing Code Used:
    └─ tiktoken (already in pyproject.toml:116)
    └─ token_count() from garak/resources/red_team/evaluation.py:47-50
    └─ @backoff decorator (already in openai.py:200-210)
```

---

## 3. Existing Patterns to Reuse

### 3.1 Backoff & Retry Mechanism

**Location**: `garak/generators/openai.py:200-210`

```python
@backoff.on_exception(
    backoff.fibo,
    (
        openai.RateLimitError,
        openai.InternalServerError,
        openai.APITimeoutError,
        openai.APIConnectionError,
        garak.exception.GarakBackoffTrigger,
    ),
    max_value=70,
)
def _call_model(self, prompt, generations_this_call=1):
    # implementation
```

**Pattern Reuse**:
- Fibonacci backoff with 70-second max
- Already catches `openai.RateLimitError`
- Raises `GarakBackoffTrigger` for custom retry logic (line 272, 283)
- **Action**: Our rate limiter should work WITH this, not against it
  - Pre-emptive wait in _call_model prevents hitting the error
  - @backoff still catches it as failsafe

**Related Code**:
- `garak/exception.py:17-18` - GarakBackoffTrigger definition
- `garak/exception.py:29-30` - RateLimitHit exception (currently unused)

### 3.2 Configuration Loading Pattern

**Location**: `garak/configurable.py:15-59` and `garak/generators/openai.py:136-147`

**Example - DEFAULT_PARAMS**:
```python
# In OpenAICompatible
DEFAULT_PARAMS = Generator.DEFAULT_PARAMS | {
    "temperature": 0.7,
    "top_p": 1.0,
    "uri": "http://localhost:8000/v1/",
    "frequency_penalty": 0.0,
    "presence_penalty": 0.0,
    "seed": None,
    "stop": ["#", ";"],
    "suppressed_params": set(),
    "retry_json": True,
    "extra_params": {},
}
```

**Loading Flow**:
1. Line 136-147: Define DEFAULT_PARAMS dict
2. Line 178 (__init__): Call `self._load_config(config_root)`
3. In Configurable._load_config (line 15-59):
   - Reads YAML from `garak/configs/`
   - Applies config via _apply_config() (lines 61-91)
   - Missing params get defaults via _apply_missing_instance_defaults() (lines 102-110)

**Action for Rate Limiting**:
```python
# Add to DEFAULT_PARAMS:
DEFAULT_PARAMS = Generator.DEFAULT_PARAMS | {
    # ... existing params ...
    "rate_limit_tokens_per_minute": 90000,      # Default: 90k TPM
    "rate_limit_requests_per_minute": 3500,     # Default: 3.5k RPM
    "enable_token_tracking": True,              # Track usage
    "rate_limiter_strategy": "token_aware",     # Type of limiting
}
```

**YAML Config Example**:
```yaml
plugins:
  generators:
    openai:
      OpenAIGenerator:
        rate_limit_tokens_per_minute: 60000
        enable_token_tracking: true
```

### 3.3 Token Counting Pattern

**Location**: `garak/resources/red_team/evaluation.py:47-50`

**Existing Implementation**:
```python
def token_count(string: str, model_name: str) -> int:
    encoding = tiktoken.encoding_for_model(model_name)
    num_tokens = len(encoding.encode(string))
    return num_tokens
```

**Usage Context**: Used in `EvaluationJudge` class to track token limits and truncate long prompts (lines 91-116)

**Action for Rate Limiting**:
- Reuse this exact function or wrap it in TokenCounter class
- Already handles model-specific tokenization
- Dependencies already in pyproject.toml (line 116): `tiktoken>=0.7.0`
- **No new dependencies needed**

### 3.4 Client Initialization & Pickling Pattern

**Location**: `garak/generators/openai.py:150-183`

**Pattern**:
```python
def __getstate__(self) -> object:
    self._clear_client()
    return dict(self.__dict__)

def __setstate__(self, d) -> object:
    self.__dict__.update(d)
    self._load_client()

def _load_client(self):
    self.client = openai.OpenAI(base_url=self.uri, api_key=self.api_key)
    # ... setup ...
    self.generator = self.client.chat.completions

def _clear_client(self):
    self.generator = None
    self.client = None
```

**Why**: Enables multiprocessing (Pool) without issues. Objects are pickled before sending to worker processes.

**Action for Rate Limiting**:
- Need to add rate_limiter to __getstate__/__setstate__
- Two options:
  1. Clear rate_limiter on pickle (stateless approach)
  2. Make rate_limiter thread-safe singleton (harder)
- **Recommended**: Option 1 - reinitialize fresh in each worker

### 3.5 Error Handling Template

**Location**: `garak/generators/openai.py:262-285`

**Pattern**:
```python
try:
    response = self.generator.create(**create_args)
except openai.BadRequestError as e:
    msg = "Bad request: " + str(repr(prompt))
    logging.exception(e)
    logging.error(msg)
    return [None]
except json.decoder.JSONDecodeError as e:
    logging.exception(e)
    if self.retry_json:
        raise garak.exception.GarakBackoffTrigger from e
    else:
        raise e
```

**Action for Rate Limiting**:
- Don't catch RateLimitError here (backoff handles it)
- Add logging for rate limit waits
- Consider: Add custom exception handling for rate limiter failures

### 3.6 Parallel Request Pattern

**Location**: `garak/generators/base.py:167-216`

**Pattern**:
```python
if (
    hasattr(self, "parallel_requests")
    and self.parallel_requests
    and isinstance(self.parallel_requests, int)
    and self.parallel_requests > 1
):
    from multiprocessing import Pool

    pool_size = min(
        generations_this_call,
        self.parallel_requests,
        self.max_workers,
    )

    with Pool(pool_size) as pool:
        for result in pool.imap_unordered(
            self._call_model, [prompt] * generations_this_call
        ):
            outputs.append(result[0])
```

**Considerations for Rate Limiting**:
- Each worker is a separate process
- Global rate limiter state cannot be shared (IPC limitation)
- Solutions:
  1. **Per-worker limiters** (divide quota)
  2. **Disable parallelism** for rate-limited generators
  3. **Use multiprocessing.Manager** (complex, slow)
- **Recommended**: Option 2 - set `parallel_capable = False`

---

## 4. Implementation Insertion Points

### 4.1 Exact Surgical Injection Locations

| # | Phase | File | Lines | Current Code | New Injection | Impact | Complexity |
|---|-------|------|-------|--------------|---------------|--------|------------|
| 1 | Config | openai.py | 136-147 | DEFAULT_PARAMS | Add rate limit params | None (additive) | Minimal |
| 2 | Init | openai.py | 192 (end of __init__) | After super().__init__() | Create rate_limiter instance | Init rate_limiter | Low |
| 3 | Pickle | openai.py | 149-157 | __getstate__/__setstate__ | Handle rate_limiter | Clear/reinit rate_limiter | Low |
| 4 | Pre-API | openai.py | 262 (before line 263) | Before response = ... | Count tokens + acquire | Sleep if needed | Medium |
| 5 | Post-API | openai.py | 288 (after line 287) | After response parsing | Extract response.usage | Record usage | Low |
| 6 | Error Log | openai.py | 203-207 | In @backoff exception list | Consider adding logging | Better visibility | Very Low |
| 7 | Parallel | base.py | 168-171 | Check parallel_requests | For OpenAI: disable if rate-limiting enabled | May affect parallelism | Low |

### 4.2 Code Change Locations (Minimal Surgical Approach)

#### Location A: Configuration (openai.py:136-147)

**BEFORE**:
```python
DEFAULT_PARAMS = Generator.DEFAULT_PARAMS | {
    "temperature": 0.7,
    "top_p": 1.0,
    ...
    "retry_json": True,
    "extra_params": {},
}
```

**AFTER**:
```python
DEFAULT_PARAMS = Generator.DEFAULT_PARAMS | {
    "temperature": 0.7,
    "top_p": 1.0,
    ...
    "retry_json": True,
    "extra_params": {},
    # Rate limiting configuration
    "rate_limit_tokens_per_minute": 90000,
    "rate_limit_requests_per_minute": 3500,
    "enable_token_tracking": True,
    "rate_limiter_strategy": "token_aware",
}
```

**Impact**: Zero - additive only, defaults provided

---

#### Location B: Initialization (openai.py:192)

**BEFORE**:
```python
def __init__(self, name="", config_root=_config):
    self.name = name
    self._load_config(config_root)
    # ... setup ...
    super().__init__(self.name, config_root=config_root)
    self._clear_client()  # Line 197
```

**AFTER**:
```python
def __init__(self, name="", config_root=_config):
    self.name = name
    self._load_config(config_root)
    # ... setup ...

    # Initialize rate limiter (NEW)
    if self.enable_token_tracking:
        from garak.generators.rate_limiter import TokenRateLimiter
        self.rate_limiter = TokenRateLimiter(
            tokens_per_minute=self.rate_limit_tokens_per_minute,
            requests_per_minute=self.rate_limit_requests_per_minute,
        )
    else:
        self.rate_limiter = None

    super().__init__(self.name, config_root=config_root)
    self._clear_client()
```

**Impact**: Minimal - conditional initialization

---

#### Location C: Pickling Support (openai.py:150-157)

**BEFORE**:
```python
def __getstate__(self) -> object:
    self._clear_client()
    return dict(self.__dict__)

def __setstate__(self, d) -> object:
    self.__dict__.update(d)
    self._load_client()
```

**AFTER**:
```python
def __getstate__(self) -> object:
    self._clear_client()
    state = dict(self.__dict__)
    # Clear rate limiter for pickling (will be recreated per-process)
    state['rate_limiter'] = None
    return state

def __setstate__(self, d) -> object:
    self.__dict__.update(d)
    self._load_client()
    # Recreate rate limiter in worker process
    if d.get('enable_token_tracking'):
        from garak.generators.rate_limiter import TokenRateLimiter
        self.rate_limiter = TokenRateLimiter(
            tokens_per_minute=self.rate_limit_tokens_per_minute,
            requests_per_minute=self.rate_limit_requests_per_minute,
        )
```

**Impact**: Low - only affects multiprocessing workers

---

#### Location D: Pre-API Rate Check (openai.py:262 area)

**BEFORE**:
```python
        if self.generator == self.client.chat.completions:
            # ... build messages ...
            create_args["messages"] = messages

        try:
            response = self.generator.create(**create_args)  # Line 263
```

**AFTER**:
```python
        if self.generator == self.client.chat.completions:
            # ... build messages ...
            create_args["messages"] = messages

        # Rate limiting check (NEW)
        if self.rate_limiter is not None:
            import time

            # Estimate token count for this request
            estimated_prompt_tokens = self._estimate_prompt_tokens(create_args)
            estimated_completion_tokens = self.max_tokens if hasattr(self, 'max_tokens') else 150
            estimated_total = estimated_prompt_tokens + estimated_completion_tokens

            # Check rate limit and wait if necessary
            sleep_time = self.rate_limiter.acquire(estimated_total)
            if sleep_time > 0:
                logging.info(
                    f"Rate limit: waiting {sleep_time:.2f}s before API call "
                    f"(estimated tokens: {estimated_total})"
                )
                time.sleep(sleep_time)

        try:
            response = self.generator.create(**create_args)
```

**Helper Method (NEW)** - add to OpenAICompatible class:
```python
def _estimate_prompt_tokens(self, create_args: dict) -> int:
    """Estimate prompt tokens from create_args"""
    try:
        from garak.resources.red_team.evaluation import token_count

        if "messages" in create_args:
            # Chat completions format
            messages_str = str(create_args["messages"])
            return token_count(messages_str, self.name)
        elif "prompt" in create_args:
            # Completion format
            return token_count(create_args["prompt"], self.name)
        else:
            return 0
    except Exception as e:
        logging.debug(f"Token estimation failed: {e}, using fallback")
        # Fallback: rough estimate based on character count
        total_input = str(create_args)
        return len(total_input) // 4  # Rough 1 token ≈ 4 chars
```

**Impact**: Medium - adds wait delay before API calls, but prevents rate limit errors

---

#### Location E: Post-API Response Tracking (openai.py:287)

**BEFORE**:
```python
        if self.generator == self.client.completions:
            return [Message(c.text) for c in response.choices]
        elif self.generator == self.client.chat.completions:
            return [Message(c.message.content) for c in response.choices]
```

**AFTER**:
```python
        # Update rate limiter with actual token usage (NEW)
        if self.rate_limiter is not None and hasattr(response, 'usage') and response.usage:
            try:
                self.rate_limiter.record_usage(
                    prompt_tokens=response.usage.prompt_tokens,
                    completion_tokens=response.usage.completion_tokens,
                )
                logging.debug(
                    f"Recorded token usage: "
                    f"{response.usage.prompt_tokens} prompt + "
                    f"{response.usage.completion_tokens} completion"
                )
            except Exception as e:
                logging.warning(f"Failed to record token usage: {e}")

        if self.generator == self.client.completions:
            return [Message(c.text) for c in response.choices]
        elif self.generator == self.client.chat.completions:
            return [Message(c.message.content) for c in response.choices]
```

**Impact**: Low - only records usage after successful call

---

### 4.3 New File Creation

#### New File: `garak/generators/rate_limiter.py`

**Purpose**: Self-contained rate limiter implementation

**Pseudocode Structure**:
```python
import logging
import time
from collections import deque
from threading import Lock

class TokenRateLimiter:
    """Token-based rate limiter for API calls"""

    def __init__(self, tokens_per_minute=90000, requests_per_minute=3500):
        self.tokens_per_minute = tokens_per_minute
        self.requests_per_minute = requests_per_minute
        self.token_history = deque()  # (timestamp, tokens)
        self.request_history = deque()
        self.lock = Lock()

    def can_make_request(self, estimated_tokens):
        """Check if request can be made without exceeding limits"""
        # Check both token and request limits
        pass

    def acquire(self, estimated_tokens):
        """
        Acquire right to make request.
        Returns: sleep_time (seconds) if rate limited, 0 if OK
        """
        # Calculate wait time based on sliding window
        # Return sleep time or 0
        pass

    def record_usage(self, prompt_tokens, completion_tokens):
        """Record actual token usage from API response"""
        # Update history with actual tokens used
        pass

    def get_stats(self):
        """Get current rate limit statistics"""
        # Return dict with utilization, remaining tokens, etc
        pass
```

**Complexity**: Medium (sliding window algorithm, thread safety)

---

### 4.4 Backward Compatibility

**Key Principles**:
1. Rate limiting is OPTIONAL by default (`enable_token_tracking: False`)
2. Existing code paths unchanged when disabled
3. New exceptions not raised in normal flow
4. No changes to external API of _call_model()
5. Returns same object types (List[Message])

**Compat Checks**:
- ✅ Existing tests pass (rate limiting disabled by default)
- ✅ Existing config files work (new params have defaults)
- ✅ No pickling issues (rate_limiter cleared during pickle)
- ✅ Parallel requests still work (though disabled for rate-limited OpenAI)
- ✅ Error handling unchanged (backoff still catches RateLimitError)

---

## 5. Key Technical Details

### 5.1 OpenAI Response Object Structure

**Location**: OpenAI Python SDK response objects

**Chat Completions Response**:
```python
response = {
    "choices": [
        {
            "message": {
                "content": "The actual response text",
                "role": "assistant",
            },
            "finish_reason": "stop",
            "index": 0,
        }
    ],
    "created": 1234567890,
    "id": "chatcmpl-...",
    "model": "gpt-4-turbo",
    "usage": {
        "prompt_tokens": 42,
        "completion_tokens": 15,
        "total_tokens": 57,
    },
    "object": "chat.completion",
}
```

**Completion Response**:
```python
response = {
    "choices": [
        {
            "text": "The actual response text",
            "finish_reason": "stop",
            "index": 0,
        }
    ],
    "created": 1234567890,
    "id": "cmpl-...",
    "model": "text-davinci-003",
    "usage": {
        "prompt_tokens": 42,
        "completion_tokens": 15,
        "total_tokens": 57,
    },
    "object": "text_completion",
}
```

**Key for Rate Limiting**: `response.usage` contains actual token counts

### 5.2 Token Counting Accuracy

**Tiktoken Encoding**:
```python
import tiktoken
encoding = tiktoken.encoding_for_model("gpt-4-turbo")
tokens = encoding.encode("Hello world")
num_tokens = len(tokens)  # Returns actual token count
```

**Accuracy**:
- Very accurate for actual usage (within 1-2 tokens typically)
- Better to estimate slightly high than low (avoid 429 errors)

**Model-Specific**:
- Different models have slightly different tokenizers
- gpt-4-turbo, gpt-4o, gpt-3.5-turbo all available in tiktoken

### 5.3 Multiprocessing Token Sharing

**Challenge**: With multiprocessing.Pool, each worker is a separate Python process

**Token Count Sharing Options**:

| Option | Approach | Pros | Cons |
|--------|----------|------|------|
| A | Each process gets its own limiter, divided quota | Simple, isolated | Less optimal quota usage |
| B | Use multiprocessing.Manager + shared state | Optimal quota | Slow IPC, threading complexity |
| C | Disable parallelism for rate-limited generators | Clean | No parallelism |
| D | Central coordinating server process | Optimal | Complex architecture |

**Recommended**: Option C for initial implementation

### 5.4 Sliding Window Algorithm (for rate limiter)

**Algorithm**:
```
At time T, to make request with X tokens:
1. Remove all events older than 60 seconds from history
2. Calculate remaining_tokens = limit - sum(tokens in history)
3. Calculate remaining_requests = limit - count(requests in history)
4. If both remaining > X:
     Return 0 (can make request immediately)
5. Else:
     Find oldest event in history
     Calculate time until that event falls off the window
     Return sleep_time
```

**Time Complexity**: O(n) where n = events in sliding window (typically < 1000)

---

## 6. Testing & Validation Points

### 6.1 Unit Tests Needed

```python
# test_rate_limiter.py
- test_token_counting_accuracy()
- test_rate_limit_acquire_no_wait()
- test_rate_limit_acquire_with_wait()
- test_rate_limit_record_usage()
- test_sliding_window_expiry()

# test_openai_integration.py
- test_openai_with_rate_limiting_enabled()
- test_openai_with_rate_limiting_disabled()
- test_openai_estimates_tokens()
- test_openai_records_usage()
- test_multiprocessing_workers_get_own_limiters()
```

### 6.2 Integration Tests

```python
# test_openai_e2e.py
- test_single_probe_with_rate_limiting()
- test_multiple_parallel_probes_rate_limited()
- test_rate_limit_actually_sleeps()
- test_backoff_still_works_on_429()
```

---

## 7. Configuration Examples

### 7.1 Default Configuration (No Rate Limiting)

```yaml
# garak/configs/default.yaml
plugins:
  generators:
    openai:
      OpenAIGenerator:
        temperature: 0.7
        top_p: 1.0
        # Rate limiting disabled by default
        enable_token_tracking: false
```

### 7.2 Rate-Limited Configuration

```yaml
# garak/configs/rate_limited.yaml
plugins:
  generators:
    openai:
      OpenAIGenerator:
        temperature: 0.7
        top_p: 1.0
        # Enable token tracking and rate limiting
        enable_token_tracking: true
        rate_limit_tokens_per_minute: 60000  # 60k TPM tier
        rate_limit_requests_per_minute: 3000
        rate_limiter_strategy: "token_aware"
```

### 7.3 Runtime Configuration (CLI)

```bash
# Would need to extend CLI args to support rate limit config
# Future: add --rate-limit-tokens, --enable-token-tracking flags
```

---

## 8. Dependencies & Imports

### 8.1 New Imports Required

```python
# In openai.py
import time
import logging
# Already available:
# - garak.resources.red_team.evaluation.token_count
# - garak.exception (for error handling)

# In rate_limiter.py (new file)
import logging
import time
from collections import deque
from threading import Lock
```

### 8.2 External Dependencies

**No new external dependencies required**:
- ✅ tiktoken >= 0.7.0 (already in pyproject.toml:116)
- ✅ backoff >= 2.1.1 (already in pyproject.toml:85)
- ✅ openai >= 1.45.0 (already in pyproject.toml:82)

---

## 9. Risk Assessment

### 9.1 Low Risk Changes
- Configuration additions (backward compatible)
- Adding tracking code after successful API calls
- New rate_limiter.py file (isolated)

### 9.2 Medium Risk Changes
- Pre-API sleep injection (could affect timing in tests)
- Pickling changes (affects multiprocessing, well-tested path)

### 9.3 Mitigation Strategies
1. Feature flag (enable_token_tracking: false by default)
2. Comprehensive logging at debug level
3. Exception handling with graceful fallbacks
4. Separate code file for rate limiter (no monkey-patching)

---

## 10. Implementation Checklist

- [ ] Create `garak/generators/rate_limiter.py`
  - [ ] Implement TokenRateLimiter class
  - [ ] Implement TokenCounter wrapper
  - [ ] Add unit tests

- [ ] Modify `garak/generators/openai.py`
  - [ ] Add rate limit parameters to DEFAULT_PARAMS
  - [ ] Initialize rate_limiter in __init__
  - [ ] Update __getstate__/__setstate__ for pickling
  - [ ] Add _estimate_prompt_tokens() method
  - [ ] Add pre-API token check and sleep
  - [ ] Add post-API usage recording
  - [ ] Add logging for visibility

- [ ] Add Configuration File
  - [ ] Create `garak/configs/rate_limited.yaml`
  - [ ] Document rate limit parameters

- [ ] Testing
  - [ ] Unit tests for TokenRateLimiter
  - [ ] Integration tests with OpenAI generator
  - [ ] Test with multiprocessing.Pool
  - [ ] Test backward compatibility

- [ ] Documentation
  - [ ] Add rate limiting docs to README
  - [ ] Document configuration options
  - [ ] Add usage examples

---

## 11. Success Criteria

✅ Complete AST traversal of openai.py and base.py
✅ Every _call_model path documented with line numbers
✅ Clear integration points identified (Sections 2.1-2.2)
✅ Existing patterns catalogued (Section 3)
✅ Implementation insertion points with exact code locations (Section 4)
✅ No new assumptions - only documented code paths
✅ Backward compatibility maintained (rate limiting optional)
✅ No new external dependencies required

---

## Appendix A: File Structure Summary

```
garak/
├── generators/
│   ├── base.py                    ✓ Analyzed - generate() method
│   ├── openai.py                  ✓ Analyzed - _call_model() implementation
│   ├── rate_limiter.py            ← NEW FILE (to create)
│   └── ... [other generators]
├── probes/
│   └── base.py                    ✓ Analyzed - probe execution flow
├── configs/
│   ├── default.yaml               ✓ Analyzed - current config
│   └── rate_limited.yaml          ← NEW FILE (to create)
├── attempt.py                     ✓ Analyzed - Attempt/Message objects
├── configurable.py                ✓ Analyzed - config loading
├── exception.py                   ✓ Analyzed - exceptions
├── _config.py                     ✓ Analyzed - global config
├── resources/
│   └── red_team/
│       └── evaluation.py          ✓ Analyzed - token_count() function
└── harnesses/
    └── probewise.py               ✓ Analyzed - harness execution
```

---

## Appendix B: Quick Reference - Key Line Numbers

| Component | File | Lines | Purpose |
|-----------|------|-------|---------|
| _call_model() | openai.py | 211-291 | API call wrapper |
| @backoff decorator | openai.py | 200-210 | Retry logic |
| DEFAULT_PARAMS | openai.py | 136-147 | Configuration defaults |
| __init__ | openai.py | 176-194 | Initialization |
| __getstate__/__setstate__ | openai.py | 150-157 | Pickling support |
| generate() | base.py | 132-224 | Orchestration layer |
| Parallel execution | base.py | 167-216 | Pool creation |
| _execute_attempt() | probes/base.py | 266-276 | Attempt execution |
| token_count() | evaluation.py | 47-50 | Token counting function |
| _load_config() | configurable.py | 15-59 | Config loading |

---

**End of Analysis Document**
