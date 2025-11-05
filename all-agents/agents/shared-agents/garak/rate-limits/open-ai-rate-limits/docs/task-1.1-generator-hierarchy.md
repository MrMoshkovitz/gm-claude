# Task 1.1: OpenAI Generator Hierarchy Analysis

**Status**: ✅ COMPLETE
**Date**: 2025-10-20
**Deliverable**: Generator class hierarchy mapping with all _call_model paths documented

---

## 1. Class Hierarchy & Inheritance Chain

### Class Inheritance Tree

```
garak/generators/base.py:20
│
└── class Generator(Configurable)
    │   _call_model() @ base.py:68-78 [ABSTRACT - raises NotImplementedError]
    │   DEFAULT_PARAMS @ base.py:24-31
    │   generate() @ base.py:132-224 [ORCHESTRATOR]
    │
    └── garak/generators/openai.py:126
        │
        └── class OpenAICompatible(Generator)
            │   Implements: Chat + Completion models via OpenAI API
            │   supports_multiple_generations = True
            │   generator_family_name = "OpenAICompatible"
            │
            │   @backoff.on_exception @ openai.py:200-210
            │   def _call_model() @ openai.py:211-290 [CONCRETE IMPLEMENTATION]
            │   def __init__() @ openai.py:176-197
            │   def _load_client() @ openai.py:159-167
            │   DEFAULT_PARAMS @ openai.py:136-147
            │
            └── garak/generators/openai.py:293
                │
                └── class OpenAIGenerator(OpenAICompatible)
                    │   Specializes for OpenAI Public API
                    │   generator_family_name = "OpenAI"
                    │   ENV_VAR = "OPENAI_API_KEY"
                    │
                    │   def _load_client() @ openai.py:305-335 [OVERRIDE]
                    │   def __init__() @ openai.py:337-343
                    │   DEFAULT_PARAMS @ openai.py:301-303 [FILTERED]
                    │
                    └── garak/generators/openai.py:346
                        │
                        └── class OpenAIReasoningGenerator(OpenAIGenerator)
                            Specializes for o1/o3 reasoning models
                            supports_multiple_generations = False
                            DEFAULT_PARAMS @ openai.py:351-360
                            suppressed_params: ["n", "temperature", "max_tokens", "stop"]
```

---

## 2. Detailed Class Specifications

### 2.1 Generator Base Class (base.py:20-78)

**Location**: `garak/generators/base.py:20`

**Key Components**:
```python
class Generator(Configurable):
    DEFAULT_PARAMS = {
        "max_tokens": 150,
        "temperature": None,
        "top_k": None,
        "context_len": None,
        "skip_seq_start": None,
        "skip_seq_end": None,
    }

    supports_multiple_generations = False
    parallel_capable = True

    def _call_model(self, prompt: Conversation, generations_this_call: int = 1) -> List[Union[Message, None]]:
        """ABSTRACT METHOD - must be implemented by subclasses"""
        raise NotImplementedError

    def generate(self, prompt: Conversation, generations_this_call: int = 1) -> List[Union[Message, None]]:
        """ORCHESTRATOR: Handles parallel execution, post-processing, sequencing"""
        # Lines 132-224: Complex dispatch logic for single/multiple/parallel generations
```

**Critical for Rate Limiting**:
- `generate()` @ base.py:132-224 is the orchestrator that calls `_call_model()`
- Parallel execution logic @ base.py:167-216 uses `multiprocessing.Pool`
- Rate limiter must be thread-safe for parallel requests

---

### 2.2 OpenAICompatible Class (openai.py:126-291)

**Location**: `garak/generators/openai.py:126`

**Inheritance**: `OpenAICompatible(Generator)`

**Key Methods**:

#### 2.2.1 __init__ @ openai.py:176-197

```python
def __init__(self, name="", config_root=_config):
    self.name = name                              # Line 177: Model name (e.g., gpt-4o)
    self._load_config(config_root)                # Line 178: Load config from YAML/defaults
    self.fullname = f"{...} {self.name}"          # Line 179: Descriptive name
    self.key_env_var = self.ENV_VAR               # Line 180: API key env var name

    self._load_client()                           # Line 182: INIT OpenAI client

    # Validation (lines 184-190)
    if self.generator not in (self.client.chat.completions, self.client.completions):
        raise ValueError("Unsupported model")

    self._validate_config()                       # Line 192: Subclass validation hook
    super().__init__(self.name, config_root)     # Line 194: Parent class init
    self._clear_client()                          # Line 197: Clear for pickling
```

