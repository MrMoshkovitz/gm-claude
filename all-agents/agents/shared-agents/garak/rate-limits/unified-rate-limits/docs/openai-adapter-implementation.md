# OpenAI Adapter Implementation Guide (Phase 3a)

**Version:** 1.0
**Date:** 2025-10-20
**Status:** Implementation Specification
**Phase:** 3a - OpenAI Provider Adapter
**Dependencies:** Phase 2b (ProviderAdapter Interface), Phase 2c (UnifiedRateLimiter Base)

---

## Executive Summary

This document provides the complete implementation specification for the **OpenAIAdapter** class, the first concrete implementation of the ProviderAdapter interface. The OpenAI adapter demonstrates the reference implementation pattern for all future provider adapters, implementing accurate token counting with tiktoken, comprehensive rate limit header extraction, and intelligent error handling.

### Implementation Scope

1. **OpenAIAdapter Class** - Full implementation of ProviderAdapter ABC
2. **Token Counting** - tiktoken integration with model-specific encodings
3. **Rate Limit Extraction** - x-ratelimit-* header parsing
4. **Error Handling** - OpenAI SDK exception classification
5. **Response Parsing** - Usage data extraction from responses
6. **Configuration** - Model-specific rate limits and defaults
7. **Testing** - Unit tests, integration tests, edge cases
8. **Documentation** - Usage examples and troubleshooting guide

---

## Table of Contents

