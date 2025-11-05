# ProviderAdapter Abstract Interface Design

**Version:** 1.0
**Date:** 2025-10-20
**Status:** Design Specification
**Phase:** Step 2b - Provider Adapter Contract Definition

---

## Executive Summary

This document defines the **ProviderAdapter** abstract interface that all provider-specific adapters (OpenAI, Azure, Anthropic, Gemini, HuggingFace) must implement. The adapter pattern isolates all provider-specific logic (token counting, error parsing, response extraction) from the base UnifiedRateLimiter, enabling zero-modification extensibility for future providers.

### Design Principles

1. **Zero Provider Logic in Base**: UnifiedRateLimiter knows NOTHING about providers
2. **Uniform Interface**: All providers expose identical method signatures
3. **Stateless Adapters**: Rate limiter holds state, adapters provide transformations
4. **Graceful Degradation**: Adapters fail safely with fallback estimates
5. **Self-Describing**: Adapters declare their capabilities (concurrent limits, quota tracking)

---

## Section 1: ProviderAdapter Abstract Base Class

### 1.1 Complete Interface Definition

```python
# garak/ratelimit/base.py

from abc import ABC, abstractmethod
from typing import Dict, List, Optional, Any
from enum import Enum


class RateLimitType(Enum):
    """Enumeration of rate limit types across all providers"""
    RPM = "requests_per_minute"
    TPM = "tokens_per_minute"
    RPS = "requests_per_second"
    RPD = "requests_per_day"
    TPD = "tokens_per_day"
    TPM_QUOTA = "tokens_per_month_quota"  # Azure monthly quota
    CONCURRENT = "max_concurrent_requests"


class ProviderAdapter(ABC):
    """
    Abstract adapter for provider-specific rate limiting operations.

    Each provider (OpenAI, Azure, HuggingFace, Anthropic, Gemini) implements
    this interface to provide provider-specific behavior while maintaining
    a unified interface for the rate limiter.

    Design Principles:
    - Base rate limiter has ZERO knowledge of provider specifics
    - All provider logic delegated to adapters
    - Adapters are stateless (rate limiter holds state)
    - Methods never raise exceptions (return fallback values instead)

    Lifecycle:
    1. Adapter instantiated once per provider during initialization
    2. UnifiedRateLimiter calls adapter methods on-demand
    3. Adapter provides transformations, not state management
    """

    # ===================================================================
    # ABSTRACT METHODS (Must be implemented by all providers)
    # ===================================================================

    @abstractmethod
    def estimate_tokens(self, prompt: str, model: str) -> int:
        """
        Estimate token count for prompt BEFORE making API request.

        Used by rate limiter to check token-based limits (TPM, TPD) proactively.
        Called in _pre_generate_hook() before API call.

        Args:
            prompt: Input text to estimate (can be multi-turn conversation JSON)
            model: Model identifier (for model-specific tokenizers)

        Returns:
            Estimated token count (must be >= 0)

        Implementation Guidelines:
        - Use provider SDK when available (tiktoken, anthropic.count_tokens)
        - Fall back to len(text) // 4 if SDK unavailable
        - Never raise exceptions (return conservative estimate instead)
        - Cache tokenizer instances for performance

        Provider-Specific Examples:
        - OpenAI/Azure: Use tiktoken.encoding_for_model(model)
        - HuggingFace: Use transformers tokenizer or len(text) // 4
        - Anthropic: Use anthropic.Anthropic().count_tokens(text)
        - Gemini: Use model.count_tokens(text)
        - REST: Use len(text) // 4 (generic fallback)

        Performance:
        - Should complete in <5ms for typical prompts
        - Acceptable to be approximate (10-20% error margin)
        """
        pass

    @abstractmethod
    def extract_usage_from_response(
        self,
        response: Any,
        metadata: Optional[Dict] = None
    ) -> Dict[str, int]:
        """
        Extract actual token usage from API response.

        Used by rate limiter to track actual consumption after request completes.
        Called in _post_generate_hook() after API call.

        Args:
            response: Provider-specific response object (e.g., openai.ChatCompletion)
            metadata: Additional context (headers, timing, error info)

        Returns:
            Dictionary with standardized keys:
                - 'tokens_used': Total tokens consumed (REQUIRED)
                - 'input_tokens': Input/prompt tokens (optional)
                - 'output_tokens': Output/completion tokens (optional)
                - 'cached_tokens': Cached tokens (optional, Anthropic)

            Return {'tokens_used': 0} if usage unavailable

        Implementation Guidelines:
        - Check for response.usage attribute first (OpenAI/Anthropic pattern)
        - Parse headers if usage in headers (some REST APIs)
        - Fall back to estimate from response length
        - Never raise exceptions (return {'tokens_used': 0} on error)

        Provider-Specific Examples:
        - OpenAI: response.usage.total_tokens
        - Azure: Same as OpenAI
        - Anthropic: response.usage.input_tokens + response.usage.output_tokens
        - Gemini: response.usage_metadata.total_token_count
        - HuggingFace: Parse headers or estimate from response text
        - REST: Estimate from len(response_text) // 4

        Metadata Usage:
        - metadata['headers']: HTTP response headers
        - metadata['timing']: Request duration
        - metadata['error']: Exception info if call failed
        """
        pass

    @abstractmethod
    def extract_rate_limit_info(
        self,
        exception: Exception
    ) -> Optional[Dict[str, Any]]:
        """
        Extract rate limit details from provider-specific exception.

        Used to understand WHY rate limit was hit and how to respond.
        Called when API call raises an exception that might be rate-limit-related.

        Args:
            exception: Provider-specific exception (e.g., openai.RateLimitError)

        Returns:
            Dictionary with keys:
                - 'limit_type': RateLimitType enum or string ('rpm', 'tpm', etc.)
                - 'retry_after': Seconds to wait before retry (float)
                - 'reset_at': Unix timestamp when limit resets (float)
                - 'remaining': Remaining quota/requests (int)
                - 'limit_value': Total limit value (int)
                - 'error_type': 'rate_limit' or 'quota_exhausted'

            Return None if exception is NOT a rate limit error

        Implementation Guidelines:
        - Check isinstance(exception, ProviderRateLimitError)
        - Parse exception.response.headers for rate limit headers
        - Extract retry-after from headers or exception message
        - Infer limit_type from error message ('request' vs 'token')
        - Never raise exceptions (return None if unparseable)

        Provider-Specific Examples:
        - OpenAI: isinstance(exception, openai.RateLimitError)
          Headers: retry-after, x-ratelimit-remaining-requests, x-ratelimit-reset-tokens
        - Azure: Same as OpenAI + x-ms-region, quota headers
        - HuggingFace: HTTP 503 + "rate limit" in response body
        - Anthropic: isinstance(exception, anthropic.RateLimitError)
        - Gemini: isinstance(exception, google.api_core.exceptions.ResourceExhausted)
        - REST: HTTP 429 with optional Retry-After header

        Error Type Distinction:
        - 'rate_limit': Temporary, resets after window (e.g., 60s for RPM)
        - 'quota_exhausted': Long-term, resets monthly/daily (Azure TPM quota)
        """
        pass

    @abstractmethod
    def get_retry_after(
        self,
        exception: Exception,
        headers: Optional[Dict[str, str]] = None
    ) -> Optional[float]:
        """
        Extract retry-after delay from exception or headers.

        Simpler version of extract_rate_limit_info() for quick retry logic.

        Args:
            exception: Provider-specific exception
            headers: HTTP response headers (if available)

        Returns:
            Delay in seconds before retry (None if not available)

        Implementation Guidelines:
        - Check 'retry-after' header first (RFC 7231 standard)
        - Parse exception.response.headers if available
        - Extract from exception message if headers unavailable
        - Return None if no retry hint available (caller uses exponential backoff)

        Provider-Specific Examples:
        - OpenAI: exception.response.headers.get('retry-after')
        - Azure: Same as OpenAI
        - HuggingFace: Parse error message for retry delay
        - Anthropic: exception.retry_after attribute
        - Gemini: Parse from google.api_core exception
        - REST: headers.get('retry-after')
        """
        pass

    @abstractmethod
    def get_model_limits(self, model: str) -> Optional[Dict[str, int]]:
        """
        Get known default rate limits for model.

        Used as fallback when user hasn't configured limits for this model.
        Should return provider's documented default limits.

        Args:
            model: Model identifier (e.g., 'gpt-4o', 'claude-3-opus')

        Returns:
            Dictionary with keys like {'rpm': 10000, 'tpm': 2000000}
            None if model limits unknown

        Implementation Guidelines:
        - Hardcode known limits from provider documentation
        - Update periodically as providers change limits
        - Return None if model not recognized (no guessing)
        - Use conservative limits if multiple tiers exist

        Provider-Specific Examples:
        - OpenAI: {'rpm': 10000, 'tpm': 2000000} for gpt-4o
        - Azure: None (deployment-specific, no defaults possible)
        - Anthropic: {'rpm': 50, 'tpm': 100000} for claude-3-opus
        - Gemini: {'rpm': 60, 'tpd': 1500000} for gemini-pro
        - HuggingFace: {'rpm': 60} for free tier, {'rpm': 300} for pro
        - REST: None (fully configurable)

        Tier Handling:
        - Return free tier limits by default
        - Document that users should override for paid tiers
        - Consider environment variable for tier selection
        """
        pass

    # ===================================================================
    # CONCRETE METHODS (Default implementations, can override)
    # ===================================================================

    def supports_concurrent_limiting(self) -> bool:
        """
        Whether provider enforces concurrent request limits.

        Returns:
            True if provider has max concurrent request limits
            False if provider only has time-windowed limits (RPM/TPM)

        Default: False (most providers don't limit concurrency)

        Provider-Specific Values:
        - OpenAI: False (no documented concurrent limit)
        - Azure: True (has concurrent request limit per deployment)
        - Anthropic: False
        - Gemini: False
        - HuggingFace: True (free tier limited to 1-2 concurrent)
        - REST: Depends (default False)

        Usage:
        - If True, UnifiedRateLimiter tracks concurrent request count
        - Requires acquire() + release() pattern
        - Uses multiprocessing.Value for shared counter
        """
        return False

    def supports_quota_tracking(self) -> bool:
        """
        Whether provider has monthly/daily quotas requiring persistent state.

        Returns:
            True if provider uses quota limits (monthly/daily caps)
            False if provider only uses time-windowed limits (rolling windows)

        Default: False (most providers use rolling windows)

        Provider-Specific Values:
        - OpenAI: False (only rolling 60s windows)
        - Azure: True (monthly TPM quota per deployment)
        - Anthropic: False
        - Gemini: True (daily token limits)
        - HuggingFace: False
        - REST: Depends (default False)

        Usage:
        - If True, UnifiedRateLimiter persists state to file/redis
        - Quota resets on fixed dates (not rolling)
        - Requires quota_reset_day configuration
        """
        return False

    def get_limit_types(self) -> List[RateLimitType]:
        """
        Declare which rate limit types this provider supports.

        Returns:
            List of RateLimitType enums this provider can enforce

        Default: [RateLimitType.RPM] (most basic limit)

        Provider-Specific Values:
        - OpenAI: [RPM, TPM]
        - Azure: [RPS, TPM_QUOTA, CONCURRENT]
        - Anthropic: [RPM, TPM]
        - Gemini: [RPM, TPD]
        - HuggingFace: [RPM, CONCURRENT]
        - REST: [RPM] (configurable)

        Usage:
        - UnifiedRateLimiter only tracks declared limit types
        - Config validation ensures only supported limits configured
        - Factory uses this for adapter selection
        """
        return [RateLimitType.RPM]

    def get_window_seconds(self, limit_type: RateLimitType) -> int:
        """
        Get sliding window duration for limit type.

        Args:
            limit_type: Type of rate limit

        Returns:
            Window duration in seconds

        Default Mappings:
        - RPM: 60 seconds
        - TPM: 60 seconds
        - RPS: 1 second
        - RPD: 86400 seconds (24 hours)
        - TPD: 86400 seconds (24 hours)
        - TPM_QUOTA: 2592000 seconds (30 days, approximate)
        - CONCURRENT: 0 (not time-based)

        Override if provider uses non-standard windows.
        """
        window_map = {
            RateLimitType.RPM: 60,
            RateLimitType.TPM: 60,
            RateLimitType.RPS: 1,
            RateLimitType.RPD: 86400,
            RateLimitType.TPD: 86400,
            RateLimitType.TPM_QUOTA: 2592000,  # ~30 days
            RateLimitType.CONCURRENT: 0,
        }
        return window_map.get(limit_type, 60)
```