**Rate Limiting Integration**: After line 192, before line 194:
- Initialize rate limiter with model name, tier, and rate limits
- Load configuration from `/Plan/rate_config.json`

---

#### 2.2.2 _load_client @ openai.py:159-167

```python
def _load_client(self):
    self.client = openai.OpenAI(base_url=self.uri, api_key=self.api_key)  # Line 162

    if self.name in ("", None):
        raise ValueError("Model name required")

    self.generator = self.client.chat.completions  # Line 167: Chat API endpoint
```

**Note**: `OpenAIGenerator` overrides this @ openai.py:305-335

---

#### 2.2.3 @backoff decorator @ openai.py:200-210

```python
@backoff.on_exception(
    backoff.fibo,                                 # Fibonacci backoff strategy
    (
        openai.RateLimitError,                    # 429 errors
        openai.InternalServerError,               # 500 errors
        openai.APITimeoutError,                   # Timeout errors
        openai.APIConnectionError,                # Connection errors
        garak.exception.GarakBackoffTrigger,      # Custom backoff trigger
    ),
    max_value=70,                                 # Max 70 second wait
)
def _call_model(self, prompt, generations_this_call=1):
    # ... implementation ...
```

**Critical for Rate Limiting**:
- Backoff WRAPS _call_model, so rate limiting happens INSIDE backoff
- Pre-emptive rate limiting prevents 429 errors before they occur
- Backoff is secondary failsafe if limits slip

---

#### 2.2.4 _call_model @ openai.py:211-290 (CORE API INTEGRATION)

```python
def _call_model(self, prompt: Union[Conversation, List[dict]], generations_this_call: int = 1) -> List[Union[Message, None]]:

    # CLIENT RELOAD (lines 214-216)
    if self.client is None:
        self._load_client()

    # PARAMETER BUILDING (lines 218-233)
    create_args = {}
    for arg in inspect.signature(self.generator.create).parameters:  # Line 221
        # Dynamically build parameters from class attributes
        # Lines 222-229: Handle model name, suppress params, etc.

    # PROMPT PREPARATION (lines 235-260)
    if self.generator == self.client.completions:
        # COMPLETION MODEL PATH (lines 235-244)
        create_args["prompt"] = prompt.last_message().text

    elif self.generator == self.client.chat.completions:
        # CHAT MODEL PATH (lines 246-260)
        messages = self._conversation_to_list(prompt)  # Convert Conversation → list[dict]
        create_args["messages"] = messages

    # ⭐ PRE-REQUEST HOOK (RATE LIMITING INSERTION POINT #1)
    # → INSERT token estimation here
    # → INSERT rate limiter check here

    try:
        response = self.generator.create(**create_args)  # Line 263: ACTUAL API CALL

    except openai.BadRequestError as e:
        # Handle 400 errors (client error, don't retry)
        return [None]  # Line 268

    except json.decoder.JSONDecodeError as e:
        # Handle response parsing errors
        if self.retry_json:
            raise garak.exception.GarakBackoffTrigger from e  # Trigger backoff retry

    # RESPONSE VALIDATION (lines 276-285)
    if not hasattr(response, "choices"):
        if self.retry_json:
            raise garak.exception.GarakBackoffTrigger("No choices in response")

    # ⭐ POST-RESPONSE HOOK (RATE LIMITING INSERTION POINT #2)
    # → EXTRACT response.usage.prompt_tokens
    # → EXTRACT response.usage.completion_tokens
    # → RECORD in rate limiter

    # RESPONSE PARSING (lines 287-290)
    if self.generator == self.client.completions:
        return [Message(c.text) for c in response.choices]  # Line 288
    elif self.generator == self.client.chat.completions:
        return [Message(c.message.content) for c in response.choices]  # Line 290
```

**Response.usage Structure** (available after line 263):
```python
response.usage = {
    'prompt_tokens': int,        # Exact count from API
    'completion_tokens': int,    # Exact count from API
    'total_tokens': int          # Sum of above
}
```

---

### 2.3 OpenAIGenerator Class (openai.py:293-343)

**Location**: `garak/generators/openai.py:293`

**Inheritance**: `OpenAIGenerator(OpenAICompatible)`

**Specialization**: Public OpenAI API (not Azure, not compatible endpoint)

