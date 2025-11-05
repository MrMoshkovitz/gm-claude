# Task 1.3: Existing Error Handling and Retry Patterns

**Status**: ✅ COMPLETE
**Date**: 2025-10-20
**Deliverable**: Catalog of reusable error handling patterns for rate limiter integration

---

## 1. EXECUTIVE SUMMARY

The `garak/generators/openai.py` file implements a robust set of error handling and retry patterns that should be leveraged for rate limiter integration. This document catalogs:

- **Backoff/Retry Strategy**: Exponential (fibonacci) backoff for transient errors
- **Exception Handling**: Layered approach with type-specific recovery
- **Graceful Degradation**: Multi-level fallbacks (retry → None → empty list)
- **Configuration Flags**: Feature-gating via `retry_json` parameter
- **Client Lifecycle**: Lazy loading and pickling-safe client management

**Key Finding**: The existing decorator pattern `@backoff.on_exception` is ideal for rate limiting - we can add rate limit errors to this same decorator or create a complementary pattern.

---

## 2. DETAILED PATTERN CATALOG

### 2.1 Pattern 1: Exponential Backoff with Fibonacci Sequence

**Location**: `garak/generators/openai.py:200-210`

**Pattern**:
```python
@backoff.on_exception(
    backoff.fibo,                           # Fibonacci sequence: 1, 1, 2, 3, 5, 8, 13, 21, 34, 55
    (
        openai.RateLimitError,              # 429 Too Many Requests
        openai.InternalServerError,         # 500 Internal Server Error
        openai.APITimeoutError,             # Request timeout
        openai.APIConnectionError,          # Network issues
        garak.exception.GarakBackoffTrigger, # Custom trigger for app-level retry
    ),
    max_value=70,                           # Max delay between retries: 70 seconds
)
def _call_model(self, prompt, generations_this_call=1):
    # Method body
```

**How It Works**:
1. Fibonacci sequence generates: 1s, 1s, 2s, 3s, 5s, 8s, 13s, 21s, 34s, 55s, 70s (capped)
2. Total max backoff across ~11 retries: ~233 seconds (~3.9 minutes)
3. Transient errors automatically trigger retry with exponential delay
4. Jitter applied by backoff library to prevent thundering herd

**Reuse for Rate Limiting**:
- Rate limiter should raise a custom exception (e.g., `GarakRateLimitExceeded`) on first detection
- Add to `@backoff.on_exception` tuple alongside existing errors
- OR: Create separate `@backoff.on_exception` decorator specifically for rate limiting

**Python backoff Library Reference**:
```python
import backoff

# Fibonacci sequence: F(0)=1, F(1)=1, F(n)=F(n-1)+F(n-2)
# With max_value=70: 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 70, 70, 70...
@backoff.on_exception(backoff.fibo, exception_class, max_value=70)
def function():
    pass
```

**Risks**:
- Backoff library depends on function raising exception to trigger retry
- Must integrate rate limiting as exception or raise from within decorated function
- Cannot silently sleep (no exception = no retry)

---

### 2.2 Pattern 2: Layered Exception Handling with Type-Specific Recovery

**Location**: `garak/generators/openai.py:262-274`

**Pattern**:
```python
try:
    response = self.generator.create(**create_args)
except openai.BadRequestError as e:
    msg = "Bad request: " + str(repr(prompt))
    logging.exception(e)
    logging.error(msg)
    return [None]                          # Unrecoverable: return None
except json.decoder.JSONDecodeError as e:
    logging.exception(e)
    if self.retry_json:
        raise garak.exception.GarakBackoffTrigger from e  # Retry via decorator
    else:
        raise e                             # Re-raise if disabled
```

**How It Works**:
1. **BadRequestError** (400 Bad Request): Unrecoverable, log and return [None]
2. **JSONDecodeError**: Conditionally recoverable:
   - If `retry_json=True`: Signal retry via `GarakBackoffTrigger`
   - If `retry_json=False`: Re-raise exception (hard fail)
3. Logging at two levels: exception() logs full traceback, error() logs context

**Exception Hierarchy** (OpenAI Python SDK):
```
APIError                                    # Base exception
├── APIConnectionError                      # Network issues (retryable)
├── RateLimitError                          # 429 (retryable)
├── APITimeoutError                         # Timeout (retryable)
├── InternalServerError                     # 500 (retryable)
├── BadRequestError                         # 400 (NOT retryable)
├── NotFoundError                           # 404 (NOT retryable)
├── AuthenticationError                     # 401 (NOT retryable)
└── PermissionError                         # 403 (NOT retryable)
```