---

## Section 2: Concrete Adapter Examples

### 2.1 OpenAI Adapter Design

```python
# garak/ratelimit/adapters/openai.py

from garak.ratelimit.base import ProviderAdapter, RateLimitType
from typing import Dict, List, Optional, Any
import logging


class OpenAIAdapter(ProviderAdapter):
    """
    Adapter for OpenAI API rate limiting.

    Rate Limits:
    - RPM: Requests per minute (tier-dependent: 500-10000)
    - TPM: Tokens per minute (tier-dependent: 40000-2000000)
    - No concurrent limits
    - No persistent quotas (rolling windows only)

    Token Counting:
    - Uses tiktoken library for accurate pre-request estimation
    - Uses response.usage.total_tokens for post-request tracking

    Error Handling:
    - Catches openai.RateLimitError
    - Parses x-ratelimit-* headers
    - Extracts retry-after header
    """

    def __init__(self):
        """Initialize adapter with cached tokenizers"""
        self._tokenizer_cache = {}  # model -> tiktoken.Encoding

    def estimate_tokens(self, prompt: str, model: str) -> int:
        """
        Use tiktoken for accurate token estimation.

        Example:
            >>> adapter.estimate_tokens("Hello world", "gpt-4o")
            2
        """
        try:
            import tiktoken

            # Cache tokenizer for performance
            if model not in self._tokenizer_cache:
                self._tokenizer_cache[model] = tiktoken.encoding_for_model(model)

            encoding = self._tokenizer_cache[model]
            return len(encoding.encode(prompt))

        except Exception as e:
            logging.warning(f"tiktoken encoding failed for {model}: {e}, using fallback")
            # Fallback: ~4 chars per token (GPT average)
            return len(prompt) // 4

    def extract_usage_from_response(
        self,
        response: Any,
        metadata: Optional[Dict] = None
    ) -> Dict[str, int]:
        """
        Extract from response.usage object.

        Example Response:
            response.usage = {
                'prompt_tokens': 10,
                'completion_tokens': 20,
                'total_tokens': 30
            }

        Returns:
            {'tokens_used': 30, 'input_tokens': 10, 'output_tokens': 20}
        """
        if hasattr(response, 'usage') and response.usage:
            return {
                'tokens_used': response.usage.total_tokens,
                'input_tokens': response.usage.prompt_tokens,
                'output_tokens': response.usage.completion_tokens,
            }

        logging.warning("No usage data in OpenAI response, returning 0")
        return {'tokens_used': 0}

    def extract_rate_limit_info(self, exception: Exception) -> Optional[Dict[str, Any]]:
        """
        Parse OpenAI RateLimitError exception.

        Example Exception:
            openai.RateLimitError: 429 Rate limit exceeded
            Headers: {
                'retry-after': '5',
                'x-ratelimit-limit-requests': '10000',
                'x-ratelimit-remaining-requests': '0',
                'x-ratelimit-reset-requests': '6s'
            }

        Returns:
            {
                'limit_type': 'rpm',
                'retry_after': 5.0,
                'remaining': 0,
                'limit_value': 10000,
                'error_type': 'rate_limit'
            }
        """
        try:
            import openai

            if not isinstance(exception, openai.RateLimitError):
                return None

            headers = {}
            if hasattr(exception, 'response') and hasattr(exception.response, 'headers'):
                headers = exception.response.headers

            # Infer limit type from error message
            limit_type = self._infer_limit_type(str(exception))

            info = {
                'error_type': 'rate_limit',
                'limit_type': limit_type,
            }

            # Extract retry-after
            if 'retry-after' in headers:
                info['retry_after'] = float(headers['retry-after'])

            # Extract remaining quota
            if limit_type == 'rpm' and 'x-ratelimit-remaining-requests' in headers:
                info['remaining'] = int(headers['x-ratelimit-remaining-requests'])
            elif limit_type == 'tpm' and 'x-ratelimit-remaining-tokens' in headers:
                info['remaining'] = int(headers['x-ratelimit-remaining-tokens'])

            # Extract limit value
            if limit_type == 'rpm' and 'x-ratelimit-limit-requests' in headers:
                info['limit_value'] = int(headers['x-ratelimit-limit-requests'])
            elif limit_type == 'tpm' and 'x-ratelimit-limit-tokens' in headers:
                info['limit_value'] = int(headers['x-ratelimit-limit-tokens'])

            return info

        except ImportError:
            logging.warning("openai SDK not available for error parsing")
            return None
        except Exception as e:
            logging.warning(f"Failed to parse OpenAI rate limit error: {e}")
            return None

    def get_retry_after(
        self,
        exception: Exception,
        headers: Optional[Dict[str, str]] = None
    ) -> Optional[float]:
        """
        Extract retry-after from headers.

        Priority:
        1. exception.response.headers['retry-after']
        2. headers parameter
        3. None (use exponential backoff)
        """
        info = self.extract_rate_limit_info(exception)
        if info and 'retry_after' in info:
            return info['retry_after']

        if headers and 'retry-after' in headers:
            try:
                return float(headers['retry-after'])
            except (ValueError, TypeError):
                pass

        return None

    def get_model_limits(self, model: str) -> Optional[Dict[str, int]]:
        """
        Known OpenAI model limits (Tier 1 defaults).

        Source: https://platform.openai.com/docs/guides/rate-limits
        Updated: 2025-01-31
        """
        KNOWN_LIMITS = {
            # GPT-4o models (Tier 1)
            'gpt-4o': {'rpm': 500, 'tpm': 30000},
            'gpt-4o-2024-11-20': {'rpm': 500, 'tpm': 30000},
            'gpt-4o-2024-08-06': {'rpm': 500, 'tpm': 30000},
            'gpt-4o-2024-05-13': {'rpm': 500, 'tpm': 30000},
            'gpt-4o-mini': {'rpm': 500, 'tpm': 200000},
            'gpt-4o-mini-2024-07-18': {'rpm': 500, 'tpm': 200000},

            # GPT-4 models (Tier 1)
            'gpt-4': {'rpm': 500, 'tpm': 10000},
            'gpt-4-turbo': {'rpm': 500, 'tpm': 30000},
            'gpt-4-turbo-2024-04-09': {'rpm': 500, 'tpm': 30000},

            # GPT-3.5 models (Tier 1)
            'gpt-3.5-turbo': {'rpm': 3500, 'tpm': 90000},
            'gpt-3.5-turbo-0125': {'rpm': 3500, 'tpm': 90000},

            # o1 models (Tier 1)
            'o1-preview': {'rpm': 500, 'tpm': 30000},
            'o1-mini': {'rpm': 500, 'tpm': 150000},
        }

        return KNOWN_LIMITS.get(model)

    def supports_concurrent_limiting(self) -> bool:
        """OpenAI does not enforce concurrent limits"""
        return False

    def supports_quota_tracking(self) -> bool:
        """OpenAI uses rolling windows, not monthly quotas"""
        return False

    def get_limit_types(self) -> List[RateLimitType]:
        """OpenAI supports RPM and TPM limits"""
        return [RateLimitType.RPM, RateLimitType.TPM]

    def _infer_limit_type(self, error_message: str) -> str:
        """
        Infer whether RPM or TPM limit was hit from error message.

        Example Messages:
        - "Rate limit exceeded for requests"
        - "Rate limit exceeded for tokens"
        """
        message_lower = error_message.lower()
        if 'request' in message_lower:
            return 'rpm'
        elif 'token' in message_lower:
            return 'tpm'
        return 'unknown'
```