**Key Override**: _load_client @ openai.py:305-335

```python
def _load_client(self):
    self.client = openai.OpenAI(api_key=self.api_key)  # Line 306: No base_url

    # MODEL DETECTION (lines 318-325)
    if self.name in completion_models:
        self.generator = self.client.completions      # Line 319
    elif self.name in chat_models:
        self.generator = self.client.chat.completions # Line 321
    elif re.match(r"^.+-[01][0-9][0-3][0-9]$", self.name):
        self.generator = self.client.completions      # Line 325: Handle date-suffixed models
    else:
        raise ValueError(f"Unknown model: {self.name}")

    # REASONING MODEL CHECK (lines 332-335)
    if self.__class__.__name__ == "OpenAIGenerator" and self.name.startswith("o"):
        raise BadGeneratorException("Use OpenAIReasoningGenerator for o1/o3 models")
```

**Configuration** @ openai.py:301-303:
```python
DEFAULT_PARAMS = {
    k: val for k, val in OpenAICompatible.DEFAULT_PARAMS.items() if k != "uri"
}
# Removes "uri" since public OpenAI has fixed endpoint
```

---

### 2.4 OpenAIReasoningGenerator Class (openai.py:346-360)

**Location**: `garak/generators/openai.py:346`

**Inheritance**: `OpenAIReasoningGenerator(OpenAIGenerator)`

**Specialization**: OpenAI o1/o3 reasoning models

**Key Differences**:
```python
supports_multiple_generations = False  # Line 349: Can't request multiple in single call

DEFAULT_PARAMS = Generator.DEFAULT_PARAMS | {
    "top_p": 1.0,
    "suppressed_params": set(["n", "temperature", "max_tokens", "stop"]),  # Line 357
    "max_completion_tokens": 1500,  # Line 359: Different param name
}
```

**Rate Limiting Implication**: No multiple generations support means no batch tokens in single request.

---

## 3. REQUEST FLOW TRACING

### 3.1 Probe → Generator → API Flow

```
1. garak/probes/base.py:269-270
   └─ probe._execute_attempt(attempt)
      └─ this_attempt.outputs = generator.generate(prompt, generations_this_call)

2. garak/generators/base.py:132-224
   └─ Generator.generate(prompt, generations_this_call)
      ├─ IF generations_this_call == 1:
      │  └─ outputs = self._call_model(prompt, 1)
      │
      ├─ ELIF supports_multiple_generations:
      │  └─ outputs = self._call_model(prompt, generations_this_call)
      │
      └─ ELSE (parallel):
         ├─ IF parallel_requests > 1:
         │  └─ Pool(pool_size).imap_unordered(_call_model, [prompts]*n)
         │
         └─ ELSE:
            └─ Loop: _call_model(prompt, 1) × n times

3. garak/generators/openai.py:211-290
   └─ @backoff.on_exception wrapper @ line 200
      └─ OpenAICompatible._call_model(prompt, generations_this_call)
         ├─ Reload client if needed (line 214-216)
         ├─ Build create_args from config (lines 218-233)
         ├─ Prepare prompt (lines 235-260)
         │
         ├─ ⭐ [RATE LIMITING INSERTION #1]
         │  ├─ Token count: estimate_input_tokens(prompt)
         │  └─ Rate check: rate_limiter.check_and_wait(tokens)
         │
         ├─ response = self.generator.create(**create_args) [LINE 263]
         │
         ├─ Error handling (lines 264-285)
         │
         ├─ ⭐ [RATE LIMITING INSERTION #2]
         │  ├─ Extract: response.usage.prompt_tokens
         │  ├─ Extract: response.usage.completion_tokens
         │  └─ Record: rate_limiter.record_usage(tokens)
         │
         └─ Parse response & return [Message, ...] (lines 287-290)
```

---

## 4. PARAMETER FLOW

### 4.1 Configuration Cascade

```
1. DEFAULT_PARAMS @ class level
   └─ Generator.DEFAULT_PARAMS (base.py:24-31)
      └─ + OpenAICompatible.DEFAULT_PARAMS (openai.py:136-147)
         └─ Filtered/overridden by OpenAIGenerator (openai.py:301-303)

2. Config loading @ __init__
   └─ _load_config(config_root) @ openai.py:178
      └─ Configurable._load_config() @ configurable.py:15-59
         ├─ Load from YAML config files
         ├─ Load from environment variables
         └─ Apply defaults via _apply_missing_instance_defaults()

3. Instance attributes @ self
   └─ Used in _call_model via inspect.signature() @ line 221
      └─ Dynamic parameter extraction from self.{param_name}

4. API Request
   └─ create_args dict (lines 218-233)
      └─ self.generator.create(**create_args) @ line 263
```