**Reuse for Rate Limiting**:
- Rate limiter should raise `TokenBudgetExhausted` (custom exception)
- Catch at appropriate level:
  - If budget exhausted during estimation: return [None] (unrecoverable)
  - If budget exhausted between estimation and API call: retry (recoverable)
- Pattern allows conditional behavior via configuration flag

**Recommended Rate Limiting Exceptions**:
```python
class TokenBudgetExhausted(Exception):
    """Token budget exhausted - hard stop"""
    pass

class RateLimitViolation(garak.exception.GarakBackoffTrigger):
    """Rate limit hit - signal retry via backoff"""
    pass
```

---

### 2.3 Pattern 3: Response Validation with Retry Trigger

**Location**: `garak/generators/openai.py:276-285`

**Pattern**:
```python
if not hasattr(response, "choices"):
    logging.debug(
        "Did not get a well-formed response, retrying. Expected object with .choices member, got: '%s'"
        % repr(response)
    )
    msg = "no .choices member in generator response"
    if self.retry_json:
        raise garak.exception.GarakBackoffTrigger(msg)  # Trigger retry
    else:
        return [None]                       # Graceful failure
```

**How It Works**:
1. Validates response structure (expected `.choices` attribute)
2. Logs debug message with actual response
3. Conditionally:
   - If `retry_json=True`: Raise `GarakBackoffTrigger` → decorator catches and retries
   - If `retry_json=False`: Return [None] → graceful degradation

**Validation Points**:
- Response object existence
- `.choices` attribute presence
- `.choices` not empty (implicit in parsing)
- Message content accessibility (`.message.content` for chat, `.text` for completion)

**Reuse for Rate Limiting**:
- Validate rate limiter response object for sanity
- If rate limiter returns invalid state: trigger retry
- Pattern enables self-healing (retry) vs failing gracefully

---

### 2.4 Pattern 4: Input Validation with Type Checking

**Location**: `garak/generators/openai.py:236-258`

**Pattern**:
```python
# For completions API
if not isinstance(prompt, Conversation) or len(prompt.turns) > 1:
    msg = (
        f"Expected a Conversation with one Turn for {self.generator_family_name} "
        f"completions model {self.name}, but got {type(prompt)}. Returning nothing!"
    )
    logging.error(msg)
    return list()                           # Return empty list for bad input

# For chat completions API
elif isinstance(prompt, Conversation):
    messages = self._conversation_to_list(prompt)
elif isinstance(prompt, list):
    messages = prompt
else:
    msg = (
        f"Expected a Conversation or list of dicts for {self.generator_family_name} "
        f"Chat model {self.name}, but got {type(prompt)} instead. Returning nothing!"
    )
    logging.error(msg)
    return list()                           # Return empty list for bad input
```

**How It Works**:
1. Type checking before processing
2. Descriptive error messages with expected type and actual type
3. Returns empty list `[]` (not [None]) for input validation failures
4. Logs at ERROR level (not exception level) since no exception thrown

**Key Distinction**:
- Bad input (type error): Return `[]` (no attempt made)
- API error during request: Return `[None]` (attempt made but failed)
- No response data: Return `[Message(...)]` (success)

**Reuse for Rate Limiting**:
- Validate token estimation input parameters
- Pre-flight check before calling rate limiter
- Example: Check if estimated tokens is non-negative integer

---

### 2.5 Pattern 5: Lazy Client Loading and Pickling Support

**Location**: `garak/generators/openai.py:150-157, 214-216`

**Pattern - Pickling**:
```python
def __getstate__(self) -> object:
    self._clear_client()                    # Clear non-serializable client
    return dict(self.__dict__)

def __setstate__(self, d) -> object:
    self.__dict__.update(d)
    self._load_client()                     # Reload client in worker process
```

**Pattern - Lazy Loading**:
```python
def _call_model(self, prompt, generations_this_call=1):
    if self.client is None:
        # reload client once when consuming the generator
        self._load_client()
```