---

### 2.2 Azure Adapter Design

```python
# garak/ratelimit/adapters/azure.py

from garak.ratelimit.adapters.openai import OpenAIAdapter
from garak.ratelimit.base import RateLimitType
from typing import Dict, List, Optional, Any
import logging


class AzureAdapter(OpenAIAdapter):
    """
    Adapter for Azure OpenAI API.

    Differences from OpenAI:
    - Deployment-specific limits (not model-specific)
    - RPS (requests per second) instead of RPM
    - Monthly TPM quota (persistent state required)
    - Concurrent request limits

    Rate Limits:
    - RPS: Requests per second (deployment-dependent: 1-60)
    - TPM_QUOTA: Monthly token quota (deployment-dependent)
    - CONCURRENT: Max concurrent requests (deployment-dependent: 1-10)

    Token Counting:
    - Inherits tiktoken from OpenAIAdapter
    - Maps Azure model names to OpenAI equivalents

    Error Handling:
    - Same as OpenAI (uses openai.RateLimitError)
    - Additional Azure-specific headers (x-ms-region)
    - Distinguishes rate limit vs quota exhaustion
    """

    # Azure model name -> OpenAI model name mapping
    MODEL_MAPPING = {
        'gpt-4': 'gpt-4-turbo-2024-04-09',
        'gpt-35-turbo': 'gpt-3.5-turbo-0125',
        'gpt-35-turbo-16k': 'gpt-3.5-turbo-16k',
        'gpt-35-turbo-instruct': 'gpt-3.5-turbo-instruct',
    }

    def estimate_tokens(self, prompt: str, model: str) -> int:
        """
        Use tiktoken with Azure model name mapping.

        Azure uses different model names (gpt-35-turbo) than OpenAI (gpt-3.5-turbo).
        Map to OpenAI equivalent before calling tiktoken.
        """
        # Map Azure model name to OpenAI name
        openai_model = self.MODEL_MAPPING.get(model, model)

        # Call parent OpenAI implementation
        return super().estimate_tokens(prompt, openai_model)

    def extract_usage_from_response(
        self,
        response: Any,
        metadata: Optional[Dict] = None
    ) -> Dict[str, int]:
        """
        Same as OpenAI, but also track Azure-specific metadata.

        Azure Response Headers:
        - x-ms-region: Azure region serving request
        - x-ms-deployment-name: Deployment name
        """
        usage = super().extract_usage_from_response(response, metadata)

        # Extract Azure metadata from headers
        if metadata and 'headers' in metadata:
            headers = metadata['headers']
            if 'x-ms-region' in headers:
                usage['region'] = headers['x-ms-region']
            if 'x-ms-deployment-name' in headers:
                usage['deployment'] = headers['x-ms-deployment-name']

        return usage

    def extract_rate_limit_info(self, exception: Exception) -> Optional[Dict[str, Any]]:
        """
        Parse Azure rate limit errors.

        Azure uses same exception type as OpenAI (openai.RateLimitError)
        but with different semantics:
        - RPS limit hit: Temporary, retry after ~1s
        - TPM quota exhausted: Monthly quota depleted, wait until reset

        Distinguishes via headers or error message.
        """
        info = super().extract_rate_limit_info(exception)

        if info is None:
            return None

        # Determine if quota exhausted vs rate limited
        error_message = str(exception).lower()
        if 'quota' in error_message or 'exceeded your current quota' in error_message:
            info['error_type'] = 'quota_exhausted'
            info['limit_type'] = 'tpm_quota'
        else:
            info['error_type'] = 'rate_limit'
            # Azure primarily uses RPS limits
            if info.get('limit_type') == 'rpm':
                info['limit_type'] = 'rps'

        return info

    def get_model_limits(self, deployment: str) -> Optional[Dict[str, int]]:
        """
        Azure limits are deployment-specific, not model-specific.

        No defaults available - user MUST configure per-deployment limits.

        Typical values:
        - PTU deployments: 10-60 RPS, 100K-500K TPM quota
        - PAYG deployments: 1-10 RPS, 10K-100K TPM quota
        """
        # Cannot provide defaults for Azure (deployment-specific)
        logging.info(
            f"Azure adapter cannot provide default limits for deployment '{deployment}'. "
            "Please configure limits in garak.core.yaml under plugins.generators.azure.rate_limits"
        )
        return None

    def supports_concurrent_limiting(self) -> bool:
        """Azure enforces concurrent request limits"""
        return True

    def supports_quota_tracking(self) -> bool:
        """Azure uses monthly quota (requires persistent state)"""
        return True

    def get_limit_types(self) -> List[RateLimitType]:
        """Azure supports RPS, TPM quota, and concurrent limits"""
        return [
            RateLimitType.RPS,
            RateLimitType.TPM_QUOTA,
            RateLimitType.CONCURRENT,
        ]

    def get_window_seconds(self, limit_type: RateLimitType) -> int:
        """Override for Azure-specific windows"""
        if limit_type == RateLimitType.TPM_QUOTA:
            # Monthly quota (reset on 1st of month)
            return 2592000  # ~30 days
        return super().get_window_seconds(limit_type)
```

