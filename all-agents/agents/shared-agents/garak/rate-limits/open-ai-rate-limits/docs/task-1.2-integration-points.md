# Task 1.2: Integration Points for Rate Limiting

**Status**: ✅ COMPLETE
**Date**: 2025-10-20
**Deliverable**: Exact line numbers and code injection locations for rate limiter integration

---

## 1. INTEGRATION POINT SUMMARY

```
Integration Points in garak/generators/openai.py:

POINT 1: Initialization (lines 192-194)
├─ Location: Between _validate_config() and super().__init__()
├─ Purpose: Initialize rate limiter with model tier detection
└─ Severity: Critical - sets up entire rate limiting system

POINT 2: Pre-Request Token Estimation (lines 262-263)
├─ Location: Before response = self.generator.create(**create_args)
├─ Purpose: Estimate tokens, check RPM/TPM limits, sleep if needed
└─ Severity: Critical - prevents rate limit errors

POINT 3: Post-Response Usage Recording (lines 286-287)
├─ Location: After response validation, before response parsing
├─ Purpose: Extract actual token usage from API response
└─ Severity: High - ensures accurate limit tracking

POINT 4: Pickling Support (lines 150-157)
├─ Location: __getstate__() and __setstate__() methods
├─ Purpose: Handle rate limiter for multiprocessing.Pool
└─ Severity: High - required for parallel requests

POINT 5: Configuration Loading (lines 176-178)
├─ Location: __init__ method, config cascade
├─ Purpose: Add rate limiting configuration parameters
└─ Severity: Medium - enables configuration-based control
```

---

## 2. DETAILED INJECTION POINTS

### 2.1 POINT 1: Initialization (lines 192-194)

**Current Code**:
```python
176  def __init__(self, name="", config_root=_config):
177      self.name = name
178      self._load_config(config_root)
179      self.fullname = f"{self.generator_family_name} {self.name}"
180      self.key_env_var = self.ENV_VAR
181
182      self._load_client()
183
184      if self.generator not in (
185          self.client.chat.completions,
186          self.client.completions,
187      ):
188          raise ValueError(
189              "Unsupported model at generation time in generators/openai.py - please add a clause!"
190          )
191
192      self._validate_config()
193
194      super().__init__(self.name, config_root=config_root)
195
196      # clear client config to enable object to `pickle`
197      self._clear_client()
```

**Injection Strategy**:
```python
192      self._validate_config()
193
         # ⭐ INSERTION POINT 1: Initialize rate limiter
         self._init_rate_limiter()
194
195      super().__init__(self.name, config_root=config_root)
```

**New Method to Add** (after _validate_config):
```python
    def _init_rate_limiter(self):
        """Initialize rate limiter with model-specific rate limits"""
        import json
        import os
        from pathlib import Path

        # Check if rate limiting is enabled
        if not hasattr(self, 'enable_rate_limiting'):
            self.enable_rate_limiting = True  # Default to enabled

        if not self.enable_rate_limiting:
            self.rate_limiter = None
            return

        try:
            # Load rate configuration
            rate_config_path = Path(__file__).parent.parent / "resources" / "rate_config.json"

            if not rate_config_path.exists():
                logging.warning(f"Rate config not found at {rate_config_path}, using defaults")
                self.rate_limiter = None
                return

            with open(rate_config_path, 'r') as f:
                config = json.load(f)

            # Determine generator type and load rates
            generator_type = self.__class__.__name__  # e.g., "OpenAIGenerator"
            if generator_type not in config:
                logging.warning(f"No config for {generator_type}, rate limiting disabled")
                self.rate_limiter = None
                return

            gen_config = config[generator_type]

            # Get model-specific rates
            if self.name not in gen_config.get("models", {}):
                logging.warning(f"No rates defined for model {self.name}, using defaults")
                self.rate_limiter = None
                return

            model_config = gen_config["models"][self.name]

            # Get tier (from environment, config, or default)
            if not hasattr(self, 'tier'):
                self.tier = os.getenv("OPENAI_TIER", "free")

            if self.tier not in model_config.get("rates", {}):
                logging.warning(f"Tier {self.tier} not found for {self.name}, using free")
                self.tier = "free"

            tier_rates = model_config["rates"][self.tier]

            # Initialize rate limiter from garak.generators.rate_limiter
            from garak.generators.rate_limiter import TokenRateLimiter

            self.rate_limiter = TokenRateLimiter(
                model_name=self.name,
                rpm_limit=int(tier_rates.get("rpm", 3)),
                tpm_limit=int(tier_rates.get("tpm", 40000)),
            )

            logging.info(
                f"Rate limiter initialized for {self.name} "
                f"(tier: {self.tier}, RPM: {tier_rates.get('rpm')}, TPM: {tier_rates.get('tpm')})"
            )

        except Exception as e:
            logging.error(f"Failed to initialize rate limiter: {e}, disabling")
            self.rate_limiter = None
```