### 4.2 Key Parameters for Rate Limiting

```python
# In create_args (lines 218-233):
{
    "model": self.name,              # e.g., "gpt-4o"
    "n": generations_this_call,      # Number of responses (1-10 typically)
    "temperature": self.temperature, # Sampling parameter
    "max_tokens": self.max_tokens,   # Output limit
    "messages": [...],               # Input messages
    # ... other params from inspect.signature
}

# From self (used for rate limiting):
self.name                            # Model name (determines tier)
self.max_tokens                      # Used for completion token estimation
self.temperature                     # Config parameter
self.extra_params                    # Extra OpenAI params

# Environment:
OPENAI_API_KEY                       # From self.api_key
```

---

## 5. RATE LIMITING INTEGRATION POINTS

### 5.1 Insertion Point #1: Pre-Request (Line 262-263)

**Location**: Between lines 262 and 263 in openai.py

```python
# CURRENT CODE (lines 261-263):
        try:
            response = self.generator.create(**create_args)

# INSERTION POINT #1:
        # ⭐ TOKEN COUNTING & RATE LIMITING
        if hasattr(self, 'rate_limiter'):
            # Estimate input tokens
            estimated_prompt_tokens = self._estimate_prompt_tokens(create_args)
            estimated_completion_tokens = self.max_tokens if hasattr(self, 'max_tokens') else 150
            estimated_total = estimated_prompt_tokens + estimated_completion_tokens

            # Check and wait for rate limits
            self.rate_limiter.check_and_wait(estimated_total)

        try:
            response = self.generator.create(**create_args)
```

**What to extract**:
- Input prompt tokens (from messages or prompt field in create_args)
- Estimated output tokens (from max_tokens parameter)
- Calculate total and check against TPM/RPM limits
- Sleep if necessary before making API call

---

### 5.2 Insertion Point #2: Post-Response (Line 287-291)

**Location**: Between lines 286 and 287 in openai.py

```python
# CURRENT CODE (lines 287-291):
        if self.generator == self.client.completions:
            return [Message(c.text) for c in response.choices]
        elif self.generator == self.client.chat.completions:
            return [Message(c.message.content) for c in response.choices]

# INSERTION POINT #2 (after line 286, before 287):
        # ⭐ RECORD ACTUAL TOKEN USAGE
        if hasattr(self, 'rate_limiter') and hasattr(response, 'usage'):
            actual_prompt_tokens = response.usage.prompt_tokens
            actual_completion_tokens = response.usage.completion_tokens
            self.rate_limiter.record_usage(
                prompt_tokens=actual_prompt_tokens,
                completion_tokens=actual_completion_tokens
            )
            logging.debug(f"Token usage recorded: {actual_prompt_tokens} input, {actual_completion_tokens} output")

        if self.generator == self.client.completions:
            return [Message(c.text) for c in response.choices]
```

**What to capture**:
- `response.usage.prompt_tokens` - Actual input tokens used
- `response.usage.completion_tokens` - Actual output tokens generated
- Record for accurate rate limit tracking

---

### 5.3 Insertion Point #3: Initialization (Line 192)

**Location**: Between lines 192 and 194 in openai.py

```python
# CURRENT CODE (lines 192-194):
        self._validate_config()
        super().__init__(self.name, config_root=config_root)

# INSERTION POINT #3:
        self._validate_config()

        # ⭐ INITIALIZE RATE LIMITER
        self._init_rate_limiter()  # New method

        super().__init__(self.name, config_root=config_root)

# New method to add:
    def _init_rate_limiter(self):
        """Initialize rate limiter if configuration provided"""
        if not hasattr(self, 'enable_rate_limiting') or not self.enable_rate_limiting:
            self.rate_limiter = None
            return

        # Load configuration from rate_config.json
        # Model auto-detection from self.name
        # Tier detection from CLI or config
        # Initialize TokenRateLimiter with RPM/TPM limits
```

---

## 6. ERROR HANDLING PATTERNS

### 6.1 Current Exception Hierarchy