**How It Works**:
1. Serialization: Clear client before pickle (non-serializable)
2. Deserialization: Reload client after unpickle (new process, new connection)
3. Lazy loading: Check `self.client is None` before use (in case unpickled)
4. Single reload per deserialization (cached after first access)

**Pickle Lifecycle**:
```
Main process: OpenAIGenerator instance created
            ↓
            Pickle: __getstate__() removes client, returns state dict
            ↓
            [Transfer to worker process]
            ↓
Worker process: Unpickle: __setstate__() restores state, reloads client
            ↓
            _call_model(): Checks if client is None, reloads if needed
            ↓
            Worker process: API calls work with fresh client connection
```

**Reuse for Rate Limiting**:
- Rate limiter uses `threading.Lock()` which is NOT serializable
- Solution 1 (Recommended): Clear rate limiter in `__getstate__`, recreate in worker
- Solution 2 (Alternative): Use process-safe rate limiter (e.g., multiprocessing.Manager)
- Example:
  ```python
  def __getstate__(self):
      self._clear_client()
      state = dict(self.__dict__)
      state['rate_limiter'] = None  # Clear non-serializable rate limiter
      return state

  def __setstate__(self, d):
      self.__dict__.update(d)
      self._load_client()
      if d.get('enable_rate_limiting', True):
          self._init_rate_limiter()  # Recreate in worker
  ```

**Critical Implication**:
- Each worker process gets its OWN rate limiter instance
- Rate limits are NOT globally enforced across workers
- Recommended: Use global/shared rate limiter (see Pattern 6 or multiprocessing.Manager)

---

### 2.6 Pattern 6: Configuration Flags for Feature Control

**Location**: `garak/generators/openai.py:136-147` (DEFAULT_PARAMS)

**Pattern**:
```python
DEFAULT_PARAMS = Generator.DEFAULT_PARAMS | {
    "temperature": 0.7,
    "top_p": 1.0,
    "uri": "http://localhost:8000/v1/",
    "frequency_penalty": 0.0,
    "presence_penalty": 0.0,
    "seed": None,
    "stop": ["#", ";"],
    "suppressed_params": set(),
    "retry_json": True,                     # Feature flag for JSON retry
    "extra_params": {},
}
```

**How It Works**:
1. Define defaults in `DEFAULT_PARAMS` dictionary
2. Can be overridden via:
   - YAML config file (`config_root` → `_load_config()`)
   - CLI arguments (`--generator_options rate_limiting=false`)
   - Direct instantiation (`gen.rate_limiting = False`)
3. Check at runtime: `if self.retry_json: ...`

**Configuration Cascade** (Priority Order):
```
1. CLI arguments (highest)        # --generator_options retry_json=false
2. YAML config                    # config/openai.yaml: retry_json: false
3. Environment variables          # OPENAI_RETRY_JSON=false
4. DEFAULT_PARAMS (lowest)        # DEFAULT_PARAMS["retry_json"] = True
```

**Reuse for Rate Limiting**:
- Add `enable_rate_limiting` flag (default: True)
- Add `tier` parameter (default: "free")
- Add `token_budget` (optional, for hard limit)
- Pattern enables easy disable for testing
- Pattern enables per-tier configuration

**Example Configuration Addition**:
```python
DEFAULT_PARAMS = Generator.DEFAULT_PARAMS | {
    # ... existing params ...
    "enable_rate_limiting": True,           # Feature flag
    "tier": "free",                         # Rate limit tier
    "token_budget": None,                   # Optional hard limit
}
```

---

### 2.7 Pattern 7: Model-Specific Detection and Validation

**Location**: `garak/generators/openai.py:305-330`

**Pattern**:
```python
def _load_client(self):
    self.client = openai.OpenAI(api_key=self.api_key)

    if self.name == "":
        openai_model_list = sorted([m.id for m in self.client.models.list().data])
        raise ValueError(
            f"Model name is required for {self.generator_family_name}, use --target_name\n"
            + "  API returns following available models: ▶️   "
            + "  ".join(openai_model_list)
        )

    if self.name in completion_models:
        self.generator = self.client.completions
    elif self.name in chat_models:
        self.generator = self.client.chat.completions
    # ... more detection logic ...
    else:
        raise ValueError(
            f"No {self.generator_family_name} API defined for '{self.name}'"
        )
```

**How It Works**:
1. Model name validation (required)
2. Dynamic API selection based on model list membership
3. Helpful error messages listing available models
4. Regex fallback for versioned model names