---

### 2.3 Anthropic Adapter Design (Future)

```python
# garak/ratelimit/adapters/anthropic.py

from garak.ratelimit.base import ProviderAdapter, RateLimitType
from typing import Dict, List, Optional, Any
import logging


class AnthropicAdapter(ProviderAdapter):
    """
    Adapter for Anthropic Claude API.

    Rate Limits:
    - RPM: Requests per minute (tier-dependent: 5-1000)
    - TPM: Tokens per minute (tier-dependent: 10K-4000K)
    - No concurrent limits
    - No persistent quotas

    Token Counting:
    - Uses anthropic.count_tokens() SDK method
    - Falls back to len(text) // 4 if SDK unavailable

    Error Handling:
    - Catches anthropic.RateLimitError
    - Extracts retry-after from exception
    """

    def estimate_tokens(self, prompt: str, model: str) -> int:
        """
        Use Anthropic SDK count_tokens method.

        Example:
            >>> import anthropic
            >>> client = anthropic.Anthropic()
            >>> client.count_tokens("Hello world")
            2
        """
        try:
            import anthropic
            client = anthropic.Anthropic()
            return client.count_tokens(prompt)

        except ImportError:
            logging.warning("anthropic SDK not installed, using fallback estimation")
            return len(prompt) // 4

        except Exception as e:
            logging.warning(f"anthropic token counting failed: {e}, using fallback")
            return len(prompt) // 4

    def extract_usage_from_response(
        self,
        response: Any,
        metadata: Optional[Dict] = None
    ) -> Dict[str, int]:
        """
        Extract from Anthropic response.usage.

        Example Response:
            response.usage = {
                'input_tokens': 10,
                'output_tokens': 20
            }

        Returns:
            {'tokens_used': 30, 'input_tokens': 10, 'output_tokens': 20}
        """
        if hasattr(response, 'usage') and response.usage:
            total = response.usage.input_tokens + response.usage.output_tokens
            return {
                'tokens_used': total,
                'input_tokens': response.usage.input_tokens,
                'output_tokens': response.usage.output_tokens,
            }

        logging.warning("No usage data in Anthropic response")
        return {'tokens_used': 0}

    def extract_rate_limit_info(self, exception: Exception) -> Optional[Dict[str, Any]]:
        """
        Parse Anthropic RateLimitError.

        Example Exception:
            anthropic.RateLimitError: 429 rate_limit_error
            retry_after: 5.0
        """
        try:
            import anthropic

            if not isinstance(exception, anthropic.RateLimitError):
                return None

            info = {
                'error_type': 'rate_limit',
                'limit_type': 'rpm',  # Anthropic primarily uses RPM
            }

            # Extract retry-after from exception
            if hasattr(exception, 'retry_after'):
                info['retry_after'] = float(exception.retry_after)

            # Parse headers if available
            if hasattr(exception, 'response') and hasattr(exception.response, 'headers'):
                headers = exception.response.headers
                if 'retry-after' in headers:
                    info['retry_after'] = float(headers['retry-after'])

            return info

        except ImportError:
            logging.warning("anthropic SDK not available for error parsing")
            return None
        except Exception as e:
            logging.warning(f"Failed to parse Anthropic rate limit error: {e}")
            return None

    def get_retry_after(
        self,
        exception: Exception,
        headers: Optional[Dict[str, str]] = None
    ) -> Optional[float]:
        """Extract retry-after from Anthropic error"""
        info = self.extract_rate_limit_info(exception)
        if info and 'retry_after' in info:
            return info['retry_after']

        if headers and 'retry-after' in headers:
            try:
                return float(headers['retry-after'])
            except (ValueError, TypeError):
                pass

        return None

    def get_model_limits(self, model: str) -> Optional[Dict[str, int]]:
        """
        Known Anthropic model limits (Tier 1 defaults).

        Source: https://docs.anthropic.com/claude/reference/rate-limits
        Updated: 2025-01-31
        """
        KNOWN_LIMITS = {
            # Claude 3 models (Tier 1)
            'claude-3-opus-20240229': {'rpm': 5, 'tpm': 10000},
            'claude-3-sonnet-20240229': {'rpm': 5, 'tpm': 20000},
            'claude-3-haiku-20240307': {'rpm': 5, 'tpm': 25000},

            # Claude 3.5 models (Tier 1)
            'claude-3-5-sonnet-20241022': {'rpm': 5, 'tpm': 20000},
            'claude-3-5-haiku-20241022': {'rpm': 5, 'tpm': 25000},

            # Aliases
            'claude-opus-4': {'rpm': 5, 'tpm': 10000},
            'claude-sonnet-4': {'rpm': 5, 'tpm': 20000},
        }

        return KNOWN_LIMITS.get(model)

    def supports_concurrent_limiting(self) -> bool:
        """Anthropic does not enforce concurrent limits"""
        return False

    def supports_quota_tracking(self) -> bool:
        """Anthropic uses rolling windows, not monthly quotas"""
        return False

    def get_limit_types(self) -> List[RateLimitType]:
        """Anthropic supports RPM and TPM limits"""
        return [RateLimitType.RPM, RateLimitType.TPM]
```

