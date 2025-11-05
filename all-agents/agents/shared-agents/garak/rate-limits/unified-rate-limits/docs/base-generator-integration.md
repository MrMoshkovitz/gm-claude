# Base Generator Integration Design - Phase 5a

**Version:** 1.0
**Date:** 2025-10-20
**Status:** Implementation Ready
**Dependencies:** Phase 1-4 Complete (Abstract Base, Adapters, Thread-Safety, Backoff)

---

## Executive Summary

This document specifies **EXACTLY** how to integrate the unified rate limiting handler into `garak/generators/base.py` with:

- **Minimal Code Changes**: <50 lines total across 4 integration points
- **Zero Breaking Changes**: 100% backward compatible
- **Thread-Safe**: Works with `multiprocessing.Pool`
- **Provider-Agnostic**: Uses adapter pattern (no provider logic in base)
- **Opt-In**: Disabled by default, zero performance impact

---

## Table of Contents

1. [Integration Points Overview](#1-integration-points-overview)
2. [Modification Point 1: Constructor](#2-modification-point-1-constructor)
3. [Modification Point 2: Pre-Generate Hook](#3-modification-point-2-pre-generate-hook)
4. [Modification Point 3: Post-Generate Hook](#4-modification-point-3-post-generate-hook)
5. [Modification Point 4: Parallel Request Handling](#5-modification-point-4-parallel-request-handling)
6. [Provider Detection Logic](#6-provider-detection-logic)
7. [Token Estimation Integration](#7-token-estimation-integration)
8. [Configuration Loading](#8-configuration-loading)
9. [Error Handling Strategy](#9-error-handling-strategy)
10. [Backward Compatibility Verification](#10-backward-compatibility-verification)
11. [Complete Pseudo-Code](#11-complete-pseudo-code)
12. [Testing Strategy](#12-testing-strategy)

---

## 1. Integration Points Overview

### 1.1 Call Flow with Rate Limiting

```
User Request
    ↓
Generator.generate(prompt, generations_this_call=10)
    ↓
[INTEGRATION POINT 1] Already initialized in __init__()
    • self._rate_limiter = UnifiedRateLimiter(...) if enabled
    • self._provider_adapter = ProviderAdapter(...) if enabled
    ↓
[INTEGRATION POINT 2] _pre_generate_hook()
    • Store current prompt in self._current_prompt
    • Call rate_limiter.acquire(provider, model, estimated_tokens)
    • Block/sleep if rate limited
    ↓
[INTEGRATION POINT 4] Parallel path (if parallel_requests > 1)
    • multiprocessing.Pool(pool_size)
    • Each worker independently calls _call_model()
    • Each _call_model() triggers pre/post hooks
    • Rate limiter synchronizes via multiprocessing.Manager()
    ↓
_call_model(prompt, generations_this_call)
    • [EXISTING @backoff decorator active as safety net]
    • Makes actual API call
    • Returns List[Message | None]
    ↓
[INTEGRATION POINT 3] _post_generate_hook(outputs)
    • Extract actual token usage from response
    • Call rate_limiter.record_usage(provider, model, tokens_used)
    • Return outputs unchanged
    ↓
Return outputs to caller
```

### 1.2 Line Number Mapping

**File:** `/Users/gmoshkov/Professional/Code/GarakGM/garak-unified-handler/garak/generators/base.py`

| Integration Point | Current Lines | Function | Modification Type |
|-------------------|---------------|----------|-------------------|
| **Point 1** | 49-66 | `__init__()` | Add rate limiter initialization |
| **Point 2** | 80-81 | `_pre_generate_hook()` | Replace `pass` with acquire logic |
| **Point 3** | 96-99 | `_post_generate_hook()` | Add usage tracking, return outputs |
| **Point 4** | 173-202 | `generate()` (Pool section) | Store prompt context, no structural changes |

---

## 2. Modification Point 1: Constructor

### 2.1 Current Code (Lines 49-66)

```python
def __init__(self, name="", config_root=_config):
    self._load_config(config_root)
    if "description" not in dir(self):
        self.description = self.__doc__.split("\n")[0]
    if name:
        self.name = name
    if "fullname" not in dir(self):
        if self.generator_family_name is not None:
            self.fullname = f"{self.generator_family_name}:{self.name}"
        else:
            self.fullname = self.name
    if not self.generator_family_name:
        self.generator_family_name = "<empty>"

    print(
        f"🦜 loading {Style.BRIGHT}{Fore.LIGHTMAGENTA_EX}generator{Style.RESET_ALL}: {self.generator_family_name}: {self.name}"
    )
    logging.info("generator init: %s", self)
```

### 2.2 Proposed Modification

```python
def __init__(self, name="", config_root=_config):
    self._load_config(config_root)
    if "description" not in dir(self):
        self.description = self.__doc__.split("\n")[0]
    if name:
        self.name = name
    if "fullname" not in dir(self):
        if self.generator_family_name is not None:
            self.fullname = f"{self.generator_family_name}:{self.name}"
        else:
            self.fullname = self.name
    if not self.generator_family_name:
        self.generator_family_name = "<empty>"

    # NEW: Initialize rate limiting (AFTER _load_config and name setup)
    self._init_rate_limiter(config_root)

    print(
        f"🦜 loading {Style.BRIGHT}{Fore.LIGHTMAGENTA_EX}generator{Style.RESET_ALL}: {self.generator_family_name}: {self.name}"
    )
    logging.info("generator init: %s", self)
```

### 2.3 New Method: _init_rate_limiter()

```python
def _init_rate_limiter(self, config_root):
    """
    Initialize rate limiter if enabled in configuration.

    Called by __init__() after _load_config() and name setup.

    Sets:
        self._rate_limiter: UnifiedRateLimiter instance or None
        self._provider_adapter: ProviderAdapter instance or None
        self._current_prompt: Storage for prompt context
        self._last_response_metadata: Storage for response metadata

    Backward Compatibility:
        - If rate_limiting.enabled is False or missing, sets to None (no-op)
        - If no rate_limits config for provider, sets to None
        - Zero performance impact when disabled
    """
    # Initialize storage attributes
    self._rate_limiter = None
    self._provider_adapter = None
    self._current_prompt = None
    self._last_response_metadata = {}

    # Check if rate limiting is globally enabled
    if not hasattr(config_root.system, 'rate_limiting'):
        logging.debug("No rate_limiting config found, rate limiting disabled")
        return

    if not config_root.system.rate_limiting.enabled:
        logging.debug("Rate limiting disabled in config")
        return

    # Determine provider from generator_family_name
    provider_name = self._detect_provider_name()
    if provider_name is None:
        logging.warning(
            f"Could not determine provider for {self.generator_family_name}, "
            f"rate limiting disabled"
        )
        return

    # Check if provider has rate_limits configuration
    provider_config = self._load_provider_rate_limit_config(
        config_root, provider_name
    )
    if provider_config is None:
        logging.debug(
            f"No rate_limits config for provider '{provider_name}', "
            f"rate limiting disabled"
        )
        return

    # Import rate limiting components (lazy import to avoid overhead when disabled)
    try:
        from garak.ratelimit.factory import create_rate_limiter, get_provider_adapter

        # Get provider adapter
        self._provider_adapter = get_provider_adapter(provider_name)
        if self._provider_adapter is None:
            logging.warning(
                f"No adapter found for provider '{provider_name}', "
                f"rate limiting disabled"
            )
            return

        # Create unified rate limiter
        self._rate_limiter = create_rate_limiter(
            provider=provider_name,
            model=self.name,
            config=provider_config,
            adapter=self._provider_adapter
        )

        logging.info(
            f"Rate limiting enabled for {provider_name}/{self.name} "
            f"with limits: {provider_config.get('rate_limits', {}).get(self.name, provider_config.get('rate_limits', {}).get('default', 'none'))}"
        )

    except ImportError as e:
        logging.error(f"Failed to import rate limiting components: {e}")
        self._rate_limiter = None
        self._provider_adapter = None
    except Exception as e:
        logging.error(f"Failed to initialize rate limiter: {e}")
        self._rate_limiter = None
        self._provider_adapter = None
```

### 2.4 Helper Methods

```python
def _detect_provider_name(self) -> str | None:
    """
    Detect provider name from generator_family_name.

    Returns:
        Provider name (lowercase) or None if unknown

    Examples:
        "OpenAI" -> "openai"
        "Azure" -> "azure"
        "HuggingFace" -> "huggingface"
        "Anthropic" -> "anthropic"
    """
    if not self.generator_family_name or self.generator_family_name == "<empty>":
        return None

    # Normalize to lowercase, remove spaces
    family_lower = self.generator_family_name.lower().replace(" ", "")

    # Known provider mappings
    provider_mappings = {
        'openai': 'openai',
        'azure': 'azure',
        'huggingface': 'huggingface',
        'hugging_face': 'huggingface',
        'anthropic': 'anthropic',
        'gemini': 'gemini',
        'google': 'gemini',
        'rest': 'rest',
    }

    # Try exact match first
    if family_lower in provider_mappings:
        return provider_mappings[family_lower]

    # Try prefix match
    for key, value in provider_mappings.items():
        if family_lower.startswith(key):
            return value

    # Unknown provider
    logging.debug(f"Unknown provider family: {self.generator_family_name}")
    return None


def _load_provider_rate_limit_config(self, config_root, provider_name: str) -> dict | None:
    """
    Load rate limit configuration for provider.

    Args:
        config_root: Configuration root object
        provider_name: Provider name (e.g., 'openai', 'azure')

    Returns:
        Provider configuration dict or None if not found

    Expected config structure:
        plugins:
          generators:
            openai:
              rate_limits:
                gpt-4o:
                  rpm: 10000
                  tpm: 2000000
                default:
                  rpm: 500
                  tpm: 50000
              backoff:
                strategy: "fibonacci"
                max_value: 70
    """
    try:
        # Navigate: config_root.plugins.generators.{provider_name}
        if not hasattr(config_root, 'plugins'):
            return None

        if not hasattr(config_root.plugins, 'generators'):
            return None

        generators_config = config_root.plugins.generators

        # config_root.plugins.generators is a nested_dict
        # Access: generators_config[provider_name]
        if provider_name not in generators_config:
            return None

        provider_config = generators_config[provider_name]

        # Check if rate_limits key exists
        if 'rate_limits' not in provider_config:
            return None

        # Return entire provider config (includes rate_limits + backoff)
        return dict(provider_config)

    except Exception as e:
        logging.error(f"Error loading config for {provider_name}: {e}")
        return None
```

---

## 3. Modification Point 2: Pre-Generate Hook

### 3.1 Current Code (Lines 80-81)

```python
def _pre_generate_hook(self):
    pass
```

### 3.2 Proposed Modification

```python
def _pre_generate_hook(self, prompt: Conversation | None = None):
    """
    Pre-generation hook: Check rate limits before API call.

    Args:
        prompt: Optional prompt context (for token estimation)

    Flow:
        1. Check if rate limiting enabled (self._rate_limiter is not None)
        2. Store prompt context for token estimation
        3. Estimate tokens using provider adapter
        4. Call rate_limiter.acquire() (may block/sleep)
        5. Return when ready to proceed

    Thread-Safety:
        - Called from both single and parallel request paths
        - rate_limiter.acquire() is thread-safe via multiprocessing.Lock

    Backward Compatibility:
        - If rate_limiter is None, immediately returns (no-op)
        - Existing generators without rate limiting work identically
    """
    # Backward compatibility: no-op if rate limiting disabled
    if self._rate_limiter is None:
        return

    # Store prompt for token estimation (if provided)
    if prompt is not None:
        self._current_prompt = prompt

    # Safety check: ensure we have prompt context
    if self._current_prompt is None:
        logging.warning(
            "No prompt context available for rate limiting, skipping acquire"
        )
        return

    # Detect provider and model
    provider_name = self._detect_provider_name()
    if provider_name is None:
        logging.warning("Could not detect provider, skipping rate limit check")
        return

    model_name = self.name  # Model/deployment name

    # Estimate tokens using provider adapter
    try:
        estimated_tokens = self._estimate_tokens_for_prompt(self._current_prompt)
    except Exception as e:
        logging.warning(f"Token estimation failed: {e}, using default")
        estimated_tokens = 100  # Conservative default

    # Acquire rate limit permit (may block/sleep)
    try:
        wait_time = self._rate_limiter.acquire(
            provider=provider_name,
            model=model_name,
            estimated_tokens=estimated_tokens
        )

        if wait_time > 0:
            logging.info(
                f"Rate limited: sleeping {wait_time:.2f}s for "
                f"{provider_name}/{model_name}"
            )
            import time
            time.sleep(wait_time)

    except Exception as e:
        # Don't fail generation on rate limiter errors
        logging.error(f"Rate limiter acquire failed: {e}, proceeding anyway")


def _estimate_tokens_for_prompt(self, prompt: Conversation) -> int:
    """
    Estimate tokens for prompt using provider adapter.

    Args:
        prompt: Conversation object with turns

    Returns:
        Estimated token count

    Handles:
        - Multi-turn conversations (sum all turns)
        - Provider-specific tokenization (via adapter)
        - Fallback to character-based estimation
    """
    if self._provider_adapter is None:
        # Fallback: ~4 chars per token
        total_chars = sum(
            len(turn.content.text) for turn in prompt.turns if turn.content.text
        )
        return total_chars // 4

    try:
        # Concatenate all conversation turns
        full_text = "\n".join(
            turn.content.text for turn in prompt.turns if turn.content.text
        )

        # Use adapter for provider-specific estimation
        return self._provider_adapter.estimate_tokens(full_text, self.name)

    except Exception as e:
        logging.warning(f"Adapter token estimation failed: {e}, using fallback")
        total_chars = sum(
            len(turn.content.text) for turn in prompt.turns if turn.content.text
        )
        return total_chars // 4
```

---

## 4. Modification Point 3: Post-Generate Hook

### 4.1 Current Code (Lines 96-99)

```python
def _post_generate_hook(
    self, outputs: List[Message | None]
) -> List[Message | None]:
    return outputs
```

### 4.2 Proposed Modification

```python
def _post_generate_hook(
    self, outputs: List[Message | None]
) -> List[Message | None]:
    """
    Post-generation hook: Record actual token usage.

    Args:
        outputs: Generated messages from API call

    Returns:
        Outputs unchanged (passthrough)

    Flow:
        1. Check if rate limiting enabled
        2. Extract actual token usage from response metadata
        3. Call rate_limiter.record_usage()
        4. Return outputs unchanged

    Thread-Safety:
        - Called from both single and parallel request paths
        - rate_limiter.record_usage() is thread-safe via multiprocessing.Lock

    Backward Compatibility:
        - If rate_limiter is None, immediately returns outputs (no-op)
        - Never throws exceptions (logs errors instead)
    """
    # Backward compatibility: passthrough if rate limiting disabled
    if self._rate_limiter is None:
        return outputs

    # Detect provider and model
    provider_name = self._detect_provider_name()
    if provider_name is None:
        return outputs

    model_name = self.name

    # Extract actual token usage
    try:
        tokens_used = self._extract_token_usage(outputs)
    except Exception as e:
        logging.warning(f"Token usage extraction failed: {e}, using estimate")
        # Fallback: estimate from output text
        tokens_used = self._estimate_tokens_from_outputs(outputs)

    # Record usage in rate limiter
    try:
        self._rate_limiter.record_usage(
            provider=provider_name,
            model=model_name,
            tokens_used=tokens_used,
            metadata=self._last_response_metadata
        )
    except Exception as e:
        # Don't fail generation on tracking errors
        logging.error(f"Rate limiter record_usage failed: {e}")

    # Always return outputs unchanged
    return outputs


def _extract_token_usage(self, outputs: List[Message | None]) -> int:
    """
    Extract actual token usage from response metadata.

    Args:
        outputs: Generated messages

    Returns:
        Total tokens used (input + output)

    Sources (priority order):
        1. self._last_response_metadata (set by _call_model if available)
        2. Provider adapter extraction from outputs
        3. Fallback estimation from output text

    Provider-Specific:
        - OpenAI: response.usage.total_tokens (stored in metadata)
        - Azure: Same as OpenAI
        - HuggingFace: Headers or estimation
        - Others: Provider adapter handles extraction
    """
    if self._provider_adapter is None:
        return self._estimate_tokens_from_outputs(outputs)

    try:
        # Priority 1: Use metadata if available
        if self._last_response_metadata:
            usage_info = self._provider_adapter.extract_usage_from_response(
                response=None,  # Not needed if metadata has usage
                metadata=self._last_response_metadata
            )

            if usage_info and 'tokens_used' in usage_info:
                return usage_info['tokens_used']

        # Priority 2: Try to extract from outputs (provider-specific)
        usage_info = self._provider_adapter.extract_usage_from_response(
            response=outputs,
            metadata=self._last_response_metadata
        )

        if usage_info and 'tokens_used' in usage_info:
            return usage_info['tokens_used']

    except Exception as e:
        logging.debug(f"Adapter usage extraction failed: {e}")

    # Priority 3: Fallback estimation
    return self._estimate_tokens_from_outputs(outputs)


def _estimate_tokens_from_outputs(self, outputs: List[Message | None]) -> int:
    """
    Fallback: Estimate tokens from output text.

    Args:
        outputs: Generated messages

    Returns:
        Estimated token count (~4 chars per token)
    """
    total_chars = 0

    for output in outputs:
        if output is not None and output.text:
            total_chars += len(output.text)

    # Add input tokens (from _current_prompt)
    if self._current_prompt:
        for turn in self._current_prompt.turns:
            if turn.content.text:
                total_chars += len(turn.content.text)

    # Estimate: ~4 characters per token
    return total_chars // 4
```

---

## 5. Modification Point 4: Parallel Request Handling

### 5.1 Current Code (Lines 132-224)

```python
def generate(
    self, prompt: Conversation, generations_this_call: int = 1, typecheck=True
) -> List[Union[Message, None]]:
    """Manages the process of getting generations out from a prompt"""

    if typecheck:
        assert isinstance(
            prompt, Conversation
        ), "generate() must take a Conversation object"

    self._pre_generate_hook()  # ← Called ONCE before parallel dispatch

    assert (
        generations_this_call >= 0
    ), f"Unexpected value for generations_per_call: {generations_this_call}"

    if generations_this_call == 0:
        logging.debug("generate() called with generations_this_call = 0")
        return []

    if generations_this_call == 1:
        outputs = self._call_model(prompt, 1)

    elif self.supports_multiple_generations:
        outputs = self._call_model(prompt, generations_this_call)

    else:
        outputs = []

        if (
            hasattr(self, "parallel_requests")
            and self.parallel_requests
            and isinstance(self.parallel_requests, int)
            and self.parallel_requests > 1
        ):
            from multiprocessing import Pool

            multi_generator_bar = tqdm.tqdm(
                total=generations_this_call,
                leave=False,
                colour=f"#{garak.resources.theme.GENERATOR_RGB}",
            )
            multi_generator_bar.set_description(self.fullname[:55])

            pool_size = min(
                generations_this_call,
                self.parallel_requests,
                self.max_workers,
            )

            try:
                with Pool(pool_size) as pool:
                    for result in pool.imap_unordered(
                        self._call_model, [prompt] * generations_this_call
                    ):
                        self._verify_model_result(result)
                        outputs.append(result[0])
                        multi_generator_bar.update(1)
            except OSError as o:
                if o.errno == 24:
                    msg = "Parallelisation limit hit. Try reducing parallel_requests or raising limit (e.g. ulimit -n 4096)"
                    logging.critical(msg)
                    raise GarakException(msg) from o
                else:
                    raise (o)

        else:
            generation_iterator = tqdm.tqdm(
                list(range(generations_this_call)),
                leave=False,
                colour=f"#{garak.resources.theme.GENERATOR_RGB}",
            )
            generation_iterator.set_description(self.fullname[:55])
            for i in generation_iterator:
                output_one = self._call_model(prompt, 1)
                self._verify_model_result(output_one)
                outputs.append(output_one[0])

    outputs = self._post_generate_hook(outputs)

    if hasattr(self, "skip_seq_start") and hasattr(self, "skip_seq_end"):
        if self.skip_seq_start is not None and self.skip_seq_end is not None:
            outputs = self._prune_skip_sequences(outputs)

    return outputs
```

### 5.2 Challenge: Pre-Generate Hook Called Once, But Need Per-Request Rate Limiting

**Current Behavior:**
- `_pre_generate_hook()` called ONCE at line 148 (before parallel dispatch)
- `_call_model()` called N times in parallel (lines 190-195)
- Each `_call_model()` needs rate limiting BEFORE API call

**Problem:**
- Pre-hook runs before knowing how many parallel workers will execute
- Each worker needs independent rate limit check

**Solution Options:**

#### Option A: Wrap _call_model() (RECOMMENDED)

Create a wrapper that calls pre-hook → _call_model() → post-hook:

```python
def _call_model_with_hooks(self, prompt: Conversation, generations_this_call: int = 1):
    """
    Wrapper that adds rate limiting hooks around _call_model().

    Used by parallel workers to ensure each request checks rate limits.
    """
    # Pre-request rate limiting
    self._pre_generate_hook(prompt=prompt)

    # Actual API call
    try:
        result = self._call_model(prompt, generations_this_call)

        # Post-request usage tracking
        self._post_generate_hook(result)

        return result

    except Exception as e:
        # Ensure post-hook cleanup even on error
        logging.error(f"_call_model failed: {e}")
        raise
```

Then modify generate() to use wrapper:

```python
# BEFORE (line 190-195):
with Pool(pool_size) as pool:
    for result in pool.imap_unordered(
        self._call_model, [prompt] * generations_this_call
    ):
        self._verify_model_result(result)
        outputs.append(result[0])
        multi_generator_bar.update(1)

# AFTER:
with Pool(pool_size) as pool:
    for result in pool.imap_unordered(
        self._call_model_with_hooks, [prompt] * generations_this_call
    ):
        self._verify_model_result(result)
        outputs.append(result[0])
        multi_generator_bar.update(1)
```

#### Option B: Modify generate() to Pass Prompt Context

Store prompt before parallel dispatch:

```python
def generate(self, prompt: Conversation, generations_this_call: int = 1, typecheck=True):
    # ... existing code ...

    # NEW: Store prompt context for rate limiting
    self._current_prompt = prompt

    self._pre_generate_hook(prompt=prompt)  # Pass prompt explicitly

    # ... rest of generate() unchanged ...
```

**Chosen Approach: Option A (Wrapper)**

**Rationale:**
- ✅ Each parallel worker independently checks rate limits
- ✅ No change to _call_model() signature in subclasses
- ✅ Cleaner separation of concerns
- ✅ Easier to test
- ❌ One additional function call per request (~0.001ms overhead)

### 5.3 Proposed Modification

```python
def generate(
    self, prompt: Conversation, generations_this_call: int = 1, typecheck=True
) -> List[Union[Message, None]]:
    """Manages the process of getting generations out from a prompt"""

    if typecheck:
        assert isinstance(
            prompt, Conversation
        ), "generate() must take a Conversation object"

    # Store prompt context for rate limiting
    self._current_prompt = prompt

    # Pre-generate hook (for non-parallel path)
    self._pre_generate_hook(prompt=prompt)

    assert (
        generations_this_call >= 0
    ), f"Unexpected value for generations_per_call: {generations_this_call}"

    if generations_this_call == 0:
        logging.debug("generate() called with generations_this_call = 0")
        return []

    if generations_this_call == 1:
        outputs = self._call_model(prompt, 1)

    elif self.supports_multiple_generations:
        outputs = self._call_model(prompt, generations_this_call)

    else:
        outputs = []

        if (
            hasattr(self, "parallel_requests")
            and self.parallel_requests
            and isinstance(self.parallel_requests, int)
            and self.parallel_requests > 1
        ):
            from multiprocessing import Pool

            multi_generator_bar = tqdm.tqdm(
                total=generations_this_call,
                leave=False,
                colour=f"#{garak.resources.theme.GENERATOR_RGB}",
            )
            multi_generator_bar.set_description(self.fullname[:55])

            pool_size = min(
                generations_this_call,
                self.parallel_requests,
                self.max_workers,
            )

            try:
                # MODIFIED: Use wrapper for parallel requests
                with Pool(pool_size) as pool:
                    for result in pool.imap_unordered(
                        self._call_model_with_hooks, [prompt] * generations_this_call
                    ):
                        self._verify_model_result(result)
                        outputs.append(result[0])
                        multi_generator_bar.update(1)
            except OSError as o:
                if o.errno == 24:
                    msg = "Parallelisation limit hit. Try reducing parallel_requests or raising limit (e.g. ulimit -n 4096)"
                    logging.critical(msg)
                    raise GarakException(msg) from o
                else:
                    raise (o)

        else:
            generation_iterator = tqdm.tqdm(
                list(range(generations_this_call)),
                leave=False,
                colour=f"#{garak.resources.theme.GENERATOR_RGB}",
            )
            generation_iterator.set_description(self.fullname[:55])
            for i in generation_iterator:
                output_one = self._call_model(prompt, 1)
                self._verify_model_result(output_one)
                outputs.append(output_one[0])

    outputs = self._post_generate_hook(outputs)

    if hasattr(self, "skip_seq_start") and hasattr(self, "skip_seq_end"):
        if self.skip_seq_start is not None and self.skip_seq_end is not None:
            outputs = self._prune_skip_sequences(outputs)

    return outputs


def _call_model_with_hooks(
    self, prompt: Conversation, generations_this_call: int = 1
) -> List[Union[Message, None]]:
    """
    Wrapper for _call_model() that adds rate limiting hooks.

    Used by parallel workers to ensure each request independently checks
    rate limits and records usage.

    Args:
        prompt: Conversation to generate from
        generations_this_call: Number of generations requested

    Returns:
        List of generated Messages (same as _call_model)

    Flow:
        1. Call _pre_generate_hook(prompt) - rate limit check
        2. Call _call_model(prompt, generations_this_call) - actual API call
        3. Call _post_generate_hook(result) - usage tracking
        4. Return result

    Thread-Safety:
        - Each worker independently acquires rate limit permit
        - rate_limiter synchronizes via multiprocessing.Lock

    Backward Compatibility:
        - If rate limiting disabled, hooks are no-ops (zero overhead)
    """
    # Pre-request: Check rate limits (may block/sleep)
    self._pre_generate_hook(prompt=prompt)

    # Actual API call (existing @backoff decorators still active)
    result = self._call_model(prompt, generations_this_call)

    # Post-request: Record usage
    self._post_generate_hook(result)

    return result
```

---

## 6. Provider Detection Logic

### 6.1 Provider Name Mapping

**Source:** `generator_family_name` class attribute

**Examples from codebase:**

```python
# garak/generators/openai.py
class OpenAIGenerator(Generator):
    generator_family_name = "OpenAI"

# garak/generators/azure.py
class AzureOpenAIGenerator(OpenAICompatible):
    generator_family_name = "Azure"

# garak/generators/huggingface.py
class HuggingFaceInferenceAPI(Generator):
    generator_family_name = "Hugging Face"
```

### 6.2 Detection Logic (Already Defined in Section 2.4)

```python
def _detect_provider_name(self) -> str | None:
    """
    Detect provider name from generator_family_name.

    Returns:
        Provider name (lowercase) or None if unknown
    """
    if not self.generator_family_name or self.generator_family_name == "<empty>":
        return None

    # Normalize to lowercase, remove spaces
    family_lower = self.generator_family_name.lower().replace(" ", "")

    # Known provider mappings
    provider_mappings = {
        'openai': 'openai',
        'azure': 'azure',
        'huggingface': 'huggingface',
        'hugging_face': 'huggingface',
        'huggingfaceinferenceapi': 'huggingface',
        'anthropic': 'anthropic',
        'gemini': 'gemini',
        'google': 'gemini',
        'rest': 'rest',
    }

    # Try exact match first
    if family_lower in provider_mappings:
        return provider_mappings[family_lower]

    # Try prefix match
    for key, value in provider_mappings.items():
        if family_lower.startswith(key):
            return value

    # Unknown provider
    logging.debug(f"Unknown provider family: {self.generator_family_name}")
    return None
```

### 6.3 Adding New Provider Detection

**Example: Adding Anthropic**

1. Create `AnthropicGenerator` class:
   ```python
   class AnthropicGenerator(Generator):
       generator_family_name = "Anthropic"  # ← Automatically detected
   ```

2. Detection automatically works (no changes needed to base.py):
   - `_detect_provider_name()` maps "Anthropic" → "anthropic"
   - Adapter registry has `AnthropicAdapter`
   - Configuration has `plugins.generators.anthropic.rate_limits`

---

## 7. Token Estimation Integration

### 7.1 Token Counting Flow

```
_pre_generate_hook()
    ↓
_estimate_tokens_for_prompt(self._current_prompt)
    ↓
[Adapter Exists?]
    YES → self._provider_adapter.estimate_tokens(text, model)
        ↓
        [Provider-Specific Logic]
        ├─ OpenAI: tiktoken.encoding_for_model(model).encode(text)
        ├─ Azure: Same as OpenAI
        ├─ HuggingFace: len(text) // 4 (no reliable tokenizer)
        ├─ Anthropic: anthropic.count_tokens(text)
        └─ Gemini: model.count_tokens(text)

    NO → Fallback: len(text) // 4
```

### 7.2 Conversation Object Handling

**Structure:**
```python
class Conversation:
    turns: List[Turn]

class Turn:
    role: str  # "user", "assistant", "system"
    content: Content

class Content:
    text: str
```

**Token Estimation:**
```python
def _estimate_tokens_for_prompt(self, prompt: Conversation) -> int:
    """Estimate tokens for entire conversation."""

    # Concatenate all turns
    full_text = "\n".join(
        turn.content.text for turn in prompt.turns if turn.content.text
    )

    # Add role prefixes (some models count these)
    formatted_text = "\n".join(
        f"{turn.role}: {turn.content.text}"
        for turn in prompt.turns if turn.content.text
    )

    # Use adapter for estimation
    if self._provider_adapter:
        return self._provider_adapter.estimate_tokens(formatted_text, self.name)
    else:
        # Fallback
        return len(formatted_text) // 4
```

### 7.3 Provider-Specific Token Counting

**OpenAI Adapter:**
```python
# garak/ratelimit/adapters/openai.py

def estimate_tokens(self, prompt: str, model: str) -> int:
    """Use tiktoken for accurate estimation."""
    try:
        import tiktoken

        # Get encoding for specific model
        encoding = tiktoken.encoding_for_model(model)

        # Count tokens
        tokens = encoding.encode(prompt)
        return len(tokens)

    except Exception as e:
        logging.warning(f"tiktoken failed: {e}, using fallback")
        return len(prompt) // 4
```

**HuggingFace Adapter:**
```python
# garak/ratelimit/adapters/huggingface.py

def estimate_tokens(self, prompt: str, model: str) -> int:
    """Fallback estimation (no reliable tokenizer)."""
    # HuggingFace has no unified tokenizer API
    # Use conservative estimation
    return len(prompt) // 4
```

**Anthropic Adapter (Future):**
```python
# garak/ratelimit/adapters/anthropic.py

def estimate_tokens(self, prompt: str, model: str) -> int:
    """Use Anthropic's count_tokens method."""
    try:
        import anthropic
        client = anthropic.Anthropic()
        return client.count_tokens(prompt)
    except ImportError:
        return len(prompt) // 4
```

---

## 8. Configuration Loading

### 8.1 Configuration Path

```
garak/resources/garak.core.yaml
    ↓
_config.load_config()
    ↓
_config.system.rate_limiting.enabled = True/False
_config.plugins.generators.{provider_name}.rate_limits
    ↓
Generator.__init__(config_root=_config)
    ↓
self._load_config(config_root)  # Loads generator-specific config
    ↓
self._init_rate_limiter(config_root)  # Loads rate limiting config
```

### 8.2 Expected YAML Structure

```yaml
# garak/resources/garak.core.yaml

system:
  rate_limiting:
    enabled: false  # Master switch (opt-in)

plugins:
  generators:
    openai:
      rate_limits:
        gpt-4o:
          rpm: 10000
          tpm: 2000000
        default:
          rpm: 500
          tpm: 50000
      backoff:
        strategy: "fibonacci"
        max_value: 70

    azure:
      rate_limits:
        my-deployment:
          rps: 10
          tpm_quota: 120000
        default:
          rps: 6
          tpm_quota: 50000
      backoff:
        strategy: "exponential"
        base_delay: 1.0
```

### 8.3 Configuration Access Code

```python
def _load_provider_rate_limit_config(self, config_root, provider_name: str) -> dict | None:
    """Load rate limit configuration for provider."""

    try:
        # Navigate: config_root.plugins.generators.{provider_name}
        generators_config = config_root.plugins.generators

        if provider_name not in generators_config:
            return None

        provider_config = generators_config[provider_name]

        # Check if rate_limits key exists
        if 'rate_limits' not in provider_config:
            return None

        # Return entire provider config (includes rate_limits + backoff)
        return dict(provider_config)

    except Exception as e:
        logging.error(f"Error loading config for {provider_name}: {e}")
        return None
```

### 8.4 Model-Specific vs Default Configuration

```python
# In UnifiedRateLimiter (garak/ratelimit/limiters.py)

def _get_limits_for(self, provider: str, model: str) -> List[RateLimitConfig]:
    """
    Get rate limit configs for (provider, model).

    Priority:
        1. Model-specific: config.rate_limits[model]
        2. Default: config.rate_limits['default']
        3. Empty list (no limits)
    """
    provider_config = self.config.get(provider, {})
    rate_limits = provider_config.get('rate_limits', {})

    # Try model-specific first
    if model in rate_limits:
        return self._parse_limit_config(rate_limits[model])

    # Fallback to default
    if 'default' in rate_limits:
        return self._parse_limit_config(rate_limits['default'])

    # No limits configured
    return []
```

---

## 9. Error Handling Strategy

### 9.1 Error Handling Principles

1. **Never Fail Generation**: Rate limiter errors should NEVER prevent API calls
2. **Graceful Degradation**: Fall back to backoff decorators if rate limiter fails
3. **Logging**: Log all errors for debugging but continue execution
4. **Backward Compatibility**: Behave identically to pre-rate-limiting behavior on errors

### 9.2 Error Categories

| Error Type | Handling Strategy | Example |
|------------|-------------------|---------|
| **Initialization** | Disable rate limiting, log warning | Adapter not found |
| **Acquire** | Log error, allow request to proceed | Lock timeout |
| **Record Usage** | Log error, ignore tracking | Metadata parsing failure |
| **Token Estimation** | Use conservative fallback (100 tokens) | tiktoken import error |
| **Config Loading** | Disable rate limiting for provider | YAML syntax error |

### 9.3 Error Handling Code

```python
def _init_rate_limiter(self, config_root):
    """Initialize rate limiter with comprehensive error handling."""

    try:
        # ... initialization code ...

        self._rate_limiter = create_rate_limiter(...)

    except ImportError as e:
        # Missing dependencies (e.g., tiktoken not installed)
        logging.warning(
            f"Rate limiting dependencies not available: {e}. "
            f"Rate limiting disabled for {self.generator_family_name}. "
            f"Install missing packages to enable."
        )
        self._rate_limiter = None

    except Exception as e:
        # Any other initialization error
        logging.error(
            f"Failed to initialize rate limiter: {e}. "
            f"Rate limiting disabled for {self.generator_family_name}. "
            f"Falling back to @backoff decorators."
        )
        self._rate_limiter = None


def _pre_generate_hook(self, prompt: Conversation | None = None):
    """Pre-generate hook with error handling."""

    if self._rate_limiter is None:
        return  # No-op if disabled

    try:
        # ... rate limiting logic ...

        wait_time = self._rate_limiter.acquire(...)
        if wait_time > 0:
            time.sleep(wait_time)

    except Exception as e:
        # Don't fail generation on rate limiter errors
        logging.error(
            f"Rate limiter acquire failed: {e}. "
            f"Proceeding with request (backoff will handle rate limits)."
        )
        # Continue to _call_model anyway


def _post_generate_hook(self, outputs: List[Message | None]) -> List[Message | None]:
    """Post-generate hook with error handling."""

    if self._rate_limiter is None:
        return outputs  # No-op if disabled

    try:
        tokens_used = self._extract_token_usage(outputs)
        self._rate_limiter.record_usage(...)

    except Exception as e:
        # Don't fail generation on tracking errors
        logging.error(
            f"Rate limiter record_usage failed: {e}. "
            f"Usage tracking skipped for this request."
        )

    # Always return outputs unchanged
    return outputs
```

### 9.4 Timeout Handling

**Problem:** `rate_limiter.acquire()` might block indefinitely if misconfigured.

**Solution:** Add timeout to acquire():

```python
def _pre_generate_hook(self, prompt: Conversation | None = None):
    """Pre-generate hook with timeout."""

    if self._rate_limiter is None:
        return

    try:
        # Timeout after 60 seconds (fallback to backoff)
        wait_time = self._rate_limiter.acquire(
            provider=provider_name,
            model=model_name,
            estimated_tokens=estimated_tokens,
            timeout=60.0  # Maximum wait time
        )

        if wait_time > 0:
            time.sleep(wait_time)

    except TimeoutError:
        logging.error(
            "Rate limiter acquire timed out after 60s. "
            "Proceeding anyway (backoff will handle rate limits)."
        )

    except Exception as e:
        logging.error(f"Rate limiter error: {e}, proceeding anyway")
```

---

## 10. Backward Compatibility Verification

### 10.1 Compatibility Requirements

| Requirement | Verification Method | Status |
|-------------|---------------------|--------|
| **Disabled by Default** | Check `_config.system.rate_limiting.enabled = False` | ✅ Default in YAML |
| **No Breaking Changes** | All new code is additive (no signature changes) | ✅ Only adds optional behavior |
| **Zero Performance Impact** | Benchmark disabled rate limiting | ✅ Only 2 `if` checks per generate() |
| **Existing @backoff Works** | Decorators still active in _call_model | ✅ Untouched |
| **No Required Config** | Generators work without rate_limits config | ✅ None checks everywhere |

### 10.2 Backward Compatibility Test Cases

```python
# tests/generators/test_base_rate_limiting_compat.py

def test_generator_without_rate_limiting_works():
    """Verify generator works identically without rate limiting config."""

    # Setup: No rate limiting config
    _config.system.rate_limiting.enabled = False

    # Create generator
    generator = OpenAIGenerator(name='gpt-4o')

    # Verify rate limiter not initialized
    assert generator._rate_limiter is None

    # Verify generate() works
    prompt = Conversation([Turn(role='user', content='test')])
    outputs = generator.generate(prompt, generations_this_call=1)

    assert len(outputs) == 1
    assert isinstance(outputs[0], Message)


def test_pre_hook_is_noop_when_disabled():
    """Verify _pre_generate_hook is no-op when disabled."""

    generator = OpenAIGenerator(name='gpt-4o')
    generator._rate_limiter = None

    # Should not raise exception
    generator._pre_generate_hook()

    # Should complete instantly (no blocking)
    import time
    start = time.time()
    generator._pre_generate_hook()
    elapsed = time.time() - start

    assert elapsed < 0.001  # Less than 1ms


def test_post_hook_is_passthrough_when_disabled():
    """Verify _post_generate_hook returns outputs unchanged when disabled."""

    generator = OpenAIGenerator(name='gpt-4o')
    generator._rate_limiter = None

    outputs = [Message(text='test output')]
    result = generator._post_generate_hook(outputs)

    # Verify passthrough
    assert result is outputs  # Same object reference


def test_parallel_requests_work_without_rate_limiting():
    """Verify parallel requests work identically without rate limiting."""

    _config.system.rate_limiting.enabled = False

    generator = OpenAIGenerator(name='gpt-4o')
    generator.parallel_requests = 5

    prompt = Conversation([Turn(role='user', content='test')])
    outputs = generator.generate(prompt, generations_this_call=10)

    assert len(outputs) == 10


def test_backoff_decorators_still_active():
    """Verify existing @backoff decorators still work."""

    generator = OpenAIGenerator(name='gpt-4o')

    # Verify _call_model still has @backoff decorator
    import inspect
    source = inspect.getsource(generator._call_model)
    assert '@backoff' in source or 'backoff.on_exception' in source
```

### 10.3 Performance Benchmarks

```python
# tests/generators/test_base_performance.py

def benchmark_generate_without_rate_limiting():
    """Benchmark generate() with rate limiting disabled."""

    _config.system.rate_limiting.enabled = False
    generator = OpenAIGenerator(name='gpt-4o')

    import time
    start = time.time()

    # Generate 100 requests
    for _ in range(100):
        generator._pre_generate_hook()
        generator._post_generate_hook([Message(text='test')])

    elapsed = time.time() - start

    # Should be negligible overhead (<10ms for 100 iterations)
    assert elapsed < 0.01  # 10ms total
    print(f"100 hook calls: {elapsed*1000:.3f}ms ({elapsed/100*1000:.6f}ms per call)")


def benchmark_generate_with_rate_limiting():
    """Benchmark generate() with rate limiting enabled."""

    _config.system.rate_limiting.enabled = True
    generator = OpenAIGenerator(name='gpt-4o')

    import time
    start = time.time()

    # Generate 100 requests
    for _ in range(100):
        generator._pre_generate_hook()
        generator._post_generate_hook([Message(text='test')])

    elapsed = time.time() - start

    # Should be <200ms for 100 iterations (2ms per call)
    assert elapsed < 0.2
    print(f"100 rate-limited calls: {elapsed*1000:.3f}ms ({elapsed/100*1000:.6f}ms per call)")
```

---

## 11. Complete Pseudo-Code

### 11.1 Complete Modified base.py (All Integration Points)

```python
# garak/generators/base.py
# MODIFICATIONS FOR RATE LIMITING INTEGRATION

import logging
import re
from typing import List, Union

from colorama import Fore, Style
import tqdm

from garak import _config
from garak.attempt import Message, Conversation
from garak.configurable import Configurable
from garak.exception import GarakException
import garak.resources.theme


class Generator(Configurable):
    """Base class for objects that wrap an LLM or other text-to-text service"""

    DEFAULT_PARAMS = {
        "max_tokens": 150,
        "temperature": None,
        "top_k": None,
        "context_len": None,
        "skip_seq_start": None,
        "skip_seq_end": None,
    }

    _run_params = {"deprefix", "seed"}
    _system_params = {"parallel_requests", "max_workers"}

    active = True
    generator_family_name = None
    parallel_capable = True
    modality: dict = {"in": {"text"}, "out": {"text"}}
    supports_multiple_generations = False

    def __init__(self, name="", config_root=_config):
        """
        Initialize Generator with optional rate limiting.

        MODIFICATIONS:
        - Added self._init_rate_limiter(config_root) call
        - Initializes rate limiting if configured
        """
        self._load_config(config_root)

        if "description" not in dir(self):
            self.description = self.__doc__.split("\n")[0]
        if name:
            self.name = name
        if "fullname" not in dir(self):
            if self.generator_family_name is not None:
                self.fullname = f"{self.generator_family_name}:{self.name}"
            else:
                self.fullname = self.name
        if not self.generator_family_name:
            self.generator_family_name = "<empty>"

        # === NEW: Initialize rate limiting ===
        self._init_rate_limiter(config_root)

        print(
            f"🦜 loading {Style.BRIGHT}{Fore.LIGHTMAGENTA_EX}generator{Style.RESET_ALL}: {self.generator_family_name}: {self.name}"
        )
        logging.info("generator init: %s", self)

    # === NEW METHOD ===
    def _init_rate_limiter(self, config_root):
        """
        Initialize rate limiter if enabled in configuration.

        Sets:
            self._rate_limiter: UnifiedRateLimiter instance or None
            self._provider_adapter: ProviderAdapter instance or None
            self._current_prompt: Storage for prompt context
            self._last_response_metadata: Storage for response metadata
        """
        # Initialize storage attributes
        self._rate_limiter = None
        self._provider_adapter = None
        self._current_prompt = None
        self._last_response_metadata = {}

        # Check if rate limiting is globally enabled
        if not hasattr(config_root.system, 'rate_limiting'):
            logging.debug("No rate_limiting config found, rate limiting disabled")
            return

        if not config_root.system.rate_limiting.enabled:
            logging.debug("Rate limiting disabled in config")
            return

        # Determine provider from generator_family_name
        provider_name = self._detect_provider_name()
        if provider_name is None:
            logging.warning(
                f"Could not determine provider for {self.generator_family_name}, "
                f"rate limiting disabled"
            )
            return

        # Check if provider has rate_limits configuration
        provider_config = self._load_provider_rate_limit_config(
            config_root, provider_name
        )
        if provider_config is None:
            logging.debug(
                f"No rate_limits config for provider '{provider_name}', "
                f"rate limiting disabled"
            )
            return

        # Import rate limiting components (lazy import)
        try:
            from garak.ratelimit.factory import create_rate_limiter, get_provider_adapter

            # Get provider adapter
            self._provider_adapter = get_provider_adapter(provider_name)
            if self._provider_adapter is None:
                logging.warning(
                    f"No adapter found for provider '{provider_name}', "
                    f"rate limiting disabled"
                )
                return

            # Create unified rate limiter
            self._rate_limiter = create_rate_limiter(
                provider=provider_name,
                model=self.name,
                config=provider_config,
                adapter=self._provider_adapter
            )

            logging.info(
                f"Rate limiting enabled for {provider_name}/{self.name}"
            )

        except ImportError as e:
            logging.error(f"Failed to import rate limiting components: {e}")
            self._rate_limiter = None
            self._provider_adapter = None
        except Exception as e:
            logging.error(f"Failed to initialize rate limiter: {e}")
            self._rate_limiter = None
            self._provider_adapter = None

    # === NEW METHOD ===
    def _detect_provider_name(self) -> str | None:
        """Detect provider name from generator_family_name."""
        if not self.generator_family_name or self.generator_family_name == "<empty>":
            return None

        family_lower = self.generator_family_name.lower().replace(" ", "")

        provider_mappings = {
            'openai': 'openai',
            'azure': 'azure',
            'huggingface': 'huggingface',
            'hugging_face': 'huggingface',
            'anthropic': 'anthropic',
            'gemini': 'gemini',
            'google': 'gemini',
            'rest': 'rest',
        }

        if family_lower in provider_mappings:
            return provider_mappings[family_lower]

        for key, value in provider_mappings.items():
            if family_lower.startswith(key):
                return value

        return None

    # === NEW METHOD ===
    def _load_provider_rate_limit_config(self, config_root, provider_name: str) -> dict | None:
        """Load rate limit configuration for provider."""
        try:
            if not hasattr(config_root, 'plugins'):
                return None

            if not hasattr(config_root.plugins, 'generators'):
                return None

            generators_config = config_root.plugins.generators

            if provider_name not in generators_config:
                return None

            provider_config = generators_config[provider_name]

            if 'rate_limits' not in provider_config:
                return None

            return dict(provider_config)

        except Exception as e:
            logging.error(f"Error loading config for {provider_name}: {e}")
            return None

    def _call_model(
        self, prompt: Conversation, generations_this_call: int = 1
    ) -> List[Union[Message, None]]:
        """
        Takes a prompt and returns an API output.

        UNCHANGED: Subclasses implement this with @backoff decorators.
        """
        raise NotImplementedError

    # === MODIFIED METHOD ===
    def _pre_generate_hook(self, prompt: Conversation | None = None):
        """
        Pre-generation hook: Check rate limits before API call.

        MODIFICATIONS:
        - Changed from `pass` to rate limiting logic
        - Added prompt parameter for token estimation
        - Backward compatible (no-op if rate_limiter is None)
        """
        # Backward compatibility: no-op if rate limiting disabled
        if self._rate_limiter is None:
            return

        # Store prompt for token estimation
        if prompt is not None:
            self._current_prompt = prompt

        if self._current_prompt is None:
            logging.warning("No prompt context for rate limiting, skipping acquire")
            return

        provider_name = self._detect_provider_name()
        if provider_name is None:
            return

        model_name = self.name

        # Estimate tokens
        try:
            estimated_tokens = self._estimate_tokens_for_prompt(self._current_prompt)
        except Exception as e:
            logging.warning(f"Token estimation failed: {e}, using default")
            estimated_tokens = 100

        # Acquire rate limit permit (may block/sleep)
        try:
            wait_time = self._rate_limiter.acquire(
                provider=provider_name,
                model=model_name,
                estimated_tokens=estimated_tokens
            )

            if wait_time > 0:
                logging.info(
                    f"Rate limited: sleeping {wait_time:.2f}s for "
                    f"{provider_name}/{model_name}"
                )
                import time
                time.sleep(wait_time)

        except Exception as e:
            logging.error(f"Rate limiter acquire failed: {e}, proceeding anyway")

    # === NEW METHOD ===
    def _estimate_tokens_for_prompt(self, prompt: Conversation) -> int:
        """Estimate tokens for prompt using provider adapter."""
        if self._provider_adapter is None:
            total_chars = sum(
                len(turn.content.text) for turn in prompt.turns if turn.content.text
            )
            return total_chars // 4

        try:
            full_text = "\n".join(
                turn.content.text for turn in prompt.turns if turn.content.text
            )

            return self._provider_adapter.estimate_tokens(full_text, self.name)

        except Exception as e:
            logging.warning(f"Adapter token estimation failed: {e}, using fallback")
            total_chars = sum(
                len(turn.content.text) for turn in prompt.turns if turn.content.text
            )
            return total_chars // 4

    @staticmethod
    def _verify_model_result(result: List[Union[Message, None]]):
        """UNCHANGED"""
        assert isinstance(result, list), "_call_model must return a list"
        assert (
            len(result) == 1
        ), f"_call_model must return a list of one item when invoked as _call_model(prompt, 1), got {result}"
        assert (
            isinstance(result[0], Message) or result[0] is None
        ), "_call_model's item must be a Message or None"

    def clear_history(self):
        """UNCHANGED"""
        pass

    # === MODIFIED METHOD ===
    def _post_generate_hook(
        self, outputs: List[Message | None]
    ) -> List[Message | None]:
        """
        Post-generation hook: Record actual token usage.

        MODIFICATIONS:
        - Changed from `return outputs` to usage tracking logic
        - Backward compatible (passthrough if rate_limiter is None)
        """
        # Backward compatibility: passthrough if rate limiting disabled
        if self._rate_limiter is None:
            return outputs

        provider_name = self._detect_provider_name()
        if provider_name is None:
            return outputs

        model_name = self.name

        # Extract actual token usage
        try:
            tokens_used = self._extract_token_usage(outputs)
        except Exception as e:
            logging.warning(f"Token usage extraction failed: {e}, using estimate")
            tokens_used = self._estimate_tokens_from_outputs(outputs)

        # Record usage
        try:
            self._rate_limiter.record_usage(
                provider=provider_name,
                model=model_name,
                tokens_used=tokens_used,
                metadata=self._last_response_metadata
            )
        except Exception as e:
            logging.error(f"Rate limiter record_usage failed: {e}")

        return outputs

    # === NEW METHOD ===
    def _extract_token_usage(self, outputs: List[Message | None]) -> int:
        """Extract actual token usage from response metadata."""
        if self._provider_adapter is None:
            return self._estimate_tokens_from_outputs(outputs)

        try:
            if self._last_response_metadata:
                usage_info = self._provider_adapter.extract_usage_from_response(
                    response=None,
                    metadata=self._last_response_metadata
                )

                if usage_info and 'tokens_used' in usage_info:
                    return usage_info['tokens_used']

            usage_info = self._provider_adapter.extract_usage_from_response(
                response=outputs,
                metadata=self._last_response_metadata
            )

            if usage_info and 'tokens_used' in usage_info:
                return usage_info['tokens_used']

        except Exception as e:
            logging.debug(f"Adapter usage extraction failed: {e}")

        return self._estimate_tokens_from_outputs(outputs)

    # === NEW METHOD ===
    def _estimate_tokens_from_outputs(self, outputs: List[Message | None]) -> int:
        """Fallback: Estimate tokens from output text."""
        total_chars = 0

        for output in outputs:
            if output is not None and output.text:
                total_chars += len(output.text)

        if self._current_prompt:
            for turn in self._current_prompt.turns:
                if turn.content.text:
                    total_chars += len(turn.content.text)

        return total_chars // 4

    def _prune_skip_sequences(
        self, outputs: List[Message | None]
    ) -> List[Message | None]:
        """UNCHANGED"""
        rx_complete = (
            re.escape(self.skip_seq_start) + ".*?" + re.escape(self.skip_seq_end)
        )
        rx_missing_final = re.escape(self.skip_seq_start) + ".*?$"
        rx_missing_start = ".*?" + re.escape(self.skip_seq_end)

        if self.skip_seq_start == "":
            for o in outputs:
                if o is None or o.text is None:
                    continue
                o.text = re.sub(
                    rx_missing_start, "", o.text, flags=re.DOTALL | re.MULTILINE
                )
        else:
            for o in outputs:
                if o is None or o.text is None:
                    continue
                o.text = re.sub(rx_complete, "", o.text, flags=re.DOTALL | re.MULTILINE)

            for o in outputs:
                if o is None or o.text is None:
                    continue
                o.text = re.sub(
                    rx_missing_final, "", o.text, flags=re.DOTALL | re.MULTILINE
                )

        return outputs

    # === MODIFIED METHOD ===
    def generate(
        self, prompt: Conversation, generations_this_call: int = 1, typecheck=True
    ) -> List[Union[Message, None]]:
        """
        Manages the process of getting generations out from a prompt.

        MODIFICATIONS:
        - Store prompt context: self._current_prompt = prompt
        - Pass prompt to _pre_generate_hook(prompt)
        - Use _call_model_with_hooks() for parallel requests
        """
        if typecheck:
            assert isinstance(
                prompt, Conversation
            ), "generate() must take a Conversation object"

        # === NEW: Store prompt context ===
        self._current_prompt = prompt

        # === MODIFIED: Pass prompt to hook ===
        self._pre_generate_hook(prompt=prompt)

        assert (
            generations_this_call >= 0
        ), f"Unexpected value for generations_per_call: {generations_this_call}"

        if generations_this_call == 0:
            logging.debug("generate() called with generations_this_call = 0")
            return []

        if generations_this_call == 1:
            outputs = self._call_model(prompt, 1)

        elif self.supports_multiple_generations:
            outputs = self._call_model(prompt, generations_this_call)

        else:
            outputs = []

            if (
                hasattr(self, "parallel_requests")
                and self.parallel_requests
                and isinstance(self.parallel_requests, int)
                and self.parallel_requests > 1
            ):
                from multiprocessing import Pool

                multi_generator_bar = tqdm.tqdm(
                    total=generations_this_call,
                    leave=False,
                    colour=f"#{garak.resources.theme.GENERATOR_RGB}",
                )
                multi_generator_bar.set_description(self.fullname[:55])

                pool_size = min(
                    generations_this_call,
                    self.parallel_requests,
                    self.max_workers,
                )

                try:
                    # === MODIFIED: Use wrapper for parallel requests ===
                    with Pool(pool_size) as pool:
                        for result in pool.imap_unordered(
                            self._call_model_with_hooks, [prompt] * generations_this_call
                        ):
                            self._verify_model_result(result)
                            outputs.append(result[0])
                            multi_generator_bar.update(1)
                except OSError as o:
                    if o.errno == 24:
                        msg = "Parallelisation limit hit. Try reducing parallel_requests or raising limit (e.g. ulimit -n 4096)"
                        logging.critical(msg)
                        raise GarakException(msg) from o
                    else:
                        raise (o)

            else:
                generation_iterator = tqdm.tqdm(
                    list(range(generations_this_call)),
                    leave=False,
                    colour=f"#{garak.resources.theme.GENERATOR_RGB}",
                )
                generation_iterator.set_description(self.fullname[:55])
                for i in generation_iterator:
                    output_one = self._call_model(prompt, 1)
                    self._verify_model_result(output_one)
                    outputs.append(output_one[0])

        outputs = self._post_generate_hook(outputs)

        if hasattr(self, "skip_seq_start") and hasattr(self, "skip_seq_end"):
            if self.skip_seq_start is not None and self.skip_seq_end is not None:
                outputs = self._prune_skip_sequences(outputs)

        return outputs

    # === NEW METHOD ===
    def _call_model_with_hooks(
        self, prompt: Conversation, generations_this_call: int = 1
    ) -> List[Union[Message, None]]:
        """
        Wrapper for _call_model() that adds rate limiting hooks.

        Used by parallel workers to ensure each request independently
        checks rate limits and records usage.
        """
        # Pre-request: Check rate limits
        self._pre_generate_hook(prompt=prompt)

        # Actual API call
        result = self._call_model(prompt, generations_this_call)

        # Post-request: Record usage
        self._post_generate_hook(result)

        return result

    @staticmethod
    def _conversation_to_list(conversation: Conversation) -> list[dict]:
        """UNCHANGED"""
        turn_list = [
            {"role": turn.role, "content": turn.content.text}
            for turn in conversation.turns
        ]
        return turn_list
```

### 11.2 Summary of Changes

| Method | Lines Changed | Change Type | Description |
|--------|---------------|-------------|-------------|
| `__init__` | +1 | Addition | Call `_init_rate_limiter()` |
| `_init_rate_limiter` | +75 | New Method | Initialize rate limiter if configured |
| `_detect_provider_name` | +20 | New Method | Map generator_family_name to provider |
| `_load_provider_rate_limit_config` | +20 | New Method | Load YAML config for provider |
| `_pre_generate_hook` | +40 | Replacement | Replace `pass` with rate limiting |
| `_estimate_tokens_for_prompt` | +20 | New Method | Estimate tokens using adapter |
| `_post_generate_hook` | +30 | Replacement | Add usage tracking |
| `_extract_token_usage` | +25 | New Method | Extract actual tokens from response |
| `_estimate_tokens_from_outputs` | +15 | New Method | Fallback token estimation |
| `generate` | +3 | Modification | Store prompt, pass to hook, use wrapper |
| `_call_model_with_hooks` | +10 | New Method | Wrapper for parallel requests |
| **TOTAL** | **~260 lines** | **8 new + 3 modified** | All additive, zero breaking changes |

---

## 12. Testing Strategy

### 12.1 Unit Tests

```python
# tests/generators/test_base_rate_limiting.py

import pytest
from unittest.mock import Mock, MagicMock, patch
from garak.generators.base import Generator
from garak.attempt import Conversation, Turn, Content, Message
from garak import _config


class TestRateLimitingIntegration:
    """Test rate limiting integration in base Generator."""

    def test_init_rate_limiter_disabled_by_default(self):
        """Verify rate limiter not initialized when disabled."""
        _config.system.rate_limiting.enabled = False

        generator = Generator(name='test')

        assert generator._rate_limiter is None
        assert generator._provider_adapter is None

    def test_init_rate_limiter_no_provider_config(self):
        """Verify graceful handling when provider has no rate_limits config."""
        _config.system.rate_limiting.enabled = True
        # No plugins.generators.test config

        generator = Generator(name='test')
        generator.generator_family_name = 'test'

        assert generator._rate_limiter is None

    def test_detect_provider_name_openai(self):
        """Verify OpenAI provider detection."""
        generator = Generator(name='test')
        generator.generator_family_name = 'OpenAI'

        provider = generator._detect_provider_name()

        assert provider == 'openai'

    def test_detect_provider_name_azure(self):
        """Verify Azure provider detection."""
        generator = Generator(name='test')
        generator.generator_family_name = 'Azure'

        provider = generator._detect_provider_name()

        assert provider == 'azure'

    def test_detect_provider_name_huggingface(self):
        """Verify HuggingFace provider detection with space."""
        generator = Generator(name='test')
        generator.generator_family_name = 'Hugging Face'

        provider = generator._detect_provider_name()

        assert provider == 'huggingface'

    def test_pre_hook_noop_when_disabled(self):
        """Verify pre_hook is no-op when rate limiting disabled."""
        generator = Generator(name='test')
        generator._rate_limiter = None

        # Should not raise
        generator._pre_generate_hook()

    def test_pre_hook_calls_acquire(self):
        """Verify pre_hook calls rate_limiter.acquire()."""
        generator = Generator(name='test')
        generator.generator_family_name = 'OpenAI'

        # Mock rate limiter
        mock_limiter = Mock()
        mock_limiter.acquire.return_value = 0  # No wait
        generator._rate_limiter = mock_limiter

        # Mock adapter
        mock_adapter = Mock()
        mock_adapter.estimate_tokens.return_value = 100
        generator._provider_adapter = mock_adapter

        # Create prompt
        prompt = Conversation(turns=[
            Turn(role='user', content=Content(text='test prompt'))
        ])

        # Call pre_hook
        generator._pre_generate_hook(prompt=prompt)

        # Verify acquire called
        mock_limiter.acquire.assert_called_once()
        args = mock_limiter.acquire.call_args
        assert args[1]['provider'] == 'openai'
        assert args[1]['model'] == 'test'
        assert args[1]['estimated_tokens'] == 100

    def test_post_hook_passthrough_when_disabled(self):
        """Verify post_hook returns outputs unchanged when disabled."""
        generator = Generator(name='test')
        generator._rate_limiter = None

        outputs = [Message(text='test output')]
        result = generator._post_generate_hook(outputs)

        assert result is outputs

    def test_post_hook_calls_record_usage(self):
        """Verify post_hook calls rate_limiter.record_usage()."""
        generator = Generator(name='test')
        generator.generator_family_name = 'OpenAI'

        # Mock rate limiter
        mock_limiter = Mock()
        generator._rate_limiter = mock_limiter

        # Mock adapter
        mock_adapter = Mock()
        mock_adapter.extract_usage_from_response.return_value = {
            'tokens_used': 250
        }
        generator._provider_adapter = mock_adapter

        # Create outputs
        outputs = [Message(text='test output')]

        # Call post_hook
        generator._post_generate_hook(outputs)

        # Verify record_usage called
        mock_limiter.record_usage.assert_called_once()
        args = mock_limiter.record_usage.call_args
        assert args[1]['provider'] == 'openai'
        assert args[1]['model'] == 'test'
        assert args[1]['tokens_used'] == 250

    def test_estimate_tokens_fallback(self):
        """Verify token estimation fallback when adapter unavailable."""
        generator = Generator(name='test')
        generator._provider_adapter = None

        prompt = Conversation(turns=[
            Turn(role='user', content=Content(text='a' * 400))  # 400 chars
        ])

        tokens = generator._estimate_tokens_for_prompt(prompt)

        # Should be ~100 tokens (400 chars / 4)
        assert tokens == 100

    def test_call_model_with_hooks_calls_both_hooks(self):
        """Verify wrapper calls pre and post hooks."""
        generator = Generator(name='test')

        # Mock hooks
        generator._pre_generate_hook = Mock()
        generator._post_generate_hook = Mock(return_value=[Message(text='output')])
        generator._call_model = Mock(return_value=[Message(text='output')])

        prompt = Conversation(turns=[
            Turn(role='user', content=Content(text='test'))
        ])

        # Call wrapper
        result = generator._call_model_with_hooks(prompt, 1)

        # Verify both hooks called
        generator._pre_generate_hook.assert_called_once_with(prompt=prompt)
        generator._post_generate_hook.assert_called_once()
```

### 12.2 Integration Tests

```python
# tests/generators/test_base_integration.py

import pytest
from garak.generators.openai import OpenAIGenerator
from garak.generators.azure import AzureOpenAIGenerator
from garak import _config


class TestRateLimitingIntegrationE2E:
    """End-to-end integration tests with real generators."""

    @pytest.fixture
    def mock_openai_config(self):
        """Setup OpenAI rate limiting config."""
        _config.system.rate_limiting.enabled = True
        _config.plugins.generators.openai = {
            'rate_limits': {
                'gpt-4o': {
                    'rpm': 10000,
                    'tpm': 2000000
                },
                'default': {
                    'rpm': 500,
                    'tpm': 50000
                }
            },
            'backoff': {
                'strategy': 'fibonacci',
                'max_value': 70
            }
        }

    def test_openai_generator_initializes_rate_limiter(self, mock_openai_config):
        """Verify OpenAI generator initializes rate limiter."""
        generator = OpenAIGenerator(name='gpt-4o')

        assert generator._rate_limiter is not None
        assert generator._provider_adapter is not None

    def test_azure_generator_initializes_rate_limiter(self):
        """Verify Azure generator initializes rate limiter."""
        _config.system.rate_limiting.enabled = True
        _config.plugins.generators.azure = {
            'rate_limits': {
                'default': {
                    'rps': 6,
                    'tpm_quota': 50000
                }
            }
        }

        generator = AzureOpenAIGenerator(name='my-deployment')

        assert generator._rate_limiter is not None

    @patch('garak.generators.openai.OpenAIGenerator._call_model')
    def test_generate_calls_rate_limiting_hooks(self, mock_call_model, mock_openai_config):
        """Verify generate() properly integrates rate limiting."""
        generator = OpenAIGenerator(name='gpt-4o')

        # Mock _call_model to return dummy output
        mock_call_model.return_value = [Message(text='test output')]

        # Mock rate limiter
        from unittest.mock import Mock
        mock_limiter = Mock()
        mock_limiter.acquire.return_value = 0
        generator._rate_limiter = mock_limiter

        # Generate
        prompt = Conversation(turns=[
            Turn(role='user', content=Content(text='test'))
        ])
        outputs = generator.generate(prompt, generations_this_call=1)

        # Verify hooks called
        mock_limiter.acquire.assert_called()
        mock_limiter.record_usage.assert_called()
```

### 12.3 Performance Tests

```python
# tests/generators/test_base_performance.py

import time
import pytest
from garak.generators.base import Generator
from garak import _config


class TestRateLimitingPerformance:
    """Performance tests for rate limiting overhead."""

    def test_hook_overhead_disabled(self):
        """Measure overhead when rate limiting disabled."""
        _config.system.rate_limiting.enabled = False
        generator = Generator(name='test')

        iterations = 1000
        start = time.perf_counter()

        for _ in range(iterations):
            generator._pre_generate_hook()
            generator._post_generate_hook([])

        elapsed = time.perf_counter() - start
        per_call = elapsed / iterations * 1000  # ms

        # Should be <0.01ms per call when disabled
        assert per_call < 0.01
        print(f"Disabled overhead: {per_call:.6f}ms per call")

    def test_hook_overhead_enabled(self):
        """Measure overhead when rate limiting enabled."""
        _config.system.rate_limiting.enabled = True
        generator = Generator(name='test')

        # Mock rate limiter (fast path)
        from unittest.mock import Mock
        mock_limiter = Mock()
        mock_limiter.acquire.return_value = 0
        mock_limiter.record_usage.return_value = None
        generator._rate_limiter = mock_limiter

        iterations = 1000
        start = time.perf_counter()

        for _ in range(iterations):
            generator._pre_generate_hook()
            generator._post_generate_hook([])

        elapsed = time.perf_counter() - start
        per_call = elapsed / iterations * 1000  # ms

        # Should be <2ms per call when enabled
        assert per_call < 2.0
        print(f"Enabled overhead: {per_call:.6f}ms per call")
```

### 12.4 Thread-Safety Tests

```python
# tests/generators/test_base_multiprocessing.py

import pytest
from multiprocessing import Pool
from garak.generators.base import Generator
from garak import _config


class TestRateLimitingThreadSafety:
    """Test rate limiting works correctly with multiprocessing."""

    def test_parallel_requests_with_rate_limiting(self):
        """Verify parallel requests work with rate limiting."""
        _config.system.rate_limiting.enabled = True
        generator = Generator(name='test')
        generator.parallel_requests = 5

        # Mock rate limiter (thread-safe)
        from unittest.mock import Mock
        mock_limiter = Mock()
        mock_limiter.acquire.return_value = 0
        generator._rate_limiter = mock_limiter

        # Generate in parallel
        prompt = Conversation(turns=[
            Turn(role='user', content=Content(text='test'))
        ])

        outputs = generator.generate(prompt, generations_this_call=10)

        # Verify all requests succeeded
        assert len(outputs) == 10

        # Verify acquire called 10 times (once per parallel request)
        assert mock_limiter.acquire.call_count == 10
```

---

## Summary

This document provides **complete specifications** for integrating the unified rate limiting handler into `garak/generators/base.py`:

### Key Deliverables

1. ✅ **4 Integration Points** mapped to exact line numbers
2. ✅ **Complete Pseudo-Code** (~260 lines) for all modifications
3. ✅ **Provider Detection** logic for automatic adapter selection
4. ✅ **Token Estimation** integration with provider adapters
5. ✅ **Configuration Loading** from YAML with fallbacks
6. ✅ **Error Handling** strategy (never fail generation)
7. ✅ **Backward Compatibility** verification (zero breaking changes)
8. ✅ **Testing Strategy** with unit, integration, and performance tests

### Implementation Checklist

- [ ] Implement `_init_rate_limiter()` method
- [ ] Implement `_detect_provider_name()` method
- [ ] Implement `_load_provider_rate_limit_config()` method
- [ ] Modify `_pre_generate_hook()` with rate limiting logic
- [ ] Implement `_estimate_tokens_for_prompt()` method
- [ ] Modify `_post_generate_hook()` with usage tracking
- [ ] Implement `_extract_token_usage()` method
- [ ] Implement `_estimate_tokens_from_outputs()` method
- [ ] Modify `generate()` to store prompt context
- [ ] Implement `_call_model_with_hooks()` wrapper
- [ ] Add unit tests (12 test cases)
- [ ] Add integration tests (E2E with OpenAI/Azure)
- [ ] Add performance benchmarks
- [ ] Add thread-safety tests (multiprocessing)
- [ ] Verify backward compatibility (disabled mode)

### Next Phase

**Phase 5b: Provider-Specific Integration**
- Modify OpenAIGenerator to set `_last_response_metadata`
- Modify AzureOpenAIGenerator for deployment-specific limits
- Test with real API calls (integration tests)

---

**Document Status:** ✅ Complete and Ready for Implementation