**Reuse for Rate Limiting**:
- Look up model-specific rate limits using `self.name`
- Load from `rate_config.json` by model
- Pattern enables model-specific tier configuration
- Error messages can suggest which models have rate limit support

---

### 2.8 Pattern 8: Graceful Degradation Hierarchy

**Location**: Multiple locations in `_call_model`

**Degradation Levels**:

```
Level 1: SUCCESS
└─ return [Message(c.message.content)]    # Normal path: valid response

Level 2: RECOVERABLE ERROR → RETRY
├─ raise GarakBackoffTrigger()             # Bad JSON → retry
├─ raise openai.RateLimitError()           # Rate limited → retry with backoff
└─ raise openai.APITimeoutError()          # Timeout → retry with backoff

Level 3: GRACEFUL FAILURE → [None]
├─ except BadRequestError: return [None]   # Bad request (400)
├─ if not .choices: return [None]          # Invalid response structure
└─ except TokenBudgetExhausted: return [None]  # (proposed for rate limiter)

Level 4: INPUT ERROR → []
├─ if not isinstance(prompt, Conversation): return []
└─ if len(prompt.turns) > 1: return []
```

**Key Principle**:
- `[Message(...)]` = Success (1 or more messages)
- `[None]` = Attempted but failed (error during execution)
- `[]` = Not attempted (input validation error)

**Reuse for Rate Limiting**:
- Rate limit errors (soft): Trigger retry (level 2)
- Budget exhaustion (hard): Return [None] (level 3)
- Invalid token estimate: Return [None] (level 3)
- Invalid model for rate limiting: Return [] (level 4) or skip initialization

---

## 3. INTEGRATION STRATEGY FOR RATE LIMITER

### 3.1 Recommended Architecture

Based on existing patterns, recommended integration:

```python
# 1. Add custom exception to garak.exception module
class TokenBudgetExhausted(Exception):
    """Hard stop - token budget exceeded"""
    pass

# 2. Extend @backoff decorator in _call_model
@backoff.on_exception(
    backoff.fibo,
    (
        openai.RateLimitError,
        openai.InternalServerError,
        openai.APITimeoutError,
        openai.APIConnectionError,
        garak.exception.GarakBackoffTrigger,
        # NEW: Custom rate limit exception
        # RateLimitExceeded is a subclass of GarakBackoffTrigger
    ),
    max_value=70,
)
def _call_model(...):
    # 3. Pre-request rate check
    if self.rate_limiter:
        estimated = self._estimate_request_tokens(create_args)
        self.rate_limiter.check_and_wait(estimated)  # May sleep or raise

    # 4. API call
    response = self.generator.create(**create_args)

    # 5. Post-response recording
    if self.rate_limiter and hasattr(response, 'usage'):
        self.rate_limiter.record_usage(
            response.usage.prompt_tokens,
            response.usage.completion_tokens
        )
```

### 3.2 Mapping to Task 1.2 Integration Points

| Task 1.2 Point | Existing Pattern | Implementation Strategy |
|---|---|---|
| POINT 1: Init | Pattern 6 (Config) | Add enable_rate_limiting & tier to DEFAULT_PARAMS |
| POINT 2: Pre-request | Pattern 1 (Backoff) | Add rate_limiter.check_and_wait() before API |
| POINT 3: Post-response | Pattern 2 (Exception) | Record response.usage after API success |
| POINT 4: Pickling | Pattern 5 (Pickle) | Clear rate_limiter in __getstate__, recreate in __setstate__ |
| POINT 5: Config | Pattern 6 (Config) | Extend DEFAULT_PARAMS with rate limiting options |

### 3.3 Error Handling Matrix

| Error Type | Existing Pattern | Rate Limiter Treatment |
|---|---|---|
| Rate limit hit (predictive) | Pattern 1 | Sleep via check_and_wait() |
| Budget exhausted | Pattern 2 | Raise TokenBudgetExhausted → catch as [None] |
| Invalid token estimate | Pattern 4 | Log error, use safe default estimate |
| Bad API response | Pattern 3 | Existing handling unchanged |
| Pickle/unpickle | Pattern 5 | Recreate rate limiter in worker |

---

## 4. CONCRETE IMPLEMENTATION GUIDELINES