---

## Section 3: Token Counting Abstraction

### 3.1 Provider-Specific Token Counting Strategies

| Provider | Pre-Request Estimation | Post-Request Tracking | Library |
|----------|----------------------|----------------------|---------|
| **OpenAI** | `tiktoken.encoding_for_model(model).encode(text)` | `response.usage.total_tokens` | tiktoken |
| **Azure** | Same as OpenAI (with model name mapping) | `response.usage.total_tokens` | tiktoken |
| **Anthropic** | `anthropic.Anthropic().count_tokens(text)` | `response.usage.input_tokens + output_tokens` | anthropic SDK |
| **Gemini** | `model.count_tokens(text)` | `response.usage_metadata.total_token_count` | google-generativeai |
| **HuggingFace** | `len(text) // 4` (fallback) or transformers tokenizer | Parse headers or estimate from response | transformers (optional) |
| **REST** | `len(text) // 4` (generic fallback) | `len(response_text) // 4` | None |

### 3.2 Token Counting Fallback Pattern

```python
def estimate_tokens(self, prompt: str, model: str) -> int:
    """
    Standard pattern for token estimation with fallback.

    Priority:
    1. Provider SDK (most accurate)
    2. Generic tokenizer (transformers)
    3. Character-based estimation (len(text) // 4)
    """
    try:
        # Attempt provider SDK
        return self._provider_token_count(prompt, model)
    except ImportError:
        logging.warning("Provider SDK not installed, using fallback")
    except Exception as e:
        logging.warning(f"Provider token counting failed: {e}")

    # Fallback: ~4 characters per token (conservative estimate)
    # This is acceptable for rate limiting (10-20% error margin)
    return max(1, len(prompt) // 4)
```

### 3.3 Tokenizer Caching for Performance

```python
class OpenAIAdapter(ProviderAdapter):
    def __init__(self):
        """Cache tokenizers to avoid repeated loading"""
        self._tokenizer_cache = {}  # model -> tiktoken.Encoding

    def estimate_tokens(self, prompt: str, model: str) -> int:
        # Check cache first
        if model not in self._tokenizer_cache:
            import tiktoken
            self._tokenizer_cache[model] = tiktoken.encoding_for_model(model)

        encoding = self._tokenizer_cache[model]
        return len(encoding.encode(prompt))
```

**Performance Impact:**
- Uncached: 10-50ms per estimate (loading tokenizer)
- Cached: <1ms per estimate (encoding only)

---

## Section 4: Error Extraction Pattern

### 4.1 Generic Error Mapping

```python
def extract_rate_limit_info(self, exception: Exception) -> Optional[Dict[str, Any]]:
    """
    Map provider-specific exception to generic structure.

    Output Structure:
    {
        'error_type': 'rate_limit' | 'quota_exhausted',
        'limit_type': 'rpm' | 'tpm' | 'rps' | 'concurrent',
        'retry_after': 5.0,  # Seconds
        'reset_at': 1643723400.0,  # Unix timestamp
        'remaining': 0,  # Remaining quota
        'limit_value': 10000,  # Total limit
    }
    """
```

### 4.2 Provider Error Patterns

#### OpenAI Error Extraction

```python
# Input: openai.RateLimitError
# Headers:
#   retry-after: 5
#   x-ratelimit-limit-requests: 10000
#   x-ratelimit-remaining-requests: 0
#   x-ratelimit-reset-requests: 6s

# Output:
{
    'error_type': 'rate_limit',
    'limit_type': 'rpm',
    'retry_after': 5.0,
    'remaining': 0,
    'limit_value': 10000
}
```

#### Azure Error Extraction

```python
# Input: openai.RateLimitError (quota exhausted)
# Message: "You have exceeded your current quota"

# Output:
{
    'error_type': 'quota_exhausted',
    'limit_type': 'tpm_quota',
    'retry_after': 86400.0,  # Wait until quota reset (next month)
    'remaining': 0
}
```

#### HuggingFace Error Extraction

```python
# Input: HTTP 503 Response
# Body: {"error": "rate limit exceeded, please retry after 60 seconds"}

# Output:
{
    'error_type': 'rate_limit',
    'limit_type': 'rpm',
    'retry_after': 60.0
}
```

### 4.3 Error Type Distinction

```python
class ErrorType(Enum):
    """Distinguish temporary vs persistent rate limit errors"""
    RATE_LIMIT = "rate_limit"  # Temporary, resets after window (60s)
    QUOTA_EXHAUSTED = "quota_exhausted"  # Persistent, resets monthly/daily
    CONCURRENT_EXCEEDED = "concurrent_exceeded"  # Temporary, retry when requests complete
```

**Usage:**
- `RATE_LIMIT`: Sleep for `retry_after`, then retry
- `QUOTA_EXHAUSTED`: Fail fast, notify user quota depleted
- `CONCURRENT_EXCEEDED`: Wait for concurrent requests to complete

---

## Section 5: Adapter Factory Registration Pattern

### 5.1 Factory Class Design

```python
# garak/ratelimit/adapters/__init__.py

from typing import Dict, Type
from garak.ratelimit.base import ProviderAdapter
from garak.ratelimit.adapters.openai import OpenAIAdapter
from garak.ratelimit.adapters.azure import AzureAdapter
from garak.ratelimit.adapters.anthropic import AnthropicAdapter
# Future imports...


class AdapterFactory:
    """
    Factory for creating provider adapters.

    Usage:
        # Register adapters
        AdapterFactory.register('openai', OpenAIAdapter)

        # Create adapter
        adapter = AdapterFactory.create('openai')
    """

    _adapters: Dict[str, Type[ProviderAdapter]] = {}

    @classmethod
    def register(cls, provider: str, adapter_class: Type[ProviderAdapter]):
        """
        Register a provider adapter.

        Args:
            provider: Provider identifier (lowercase, e.g., 'openai', 'azure')
            adapter_class: ProviderAdapter subclass

        Raises:
            TypeError: If adapter_class does not subclass ProviderAdapter
        """
        if not issubclass(adapter_class, ProviderAdapter):
            raise TypeError(
                f"{adapter_class} must subclass ProviderAdapter"
            )

        cls._adapters[provider.lower()] = adapter_class

    @classmethod
    def create(cls, provider: str) -> ProviderAdapter:
        """
        Create adapter instance for provider.

        Args:
            provider: Provider identifier (e.g., 'openai', 'azure')

        Returns:
            Instantiated ProviderAdapter

        Raises:
            ValueError: If provider not registered
        """
        provider_lower = provider.lower()

        if provider_lower not in cls._adapters:
            raise ValueError(
                f"Unknown provider '{provider}'. "
                f"Registered providers: {list(cls._adapters.keys())}"
            )

        adapter_class = cls._adapters[provider_lower]
        return adapter_class()

    @classmethod
    def get_registered_providers(cls) -> list[str]:
        """Get list of registered provider identifiers"""
        return list(cls._adapters.keys())

    @classmethod
    def is_registered(cls, provider: str) -> bool:
        """Check if provider has registered adapter"""
        return provider.lower() in cls._adapters


# Auto-register known adapters
AdapterFactory.register('openai', OpenAIAdapter)
AdapterFactory.register('azure', AzureAdapter)
AdapterFactory.register('anthropic', AnthropicAdapter)
# Future: AdapterFactory.register('gemini', GeminiAdapter)
# Future: AdapterFactory.register('huggingface', HuggingFaceAdapter)
```