**Configuration Parameters to Add to DEFAULT_PARAMS** (line 136-147):
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
        "retry_json": True,
        "extra_params": {},
        # ⭐ NEW PARAMETERS FOR RATE LIMITING
        "enable_rate_limiting": True,       # Enable/disable rate limiting
        "tier": "free",                     # Rate limit tier (free, tier1-5)
    }
```

---

### 2.2 POINT 2: Pre-Request Token Estimation & Rate Check (lines 262-263)

**Current Code**:
```python
260          create_args["messages"] = messages
261
262      try:
263          response = self.generator.create(**create_args)
```

**Injection Strategy**:
```python
260          create_args["messages"] = messages
261
         # ⭐ INSERTION POINT 2: Pre-request rate limiting
         if hasattr(self, 'rate_limiter') and self.rate_limiter is not None:
             estimated_tokens = self._estimate_request_tokens(create_args)
             self.rate_limiter.check_and_wait(estimated_tokens)
262
263      try:
264          response = self.generator.create(**create_args)
```

**New Method to Add** (after _call_model):
```python
    def _estimate_request_tokens(self, create_args: dict) -> int:
        """Estimate total tokens for this request (input + output)"""
        try:
            from garak.resources.red_team.evaluation import token_count
        except ImportError:
            # Fallback if not available
            logging.debug("Could not import token_count, using word-based estimation")
            total_text = str(create_args)
            return int(len(total_text.split()) * 1.3)

        try:
            # Estimate input tokens
            if "messages" in create_args:
                # Chat completions format
                messages_text = str(create_args["messages"])
                input_tokens = token_count(messages_text, self.name)
            elif "prompt" in create_args:
                # Completion format
                input_tokens = token_count(create_args["prompt"], self.name)
            else:
                input_tokens = 0

            # Estimate output tokens
            output_tokens = create_args.get("max_tokens", 150)

            # Add overhead for message formatting (4 tokens per message in chat)
            if "messages" in create_args:
                output_tokens += 4 * len(create_args["messages"])

            estimated_total = input_tokens + output_tokens

            logging.debug(
                f"Estimated tokens for {self.name}: "
                f"{input_tokens} input + {output_tokens} output = {estimated_total} total"
            )

            return estimated_total

        except Exception as e:
            logging.warning(f"Token estimation failed: {e}, using fallback")
            total_text = str(create_args)
            return int(len(total_text.split()) * 1.3)
```

---

### 2.3 POINT 3: Post-Response Token Recording (lines 286-287)

**Current Code**:
```python
276          if not hasattr(response, "choices"):
277              logging.debug(...)
278              msg = "no .choices member in generator response"
279              if self.retry_json:
280                  raise garak.exception.GarakBackoffTrigger(msg)
281              else:
282                  return [None]
283
284          if self.generator == self.client.completions:
285              return [Message(c.text) for c in response.choices]
286          elif self.generator == self.client.chat.completions:
287              return [Message(c.message.content) for c in response.choices]
```

**Injection Strategy**:
```python
276          if not hasattr(response, "choices"):
277              ...
282
         # ⭐ INSERTION POINT 3: Record actual token usage
         if hasattr(self, 'rate_limiter') and self.rate_limiter is not None:
             if hasattr(response, 'usage') and response.usage is not None:
                 self.rate_limiter.record_usage(
                     prompt_tokens=response.usage.prompt_tokens,
                     completion_tokens=response.usage.completion_tokens,
                 )
                 logging.debug(
                     f"Recorded usage for {self.name}: "
                     f"{response.usage.prompt_tokens} input + {response.usage.completion_tokens} output"
                 )
             else:
                 logging.debug("No usage information in response")
283
284          if self.generator == self.client.completions:
285              return [Message(c.text) for c in response.choices]
286          elif self.generator == self.client.chat.completions:
287              return [Message(c.message.content) for c in response.choices]
```

**Response.usage Structure** (guaranteed by OpenAI API):
```python
response.usage = {
    'prompt_tokens': int,        # Input tokens used
    'completion_tokens': int,    # Output tokens generated
    'total_tokens': int,         # Sum (always available)
}
```

---

### 2.4 POINT 4: Pickling Support (lines 150-157)

**Current Code**:
```python
149      # avoid attempt to pickle the client attribute
150      def __getstate__(self) -> object:
151          self._clear_client()
152          return dict(self.__dict__)
153
154      # restore the client attribute
155      def __setstate__(self, d) -> object:
156          self.__dict__.update(d)
157          self._load_client()
```

**Injection Strategy**:
```python
149      # avoid attempt to pickle the client attribute
150      def __getstate__(self) -> object:
151          self._clear_client()
         # ⭐ INSERTION POINT 4a: Clear rate limiter before pickle
         state = dict(self.__dict__)
         state['rate_limiter'] = None  # Will be recreated in worker process
         return state
152
153      # restore the client attribute
154      def __setstate__(self, d) -> object:
155          self.__dict__.update(d)
156          self._load_client()
         # ⭐ INSERTION POINT 4b: Recreate rate limiter in worker process
         if d.get('enable_rate_limiting', True):
             self._init_rate_limiter()