### 4.1 When Catching Rate Limiter Errors

**BAD** (Rate limiter exception gets suppressed):
```python
try:
    response = self.generator.create(**create_args)
except Exception as e:  # Catches too much
    logging.error(str(e))
    return [None]
```

**GOOD** (Rate limiter exception bubbles to decorator):
```python
# Pre-request: let rate limiter sleep or raise
if self.rate_limiter:
    self.rate_limiter.check_and_wait(estimated_tokens)

try:
    response = self.generator.create(**create_args)
except openai.BadRequestError as e:  # Specific exceptions only
    logging.error(f"Bad request: {e}")
    return [None]
```

### 4.2 When Logging Rate Limiter Events

**Pattern from existing code**:
- `logging.error()`: User-facing errors (bad request, auth failure)
- `logging.exception()`: Exception details with traceback
- `logging.debug()`: Implementation details (token estimates, rate checks)
- `logging.info()`: State changes (limiter initialized, budget status)

**Recommended for rate limiter**:
```python
logging.info(f"Rate limiter initialized for {self.name}: {rpm_limit} RPM, {tpm_limit} TPM")
logging.debug(f"Estimated tokens: {estimated_tokens}")
logging.debug(f"Rate limiter sleeping {sleep_time}s due to RPM limit")
logging.warning(f"Token budget low: {remaining_tokens} tokens left")
logging.error(f"Token budget exhausted, stopping probe execution")
```

### 4.3 When Validating Rate Limiter Input

**Pattern from existing code (input validation)**:
```python
# Check types and ranges
if not isinstance(estimated_tokens, int) or estimated_tokens < 0:
    logging.error(f"Invalid token estimate: {estimated_tokens}")
    return 0  # Safe default: estimate 0 tokens (no rate limiting)

if tpm_limit <= 0 or rpm_limit <= 0:
    logging.error(f"Invalid rate limits: RPM={rpm_limit}, TPM={tpm_limit}")
    self.rate_limiter = None  # Disable rate limiting
```

---

## 5. TESTING IMPLICATIONS

### 5.1 Existing Test Infrastructure

Current error handling tests should cover:
- Backoff retry behavior
- Exception type mapping
- Graceful degradation
- Configuration flag behavior

### 5.2 New Tests for Rate Limiting

Rate limiter tests should verify:
- Check_and_wait() blocks/sleeps as expected
- Backoff decorator retries on rate limit errors
- Token estimate is reasonable (within ±20%)
- Budget exhaustion returns [None] not exception
- Pickle/unpickle creates fresh rate limiter

### 5.3 Backward Compatibility

Existing tests should pass unchanged:
- With `enable_rate_limiting=False`, behavior identical to current
- Default `retry_json=True` still works
- Model detection unchanged
- Pickle still works (with modified __getstate__/__setstate__)

---

## 6. SUMMARY TABLE

| Pattern | Location | Key Mechanism | Rate Limiter Use |
|---------|----------|---|---|
| 1: Backoff | 200-210 | Fibonacci retry with max_value | Trigger on rate limit errors |
| 2: Exception Handling | 262-274 | Type-specific catch/raise | Catch budget exhaustion as [None] |
| 3: Response Validation | 276-285 | Check .choices, conditional retry | Validate limiter state |
| 4: Input Validation | 236-258 | Type checking, return [] | Validate token estimates |
| 5: Pickling | 150-157, 214-216 | Clear/reload client, lazy loading | Clear/reload rate limiter |
| 6: Config Flags | 136-147 | DEFAULT_PARAMS, feature gating | enable_rate_limiting, tier |
| 7: Model Detection | 305-330 | Dynamic API selection | Load model-specific limits |
| 8: Degradation | Multi | [Success] → [Retry] → [None] → [] | Budget → [None], Rate → Retry |

---

## 7. NEXT STEPS (Task 1.4)

**Deliverable**: Consolidation document with:
- Combined architecture overview (all 3 tasks)
- Unified implementation plan
- Risk assessment and mitigation
- Testing strategy

**Dependencies**: Task 1.3 ✅ COMPLETE

---

**References**:
- garak/generators/openai.py: Full file analysis
- @backoff decorator: https://github.com/litl/backoff
- OpenAI Python SDK exceptions: https://github.com/openai/openai-python/blob/main/src/openai/_exceptions.py