```python
# Lines 200-210: @backoff catches
openai.RateLimitError          # 429 - Rate Limited
openai.InternalServerError     # 500 - Server Error
openai.APITimeoutError         # Timeout
openai.APIConnectionError      # Connection Error
garak.exception.GarakBackoffTrigger  # Custom retry trigger

# Lines 264-268: BadRequestError handled
openai.BadRequestError         # 400 - Client Error (don't retry)
    → Returns [None]

# Lines 269-274: JSONDecodeError
json.decoder.JSONDecodeError  # Invalid JSON response
    → Triggers GarakBackoffTrigger if retry_json=True
```

### 6.2 Rate Limiting Error Handling

**New errors to consider**:
- Rate limiter budget exhaustion → Return [None] gracefully
- Token count failure → Log warning, proceed with estimation
- Configuration error → Raise ValueError during init

---

## 7. PICKLING & MULTIPROCESSING IMPLICATIONS

### 7.1 Pickling for Multiprocessing.Pool @ base.py:189

```python
# base.py:189-195
with Pool(pool_size) as pool:
    for result in pool.imap_unordered(self._call_model, [prompt] * generations_this_call):
        # Each worker gets a pickled copy of self
```

**Pickle Handlers** @ openai.py:150-157:

```python
def __getstate__(self) -> object:
    self._clear_client()  # Line 151: Remove unpicklable client
    return dict(self.__dict__)

def __setstate__(self, d) -> object:
    self.__dict__.update(d)
    self._load_client()  # Line 157: Recreate client in worker process
```

**Rate Limiter Consideration**:
- `OpenAIRateLimiter` should be picklable OR cleared before pickle
- Each worker process gets its own rate limiter instance
- Global state must be thread-safe within worker

---

## 8. SUMMARY TABLE

| Component | File | Lines | Purpose |
|-----------|------|-------|---------|
| Generator base | base.py | 20-78 | Abstract interface |
| Generator.generate() | base.py | 132-224 | Orchestrator, parallel dispatch |
| OpenAICompatible | openai.py | 126-291 | OpenAI API implementation |
| @backoff decorator | openai.py | 200-210 | Exponential backoff on errors |
| _call_model | openai.py | 211-290 | Core API integration |
| Parameter building | openai.py | 218-233 | Config → API args |
| Pre-API hook | openai.py | 262 | ⭐ Rate limiting insertion #1 |
| API call | openai.py | 263 | response = create(...) |
| Post-response hook | openai.py | 287 | ⭐ Rate limiting insertion #2 |
| Response parsing | openai.py | 287-290 | Extract Message content |
| OpenAIGenerator | openai.py | 293-343 | Public OpenAI specialization |
| _load_client override | openai.py | 305-335 | Model detection & routing |
| OpenAIReasoningGenerator | openai.py | 346-360 | o1/o3 specialization |

---

## 9. CRITICAL FINDINGS FOR RATE LIMITING

### 9.1 Token Availability

✅ **After API response** (line 263):
- `response.usage.prompt_tokens` - Exact from OpenAI
- `response.usage.completion_tokens` - Exact from OpenAI
- Perfect for POST-response tracking

⚠️ **Before API call** (pre-line 263):
- Must ESTIMATE tokens (no exact count without calling API)
- Use tiktoken encoding
- Err on high side (prevent 429 errors)

### 9.2 Model Detection

✅ Model name available in:
- `self.name` - Set at init time
- Used for rate limit tier lookup
- Distinguishes chat vs completion endpoints

### 9.3 Parallel Request Safety

⚠️ Critical constraint:
- `multiprocessing.Pool` @ base.py:189
- Each worker is separate process with separate Python interpreter
- Global locks don't work across processes
- Rate limiter must be per-process OR use shared memory

### 9.4 Backoff Already in Place

✅ Existing retry logic:
- `@backoff.on_exception` @ openai.py:200-210
- Catches `openai.RateLimitError`
- Fibonacci backoff up to 70 seconds
- Pre-emptive rate limiting prevents hitting this

### 9.5 Graceful Degradation

✅ Return patterns:
- Return `[None]` on error (not exception)
- Probe handles None gracefully
- Rate limiter can signal budget exhaustion via None return

---

## 10. NEXT STEPS (Task 1.2)

**Dependencies**: This analysis (Task 1.1) ✅ COMPLETE

**Next**: Task 1.2 - Identify all integration points with exact line numbers for injection

**Deliverable**: `.claude/docs/integration-points.md`