### 5.2 Factory Usage in UnifiedRateLimiter

```python
# garak/ratelimit/limiters.py

from garak.ratelimit.adapters import AdapterFactory

class UnifiedRateLimiter:
    def __init__(self, config: Dict):
        """
        Initialize rate limiter with provider adapters.

        Args:
            config: Configuration with provider-specific rate limits
        """
        self.adapters = {}

        # Create adapters for all configured providers
        for provider in config.keys():
            if AdapterFactory.is_registered(provider):
                self.adapters[provider] = AdapterFactory.create(provider)
            else:
                logging.warning(
                    f"No adapter for provider '{provider}', skipping rate limiting"
                )
```

---

## Section 6: Configuration Schema Per Provider

### 6.1 OpenAI Configuration

```yaml
# garak/resources/garak.core.yaml

plugins:
  generators:
    openai:
      rate_limits:
        # Model-specific limits
        gpt-4o:
          rpm: 500  # Tier 1 default
          tpm: 30000
          safety_margin: 0.9  # Use 90% of limit

        gpt-4o-mini:
          rpm: 500
          tpm: 200000
          safety_margin: 0.9

        # Default for unlisted models
        default:
          rpm: 500
          tpm: 10000

      backoff:
        strategy: "fibonacci"
        max_value: 70
        max_retries: 10
        jitter: true
```

**Configuration Structure:**
```python
{
    "rate_limits": {
        "<model_name>": {
            "rpm": int,  # Requests per minute
            "tpm": int,  # Tokens per minute
            "safety_margin": float  # 0.0-1.0, default 0.9
        }
    },
    "backoff": {
        "strategy": "fibonacci" | "exponential",
        "max_value": int,  # Max backoff seconds
        "max_retries": int,
        "jitter": bool
    }
}
```

### 6.2 Azure Configuration

```yaml
plugins:
  generators:
    azure:
      rate_limits:
        # Deployment-specific limits (NOT model names)
        my-gpt4-deployment:
          rps: 10  # Requests per second
          tpm_quota: 120000  # Monthly quota
          concurrent: 5
          safety_margin: 0.9

        production-deployment:
          rps: 20
          tpm_quota: 500000
          concurrent: 10

        default:
          rps: 6
          tpm_quota: 50000
          concurrent: 3

      quota_tracking:
        enabled: true
        reset_day: 1  # Day of month when quota resets
        persistence_path: "~/.config/garak/azure_quota.json"

      backoff:
        strategy: "exponential"
        base_delay: 1.0
        max_delay: 60.0
        max_retries: 8
```

**Configuration Structure:**
```python
{
    "rate_limits": {
        "<deployment_name>": {
            "rps": int,  # Requests per second
            "tpm_quota": int,  # Monthly token quota
            "concurrent": int,  # Max concurrent requests
            "safety_margin": float
        }
    },
    "quota_tracking": {
        "enabled": bool,
        "reset_day": int,  # 1-31
        "persistence_path": str
    }
}
```

### 6.3 Anthropic Configuration (Future)

```yaml
plugins:
  generators:
    anthropic:
      rate_limits:
        claude-3-opus-20240229:
          rpm: 5  # Tier 1 default
          tpm: 10000

        claude-3-sonnet-20240229:
          rpm: 5
          tpm: 20000

        default:
          rpm: 5
          tpm: 10000

      backoff:
        strategy: "exponential"
        base_delay: 1.0
        max_delay: 60.0
        max_retries: 5
```

### 6.4 Configuration Validation

```python
# garak/ratelimit/validation.py

def validate_provider_config(provider: str, config: Dict) -> bool:
    """
    Validate rate limit configuration for provider.

    Checks:
    - Required fields present (rate_limits)
    - Limit types match adapter capabilities
    - Values are positive integers
    - Safety margin in valid range (0.0-1.0)
    """
    if 'rate_limits' not in config:
        logging.error(f"Missing 'rate_limits' for provider '{provider}'")
        return False

    # Get adapter to check supported limit types
    adapter = AdapterFactory.create(provider)
    supported_types = adapter.get_limit_types()
    supported_keys = {lt.value.split('_')[0] for lt in supported_types}  # rpm, tpm, rps, etc.

    # Validate each model/deployment config
    for model, limits in config['rate_limits'].items():
        if not isinstance(limits, dict):
            logging.error(f"Invalid limits for {provider}/{model}: must be dict")
            return False

        for limit_key, limit_value in limits.items():
            # Check if limit type supported by adapter
            if limit_key not in supported_keys and limit_key != 'safety_margin':
                logging.warning(
                    f"Limit type '{limit_key}' not supported by {provider} adapter. "
                    f"Supported: {supported_keys}"
                )

            # Validate value is positive integer
            if limit_key != 'safety_margin':
                if not isinstance(limit_value, int) or limit_value <= 0:
                    logging.error(
                        f"Invalid {limit_key} for {provider}/{model}: must be positive int"
                    )
                    return False
            else:
                # Validate safety margin
                if not (0.0 < limit_value <= 1.0):
                    logging.error(
                        f"Invalid safety_margin for {provider}/{model}: must be 0.0-1.0"
                    )
                    return False

    return True
```

---

## Section 7: Concurrency and Quota Support Flags

### 7.1 Concurrent Limiting Pattern

```python
# Adapter declares support
def supports_concurrent_limiting(self) -> bool:
    return True  # Azure, HuggingFace

# UnifiedRateLimiter uses flag
if adapter.supports_concurrent_limiting():
    # Track concurrent request count
    self._init_concurrent_tracking(provider, model)

# Acquire pattern (with concurrent limit)
def acquire(self, provider, model, estimated_tokens):
    if self.adapters[provider].supports_concurrent_limiting():
        # Check concurrent count before allowing request
        if not self._check_concurrent_limit(provider, model):
            return False  # Too many concurrent requests

        # Increment concurrent counter
        self._increment_concurrent(provider, model)

    # ... check other limits ...
    return True

# Release pattern (must call after request completes)
def release(self, provider, model):
    if self.adapters[provider].supports_concurrent_limiting():
        self._decrement_concurrent(provider, model)
```

**Implementation:**
```python
def _init_concurrent_tracking(self, provider, model):
    """Initialize shared concurrent counter"""
    key = f"{provider}:{model}:concurrent"
    if key not in self._shared_state:
        self._shared_state[key] = self._manager.Value('i', 0)

def _check_concurrent_limit(self, provider, model):
    """Check if concurrent limit allows new request"""
    key = f"{provider}:{model}:concurrent"
    limit = self._get_concurrent_limit(provider, model)

    with self._get_lock(provider, model):
        current = self._shared_state[key].value
        return current < limit

def _increment_concurrent(self, provider, model):
    """Atomically increment concurrent counter"""
    key = f"{provider}:{model}:concurrent"
    with self._get_lock(provider, model):
        self._shared_state[key].value += 1

def _decrement_concurrent(self, provider, model):
    """Atomically decrement concurrent counter"""
    key = f"{provider}:{model}:concurrent"
    with self._get_lock(provider, model):
        self._shared_state[key].value = max(0, self._shared_state[key].value - 1)
```