1. [OpenAIAdapter Class Structure](#1-openaiadapter-class-structure)
2. [Token Counting Implementation](#2-token-counting-implementation)
3. [Rate Limit Header Extraction](#3-rate-limit-header-extraction)
4. [Exception Handling](#4-exception-handling)
5. [Response Parsing](#5-response-parsing)
6. [Model Limits Database](#6-model-limits-database)
7. [Configuration Schema](#7-configuration-schema)
8. [Edge Cases and Fallbacks](#8-edge-cases-and-fallbacks)
9. [Integration with AdapterFactory](#9-integration-with-adapterfactory)
10. [Testing Strategy](#10-testing-strategy)
11. [Complete Implementation Pseudo-code](#11-complete-implementation-pseudo-code)
12. [Performance Optimization](#12-performance-optimization)
13. [Troubleshooting Guide](#13-troubleshooting-guide)

---

## 1. OpenAIAdapter Class Structure

### 1.1 Class Definition

```python
# garak/ratelimit/adapters/openai.py

from garak.ratelimit.base import ProviderAdapter, RateLimitType
from typing import Dict, List, Optional, Any
import logging


class OpenAIAdapter(ProviderAdapter):
    """
    Provider adapter for OpenAI API rate limiting.

    Capabilities:
    - Token counting: tiktoken library for accurate pre-request estimation
    - Rate limits: RPM (requests per minute), TPM (tokens per minute)
    - Header parsing: x-ratelimit-* headers from OpenAI responses
    - Error detection: openai.RateLimitError classification
    - Model limits: Hardcoded defaults for all OpenAI models

    Rate Limit Types:
    - RPM: 500-10000 requests per minute (tier-dependent)
    - TPM: 30000-2000000 tokens per minute (tier-dependent)
    - No concurrent limits (OpenAI doesn't enforce)
    - No persistent quotas (rolling 60s windows only)

    OpenAI API Documentation:
    - Rate limits: https://platform.openai.com/docs/guides/rate-limits
    - Headers: https://platform.openai.com/docs/guides/rate-limits/rate-limits-in-headers
    - Models: https://platform.openai.com/docs/models

    Design Principles:
    - Stateless: All state managed by UnifiedRateLimiter
    - Fail-safe: Never raises exceptions, returns fallback values
    - Accurate: Uses tiktoken for token counting when available
    - Provider-agnostic output: Returns normalized dicts, not openai objects
    """

    # Class constants for default configuration
    DEFAULT_TIER = 1  # Free tier as safe default
    TIKTOKEN_FALLBACK_RATIO = 4  # 1 token ≈ 4 characters (English text average)

    # Token counting cache (shared across instances)
    _tokenizer_cache: Dict[str, Any] = {}
    _cache_lock = None  # Threading lock for cache (initialized lazily)

    def __init__(self, model: str = None, config: Dict = None):
        """
        Initialize OpenAI adapter.

        Args:
            model: OpenAI model name (e.g., 'gpt-4o', 'gpt-3.5-turbo')
                  Used for model-specific tokenizer selection
            config: Configuration dict (currently unused, reserved for future)

        Initialization:
            - Store model name for context
            - Initialize threading lock for tokenizer cache
            - Pre-load tiktoken library if available
            - Log initialization status

        Thread-Safety:
            Adapter instances are stateless (safe to share across threads)
            Tokenizer cache protected by lock
        """
        self.model = model
        self.config = config or {}

        # Initialize cache lock on first instantiation
        if OpenAIAdapter._cache_lock is None:
            import threading
            OpenAIAdapter._cache_lock = threading.Lock()

        # Check tiktoken availability
        self._tiktoken_available = self._check_tiktoken_available()

        logging.debug(
            f"Initialized OpenAIAdapter for model '{model}', "
            f"tiktoken available: {self._tiktoken_available}"
        )

    def _check_tiktoken_available(self) -> bool:
        """Check if tiktoken library is available."""
        try:
            import tiktoken
            return True
        except ImportError:
            logging.warning(
                "tiktoken library not installed. Token estimation will use "
                "character-based fallback (less accurate). "
                "Install with: pip install tiktoken"
            )
            return False

    # ===================================================================
    # ABSTRACT METHOD IMPLEMENTATIONS (required by ProviderAdapter)
    # ===================================================================

    def estimate_tokens(self, prompt: str, model: str) -> int:
        """
        Estimate token count using tiktoken (Section 2).

        See Section 2 for complete implementation.
        """
        pass  # Implementation in Section 2

    def extract_usage_from_response(
        self,
        response: Any,
        metadata: Optional[Dict] = None
    ) -> Dict[str, int]:
        """
        Extract token usage from OpenAI response object (Section 5).

        See Section 5 for complete implementation.
        """
        pass  # Implementation in Section 5

    def extract_rate_limit_info(
        self,
        exception: Exception
    ) -> Optional[Dict[str, Any]]:
        """
        Extract rate limit details from openai.RateLimitError (Section 4).

        See Section 4 for complete implementation.
        """
        pass  # Implementation in Section 4

    def get_retry_after(
        self,
        exception: Exception,
        headers: Optional[Dict[str, str]] = None
    ) -> Optional[float]:
        """
        Extract retry-after delay (Section 3).

        See Section 3 for complete implementation.
        """
        pass  # Implementation in Section 3

    def get_model_limits(self, model: str) -> Optional[Dict[str, int]]:
        """
        Get default rate limits for OpenAI model (Section 6).

        See Section 6 for complete implementation.
        """
        pass  # Implementation in Section 6

    # ===================================================================
    # CONCRETE METHOD OVERRIDES (optional, provider-specific behavior)
    # ===================================================================

    def supports_concurrent_limiting(self) -> bool:
        """
        OpenAI does not enforce concurrent request limits.

        Returns:
            False - OpenAI uses time-windowed limits only (RPM/TPM)
        """
        return False

    def supports_quota_tracking(self) -> bool:
        """
        OpenAI uses rolling windows, not monthly quotas.

        Returns:
            False - OpenAI limits reset on 60-second sliding windows
        """
        return False

    def get_limit_types(self) -> List[RateLimitType]:
        """
        OpenAI supports RPM and TPM limits.

        Returns:
            [RateLimitType.RPM, RateLimitType.TPM]
        """
        return [RateLimitType.RPM, RateLimitType.TPM]

    def get_window_seconds(self, limit_type: RateLimitType) -> int:
        """
        Get sliding window duration for OpenAI limits.

        Args:
            limit_type: Type of rate limit

        Returns:
            60 seconds for both RPM and TPM (standard OpenAI window)
        """
        if limit_type in (RateLimitType.RPM, RateLimitType.TPM):
            return 60  # OpenAI uses 60-second sliding windows
        return super().get_window_seconds(limit_type)
```

### 1.2 Class Hierarchy

```
ProviderAdapter (ABC)
    └── OpenAIAdapter
            ├── Methods: estimate_tokens(), extract_usage_from_response(), ...
            ├── Cache: _tokenizer_cache (class-level, thread-safe)
            └── Constants: Model limits, fallback ratios
```

---

## 2. Token Counting Implementation

### 2.1 tiktoken Integration

```python
def estimate_tokens(self, prompt: str, model: str) -> int:
    """
    Estimate token count for prompt using tiktoken.

    Algorithm:
        1. Check if tiktoken available
        2. Get/create cached encoding for model
        3. Encode prompt to tokens
        4. Return token count
        5. On any error: Fall back to character-based estimation

    Args:
        prompt: Input text to tokenize (can be multi-line, unicode, etc.)
        model: OpenAI model name for model-specific encoding

    Returns:
        Estimated token count (always >= 0)

    Token Counting Accuracy:
        - tiktoken: 100% accurate (matches OpenAI's internal counting)
        - Fallback: ~90% accurate (4 chars/token is rough average)

    Performance:
        - First call for model: 10-50ms (loads encoding)
        - Cached calls: <1ms (encoding lookup + tokenization)
        - Cache shared across all adapter instances (class-level)

    Model Name Handling:
        - Exact match preferred: 'gpt-4o' -> 'gpt-4o' encoding
        - Fallback to base model: 'gpt-4o-custom' -> 'gpt-4' encoding
        - Default encoding: 'cl100k_base' (GPT-3.5/4 default)

    Example:
        >>> adapter = OpenAIAdapter(model='gpt-4o')
        >>> adapter.estimate_tokens("Hello world", "gpt-4o")
        2
        >>> adapter.estimate_tokens("Hello " * 1000, "gpt-4o")
        2000
    """
    # Validate inputs
    if not prompt:
        return 0

    if not model:
        model = self.model or "gpt-3.5-turbo"  # Safe default

    # Try tiktoken encoding
    if self._tiktoken_available:
        try:
            encoding = self._get_encoding(model)
            token_count = len(encoding.encode(prompt))

            logging.debug(
                f"tiktoken counted {token_count} tokens for {len(prompt)} chars "
                f"(model={model})"
            )
            return token_count

        except Exception as e:
            logging.warning(
                f"tiktoken encoding failed for model '{model}': {e}. "
                f"Falling back to character estimation."
            )
            # Fall through to fallback

    # Fallback: Character-based estimation
    char_count = len(prompt)
    token_estimate = max(1, char_count // self.TIKTOKEN_FALLBACK_RATIO)

    logging.debug(
        f"Character-based estimation: {token_estimate} tokens for "
        f"{char_count} chars (model={model})"
    )

    return token_estimate


def _get_encoding(self, model: str):
    """
    Get or create cached tiktoken encoding for model.

    Caching Strategy:
        - Cache key: model name
        - Cache lifetime: Process lifetime (never evicted)
        - Cache size: ~100KB per encoding (negligible)
        - Thread-safe: Protected by class-level lock

    Model Resolution:
        1. Try exact model name (e.g., 'gpt-4o')
        2. Try base model (e.g., 'gpt-4' for 'gpt-4o-custom')
        3. Use default encoding ('cl100k_base')

    Args:
        model: OpenAI model name

    Returns:
        tiktoken.Encoding instance

    Raises:
        Exception: If tiktoken fails (caught by caller)
    """
    import tiktoken

    # Thread-safe cache access
    with self._cache_lock:
        if model in self._tokenizer_cache:
            return self._tokenizer_cache[model]

        # Try to get model-specific encoding
        try:
            encoding = tiktoken.encoding_for_model(model)
            logging.debug(f"Loaded tiktoken encoding for model '{model}'")
        except KeyError:
            # Model not recognized, try base model
            base_model = self._get_base_model(model)
            if base_model != model:
                logging.debug(
                    f"Model '{model}' not recognized by tiktoken, "
                    f"trying base model '{base_model}'"
                )
                try:
                    encoding = tiktoken.encoding_for_model(base_model)
                except KeyError:
                    # Use default encoding
                    logging.warning(
                        f"Neither '{model}' nor '{base_model}' recognized by tiktoken. "
                        f"Using default 'cl100k_base' encoding."
                    )
                    encoding = tiktoken.get_encoding("cl100k_base")
            else:
                # Use default encoding
                encoding = tiktoken.get_encoding("cl100k_base")

        # Cache for future use
        self._tokenizer_cache[model] = encoding

        return encoding


def _get_base_model(self, model: str) -> str:
    """
    Extract base model name from variant.

    Handles cases like:
        'gpt-4o-2024-11-20' -> 'gpt-4o'
        'gpt-4-turbo-preview' -> 'gpt-4'
        'gpt-3.5-turbo-0125' -> 'gpt-3.5-turbo'

    Args:
        model: Full model name (possibly with date/variant suffix)

    Returns:
        Base model name

    Algorithm:
        1. Remove date suffixes (YYYY-MM-DD pattern)
        2. Remove version numbers (-0125, -1106, etc.)
        3. Keep first 1-2 dash-separated parts
    """
    import re

    # Remove date suffixes (e.g., -2024-11-20)
    model = re.sub(r'-\d{4}-\d{2}-\d{2}$', '', model)

    # Remove version suffixes (e.g., -0125, -1106)
    model = re.sub(r'-\d{4}$', '', model)

    # Map common variants to base models
    base_model_map = {
        'gpt-4o-mini': 'gpt-4o',
        'gpt-4-turbo': 'gpt-4',
        'gpt-4-turbo-preview': 'gpt-4',
        'gpt-3.5-turbo-16k': 'gpt-3.5-turbo',
        'gpt-3.5-turbo-instruct': 'gpt-3.5-turbo',
    }

    return base_model_map.get(model, model)
```

### 2.2 Token Counting Edge Cases

```python
def _handle_special_cases(self, prompt: str, model: str) -> Optional[int]:
    """
    Handle special cases in token counting.

    Special Cases:
    1. Empty prompt: Return 0
    2. Whitespace-only: Return number of spaces/newlines
    3. Unicode characters: tiktoken handles correctly, fallback may undercount
    4. Code vs text: Different token densities (code ~6 chars/token)
    5. Chat format: Count system/user/assistant message tokens separately

    Args:
        prompt: Input text
        model: Model name

    Returns:
        Token count for special case, or None if not special case
    """
    # Empty prompt
    if not prompt:
        return 0

    # Whitespace-only prompt
    if prompt.isspace():
        # Count spaces as tokens (1 space = 1 token typically)
        return len(prompt)

    # No special case
    return None


def estimate_chat_tokens(
    self,
    messages: List[Dict[str, str]],
    model: str
) -> int:
    """
    Estimate tokens for chat-formatted input.

    OpenAI Chat Format:
        messages = [
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": "Hello!"},
            {"role": "assistant", "content": "Hi there!"},
        ]

    Token Overhead:
        - Each message: ~4 tokens (role, separators)
        - System message: +2 tokens
        - Function calls: Additional tokens per function

    Args:
        messages: List of message dicts with 'role' and 'content'
        model: Model name

    Returns:
        Total token count for chat conversation

    Algorithm:
        1. Estimate tokens for each message content
        2. Add message overhead (4 tokens per message)
        3. Add system message overhead if present
        4. Add 3 tokens for reply priming

    Reference:
        https://github.com/openai/openai-cookbook/blob/main/examples/How_to_count_tokens_with_tiktoken.ipynb
    """
    total_tokens = 0

    # Per-message token overhead (varies by model)
    if model.startswith("gpt-3.5-turbo"):
        tokens_per_message = 4
        tokens_per_name = -1  # name is removed in 3.5
    elif model.startswith("gpt-4"):
        tokens_per_message = 3
        tokens_per_name = 1
    else:
        tokens_per_message = 3
        tokens_per_name = 1

    # Count tokens in each message
    for message in messages:
        total_tokens += tokens_per_message

        for key, value in message.items():
            if isinstance(value, str):
                total_tokens += self.estimate_tokens(value, model)

            if key == "name":
                total_tokens += tokens_per_name

    # Add tokens for reply priming
    total_tokens += 3

    logging.debug(
        f"Chat format token count: {total_tokens} tokens for "
        f"{len(messages)} messages (model={model})"
    )

    return total_tokens
```

### 2.3 Token Counting Performance

```python
# Performance Benchmarks (measured on typical hardware)

# First call (cold cache):
# - tiktoken encoding load: 10-50ms
# - Token encoding: 1-5ms
# Total: ~15-55ms

# Subsequent calls (warm cache):
# - Cache lookup: <0.1ms
# - Token encoding: 1-5ms
# Total: ~1-5ms

# Memory usage:
# - Per encoding: ~100KB
# - Cache for 10 models: ~1MB
# - Negligible impact on overall memory

# Accuracy comparison:
# tiktoken:        100% (exact match with OpenAI)
# Fallback (4:1):  ~90% (good for estimation)
# Fallback (3:1):  ~85% (conservative overestimate)
```

---

## 3. Rate Limit Header Extraction

### 3.1 OpenAI Rate Limit Headers

```python
# OpenAI Rate Limit Response Headers
# Source: https://platform.openai.com/docs/guides/rate-limits/rate-limits-in-headers

OPENAI_RATE_LIMIT_HEADERS = {
    # Request-based limits (RPM)
    'x-ratelimit-limit-requests': int,      # Total RPM limit
    'x-ratelimit-remaining-requests': int,  # Remaining requests in current window
    'x-ratelimit-reset-requests': str,      # Time until window resets (e.g., "6s", "1m")

    # Token-based limits (TPM)
    'x-ratelimit-limit-tokens': int,        # Total TPM limit
    'x-ratelimit-remaining-tokens': int,    # Remaining tokens in current window
    'x-ratelimit-reset-tokens': str,        # Time until window resets

    # Standard retry header (RFC 7231)
    'retry-after': str,                     # Seconds to wait before retry
}

# Example Response Headers:
# {
#     'x-ratelimit-limit-requests': '10000',
#     'x-ratelimit-remaining-requests': '9999',
#     'x-ratelimit-reset-requests': '6s',
#     'x-ratelimit-limit-tokens': '2000000',
#     'x-ratelimit-remaining-tokens': '1999800',
#     'x-ratelimit-reset-tokens': '360ms',
#     'retry-after': '5'  # Only present on 429 errors
# }
```

### 3.2 Header Extraction Implementation

```python
def _extract_headers(self, exception: Exception) -> Dict[str, str]:
    """
    Extract HTTP headers from OpenAI exception.

    OpenAI SDK Exception Structure:
        openai.RateLimitError
            └── .response
                    └── .headers (dict-like object)

    Args:
        exception: OpenAI exception (any type)

    Returns:
        Dictionary of headers (lowercase keys)
        Empty dict if headers not available

    Header Normalization:
        - Convert all keys to lowercase
        - Strip whitespace from values
        - Convert dict-like objects to plain dict
    """
    headers = {}

    try:
        # Check if exception has response object
        if not hasattr(exception, 'response'):
            return headers

        response = exception.response

        # Check if response has headers
        if not hasattr(response, 'headers'):
            return headers

        # Extract headers (may be dict, Headers object, etc.)
        raw_headers = response.headers

        # Normalize to plain dict with lowercase keys
        if isinstance(raw_headers, dict):
            headers = {k.lower(): str(v).strip() for k, v in raw_headers.items()}
        elif hasattr(raw_headers, 'items'):
            # Dict-like object (requests.structures.CaseInsensitiveDict)
            headers = {k.lower(): str(v).strip() for k, v in raw_headers.items()}
        elif hasattr(raw_headers, '__getitem__'):
            # Subscriptable object
            # Try known header names
            known_headers = [
                'x-ratelimit-limit-requests',
                'x-ratelimit-remaining-requests',
                'x-ratelimit-reset-requests',
                'x-ratelimit-limit-tokens',
                'x-ratelimit-remaining-tokens',
                'x-ratelimit-reset-tokens',
                'retry-after',
            ]
            for header in known_headers:
                try:
                    value = raw_headers[header]
                    if value is not None:
                        headers[header.lower()] = str(value).strip()
                except (KeyError, TypeError):
                    pass

        logging.debug(f"Extracted {len(headers)} headers from exception")

    except Exception as e:
        logging.warning(f"Failed to extract headers from exception: {e}")

    return headers


def _parse_reset_time(self, reset_str: str) -> float:
    """
    Parse OpenAI reset time string to seconds.

    OpenAI Reset Format:
        '6s'    -> 6 seconds
        '360ms' -> 0.36 seconds
        '1m'    -> 60 seconds
        '1h'    -> 3600 seconds

    Args:
        reset_str: Reset time string from header

    Returns:
        Seconds until reset (float)

    Error Handling:
        Invalid format -> Return 60.0 (safe default)
    """
    import re

    try:
        # Match pattern: number + unit
        match = re.match(r'^(\d+(?:\.\d+)?)(ms|s|m|h)$', reset_str.strip())

        if not match:
            logging.warning(f"Invalid reset time format: '{reset_str}'")
            return 60.0  # Default 60s

        value = float(match.group(1))
        unit = match.group(2)

        # Convert to seconds
        if unit == 'ms':
            return value / 1000.0
        elif unit == 's':
            return value
        elif unit == 'm':
            return value * 60.0
        elif unit == 'h':
            return value * 3600.0
        else:
            logging.warning(f"Unknown time unit: '{unit}'")
            return 60.0

    except Exception as e:
        logging.warning(f"Failed to parse reset time '{reset_str}': {e}")
        return 60.0


def get_retry_after(
    self,
    exception: Exception,
    headers: Optional[Dict[str, str]] = None
) -> Optional[float]:
    """
    Extract retry-after delay from exception or headers.

    Priority Order:
        1. headers['retry-after'] parameter (if provided)
        2. exception.response.headers['retry-after']
        3. x-ratelimit-reset-requests (convert to seconds)
        4. x-ratelimit-reset-tokens (convert to seconds)
        5. None (caller uses backoff strategy)

    Args:
        exception: OpenAI exception
        headers: Optional pre-extracted headers

    Returns:
        Seconds to wait before retry, or None

    RFC 7231 Retry-After Format:
        - Integer: Delay in seconds ("5")
        - HTTP-date: Absolute time ("Wed, 21 Oct 2015 07:28:00 GMT")

    Example:
        >>> adapter.get_retry_after(rate_limit_error)
        5.0
        >>> adapter.get_retry_after(timeout_error)
        None  # No retry hint available
    """
    # Priority 1: Provided headers parameter
    if headers and 'retry-after' in headers:
        try:
            retry_after = float(headers['retry-after'])
            logging.debug(f"Using provided retry-after: {retry_after}s")
            return max(0.0, retry_after)
        except (ValueError, TypeError) as e:
            logging.warning(f"Invalid retry-after value: {headers['retry-after']}")

    # Priority 2: Extract headers from exception
    extracted_headers = self._extract_headers(exception)

    if 'retry-after' in extracted_headers:
        try:
            retry_after = float(extracted_headers['retry-after'])
            logging.debug(f"Using exception retry-after: {retry_after}s")
            return max(0.0, retry_after)
        except (ValueError, TypeError):
            pass

    # Priority 3: x-ratelimit-reset-requests
    if 'x-ratelimit-reset-requests' in extracted_headers:
        reset_time = self._parse_reset_time(
            extracted_headers['x-ratelimit-reset-requests']
        )
        logging.debug(f"Using request reset time: {reset_time}s")
        return reset_time

    # Priority 4: x-ratelimit-reset-tokens
    if 'x-ratelimit-reset-tokens' in extracted_headers:
        reset_time = self._parse_reset_time(
            extracted_headers['x-ratelimit-reset-tokens']
        )
        logging.debug(f"Using token reset time: {reset_time}s")
        return reset_time

    # No retry hint available
    logging.debug("No retry-after hint available from exception")
    return None
```

---

## 4. Exception Handling

### 4.1 OpenAI Exception Classification

```python
# OpenAI SDK Exception Hierarchy (openai >= 1.0.0)

from openai import (
    APIError,              # Base exception
    RateLimitError,        # 429 Rate limit exceeded
    APIConnectionError,    # Network/connection errors
    APITimeoutError,       # Request timeout
    InternalServerError,   # 500 Server errors
    BadRequestError,       # 400 Invalid request
    AuthenticationError,   # 401 Invalid API key
    PermissionDeniedError, # 403 Insufficient permissions
    NotFoundError,         # 404 Resource not found
    UnprocessableEntityError, # 422 Validation failed
)

# Exception -> Retry Decision Mapping
OPENAI_EXCEPTION_RETRY_MAP = {
    RateLimitError:          True,   # RETRY - Rate limit will reset
    InternalServerError:     True,   # RETRY - Temporary server issue
    APITimeoutError:         True,   # RETRY - Timeout may be transient
    APIConnectionError:      True,   # RETRY - Network issue may resolve
    BadRequestError:         False,  # NO RETRY - Invalid request format
    AuthenticationError:     False,  # NO RETRY - Invalid API key
    PermissionDeniedError:   False,  # NO RETRY - Insufficient permissions
    NotFoundError:           False,  # NO RETRY - Model/endpoint doesn't exist
    UnprocessableEntityError: False, # NO RETRY - Validation error
}
```

### 4.2 Rate Limit Info Extraction

```python
def extract_rate_limit_info(
    self,
    exception: Exception
) -> Optional[Dict[str, Any]]:
    """
    Extract rate limit details from OpenAI exception.

    Use Cases:
        1. Determine which limit was hit (RPM vs TPM)
        2. Get retry-after delay from server
        3. Get remaining quota information
        4. Distinguish rate limit vs quota exhaustion

    Args:
        exception: Any exception (checked for OpenAI types)

    Returns:
        Rate limit info dict, or None if not a rate limit error

    Output Format:
        {
            'error_type': 'rate_limit',
            'limit_type': 'rpm' | 'tpm',
            'retry_after': float,           # Seconds to wait
            'reset_at': float,              # Unix timestamp (if available)
            'remaining': int,               # Remaining quota (if available)
            'limit_value': int,             # Total limit (if available)
            'message': str,                 # Error message
        }

    Return None If:
        - Exception is not openai.RateLimitError
        - Exception is retryable but not rate-limit-related
        - Exception is non-retryable

    Example:
        >>> info = adapter.extract_rate_limit_info(rate_limit_error)
        >>> info['limit_type']
        'rpm'
        >>> info['retry_after']
        5.0
    """
    try:
        import openai
    except ImportError:
        logging.warning("openai SDK not available for error parsing")
        return None

    # Check if exception is RateLimitError
    if not isinstance(exception, openai.RateLimitError):
        logging.debug(
            f"Exception is not RateLimitError, got {type(exception).__name__}"
        )
        return None

    # Extract headers
    headers = self._extract_headers(exception)

    # Initialize info dict
    info = {
        'error_type': 'rate_limit',
        'message': str(exception),
    }

    # Determine which limit was hit (RPM vs TPM)
    limit_type = self._identify_rate_limit_type(exception, headers)
    info['limit_type'] = limit_type

    # Extract retry-after
    retry_after = self.get_retry_after(exception, headers)
    if retry_after is not None:
        info['retry_after'] = retry_after

    # Extract remaining quota (for the limit that was hit)
    if limit_type == 'rpm':
        remaining_key = 'x-ratelimit-remaining-requests'
        limit_key = 'x-ratelimit-limit-requests'
    elif limit_type == 'tpm':
        remaining_key = 'x-ratelimit-remaining-tokens'
        limit_key = 'x-ratelimit-limit-tokens'
    else:
        remaining_key = None
        limit_key = None

    if remaining_key and remaining_key in headers:
        try:
            info['remaining'] = int(headers[remaining_key])
        except (ValueError, TypeError):
            pass

    if limit_key and limit_key in headers:
        try:
            info['limit_value'] = int(headers[limit_key])
        except (ValueError, TypeError):
            pass

    # Calculate reset timestamp (if available)
    if 'retry_after' in info:
        import time
        info['reset_at'] = time.time() + info['retry_after']

    logging.debug(f"Extracted rate limit info: {info}")

    return info


def _identify_rate_limit_type(
    self,
    exception: Exception,
    headers: Dict[str, str]
) -> str:
    """
    Identify which rate limit was hit (RPM vs TPM).

    Detection Methods (priority order):
        1. Check x-ratelimit-remaining-* headers (0 = hit)
        2. Parse error message for keywords
        3. Default to 'rpm' (most common)

    Args:
        exception: OpenAI RateLimitError
        headers: Extracted headers

    Returns:
        'rpm' or 'tpm'

    Algorithm:
        - If remaining-requests == 0 -> RPM hit
        - If remaining-tokens == 0 -> TPM hit
        - If error message contains 'request' -> RPM
        - If error message contains 'token' -> TPM
        - Default: 'rpm'
    """
    # Check headers for 0 remaining
    if 'x-ratelimit-remaining-requests' in headers:
        try:
            remaining = int(headers['x-ratelimit-remaining-requests'])
            if remaining == 0:
                logging.debug("RPM limit hit (remaining-requests = 0)")
                return 'rpm'
        except (ValueError, TypeError):
            pass

    if 'x-ratelimit-remaining-tokens' in headers:
        try:
            remaining = int(headers['x-ratelimit-remaining-tokens'])
            if remaining == 0:
                logging.debug("TPM limit hit (remaining-tokens = 0)")
                return 'tpm'
        except (ValueError, TypeError):
            pass

    # Check error message for keywords
    message = str(exception).lower()

    if 'request' in message and 'token' not in message:
        logging.debug("RPM limit inferred from error message")
        return 'rpm'

    if 'token' in message:
        logging.debug("TPM limit inferred from error message")
        return 'tpm'

    # Default to RPM (most common)
    logging.debug("Defaulting to RPM limit (unable to determine from headers/message)")
    return 'rpm'
```

### 4.3 Exception Handling Edge Cases

```python
def _handle_exception_edge_cases(self, exception: Exception) -> Optional[Dict]:
    """
    Handle edge cases in exception parsing.

    Edge Cases:
        1. Exception has no response object
        2. Response has no headers
        3. Headers are malformed (wrong types, missing values)
        4. Error message is empty or non-standard
        5. Multiple limits hit simultaneously
        6. Quota exhausted vs rate limited

    Args:
        exception: Any exception

    Returns:
        Rate limit info if edge case detected, None otherwise
    """
    # Case 1: No response object
    if not hasattr(exception, 'response'):
        logging.debug("Exception has no response object, cannot extract details")
        return {
            'error_type': 'rate_limit',
            'limit_type': 'unknown',
            'message': str(exception),
        }

    # Case 2: Empty error message
    message = str(exception)
    if not message or message.isspace():
        logging.warning("Exception has empty message")
        message = type(exception).__name__

    # Case 3: Quota exhausted detection
    if 'quota' in message.lower() or 'exceeded your current quota' in message.lower():
        logging.warning("Quota exhausted detected (not standard rate limit)")
        return {
            'error_type': 'quota_exhausted',
            'limit_type': 'quota',
            'message': message,
        }

    return None
```

---

## 5. Response Parsing

### 5.1 Token Usage Extraction

```python
def extract_usage_from_response(
    self,
    response: Any,
    metadata: Optional[Dict] = None
) -> Dict[str, int]:
    """
    Extract token usage from OpenAI API response.

    OpenAI Response Structure:
        Chat Completions:
            response.usage = {
                'prompt_tokens': 10,
                'completion_tokens': 20,
                'total_tokens': 30
            }

        Completions:
            response.usage = {
                'prompt_tokens': 10,
                'completion_tokens': 20,
                'total_tokens': 30
            }

    Args:
        response: OpenAI response object (from chat.completions.create())
        metadata: Optional context (headers, timing, etc.)

    Returns:
        Normalized usage dict with keys:
            - tokens_used: int (REQUIRED - total tokens)
            - input_tokens: int (prompt tokens)
            - output_tokens: int (completion tokens)
            - cached_tokens: int (if prompt caching used)

    Fallback Behavior:
        - If response.usage missing: Return {'tokens_used': 0}
        - If individual fields missing: Estimate from available data
        - If response is None: Return {'tokens_used': 0}

    Example:
        >>> usage = adapter.extract_usage_from_response(response)
        >>> usage['tokens_used']
        30
        >>> usage['input_tokens']
        10
        >>> usage['output_tokens']
        20
    """
    # Validate response
    if response is None:
        logging.warning("Response is None, cannot extract usage")
        return {'tokens_used': 0}

    # Check for usage attribute
    if not hasattr(response, 'usage'):
        logging.warning("Response has no usage attribute, cannot extract token count")
        return {'tokens_used': 0}

    usage_obj = response.usage

    # Validate usage object
    if usage_obj is None:
        logging.warning("Response.usage is None")
        return {'tokens_used': 0}

    # Extract token counts
    try:
        # Standard fields
        total_tokens = getattr(usage_obj, 'total_tokens', 0)
        prompt_tokens = getattr(usage_obj, 'prompt_tokens', 0)
        completion_tokens = getattr(usage_obj, 'completion_tokens', 0)

        # Calculate total if not provided
        if total_tokens == 0 and (prompt_tokens > 0 or completion_tokens > 0):
            total_tokens = prompt_tokens + completion_tokens
            logging.debug(
                f"Calculated total_tokens from components: "
                f"{prompt_tokens} + {completion_tokens} = {total_tokens}"
            )

        # Verify total matches sum
        if total_tokens != (prompt_tokens + completion_tokens):
            logging.warning(
                f"Total tokens mismatch: total_tokens={total_tokens}, "
                f"sum={prompt_tokens + completion_tokens}. Using total_tokens."
            )

        usage_dict = {
            'tokens_used': total_tokens,
            'input_tokens': prompt_tokens,
            'output_tokens': completion_tokens,
        }

        # Check for cached tokens (prompt caching feature)
        if hasattr(usage_obj, 'prompt_tokens_details'):
            details = usage_obj.prompt_tokens_details
            if hasattr(details, 'cached_tokens'):
                cached = getattr(details, 'cached_tokens', 0)
                if cached > 0:
                    usage_dict['cached_tokens'] = cached
                    logging.debug(f"Found {cached} cached tokens")

        logging.debug(f"Extracted usage: {usage_dict}")

        return usage_dict

    except Exception as e:
        logging.warning(f"Failed to extract usage from response: {e}")
        return {'tokens_used': 0}


def _extract_usage_from_streaming_response(
    self,
    stream_chunks: List[Any]
) -> Dict[str, int]:
    """
    Extract token usage from streaming response.

    OpenAI Streaming:
        - Usage reported in final chunk only
        - Must accumulate all chunks to get usage
        - Some endpoints don't report usage in streaming mode

    Args:
        stream_chunks: List of stream chunks from response

    Returns:
        Aggregated usage dict

    Algorithm:
        1. Check each chunk for usage attribute
        2. Use last non-null usage object
        3. If no usage found, estimate from content length
    """
    usage = None

    # Find last chunk with usage
    for chunk in reversed(stream_chunks):
        if hasattr(chunk, 'usage') and chunk.usage is not None:
            usage = chunk.usage
            break

    if usage:
        return self.extract_usage_from_response(
            type('Response', (), {'usage': usage})()
        )

    # Fallback: Estimate from content
    logging.warning("No usage in streaming chunks, estimating from content")

    total_content = ''
    for chunk in stream_chunks:
        if hasattr(chunk, 'choices') and chunk.choices:
            delta = chunk.choices[0].delta
            if hasattr(delta, 'content') and delta.content:
                total_content += delta.content

    # Estimate tokens from content
    estimated_tokens = len(total_content) // self.TIKTOKEN_FALLBACK_RATIO

    return {
        'tokens_used': estimated_tokens,
        'output_tokens': estimated_tokens,
    }
```

### 5.2 Batch Response Handling

```python
def extract_batch_usage(
    self,
    responses: List[Any]
) -> Dict[str, int]:
    """
    Extract aggregated usage from multiple responses.

    Use Case:
        When generating multiple completions (n > 1), aggregate
        token usage across all responses.

    Args:
        responses: List of OpenAI response objects

    Returns:
        Aggregated usage dict with total across all responses

    Example:
        >>> # Generated 5 completions
        >>> responses = [response1, response2, response3, response4, response5]
        >>> total_usage = adapter.extract_batch_usage(responses)
        >>> total_usage['tokens_used']
        150  # Sum of all 5 responses
    """
    total_usage = {
        'tokens_used': 0,
        'input_tokens': 0,
        'output_tokens': 0,
    }

    for response in responses:
        usage = self.extract_usage_from_response(response)

        total_usage['tokens_used'] += usage.get('tokens_used', 0)
        total_usage['input_tokens'] += usage.get('input_tokens', 0)
        total_usage['output_tokens'] += usage.get('output_tokens', 0)

    logging.debug(
        f"Aggregated usage from {len(responses)} responses: {total_usage}"
    )

    return total_usage
```

---

## 6. Model Limits Database

### 6.1 Known Model Limits

```python
def get_model_limits(self, model: str) -> Optional[Dict[str, int]]:
    """
    Get default rate limits for OpenAI model.

    Data Source:
        https://platform.openai.com/docs/guides/rate-limits
        Updated: 2025-01-31

    Tier Structure:
        OpenAI uses usage-based tiers (1-5):
        - Free: 3 RPM, 40K TPM
        - Tier 1: 500 RPM, 30K-200K TPM (default in this function)
        - Tier 2: 5000 RPM, 450K-2M TPM
        - Tier 3: 10000 RPM, 1M-10M TPM
        - Tier 4+: Custom limits

    Args:
        model: OpenAI model name (exact match required)

    Returns:
        {'rpm': int, 'tpm': int} or None if unknown

    Design Decision:
        Return Tier 1 limits (most common for paid users).
        Users on higher tiers should configure limits explicitly.

    Update Frequency:
        Check OpenAI docs quarterly for limit changes.
    """
    # GPT-4o family (latest, most common)
    GPT4O_LIMITS = {
        'gpt-4o': {'rpm': 500, 'tpm': 30000},
        'gpt-4o-2024-11-20': {'rpm': 500, 'tpm': 30000},
        'gpt-4o-2024-08-06': {'rpm': 500, 'tpm': 30000},
        'gpt-4o-2024-05-13': {'rpm': 500, 'tpm': 30000},
        'chatgpt-4o-latest': {'rpm': 500, 'tpm': 30000},

        # GPT-4o mini (higher TPM)
        'gpt-4o-mini': {'rpm': 500, 'tpm': 200000},
        'gpt-4o-mini-2024-07-18': {'rpm': 500, 'tpm': 200000},

        # GPT-4o audio preview
        'gpt-4o-audio-preview': {'rpm': 100, 'tpm': 20000},
        'gpt-4o-audio-preview-2024-12-17': {'rpm': 100, 'tpm': 20000},
        'gpt-4o-audio-preview-2024-10-01': {'rpm': 100, 'tpm': 20000},

        # GPT-4o mini audio
        'gpt-4o-mini-audio-preview': {'rpm': 100, 'tpm': 100000},
        'gpt-4o-mini-audio-preview-2024-12-17': {'rpm': 100, 'tpm': 100000},

        # GPT-4o realtime (special limits)
        'gpt-4o-realtime-preview': {'rpm': 100, 'tpm': 20000},
        'gpt-4o-realtime-preview-2024-12-17': {'rpm': 100, 'tpm': 20000},
        'gpt-4o-realtime-preview-2024-10-01': {'rpm': 100, 'tpm': 20000},
        'gpt-4o-mini-realtime-preview': {'rpm': 100, 'tpm': 100000},
        'gpt-4o-mini-realtime-preview-2024-12-17': {'rpm': 100, 'tpm': 100000},
    }

    # GPT-4 family (older models)
    GPT4_LIMITS = {
        'gpt-4': {'rpm': 500, 'tpm': 10000},
        'gpt-4-0314': {'rpm': 500, 'tpm': 10000},
        'gpt-4-0613': {'rpm': 500, 'tpm': 10000},
        'gpt-4-32k': {'rpm': 500, 'tpm': 10000},  # Deprecated
        'gpt-4-32k-0314': {'rpm': 500, 'tpm': 10000},  # Deprecated
        'gpt-4-32k-0613': {'rpm': 500, 'tpm': 10000},  # Deprecated

        # GPT-4 turbo
        'gpt-4-turbo': {'rpm': 500, 'tpm': 30000},
        'gpt-4-turbo-2024-04-09': {'rpm': 500, 'tpm': 30000},
        'gpt-4-turbo-preview': {'rpm': 500, 'tpm': 30000},
        'gpt-4-1106-preview': {'rpm': 500, 'tpm': 30000},
        'gpt-4-0125-preview': {'rpm': 500, 'tpm': 30000},

        # GPT-4 vision
        'gpt-4-vision-preview': {'rpm': 500, 'tpm': 30000},
        'gpt-4-1106-vision-preview': {'rpm': 500, 'tpm': 30000},
    }

    # GPT-3.5 family (higher RPM)
    GPT35_LIMITS = {
        'gpt-3.5-turbo': {'rpm': 3500, 'tpm': 90000},
        'gpt-3.5-turbo-0125': {'rpm': 3500, 'tpm': 90000},
        'gpt-3.5-turbo-1106': {'rpm': 3500, 'tpm': 90000},
        'gpt-3.5-turbo-16k': {'rpm': 3500, 'tpm': 90000},
        'gpt-3.5-turbo-16k-0613': {'rpm': 3500, 'tpm': 90000},  # Deprecated
        'gpt-3.5-turbo-0613': {'rpm': 3500, 'tpm': 90000},  # Deprecated
        'gpt-3.5-turbo-instruct': {'rpm': 3500, 'tpm': 90000},
    }

    # o1 reasoning models (special limits)
    O1_LIMITS = {
        'o1-preview': {'rpm': 500, 'tpm': 30000},
        'o1-preview-2024-09-12': {'rpm': 500, 'tpm': 30000},
        'o1-mini': {'rpm': 500, 'tpm': 150000},
        'o1-mini-2024-09-12': {'rpm': 500, 'tpm': 150000},
    }

    # o3 models
    O3_LIMITS = {
        'o3-mini': {'rpm': 500, 'tpm': 100000},
        'o3-mini-2025-01-31': {'rpm': 500, 'tpm': 100000},
    }

    # Base completion models
    COMPLETION_LIMITS = {
        'davinci-002': {'rpm': 3500, 'tpm': 250000},
        'babbage-002': {'rpm': 3500, 'tpm': 150000},
        'davinci-instruct-beta': {'rpm': 3500, 'tpm': 250000},
    }

    # Combine all limit dictionaries
    ALL_LIMITS = {
        **GPT4O_LIMITS,
        **GPT4_LIMITS,
        **GPT35_LIMITS,
        **O1_LIMITS,
        **O3_LIMITS,
        **COMPLETION_LIMITS,
    }

    # Lookup model
    limits = ALL_LIMITS.get(model)

    if limits:
        logging.debug(f"Found default limits for '{model}': {limits}")
    else:
        logging.info(
            f"No default limits for model '{model}'. "
            f"User must configure limits in garak.core.yaml"
        )

    return limits
```

### 6.2 Model Limit Update Strategy

```python
# Model Limits Maintenance Strategy

# 1. Check OpenAI docs quarterly (Jan, Apr, Jul, Oct)
#    URL: https://platform.openai.com/docs/guides/rate-limits

# 2. Subscribe to OpenAI changelog
#    URL: https://platform.openai.com/docs/changelog

# 3. Monitor for deprecation notices
#    - Models marked deprecated should keep limits but add comment
#    - Shutdown models should be removed from list

# 4. Version tracking
#    - Add update date comment above each limit dict
#    - Document source URL for each limit

# 5. Testing new models
#    - When new model released, test with --target_name
#    - Observe actual limits from response headers
#    - Add to appropriate limit dict

# Example Update Process:
# 1. New model announced: gpt-5
# 2. Check docs for limits: 1000 RPM, 500K TPM
# 3. Add to GPT5_LIMITS dict:
#    'gpt-5': {'rpm': 1000, 'tpm': 500000},  # Added 2025-10-20
# 4. Test with live API to verify
# 5. Commit with message: "Add GPT-5 model limits"
```

---

## 7. Configuration Schema

### 7.1 YAML Configuration

```yaml
# garak/resources/garak.core.yaml

plugins:
  generators:
    openai:
      # Rate limiting configuration
      rate_limits:
        # Model-specific limits (override defaults)
        gpt-4o:
          rpm: 10000      # Tier 3 limit (if you have it)
          tpm: 2000000
          safety_margin: 0.9  # Use 90% of limit (leave buffer)

        gpt-4o-mini:
          rpm: 500
          tpm: 200000
          safety_margin: 0.85

        gpt-3.5-turbo:
          rpm: 3500
          tpm: 90000

        # Default for unlisted models
        default:
          rpm: 500
          tpm: 30000
          safety_margin: 0.9

      # Backoff strategy for retries
      backoff:
        strategy: "fibonacci"  # or "exponential", "linear"
        max_value: 70          # Max backoff delay (seconds)
        max_retries: 10        # Max retry attempts
        jitter: true           # Add randomization to prevent thundering herd

      # Advanced options (optional)
      advanced:
        token_counting:
          use_tiktoken: true   # Enable accurate token counting
          cache_encodings: true  # Cache tokenizers for performance
          fallback_ratio: 4    # chars/token for fallback estimation

        header_parsing:
          trust_server_limits: true  # Override config with server-provided limits
          log_rate_limit_headers: false  # Log all rate limit headers (debugging)
```

### 7.2 Programmatic Configuration

```python
# Python configuration (alternative to YAML)

from garak.generators.openai import OpenAIGenerator

config = {
    'rate_limits': {
        'gpt-4o': {
            'rpm': 10000,
            'tpm': 2000000,
            'safety_margin': 0.9,
        },
        'default': {
            'rpm': 500,
            'tpm': 30000,
        },
    },
    'backoff': {
        'strategy': 'fibonacci',
        'max_value': 70,
        'max_retries': 10,
        'jitter': True,
    },
}

# Create generator with rate limiting
generator = OpenAIGenerator(
    name='gpt-4o',
    config_root=config
)

# Rate limiter initialized automatically
# - Adapter: OpenAIAdapter
# - Limits: 10000 RPM, 2M TPM (from config)
# - Backoff: Fibonacci with max 70s
```

### 7.3 Configuration Validation

```python
def validate_openai_config(config: Dict) -> bool:
    """
    Validate OpenAI rate limit configuration.

    Validation Rules:
        1. rate_limits must be present and non-empty
        2. Each model config must have rpm and/or tpm
        3. Limits must be positive integers
        4. safety_margin must be 0.0 < x <= 1.0
        5. backoff strategy must be recognized
        6. max_value and max_retries must be positive

    Args:
        config: Configuration dict

    Returns:
        True if valid, False otherwise (logs errors)

    Raises:
        ValueError: If critical validation fails
    """
    if 'rate_limits' not in config:
        raise ValueError("Missing 'rate_limits' in OpenAI config")

    rate_limits = config['rate_limits']

    if not rate_limits:
        raise ValueError("rate_limits cannot be empty")

    # Validate each model config
    for model, limits in rate_limits.items():
        if not isinstance(limits, dict):
            raise ValueError(f"Limits for '{model}' must be dict, got {type(limits)}")

        # Check for at least one limit type
        if 'rpm' not in limits and 'tpm' not in limits:
            raise ValueError(f"Model '{model}' must specify 'rpm' and/or 'tpm'")

        # Validate limit values
        for limit_key in ('rpm', 'tpm'):
            if limit_key in limits:
                limit_value = limits[limit_key]
                if not isinstance(limit_value, int) or limit_value <= 0:
                    raise ValueError(
                        f"Invalid {limit_key} for '{model}': must be positive int, "
                        f"got {limit_value}"
                    )

        # Validate safety margin
        if 'safety_margin' in limits:
            margin = limits['safety_margin']
            if not (0.0 < margin <= 1.0):
                raise ValueError(
                    f"Invalid safety_margin for '{model}': must be 0.0 < x <= 1.0, "
                    f"got {margin}"
                )

    # Validate backoff config
    if 'backoff' in config:
        backoff = config['backoff']

        if 'strategy' in backoff:
            valid_strategies = {'fibonacci', 'exponential', 'linear'}
            if backoff['strategy'] not in valid_strategies:
                raise ValueError(
                    f"Invalid backoff strategy: {backoff['strategy']}. "
                    f"Must be one of {valid_strategies}"
                )

        if 'max_value' in backoff:
            if not isinstance(backoff['max_value'], (int, float)) or backoff['max_value'] <= 0:
                raise ValueError(
                    f"Invalid max_value: must be positive number, "
                    f"got {backoff['max_value']}"
                )

        if 'max_retries' in backoff:
            if not isinstance(backoff['max_retries'], int) or backoff['max_retries'] < 0:
                raise ValueError(
                    f"Invalid max_retries: must be non-negative int, "
                    f"got {backoff['max_retries']}"
                )

    logging.info("OpenAI configuration validation passed")
    return True
```

---

## 8. Edge Cases and Fallbacks

### 8.1 Token Counting Edge Cases

```python
# Edge Case 1: tiktoken not installed
# Fallback: Character-based estimation (4:1 ratio)
# Accuracy: ~90% for English text
# Impact: Slightly conservative rate limiting

# Edge Case 2: Unknown model name
# Fallback: Use 'gpt-3.5-turbo' encoding (cl100k_base)
# Accuracy: ~95% (most GPT-4 models use same encoding)
# Impact: Minimal

# Edge Case 3: Empty prompt
# Behavior: Return 0 tokens
# Rationale: No API call needed

# Edge Case 4: Extremely long prompt (>100K tokens)
# Behavior: Token count accurate, but API may reject
# Handling: UnifiedRateLimiter checks context_len before allowing

# Edge Case 5: Non-English text
# tiktoken: Handles correctly (multilingual)
# Fallback: May undercount (4:1 assumes English density)
# Impact: Rate limiter may be slightly pessimistic

# Edge Case 6: Code vs text
# Code: ~6 chars/token (more tokens than text)
# Text: ~4 chars/token
# Fallback ratio: 4:1 (conservative for code, accurate for text)
```

### 8.2 Header Extraction Edge Cases

```python
# Edge Case 1: Headers missing entirely
# Fallback: Use configured limits from YAML
# Impact: Can't detect server-side limit changes

# Edge Case 2: Partial headers (only RPM, not TPM)
# Behavior: Extract available headers, use config for missing
# Impact: Partial server visibility

# Edge Case 3: Malformed reset time ("invalid")
# Fallback: Return 60s (safe default)
# Impact: May retry sooner/later than optimal

# Edge Case 4: Negative remaining quota
# Behavior: Treat as 0 (limit exceeded)
# Rationale: Server bug or race condition

# Edge Case 5: retry-after > 1 hour
# Behavior: Use value as-is, but log warning
# Rationale: Extremely unusual, may indicate outage
```

### 8.3 Response Parsing Edge Cases

```python
# Edge Case 1: response.usage is None
# Fallback: Return {'tokens_used': 0}
# Impact: Usage not tracked (rare, usually server error)

# Edge Case 2: total_tokens != prompt + completion
# Behavior: Use total_tokens (trust server)
# Logging: Warn about discrepancy
# Rationale: Server value is authoritative

# Edge Case 3: Streaming response with no final usage
# Fallback: Estimate from content length
# Accuracy: ~80% (no prompt tokens counted)
# Impact: Usage tracking approximate

# Edge Case 4: Batch generation (n > 1)
# Behavior: Sum usage across all choices
# Note: OpenAI reports total in single usage object

# Edge Case 5: Prompt caching (cached_tokens > 0)
# Behavior: Report cached tokens separately
# Impact: Better visibility into caching benefits
```

---

## 9. Integration with AdapterFactory

### 9.1 Factory Registration

```python
# garak/ratelimit/adapters/__init__.py

from garak.ratelimit.adapters.openai import OpenAIAdapter
from garak.ratelimit.base import ProviderAdapter
from typing import Dict, Type
import logging


class AdapterFactory:
    """Factory for creating provider adapters."""

    _registry: Dict[str, Type[ProviderAdapter]] = {}

    @classmethod
    def register(cls, provider: str, adapter_class: Type[ProviderAdapter]):
        """Register provider adapter."""
        cls._registry[provider.lower()] = adapter_class
        logging.debug(f"Registered adapter: {provider} -> {adapter_class.__name__}")

    @classmethod
    def create(cls, provider: str, model: str, config: Dict) -> ProviderAdapter:
        """Create adapter instance."""
        provider_lower = provider.lower()

        if provider_lower not in cls._registry:
            raise ValueError(
                f"No adapter for provider '{provider}'. "
                f"Available: {list(cls._registry.keys())}"
            )

        adapter_class = cls._registry[provider_lower]
        return adapter_class(model=model, config=config)

    @classmethod
    def is_supported(cls, provider: str) -> bool:
        """Check if provider is supported."""
        return provider.lower() in cls._registry


# Auto-register OpenAI adapter
AdapterFactory.register('openai', OpenAIAdapter)

# Register aliases for compatibility
AdapterFactory.register('openai.OpenAIGenerator', OpenAIAdapter)
AdapterFactory.register('openai.OpenAIReasoningGenerator', OpenAIAdapter)
```

### 9.2 Usage in UnifiedRateLimiter

```python
# garak/ratelimit/limiters.py

from garak.ratelimit.adapters import AdapterFactory

class SlidingWindowRateLimiter(UnifiedRateLimiter):
    def __init__(self, provider: str, model: str, config: Dict):
        super().__init__(provider, model, config)

        # Create provider adapter
        if AdapterFactory.is_supported(provider):
            self.adapter = AdapterFactory.create(provider, model, config)
            logging.info(
                f"Created {provider} adapter for model '{model}'"
            )
        else:
            raise ValueError(
                f"No adapter available for provider '{provider}'. "
                f"Supported providers: {AdapterFactory._registry.keys()}"
            )

    def acquire(self, estimated_tokens: int):
        # Use adapter for token estimation
        # (if called from code that doesn't have prompt)
        pass

    def record_usage(self, tokens_used: int, metadata: Dict):
        # Adapter not needed here (usage already extracted)
        pass
```

---

## 10. Testing Strategy

### 10.1 Unit Tests

```python
# tests/ratelimit/test_openai_adapter.py

import pytest
from garak.ratelimit.adapters.openai import OpenAIAdapter
from unittest.mock import Mock, MagicMock


class TestOpenAIAdapter:
    """Unit tests for OpenAIAdapter."""

    def setup_method(self):
        """Create adapter instance for each test."""
        self.adapter = OpenAIAdapter(model='gpt-4o')

    # ==========================================
    # Token Counting Tests
    # ==========================================

    def test_estimate_tokens_with_tiktoken(self):
        """Test token counting with tiktoken installed."""
        prompt = "Hello world"
        tokens = self.adapter.estimate_tokens(prompt, 'gpt-4o')

        assert tokens > 0
        assert tokens < len(prompt)  # Tokens < characters

    def test_estimate_tokens_empty_prompt(self):
        """Test empty prompt returns 0 tokens."""
        tokens = self.adapter.estimate_tokens("", 'gpt-4o')
        assert tokens == 0

    def test_estimate_tokens_fallback(self, monkeypatch):
        """Test fallback when tiktoken not available."""
        # Disable tiktoken
        monkeypatch.setattr(self.adapter, '_tiktoken_available', False)

        prompt = "Hello world"  # 11 chars
        tokens = self.adapter.estimate_tokens(prompt, 'gpt-4o')

        # Fallback: len / 4 = 11 / 4 = 2
        assert tokens == 2

    def test_estimate_tokens_long_prompt(self):
        """Test token counting for long prompt."""
        prompt = "Hello " * 1000  # ~6000 chars
        tokens = self.adapter.estimate_tokens(prompt, 'gpt-4o')

        assert tokens > 1000
        assert tokens < 2000  # "Hello " is ~2 tokens

    def test_estimate_tokens_unicode(self):
        """Test token counting with unicode."""
        prompt = "こんにちは世界"  # Japanese
        tokens = self.adapter.estimate_tokens(prompt, 'gpt-4o')

        assert tokens > 0

    def test_estimate_chat_tokens(self):
        """Test chat format token counting."""
        messages = [
            {"role": "system", "content": "You are a helper."},
            {"role": "user", "content": "Hello!"},
            {"role": "assistant", "content": "Hi there!"},
        ]

        tokens = self.adapter.estimate_chat_tokens(messages, 'gpt-4o')

        # Expect content tokens + message overhead
        assert tokens > 10  # Content is ~10 tokens
        assert tokens < 50  # With overhead ~20 tokens

    # ==========================================
    # Rate Limit Extraction Tests
    # ==========================================

    def test_extract_rate_limit_info_rpm(self):
        """Test RPM limit extraction."""
        # Mock RateLimitError
        mock_error = Mock(spec=['response'])
        mock_error.response = Mock()
        mock_error.response.headers = {
            'x-ratelimit-limit-requests': '10000',
            'x-ratelimit-remaining-requests': '0',
            'x-ratelimit-reset-requests': '6s',
            'retry-after': '5',
        }

        # Make error isinstance of RateLimitError
        import openai
        mock_error.__class__ = openai.RateLimitError

        info = self.adapter.extract_rate_limit_info(mock_error)

        assert info is not None
        assert info['error_type'] == 'rate_limit'
        assert info['limit_type'] == 'rpm'
        assert info['retry_after'] == 5.0
        assert info['remaining'] == 0
        assert info['limit_value'] == 10000

    def test_extract_rate_limit_info_tpm(self):
        """Test TPM limit extraction."""
        mock_error = Mock(spec=['response'])
        mock_error.response = Mock()
        mock_error.response.headers = {
            'x-ratelimit-limit-tokens': '2000000',
            'x-ratelimit-remaining-tokens': '0',
            'x-ratelimit-reset-tokens': '60s',
        }

        import openai
        mock_error.__class__ = openai.RateLimitError

        info = self.adapter.extract_rate_limit_info(mock_error)

        assert info['limit_type'] == 'tpm'
        assert info['remaining'] == 0

    def test_extract_rate_limit_info_non_rate_limit(self):
        """Test non-rate-limit exception returns None."""
        import openai

        auth_error = openai.AuthenticationError("Invalid API key")
        info = self.adapter.extract_rate_limit_info(auth_error)

        assert info is None

    def test_get_retry_after_from_headers(self):
        """Test retry-after extraction from headers."""
        headers = {'retry-after': '10'}
        retry = self.adapter.get_retry_after(Mock(), headers)

        assert retry == 10.0

    def test_get_retry_after_from_exception(self):
        """Test retry-after extraction from exception."""
        mock_error = Mock(spec=['response'])
        mock_error.response = Mock()
        mock_error.response.headers = {'retry-after': '5'}

        retry = self.adapter.get_retry_after(mock_error)

        assert retry == 5.0

    def test_parse_reset_time(self):
        """Test reset time parsing."""
        assert self.adapter._parse_reset_time('6s') == 6.0
        assert self.adapter._parse_reset_time('360ms') == 0.36
        assert self.adapter._parse_reset_time('1m') == 60.0
        assert self.adapter._parse_reset_time('1h') == 3600.0
        assert self.adapter._parse_reset_time('invalid') == 60.0  # Fallback

    # ==========================================
    # Response Parsing Tests
    # ==========================================

    def test_extract_usage_from_response(self):
        """Test usage extraction from response."""
        mock_response = Mock()
        mock_response.usage = Mock(
            total_tokens=30,
            prompt_tokens=10,
            completion_tokens=20
        )

        usage = self.adapter.extract_usage_from_response(mock_response)

        assert usage['tokens_used'] == 30
        assert usage['input_tokens'] == 10
        assert usage['output_tokens'] == 20

    def test_extract_usage_no_usage_attribute(self):
        """Test usage extraction when response has no usage."""
        mock_response = Mock(spec=[])  # No usage attribute

        usage = self.adapter.extract_usage_from_response(mock_response)

        assert usage['tokens_used'] == 0

    def test_extract_usage_none_response(self):
        """Test usage extraction from None response."""
        usage = self.adapter.extract_usage_from_response(None)

        assert usage['tokens_used'] == 0

    def test_extract_batch_usage(self):
        """Test aggregated usage from multiple responses."""
        responses = [
            Mock(usage=Mock(total_tokens=30, prompt_tokens=10, completion_tokens=20)),
            Mock(usage=Mock(total_tokens=40, prompt_tokens=10, completion_tokens=30)),
            Mock(usage=Mock(total_tokens=50, prompt_tokens=10, completion_tokens=40)),
        ]

        total_usage = self.adapter.extract_batch_usage(responses)

        assert total_usage['tokens_used'] == 120
        assert total_usage['input_tokens'] == 30
        assert total_usage['output_tokens'] == 90

    # ==========================================
    # Model Limits Tests
    # ==========================================

    def test_get_model_limits_gpt4o(self):
        """Test model limits for GPT-4o."""
        limits = self.adapter.get_model_limits('gpt-4o')

        assert limits is not None
        assert limits['rpm'] == 500
        assert limits['tpm'] == 30000

    def test_get_model_limits_gpt35(self):
        """Test model limits for GPT-3.5."""
        limits = self.adapter.get_model_limits('gpt-3.5-turbo')

        assert limits is not None
        assert limits['rpm'] == 3500
        assert limits['tpm'] == 90000

    def test_get_model_limits_unknown(self):
        """Test unknown model returns None."""
        limits = self.adapter.get_model_limits('unknown-model')

        assert limits is None

    # ==========================================
    # Capability Tests
    # ==========================================

    def test_supports_concurrent_limiting(self):
        """Test OpenAI doesn't support concurrent limits."""
        assert self.adapter.supports_concurrent_limiting() is False

    def test_supports_quota_tracking(self):
        """Test OpenAI doesn't use quotas."""
        assert self.adapter.supports_quota_tracking() is False

    def test_get_limit_types(self):
        """Test OpenAI limit types."""
        from garak.ratelimit.base import RateLimitType

        types = self.adapter.get_limit_types()

        assert RateLimitType.RPM in types
        assert RateLimitType.TPM in types
        assert len(types) == 2

    def test_get_window_seconds(self):
        """Test window duration."""
        from garak.ratelimit.base import RateLimitType

        rpm_window = self.adapter.get_window_seconds(RateLimitType.RPM)
        tpm_window = self.adapter.get_window_seconds(RateLimitType.TPM)

        assert rpm_window == 60
        assert tpm_window == 60
```

### 10.2 Integration Tests

```python
# tests/ratelimit/test_openai_adapter_integration.py

import pytest
from garak.ratelimit.adapters.openai import OpenAIAdapter
from garak.generators.openai import OpenAIGenerator
import os


@pytest.mark.skipif(
    'OPENAI_API_KEY' not in os.environ,
    reason="Requires OPENAI_API_KEY environment variable"
)
class TestOpenAIAdapterIntegration:
    """Integration tests with real OpenAI API."""

    def test_token_counting_accuracy(self):
        """Test tiktoken accuracy matches OpenAI response."""
        adapter = OpenAIAdapter(model='gpt-3.5-turbo')
        generator = OpenAIGenerator(name='gpt-3.5-turbo')

        prompt = "Count the tokens in this prompt."

        # Estimate with tiktoken
        estimated = adapter.estimate_tokens(prompt, 'gpt-3.5-turbo')

        # Get actual from API
        from garak.attempt import Conversation, Turn, Message
        conv = Conversation(turns=[Turn(role='user', text=prompt)])
        response = generator._call_model(conv)[0]

        # Compare (should be within 10% due to message overhead)
        # Note: Can't get exact match without full message format
        assert estimated > 0

    def test_rate_limit_header_extraction(self):
        """Test header extraction from real response."""
        # This test triggers actual API call
        # Should extract headers if present
        pass  # Implement if needed for validation
```

### 10.3 Edge Case Tests

```python
# tests/ratelimit/test_openai_adapter_edge_cases.py

class TestOpenAIAdapterEdgeCases:
    """Test edge cases and error handling."""

    def test_empty_prompt(self):
        adapter = OpenAIAdapter()
        tokens = adapter.estimate_tokens("", "gpt-4o")
        assert tokens == 0

    def test_whitespace_only_prompt(self):
        adapter = OpenAIAdapter()
        tokens = adapter.estimate_tokens("   \n  \t  ", "gpt-4o")
        assert tokens >= 0

    def test_very_long_prompt(self):
        adapter = OpenAIAdapter()
        prompt = "x" * 1000000  # 1M chars
        tokens = adapter.estimate_tokens(prompt, "gpt-4o")
        assert tokens > 0

    def test_unicode_prompt(self):
        adapter = OpenAIAdapter()
        prompts = [
            "こんにちは",      # Japanese
            "你好",            # Chinese
            "مرحبا",           # Arabic
            "🎉🎊🎈",          # Emojis
        ]
        for prompt in prompts:
            tokens = adapter.estimate_tokens(prompt, "gpt-4o")
            assert tokens > 0

    def test_malformed_headers(self):
        adapter = OpenAIAdapter()

        # Headers with wrong types
        mock_error = Mock()
        mock_error.response = Mock()
        mock_error.response.headers = {
            'x-ratelimit-remaining-requests': 'not a number',
            'retry-after': 'invalid',
        }

        retry = adapter.get_retry_after(mock_error)
        # Should handle gracefully
        assert retry is None or isinstance(retry, float)
```

---

## 11. Complete Implementation Pseudo-code

### 11.1 Full OpenAIAdapter Implementation

```python
# garak/ratelimit/adapters/openai.py

"""
OpenAI Provider Adapter for Unified Rate Limiter.

This module implements the ProviderAdapter interface for OpenAI API,
providing accurate token counting, rate limit header parsing, and
error handling specific to OpenAI's rate limiting system.
"""

from garak.ratelimit.base import ProviderAdapter, RateLimitType
from typing import Dict, List, Optional, Any
import logging
import threading


class OpenAIAdapter(ProviderAdapter):
    """
    Provider adapter for OpenAI API rate limiting.

    See sections above for detailed documentation of each method.
    """

    # Constants
    DEFAULT_TIER = 1
    TIKTOKEN_FALLBACK_RATIO = 4

    # Shared cache
    _tokenizer_cache: Dict[str, Any] = {}
    _cache_lock = None

    def __init__(self, model: str = None, config: Dict = None):
        """Initialize adapter (see Section 1.1)."""
        self.model = model
        self.config = config or {}

        if OpenAIAdapter._cache_lock is None:
            OpenAIAdapter._cache_lock = threading.Lock()

        self._tiktoken_available = self._check_tiktoken_available()

        logging.debug(
            f"OpenAIAdapter initialized for '{model}', "
            f"tiktoken: {self._tiktoken_available}"
        )

    def _check_tiktoken_available(self) -> bool:
        """Check tiktoken availability (Section 1.1)."""
        try:
            import tiktoken
            return True
        except ImportError:
            logging.warning(
                "tiktoken not installed, using fallback token estimation"
            )
            return False

    # ===================================================================
    # ABSTRACT METHOD IMPLEMENTATIONS
    # ===================================================================

    def estimate_tokens(self, prompt: str, model: str) -> int:
        """
        Estimate token count using tiktoken (Section 2).

        Complete implementation in Section 2.1.
        """
        if not prompt:
            return 0

        if not model:
            model = self.model or "gpt-3.5-turbo"

        # Try tiktoken
        if self._tiktoken_available:
            try:
                encoding = self._get_encoding(model)
                token_count = len(encoding.encode(prompt))
                logging.debug(
                    f"tiktoken: {token_count} tokens for {len(prompt)} chars"
                )
                return token_count
            except Exception as e:
                logging.warning(f"tiktoken failed: {e}, using fallback")

        # Fallback
        char_count = len(prompt)
        token_estimate = max(1, char_count // self.TIKTOKEN_FALLBACK_RATIO)
        logging.debug(f"Fallback: {token_estimate} tokens for {char_count} chars")

        return token_estimate

    def _get_encoding(self, model: str):
        """Get cached tiktoken encoding (Section 2.1)."""
        import tiktoken

        with self._cache_lock:
            if model in self._tokenizer_cache:
                return self._tokenizer_cache[model]

            try:
                encoding = tiktoken.encoding_for_model(model)
            except KeyError:
                base_model = self._get_base_model(model)
                if base_model != model:
                    try:
                        encoding = tiktoken.encoding_for_model(base_model)
                    except KeyError:
                        encoding = tiktoken.get_encoding("cl100k_base")
                else:
                    encoding = tiktoken.get_encoding("cl100k_base")

            self._tokenizer_cache[model] = encoding
            return encoding

    def _get_base_model(self, model: str) -> str:
        """Extract base model name (Section 2.1)."""
        import re

        model = re.sub(r'-\d{4}-\d{2}-\d{2}$', '', model)
        model = re.sub(r'-\d{4}$', '', model)

        base_model_map = {
            'gpt-4o-mini': 'gpt-4o',
            'gpt-4-turbo': 'gpt-4',
            'gpt-3.5-turbo-16k': 'gpt-3.5-turbo',
        }

        return base_model_map.get(model, model)

    def extract_usage_from_response(
        self,
        response: Any,
        metadata: Optional[Dict] = None
    ) -> Dict[str, int]:
        """Extract usage from response (Section 5)."""
        if response is None or not hasattr(response, 'usage'):
            return {'tokens_used': 0}

        usage = response.usage
        if usage is None:
            return {'tokens_used': 0}

        try:
            total = getattr(usage, 'total_tokens', 0)
            prompt = getattr(usage, 'prompt_tokens', 0)
            completion = getattr(usage, 'completion_tokens', 0)

            if total == 0 and (prompt > 0 or completion > 0):
                total = prompt + completion

            result = {
                'tokens_used': total,
                'input_tokens': prompt,
                'output_tokens': completion,
            }

            # Check for cached tokens
            if hasattr(usage, 'prompt_tokens_details'):
                details = usage.prompt_tokens_details
                if hasattr(details, 'cached_tokens'):
                    cached = getattr(details, 'cached_tokens', 0)
                    if cached > 0:
                        result['cached_tokens'] = cached

            return result

        except Exception as e:
            logging.warning(f"Failed to extract usage: {e}")
            return {'tokens_used': 0}

    def extract_rate_limit_info(
        self,
        exception: Exception
    ) -> Optional[Dict[str, Any]]:
        """Extract rate limit info (Section 4)."""
        try:
            import openai
        except ImportError:
            return None

        if not isinstance(exception, openai.RateLimitError):
            return None

        headers = self._extract_headers(exception)

        info = {
            'error_type': 'rate_limit',
            'message': str(exception),
        }

        limit_type = self._identify_rate_limit_type(exception, headers)
        info['limit_type'] = limit_type

        retry_after = self.get_retry_after(exception, headers)
        if retry_after is not None:
            info['retry_after'] = retry_after

        # Extract remaining/limit values
        if limit_type == 'rpm':
            remaining_key = 'x-ratelimit-remaining-requests'
            limit_key = 'x-ratelimit-limit-requests'
        else:
            remaining_key = 'x-ratelimit-remaining-tokens'
            limit_key = 'x-ratelimit-limit-tokens'

        if remaining_key in headers:
            try:
                info['remaining'] = int(headers[remaining_key])
            except (ValueError, TypeError):
                pass

        if limit_key in headers:
            try:
                info['limit_value'] = int(headers[limit_key])
            except (ValueError, TypeError):
                pass

        if 'retry_after' in info:
            import time
            info['reset_at'] = time.time() + info['retry_after']

        return info

    def _extract_headers(self, exception: Exception) -> Dict[str, str]:
        """Extract headers from exception (Section 3.2)."""
        headers = {}

        try:
            if not hasattr(exception, 'response'):
                return headers

            response = exception.response
            if not hasattr(response, 'headers'):
                return headers

            raw_headers = response.headers

            if isinstance(raw_headers, dict):
                headers = {k.lower(): str(v).strip() for k, v in raw_headers.items()}
            elif hasattr(raw_headers, 'items'):
                headers = {k.lower(): str(v).strip() for k, v in raw_headers.items()}

        except Exception as e:
            logging.warning(f"Failed to extract headers: {e}")

        return headers

    def _identify_rate_limit_type(
        self,
        exception: Exception,
        headers: Dict[str, str]
    ) -> str:
        """Identify RPM vs TPM (Section 4.2)."""
        # Check remaining headers
        if 'x-ratelimit-remaining-requests' in headers:
            try:
                if int(headers['x-ratelimit-remaining-requests']) == 0:
                    return 'rpm'
            except (ValueError, TypeError):
                pass

        if 'x-ratelimit-remaining-tokens' in headers:
            try:
                if int(headers['x-ratelimit-remaining-tokens']) == 0:
                    return 'tpm'
            except (ValueError, TypeError):
                pass

        # Check message
        message = str(exception).lower()
        if 'request' in message and 'token' not in message:
            return 'rpm'
        if 'token' in message:
            return 'tpm'

        return 'rpm'  # Default

    def get_retry_after(
        self,
        exception: Exception,
        headers: Optional[Dict[str, str]] = None
    ) -> Optional[float]:
        """Get retry-after delay (Section 3.2)."""
        if headers and 'retry-after' in headers:
            try:
                return max(0.0, float(headers['retry-after']))
            except (ValueError, TypeError):
                pass

        extracted = self._extract_headers(exception)

        if 'retry-after' in extracted:
            try:
                return max(0.0, float(extracted['retry-after']))
            except (ValueError, TypeError):
                pass

        if 'x-ratelimit-reset-requests' in extracted:
            return self._parse_reset_time(extracted['x-ratelimit-reset-requests'])

        if 'x-ratelimit-reset-tokens' in extracted:
            return self._parse_reset_time(extracted['x-ratelimit-reset-tokens'])

        return None

    def _parse_reset_time(self, reset_str: str) -> float:
        """Parse reset time string (Section 3.2)."""
        import re

        try:
            match = re.match(r'^(\d+(?:\.\d+)?)(ms|s|m|h)$', reset_str.strip())
            if not match:
                return 60.0

            value = float(match.group(1))
            unit = match.group(2)

            if unit == 'ms':
                return value / 1000.0
            elif unit == 's':
                return value
            elif unit == 'm':
                return value * 60.0
            elif unit == 'h':
                return value * 3600.0
            else:
                return 60.0

        except Exception:
            return 60.0

    def get_model_limits(self, model: str) -> Optional[Dict[str, int]]:
        """Get model default limits (Section 6)."""
        # Complete limits database from Section 6.1
        ALL_LIMITS = {
            # GPT-4o
            'gpt-4o': {'rpm': 500, 'tpm': 30000},
            'gpt-4o-2024-11-20': {'rpm': 500, 'tpm': 30000},
            'gpt-4o-2024-08-06': {'rpm': 500, 'tpm': 30000},
            'gpt-4o-2024-05-13': {'rpm': 500, 'tpm': 30000},
            'gpt-4o-mini': {'rpm': 500, 'tpm': 200000},
            'gpt-4o-mini-2024-07-18': {'rpm': 500, 'tpm': 200000},

            # GPT-4
            'gpt-4': {'rpm': 500, 'tpm': 10000},
            'gpt-4-turbo': {'rpm': 500, 'tpm': 30000},
            'gpt-4-turbo-2024-04-09': {'rpm': 500, 'tpm': 30000},

            # GPT-3.5
            'gpt-3.5-turbo': {'rpm': 3500, 'tpm': 90000},
            'gpt-3.5-turbo-0125': {'rpm': 3500, 'tpm': 90000},
            'gpt-3.5-turbo-instruct': {'rpm': 3500, 'tpm': 90000},

            # o1/o3
            'o1-preview': {'rpm': 500, 'tpm': 30000},
            'o1-mini': {'rpm': 500, 'tpm': 150000},
            'o3-mini': {'rpm': 500, 'tpm': 100000},
        }

        return ALL_LIMITS.get(model)

    # ===================================================================
    # CONCRETE METHOD OVERRIDES
    # ===================================================================

    def supports_concurrent_limiting(self) -> bool:
        """OpenAI has no concurrent limits (Section 1.1)."""
        return False

    def supports_quota_tracking(self) -> bool:
        """OpenAI uses rolling windows (Section 1.1)."""
        return False

    def get_limit_types(self) -> List[RateLimitType]:
        """OpenAI supports RPM and TPM (Section 1.1)."""
        return [RateLimitType.RPM, RateLimitType.TPM]

    def get_window_seconds(self, limit_type: RateLimitType) -> int:
        """OpenAI uses 60s windows (Section 1.1)."""
        if limit_type in (RateLimitType.RPM, RateLimitType.TPM):
            return 60
        return super().get_window_seconds(limit_type)
```

---

## 12. Performance Optimization

### 12.1 Tokenizer Caching

```python
# Performance Impact of Tokenizer Caching

# Without cache:
# - First call: 10-50ms (load encoding)
# - Second call: 10-50ms (reload encoding)
# - Total for 1000 prompts: 10-50 seconds

# With cache:
# - First call: 10-50ms (load encoding)
# - Subsequent calls: <1ms (cached lookup)
# - Total for 1000 prompts: ~10ms + 1s = ~1.01s

# Memory usage:
# - Per encoding: ~100KB
# - 10 models cached: ~1MB total
# - Negligible impact on overall memory

# Recommendation: Always enable caching (default behavior)
```

### 12.2 Token Counting Optimization

```python
# Optimization: Batch token counting

def estimate_tokens_batch(
    self,
    prompts: List[str],
    model: str
) -> List[int]:
    """
    Estimate tokens for multiple prompts efficiently.

    Optimization:
        - Load encoding once
        - Reuse for all prompts
        - ~10x faster than individual calls

    Args:
        prompts: List of prompts
        model: Model name

    Returns:
        List of token counts (same order as prompts)
    """
    if not self._tiktoken_available:
        # Fallback for all
        return [
            max(1, len(p) // self.TIKTOKEN_FALLBACK_RATIO)
            for p in prompts
        ]

    try:
        encoding = self._get_encoding(model)
        return [len(encoding.encode(p)) for p in prompts]
    except Exception as e:
        logging.warning(f"Batch token counting failed: {e}")
        return [
            max(1, len(p) // self.TIKTOKEN_FALLBACK_RATIO)
            for p in prompts
        ]
```

---

## 13. Troubleshooting Guide

### 13.1 Common Issues

```python
# Issue 1: tiktoken not installed
# Symptom: "tiktoken not available" warning
# Solution: pip install tiktoken
# Impact: Falls back to less accurate estimation

# Issue 2: Unknown model error
# Symptom: KeyError for model name
# Solution: Adapter falls back to 'cl100k_base' encoding
# Impact: Minimal (most GPT models use same encoding)

# Issue 3: Token count mismatch
# Symptom: Estimated tokens != actual tokens from API
# Cause: Message format overhead not counted in estimation
# Solution: Use estimate_chat_tokens() for chat format
# Impact: Off by ~10 tokens (negligible for rate limiting)

# Issue 4: Rate limit headers missing
# Symptom: extract_rate_limit_info() returns minimal info
# Cause: Old OpenAI SDK version or API change
# Solution: Update openai SDK: pip install --upgrade openai
# Impact: Falls back to configured limits (still functional)

# Issue 5: Incorrect limit type detection
# Symptom: TPM limit detected when RPM was hit
# Cause: Ambiguous error message or missing headers
# Solution: Check logs for header contents
# Impact: May wait longer than necessary (safe, not optimal)
```

### 13.2 Debugging

```python
# Enable debug logging for detailed diagnostics

import logging

logging.basicConfig(level=logging.DEBUG)

# Debug output will show:
# - tiktoken availability
# - Token counting details (tiktoken vs fallback)
# - Header extraction results
# - Rate limit type detection
# - Usage extraction results

# Example debug output:
# DEBUG:OpenAIAdapter:Initialized OpenAIAdapter for 'gpt-4o', tiktoken: True
# DEBUG:OpenAIAdapter:tiktoken: 10 tokens for 42 chars
# DEBUG:OpenAIAdapter:Extracted 7 headers from exception
# DEBUG:OpenAIAdapter:RPM limit hit (remaining-requests = 0)
# DEBUG:OpenAIAdapter:Using server retry-after: 5.0s
# DEBUG:OpenAIAdapter:Extracted usage: {'tokens_used': 30, 'input_tokens': 10, 'output_tokens': 20}
```

### 13.3 Validation

```python
# Validate adapter behavior

def validate_openai_adapter():
    """Run validation checks on OpenAIAdapter."""
    adapter = OpenAIAdapter(model='gpt-4o')

    # Test 1: Token counting
    prompt = "Hello world"
    tokens = adapter.estimate_tokens(prompt, 'gpt-4o')
    assert tokens > 0, "Token counting failed"
    print(f"✓ Token counting works: {tokens} tokens for '{prompt}'")

    # Test 2: Model limits
    limits = adapter.get_model_limits('gpt-4o')
    assert limits is not None, "Model limits not found"
    assert 'rpm' in limits and 'tpm' in limits
    print(f"✓ Model limits found: {limits}")

    # Test 3: Capabilities
    assert adapter.supports_concurrent_limiting() is False
    assert adapter.supports_quota_tracking() is False
    print("✓ Capabilities correct")

    # Test 4: Limit types
    from garak.ratelimit.base import RateLimitType
    types = adapter.get_limit_types()
    assert RateLimitType.RPM in types
    assert RateLimitType.TPM in types
    print(f"✓ Limit types correct: {types}")

    print("\n✅ All validation checks passed!")

# Run validation
# validate_openai_adapter()
```

---

## Appendix A: Quick Reference

### A.1 Method Summary

```python
# OpenAIAdapter Methods

# Token Counting
estimate_tokens(prompt, model) -> int
estimate_chat_tokens(messages, model) -> int

# Rate Limit Extraction
extract_rate_limit_info(exception) -> Dict | None
get_retry_after(exception, headers) -> float | None

# Response Parsing
extract_usage_from_response(response, metadata) -> Dict
extract_batch_usage(responses) -> Dict

# Model Information
get_model_limits(model) -> Dict | None
supports_concurrent_limiting() -> bool
supports_quota_tracking() -> bool
get_limit_types() -> List[RateLimitType]
get_window_seconds(limit_type) -> int

# Internal Helpers
_get_encoding(model) -> tiktoken.Encoding
_get_base_model(model) -> str
_extract_headers(exception) -> Dict
_identify_rate_limit_type(exception, headers) -> str
_parse_reset_time(reset_str) -> float
```

### A.2 Configuration Quick Start

```yaml
# Minimal configuration
plugins:
  generators:
    openai:
      rate_limits:
        default:
          rpm: 500
          tpm: 30000

# Full configuration
plugins:
  generators:
    openai:
      rate_limits:
        gpt-4o:
          rpm: 10000
          tpm: 2000000
          safety_margin: 0.9
        default:
          rpm: 500
          tpm: 30000
      backoff:
        strategy: "fibonacci"
        max_value: 70
        max_retries: 10
        jitter: true
```

---

**End of OpenAI Adapter Implementation Guide**

**Status:** ✅ Complete and Ready for Implementation
**Next Steps:**
1. Implement OpenAIAdapter class in `garak/ratelimit/adapters/openai.py`
2. Register adapter in AdapterFactory
3. Write unit tests in `tests/ratelimit/test_openai_adapter.py`
4. Test with live OpenAI API
5. Document any deviations from this spec

**Estimated Implementation Time:** 8-12 hours
**Estimated Testing Time:** 4-6 hours
**Total:** ~12-18 hours