157
158      def _clear_client(self):
159          self.generator = None
160          self.client = None
```

**Rationale**:
- Multiprocessing.Pool pickles generator instance for each worker
- Rate limiter with threading.Lock can't pickle
- Each worker gets fresh rate limiter instance with its own lock
- Tier detection works because config is loaded from environment

---

### 2.5 POINT 5: Configuration Parameters (line 136-147)

**Current DEFAULT_PARAMS**:
```python
136      DEFAULT_PARAMS = Generator.DEFAULT_PARAMS | {
137          "temperature": 0.7,
138          "top_p": 1.0,
139          "uri": "http://localhost:8000/v1/",
140          "frequency_penalty": 0.0,
141          "presence_penalty": 0.0,
142          "seed": None,
143          "stop": ["#", ";"],
144          "suppressed_params": set(),
145          "retry_json": True,
146          "extra_params": {},
147      }
```

**With Rate Limiting Parameters**:
```python
136      DEFAULT_PARAMS = Generator.DEFAULT_PARAMS | {
137          "temperature": 0.7,
138          "top_p": 1.0,
139          "uri": "http://localhost:8000/v1/",
140          "frequency_penalty": 0.0,
141          "presence_penalty": 0.0,
142          "seed": None,
143          "stop": ["#", ";"],
144          "suppressed_params": set(),
145          "retry_json": True,
146          "extra_params": {},
         # ⭐ INSERTION POINT 5: Rate limiting configuration
147          "enable_rate_limiting": True,
148          "tier": "free",
149      }
```

**Configuration Loading Flow**:
1. DEFAULT_PARAMS provides defaults (enable_rate_limiting=True, tier="free")
2. YAML config can override (e.g., tier="tier5")
3. Environment variable can override (OPENAI_TIER)
4. _init_rate_limiter() uses loaded values

---

## 3. REQUIRED NEW FILES

### 3.1 garak/generators/rate_limiter.py

**Location**: `garak/generators/rate_limiter.py` (NEW FILE)

**Purpose**: TokenRateLimiter class with RPM/TPM enforcement

**Key Methods**:
- `__init__(model_name, rpm_limit, tpm_limit)`
- `check_and_wait(estimated_tokens) -> None` (pre-request)
- `record_usage(prompt_tokens, completion_tokens) -> None` (post-response)
- `get_stats() -> dict` (for monitoring)

**Thread Safety**: Uses `threading.Lock()` for atomic operations

**Sliding Window**: Tracks requests/tokens in 60-second window

---

### 3.2 Utilize Existing rate_config.json

**Location**: Already exists at `/Users/gmoshkov/Professional/Code/GarakGM/Plan/rate_config.json`

**Structure**:
```json
{
  "OpenAIGenerator": {
    "models": {
      "gpt-4o": {
        "rates": {
          "free": {"rpm": 3, "tpm": 150000},
          "tier1": {"rpm": 500, "tpm": 200000},
          "tier5": {"rpm": 30000, "tpm": 10000000}
        }
      },
      "gpt-3.5-turbo": { ... }
    }
  },
  "AzureOpenAIGenerator": { ... }
}
```

**Copy to**: `garak/resources/rate_config.json`

---

## 4. SUMMARY OF CHANGES

### 4.1 Modified Files

| File | Changes | Severity |
|------|---------|----------|
| garak/generators/openai.py | 5 injection points + 2 new methods | Critical |

### 4.2 New Files

| File | Purpose | Lines |
|------|---------|-------|
| garak/generators/rate_limiter.py | TokenRateLimiter class | ~200-300 |
| garak/resources/rate_config.json | Rate limit configuration | Copy from /Plan/ |

### 4.3 Line Number Summary

```
openai.py Changes:
- Line 136-149: Add enable_rate_limiting & tier to DEFAULT_PARAMS
- Line 192-193: Insert _init_rate_limiter() call
- Line 150-157: Modify __getstate__/__setstate__ for pickling
- Line 262-263: Insert pre-request rate check
- Line 286-287: Insert post-response usage recording
- NEW: _init_rate_limiter() method (~40 lines)
- NEW: _estimate_request_tokens() method (~35 lines)
```

---

## 5. MINIMAL CODE CHANGE PRINCIPLE

**Goal**: Surgical integration with zero breaking changes

**Strategy**:
1. All rate limiting optional (enable_rate_limiting flag)
2. Graceful degradation if rate_limiter not initialized
3. No changes to existing _call_model signature
4. No changes to return types or error handling
5. Uses hasattr() guards for backward compatibility

**Validation**:
- Existing tests should pass unchanged
- Rate limiting can be disabled for testing
- No API changes visible to consumers

---

## 6. NEXT STEPS (Task 1.3)

**Dependencies**: Task 1.2 ✅ COMPLETE

**Next**: Task 1.3 - Document existing error handling and retry patterns

**Deliverable**: `.claude/docs/task-1.3-existing-patterns.md`