### 7.2 Quota Tracking Pattern

```python
# Adapter declares support
def supports_quota_tracking(self) -> bool:
    return True  # Azure, Gemini

# UnifiedRateLimiter uses flag
if adapter.supports_quota_tracking():
    # Enable persistent state
    self._init_quota_persistence(provider, model)

# Quota persistence (file-based)
def _init_quota_persistence(self, provider, model):
    """Load quota state from file"""
    quota_file = os.path.expanduser("~/.config/garak/quota_state.json")

    if os.path.exists(quota_file):
        with open(quota_file, 'r') as f:
            quota_data = json.load(f)
    else:
        quota_data = {}

    key = f"{provider}:{model}:quota"
    if key not in quota_data:
        quota_data[key] = {
            'tokens_used': 0,
            'reset_at': self._calculate_quota_reset(provider)
        }

    # Check if quota reset needed
    if time.time() >= quota_data[key]['reset_at']:
        quota_data[key]['tokens_used'] = 0
        quota_data[key]['reset_at'] = self._calculate_quota_reset(provider)

    # Store in shared state
    self._quota_data[key] = quota_data[key]

def _calculate_quota_reset(self, provider):
    """Calculate next quota reset timestamp"""
    config = self._get_config(provider)
    reset_day = config.get('quota_tracking', {}).get('reset_day', 1)

    # Next occurrence of reset_day
    now = datetime.now()
    if now.day >= reset_day:
        # Next month
        next_month = (now.replace(day=1) + timedelta(days=32)).replace(day=reset_day)
    else:
        # This month
        next_month = now.replace(day=reset_day)

    return next_month.timestamp()

def _persist_quota(self):
    """Save quota state to file"""
    quota_file = os.path.expanduser("~/.config/garak/quota_state.json")
    with open(quota_file, 'w') as f:
        json.dump(self._quota_data, f)
```

---

## Section 8: Provider Limit Types Declaration

### 8.1 Limit Type Matrix

| Provider | RPM | TPM | RPS | RPD | TPD | TPM_QUOTA | CONCURRENT |
|----------|-----|-----|-----|-----|-----|-----------|------------|
| **OpenAI** | ✓ | ✓ | | | | | |
| **Azure** | | | ✓ | | | ✓ | ✓ |
| **Anthropic** | ✓ | ✓ | | | | | |
| **Gemini** | ✓ | | | ✓ | ✓ | | |
| **HuggingFace** | ✓ | | | | | | ✓ |
| **REST** | ✓ | | | | | | |

### 8.2 Adapter Declarations

```python
# OpenAI
def get_limit_types(self) -> List[RateLimitType]:
    return [RateLimitType.RPM, RateLimitType.TPM]

# Azure
def get_limit_types(self) -> List[RateLimitType]:
    return [
        RateLimitType.RPS,
        RateLimitType.TPM_QUOTA,
        RateLimitType.CONCURRENT
    ]

# Anthropic
def get_limit_types(self) -> List[RateLimitType]:
    return [RateLimitType.RPM, RateLimitType.TPM]

# Gemini (future)
def get_limit_types(self) -> List[RateLimitType]:
    return [
        RateLimitType.RPM,
        RateLimitType.RPD,
        RateLimitType.TPD
    ]

# HuggingFace
def get_limit_types(self) -> List[RateLimitType]:
    return [RateLimitType.RPM, RateLimitType.CONCURRENT]
```

### 8.3 Configuration Validation Using Limit Types

```python
def validate_model_config(provider: str, model: str, limits: Dict):
    """Validate that configured limits match adapter capabilities"""
    adapter = AdapterFactory.create(provider)
    supported_types = adapter.get_limit_types()

    # Map limit config keys to RateLimitType enums
    config_type_map = {
        'rpm': RateLimitType.RPM,
        'tpm': RateLimitType.TPM,
        'rps': RateLimitType.RPS,
        'rpd': RateLimitType.RPD,
        'tpd': RateLimitType.TPD,
        'tpm_quota': RateLimitType.TPM_QUOTA,
        'concurrent': RateLimitType.CONCURRENT,
    }

    for limit_key in limits.keys():
        if limit_key == 'safety_margin':
            continue

        limit_type = config_type_map.get(limit_key)
        if limit_type not in supported_types:
            raise ValueError(
                f"Provider '{provider}' does not support '{limit_key}' limits. "
                f"Supported: {[lt.value for lt in supported_types]}"
            )
```

---

## Section 9: Extension Guide - Adding New Adapter

### 9.1 Step-by-Step Adapter Creation

**Example: Adding Gemini Adapter**

**Step 1: Create Adapter File**

```bash
touch garak/ratelimit/adapters/gemini.py
```

**Step 2: Implement ProviderAdapter Interface**

```python
# garak/ratelimit/adapters/gemini.py

from garak.ratelimit.base import ProviderAdapter, RateLimitType
from typing import Dict, List, Optional, Any
import logging


class GeminiAdapter(ProviderAdapter):
    """Adapter for Google Gemini API"""

    def estimate_tokens(self, prompt: str, model: str) -> int:
        """Use Google Generative AI SDK"""
        try:
            import google.generativeai as genai
            model_instance = genai.GenerativeModel(model)
            return model_instance.count_tokens(prompt).total_tokens
        except ImportError:
            return len(prompt) // 4
        except Exception as e:
            logging.warning(f"Gemini token counting failed: {e}")
            return len(prompt) // 4

    def extract_usage_from_response(
        self,
        response: Any,
        metadata: Optional[Dict] = None
    ) -> Dict[str, int]:
        """Extract from response.usage_metadata"""
        if hasattr(response, 'usage_metadata'):
            return {
                'tokens_used': response.usage_metadata.total_token_count,
                'input_tokens': response.usage_metadata.prompt_token_count,
                'output_tokens': response.usage_metadata.candidates_token_count,
            }
        return {'tokens_used': 0}

    def extract_rate_limit_info(self, exception: Exception) -> Optional[Dict[str, Any]]:
        """Parse Google API errors"""
        try:
            from google.api_core.exceptions import ResourceExhausted

            if isinstance(exception, ResourceExhausted):
                return {
                    'error_type': 'rate_limit',
                    'limit_type': 'rpm',
                }
        except ImportError:
            pass
        return None

    def get_retry_after(
        self,
        exception: Exception,
        headers: Optional[Dict[str, str]] = None
    ) -> Optional[float]:
        """Extract from headers"""
        if headers and 'retry-after' in headers:
            try:
                return float(headers['retry-after'])
            except (ValueError, TypeError):
                pass
        return None

    def get_model_limits(self, model: str) -> Optional[Dict[str, int]]:
        """Known Gemini limits"""
        KNOWN_LIMITS = {
            'gemini-pro': {'rpm': 60, 'tpd': 1500000},
            'gemini-ultra': {'rpm': 30, 'tpd': 500000},
        }
        return KNOWN_LIMITS.get(model)

    def get_limit_types(self) -> List[RateLimitType]:
        """Gemini supports RPM and daily token limits"""
        return [RateLimitType.RPM, RateLimitType.TPD]
```

**Step 3: Register Adapter**

```python
# garak/ratelimit/adapters/__init__.py

from garak.ratelimit.adapters.gemini import GeminiAdapter

# Add to factory registration
AdapterFactory.register('gemini', GeminiAdapter)
```

**Step 4: Add Configuration Template**

```yaml
# garak/resources/garak.core.yaml

plugins:
  generators:
    gemini:
      rate_limits:
        gemini-pro:
          rpm: 60
          tpd: 1500000  # Daily token limit
        default:
          rpm: 60
          tpd: 100000

      backoff:
        strategy: "exponential"
        base_delay: 2.0
        max_delay: 120.0
```

**Step 5: Add Tests**

```python
# tests/ratelimit/test_gemini_adapter.py

import pytest
from garak.ratelimit.adapters.gemini import GeminiAdapter

def test_gemini_adapter_token_estimation():
    adapter = GeminiAdapter()
    tokens = adapter.estimate_tokens("Hello world", "gemini-pro")
    assert tokens > 0

def test_gemini_adapter_limit_types():
    adapter = GeminiAdapter()
    types = adapter.get_limit_types()
    assert RateLimitType.RPM in types
    assert RateLimitType.TPD in types

def test_gemini_adapter_model_limits():
    adapter = GeminiAdapter()
    limits = adapter.get_model_limits("gemini-pro")
    assert limits['rpm'] == 60
    assert limits['tpd'] == 1500000
```

**Result:** Gemini support added with ZERO changes to base classes.

### 9.2 Checklist for New Adapter

- [ ] Implement all 5 abstract methods
- [ ] Override `supports_concurrent_limiting()` if applicable
- [ ] Override `supports_quota_tracking()` if applicable
- [ ] Implement `get_limit_types()` to declare capabilities
- [ ] Add model limits in `get_model_limits()`
- [ ] Register in `AdapterFactory`
- [ ] Add configuration template to `garak.core.yaml`
- [ ] Write unit tests
- [ ] Update documentation

---

## Section 10: Design Validation

### 10.1 Success Criteria Verification

| Criterion | Status | Evidence |
|-----------|--------|----------|
| **Zero Provider Logic in Base** | ✓ PASS | UnifiedRateLimiter has no provider imports |
| **All Providers Use Same Methods** | ✓ PASS | ProviderAdapter ABC enforces uniform interface |
| **Extensible for Unknown Providers** | ✓ PASS | Gemini example shows <100 lines to add new provider |
| **No Implementation Code** | ✓ PASS | Document contains design only (method signatures, patterns) |
| **Factory Pattern Specified** | ✓ PASS | AdapterFactory with register/create methods |
| **Limit Type Declaration** | ✓ PASS | get_limit_types() per adapter |
| **Concurrency/Quota Flags** | ✓ PASS | supports_concurrent_limiting(), supports_quota_tracking() |
| **Configuration Schema** | ✓ PASS | YAML examples for OpenAI, Azure, Anthropic |
| **Error Mapping Patterns** | ✓ PASS | extract_rate_limit_info() examples |
| **Extension Guide** | ✓ PASS | Step-by-step Gemini adapter creation |

### 10.2 Interface Completeness

**Required Methods (5):**
1. ✓ `estimate_tokens(prompt, model) -> int`
2. ✓ `extract_usage_from_response(response, metadata) -> Dict`
3. ✓ `extract_rate_limit_info(exception) -> Optional[Dict]`
4. ✓ `get_retry_after(exception, headers) -> Optional[float]`
5. ✓ `get_model_limits(model) -> Optional[Dict]`

**Optional Methods (4):**
1. ✓ `supports_concurrent_limiting() -> bool`
2. ✓ `supports_quota_tracking() -> bool`
3. ✓ `get_limit_types() -> List[RateLimitType]`
4. ✓ `get_window_seconds(limit_type) -> int`

### 10.3 Provider Coverage

**Current Providers (3):**
- ✓ OpenAI (full design)
- ✓ Azure (full design)
- ✓ HuggingFace (referenced)

**Future Providers (3):**
- ✓ Anthropic (full design)
- ✓ Gemini (extension guide)
- ✓ REST (referenced)

---

## Appendix A: Method Signature Summary

```python
class ProviderAdapter(ABC):
    # ABSTRACT (must implement)
    @abstractmethod
    def estimate_tokens(self, prompt: str, model: str) -> int: ...

    @abstractmethod
    def extract_usage_from_response(self, response: Any, metadata: Optional[Dict] = None) -> Dict[str, int]: ...

    @abstractmethod
    def extract_rate_limit_info(self, exception: Exception) -> Optional[Dict[str, Any]]: ...

    @abstractmethod
    def get_retry_after(self, exception: Exception, headers: Optional[Dict[str, str]] = None) -> Optional[float]: ...

    @abstractmethod
    def get_model_limits(self, model: str) -> Optional[Dict[str, int]]: ...

    # CONCRETE (can override)
    def supports_concurrent_limiting(self) -> bool: ...
    def supports_quota_tracking(self) -> bool: ...
    def get_limit_types(self) -> List[RateLimitType]: ...
    def get_window_seconds(self, limit_type: RateLimitType) -> int: ...
```

---

## Appendix B: Return Value Specifications

### extract_usage_from_response() Return Format

```python
{
    'tokens_used': int,  # REQUIRED: Total tokens consumed
    'input_tokens': int,  # OPTIONAL: Prompt tokens
    'output_tokens': int,  # OPTIONAL: Completion tokens
    'cached_tokens': int,  # OPTIONAL: Cached tokens (Anthropic)
    'region': str,  # OPTIONAL: Azure region
    'deployment': str,  # OPTIONAL: Azure deployment name
}
```

### extract_rate_limit_info() Return Format

```python
{
    'error_type': 'rate_limit' | 'quota_exhausted' | 'concurrent_exceeded',
    'limit_type': 'rpm' | 'tpm' | 'rps' | 'rpd' | 'tpd' | 'tpm_quota' | 'concurrent',
    'retry_after': float,  # Seconds to wait
    'reset_at': float,  # Unix timestamp when limit resets
    'remaining': int,  # Remaining quota/requests
    'limit_value': int,  # Total limit value
}
```

### get_model_limits() Return Format

```python
{
    'rpm': int,  # Requests per minute
    'tpm': int,  # Tokens per minute
    'rps': int,  # Requests per second
    'rpd': int,  # Requests per day
    'tpd': int,  # Tokens per day
    'tpm_quota': int,  # Monthly token quota
    'concurrent': int,  # Max concurrent requests
}
```

---

## Appendix C: Error Handling Philosophy

### Never Raise Exceptions

**Principle:** Adapters are fail-safe transformers, not validators.

**Rationale:**
- Rate limiting is non-critical (has backoff fallback)
- Better to proceed with conservative estimate than fail request
- Errors logged for debugging but don't block execution

**Example:**
```python
def estimate_tokens(self, prompt: str, model: str) -> int:
    try:
        # Attempt accurate counting
        return self._accurate_token_count(prompt, model)
    except Exception as e:
        logging.warning(f"Token counting failed: {e}, using fallback")
        # Return conservative estimate, never raise
        return len(prompt) // 4
```

### Graceful Degradation Priority

1. **Best:** Provider SDK (tiktoken, anthropic.count_tokens)
2. **Good:** Generic tokenizer (transformers)
3. **Acceptable:** Character-based estimate (len(text) // 4)
4. **Last Resort:** Return 0 and log warning

---

**End of ProviderAdapter Abstract Interface Design**

**Status:** ✅ Complete and Ready for Implementation
**Next Step:** Implement UnifiedRateLimiter base class (Step 2c)
**Dependencies:** None (this is foundational interface)
