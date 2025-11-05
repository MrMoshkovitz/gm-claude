# Configuration Schema Design - Unified Rate Limiting Handler

**Status**: Phase 4a-4b - Configuration Design & Validation
**Last Updated**: 2025-10-20
**Reference**: CLAUDE.md, unified-handler-analysis.md

---

## Table of Contents

1. [Overview](#overview)
2. [Design Principles](#design-principles)
3. [YAML Schema Structure](#yaml-schema-structure)
4. [Pydantic Validation Models](#pydantic-validation-models)
5. [Configuration Loader](#configuration-loader)
6. [JSON Schema (IDE Support)](#json-schema-ide-support)
7. [Edge Cases & Validation](#edge-cases--validation)
8. [Pseudo-code Implementation](#pseudo-code-implementation)
9. [Migration Examples](#migration-examples)
10. [Testing Strategy](#testing-strategy)

---

## Overview

### Purpose

The configuration schema provides:
1. **Declarative rate limits** - All provider/model limits in YAML
2. **Type-safe validation** - Pydantic models catch errors at load time
3. **Hierarchical overrides** - System → Provider → Model → Deployment
4. **Backward compatibility** - Disabled by default, gradual opt-in
5. **IDE support** - JSON Schema for autocomplete/validation

### Key Requirements

| Requirement | Implementation |
|-------------|----------------|
| Provider-agnostic | Same schema works for OpenAI, Azure, HF, future providers |
| Extensible | New rate limit types added without code changes |
| Type-safe | Pydantic validates all values at load time |
| Hierarchical | Model overrides provider defaults |
| Optional | Missing config → use sensible defaults |
| Cached | Parse once, reuse across generators |

---

## Design Principles

### 1. Configuration-Driven Behavior

**All provider differences in config, not code:**

```yaml
# ✅ Right: Declarative
openai:
  rate_limits:
    gpt-4o: {rpm: 10000, tpm: 2000000}

# ❌ Wrong: Hardcoded in adapter
class OpenAIAdapter:
    def __init__(self):
        self.rpm = 10000  # BAD!
```

### 2. Hierarchical Override Pattern

**More specific config overrides general:**

```
System defaults (rate_limiting.enabled)
  ↓ Overridden by
Provider defaults (openai.rate_limits.default)
  ↓ Overridden by
Model-specific (openai.rate_limits.gpt-4o)
  ↓ Overridden by
Deployment-specific (azure.rate_limits.my-deployment)
```

### 3. Fail-Safe Defaults

**Missing config → safe default, not error:**

```python
# No config provided
config = load_rate_limit_config("openai", "gpt-4o")
# Returns: RateLimitConfig(rpm=3500, tpm=90000)  # Conservative defaults

# Provider exists but model not specified
config = load_rate_limit_config("openai", "new-model-123")
# Returns: openai.rate_limits.default or global defaults
```

### 4. Validation at Load Time

**Catch errors early, not at runtime:**

```python
# ❌ Invalid config loaded
rate_limits:
  gpt-4o: {rpm: -100}  # Negative!

# ✅ Pydantic validation fails immediately:
# ValidationError: rpm must be positive (got -100)
```

### 5. Extensibility via Union Types

**New rate limit types added without breaking existing:**

```python
class RateLimitConfig(BaseModel):
    # Core types (all providers)
    rpm: Optional[int] = None
    tpm: Optional[int] = None

    # Provider-specific types
    rps: Optional[int] = None  # Azure
    tpm_quota: Optional[int] = None  # Azure monthly
    concurrent: Optional[int] = None  # Azure

    # Future types (add here, no code changes elsewhere)
    rpd: Optional[int] = None  # Requests per day
    rpm_burst: Optional[int] = None  # Burst rate
```

---

## YAML Schema Structure

### System-Level Configuration

```yaml
system:
  rate_limiting:
    # Global on/off switch (backward compatibility)
    enabled: false  # Default: disabled

    # Safety margins (use X% of stated limits)
    default_safety_margin: 0.9  # 90% of limits

    # Sliding window configuration
    window_size_seconds: 60  # For RPM tracking
    cleanup_interval_seconds: 10  # Prune old entries

    # Logging and monitoring
    log_level: "INFO"  # DEBUG shows all acquire/release
    metrics_enabled: true  # Track usage statistics

    # Fallback behavior
    on_limit_exceeded: "backoff"  # Options: backoff, error, warn
    max_queue_wait_seconds: 300  # Max wait for acquire()
```

**Design Notes:**
- `enabled: false` → All generators work as-is (no changes)
- `default_safety_margin` → Prevent edge cases (clock skew, quota updates)
- `window_size_seconds` → Must match rate limit type (60s for RPM)
- `on_limit_exceeded` → Graceful degradation options

---

### Provider-Level Configuration

#### OpenAI Configuration

```yaml
plugins:
  generators:
    openai:
      # Rate limits per model
      rate_limits:
        # GPT-4o (Tier 5)
        gpt-4o:
          rpm: 10000  # Requests per minute
          tpm: 2000000  # Tokens per minute
          tpd: 5000000  # Tokens per day (optional)

        # GPT-4o-mini (Tier 5)
        gpt-4o-mini:
          rpm: 30000
          tpm: 10000000

        # GPT-3.5 Turbo (Tier 5)
        gpt-3.5-turbo:
          rpm: 10000
          tpm: 2000000

        # Default for unknown models (Tier 1)
        default:
          rpm: 3500
          tpm: 90000
          tpd: 200000

      # Backoff strategy
      backoff:
        strategy: "fibonacci"  # Options: fibonacci, exponential, linear
        max_value: 70  # Max backoff delay (seconds)
        max_tries: 10  # Max retry attempts
        jitter: true  # Add randomness to prevent thundering herd
        respect_retry_after: true  # Use Retry-After header if present

      # Token counting
      token_counter:
        library: "tiktoken"  # Use tiktoken for accurate counts
        fallback_chars_per_token: 4  # If tiktoken unavailable
        count_system_messages: true  # Include system message tokens

      # HTTP headers
      extract_limits_from_headers: true
      header_prefix: "x-ratelimit-"
```

**Design Notes:**
- `rate_limits` → Per-model configuration
- `default` → Fallback for unknown models
- `backoff.strategy` → Pluggable strategy pattern
- `token_counter.library` → Provider-specific tokenization
- `extract_limits_from_headers` → Dynamic limit updates from API

---

#### Azure OpenAI Configuration

```yaml
plugins:
  generators:
    azure:
      # Rate limits per deployment (not model!)
      rate_limits:
        # Production deployment
        my-gpt4-prod:
          rps: 10  # Requests per second
          tpm_quota: 120000  # Monthly token quota
          concurrent: 5  # Max concurrent requests
          rpm: 600  # Derived: 10 rps * 60s

        # Development deployment
        my-gpt35-dev:
          rps: 6
          tpm_quota: 50000
          concurrent: 3
          rpm: 360

        # Default for unknown deployments
        default:
          rps: 6
          tpm_quota: 30000
          concurrent: 3
          rpm: 360

      # Model mapping (Azure names → OpenAI names)
      model_mapping:
        gpt-35-turbo: "gpt-3.5-turbo-0125"
        gpt-4: "gpt-4-0613"
        gpt-4o: "gpt-4o-2024-05-13"

      # Backoff strategy (same as OpenAI)
      backoff:
        strategy: "fibonacci"
        max_value: 70
        max_tries: 10
        jitter: true
        respect_retry_after: true

      # Token counting (use OpenAI's tiktoken)
      token_counter:
        library: "tiktoken"
        use_mapped_model: true  # Count using OpenAI model name
        fallback_chars_per_token: 4

      # Azure-specific
      quota_tracking:
        enabled: true
        reset_day: 1  # Monthly quota resets on 1st
        warn_threshold: 0.9  # Warn at 90% quota
```

**Design Notes:**
- `rate_limits` → Per-deployment (Azure concept)
- `rps` → Azure's primary limit type
- `tpm_quota` → Monthly quota (different from per-minute)
- `concurrent` → Max parallel requests
- `model_mapping` → Handle Azure's naming differences
- `quota_tracking` → Track monthly consumption

---

#### HuggingFace Configuration

```yaml
plugins:
  generators:
    huggingface:
      # Rate limits (generic, endpoint-dependent)
      rate_limits:
        # Inference API (free tier)
        default:
          rpm: 60  # Generic rate limit
          rps: 1  # Be conservative

        # Inference Endpoints (paid)
        inference-endpoint:
          rpm: 300
          rps: 5
          concurrent: 10

      # Backoff strategy (more conservative)
      backoff:
        strategy: "fibonacci"
        max_value: 125  # Longer backoff than OpenAI
        max_tries: 15
        jitter: true
        respect_retry_after: true
        base_delay: 2.0  # Start with 2s delay

      # Token counting (no reliable counts)
      token_counter:
        library: "fallback"  # Estimate only
        fallback_chars_per_token: 4
        max_estimated_tokens: 2048  # Conservative estimate

      # HF-specific
      endpoint_detection:
        inference_api_pattern: "^https://api-inference.huggingface.co/"
        inference_endpoint_pattern: "^https://.*\\.endpoints\\.huggingface\\.cloud/"
```

**Design Notes:**
- `rate_limits` → Generic, no model-specific info
- `backoff.max_value: 125` → Longer backoff (current behavior)
- `token_counter.library: fallback` → No tiktoken available
- `endpoint_detection` → Auto-detect endpoint type for limits

---

#### Anthropic Configuration (Future)

```yaml
plugins:
  generators:
    anthropic:
      rate_limits:
        # Claude 3.5 Sonnet
        claude-3-5-sonnet-20241022:
          rpm: 4000
          tpm: 400000
          tpd: 5000000

        # Claude 3 Opus
        claude-3-opus-20240229:
          rpm: 4000
          tpm: 400000
          tpd: 5000000

        default:
          rpm: 1000
          tpm: 100000
          tpd: 1000000

      backoff:
        strategy: "exponential"
        base_delay: 1.0
        max_value: 60
        max_tries: 10
        jitter: true
        respect_retry_after: true

      token_counter:
        library: "anthropic"  # Use anthropic.count_tokens()
        fallback_chars_per_token: 4
```

**Design Notes:**
- Ready for future implementation
- Similar structure to OpenAI (RPM/TPM/TPD)
- Uses Anthropic's native token counter

---

#### Google Gemini Configuration (Future)

```yaml
plugins:
  generators:
    gemini:
      rate_limits:
        # Gemini Pro
        gemini-pro:
          rpm: 60  # Free tier
          rpd: 1500

        # Gemini Pro (Paid)
        gemini-pro-paid:
          rpm: 360
          rpd: 10000

        default:
          rpm: 60
          rpd: 1500

      backoff:
        strategy: "exponential"
        base_delay: 2.0
        max_value: 120
        max_tries: 12
        jitter: true

      token_counter:
        library: "gemini"  # Use gemini.count_tokens()
        fallback_chars_per_token: 4
```

**Design Notes:**
- Ready for future implementation
- Uses RPM + RPD (no TPM tracking)
- Longer backoff for free tier

---

### Complete Example Configuration

```yaml
# /Users/gmoshkov/Professional/Code/GarakGM/garak-unified-handler/garak/resources/garak.core.yaml

system:
  rate_limiting:
    enabled: false  # IMPORTANT: Disabled by default (backward compat)
    default_safety_margin: 0.9
    window_size_seconds: 60
    cleanup_interval_seconds: 10
    log_level: "INFO"
    metrics_enabled: true
    on_limit_exceeded: "backoff"
    max_queue_wait_seconds: 300

plugins:
  generators:
    openai:
      rate_limits:
        gpt-4o: {rpm: 10000, tpm: 2000000, tpd: 5000000}
        gpt-4o-mini: {rpm: 30000, tpm: 10000000}
        gpt-3.5-turbo: {rpm: 10000, tpm: 2000000}
        default: {rpm: 3500, tpm: 90000, tpd: 200000}
      backoff:
        strategy: "fibonacci"
        max_value: 70
        max_tries: 10
        jitter: true
        respect_retry_after: true
      token_counter:
        library: "tiktoken"
        fallback_chars_per_token: 4
        count_system_messages: true
      extract_limits_from_headers: true

    azure:
      rate_limits:
        my-gpt4-prod: {rps: 10, tpm_quota: 120000, concurrent: 5}
        my-gpt35-dev: {rps: 6, tpm_quota: 50000, concurrent: 3}
        default: {rps: 6, tpm_quota: 30000, concurrent: 3}
      model_mapping:
        gpt-35-turbo: "gpt-3.5-turbo-0125"
        gpt-4: "gpt-4-0613"
        gpt-4o: "gpt-4o-2024-05-13"
      backoff:
        strategy: "fibonacci"
        max_value: 70
        max_tries: 10
        jitter: true
      token_counter:
        library: "tiktoken"
        use_mapped_model: true
      quota_tracking:
        enabled: true
        reset_day: 1
        warn_threshold: 0.9

    huggingface:
      rate_limits:
        default: {rpm: 60, rps: 1}
        inference-endpoint: {rpm: 300, rps: 5, concurrent: 10}
      backoff:
        strategy: "fibonacci"
        max_value: 125
        max_tries: 15
        jitter: true
        base_delay: 2.0
      token_counter:
        library: "fallback"
        fallback_chars_per_token: 4
        max_estimated_tokens: 2048
      endpoint_detection:
        inference_api_pattern: "^https://api-inference.huggingface.co/"
        inference_endpoint_pattern: "^https://.*\\.endpoints\\.huggingface\\.cloud/"

    # Future providers (ready to enable)
    anthropic:
      rate_limits:
        claude-3-5-sonnet-20241022: {rpm: 4000, tpm: 400000, tpd: 5000000}
        default: {rpm: 1000, tpm: 100000, tpd: 1000000}
      backoff: {strategy: "exponential", base_delay: 1.0, max_value: 60}
      token_counter: {library: "anthropic"}

    gemini:
      rate_limits:
        gemini-pro: {rpm: 60, rpd: 1500}
        gemini-pro-paid: {rpm: 360, rpd: 10000}
        default: {rpm: 60, rpd: 1500}
      backoff: {strategy: "exponential", base_delay: 2.0, max_value: 120}
      token_counter: {library: "gemini"}
```

---

## Pydantic Validation Models

### Core Models

```python
from pydantic import BaseModel, Field, field_validator, model_validator
from typing import Optional, Literal, Dict, Any
from enum import Enum


# ----- Rate Limit Types -----

class RateLimitConfig(BaseModel):
    """Rate limit configuration for a provider/model/deployment.

    Supports multiple rate limit types:
    - rpm: Requests per minute
    - tpm: Tokens per minute
    - tpd: Tokens per day
    - rps: Requests per second
    - tpm_quota: Monthly token quota
    - concurrent: Max concurrent requests
    - rpd: Requests per day (future)
    - rpm_burst: Burst rate allowance (future)

    At least one limit type must be specified.
    """

    # Core types (most providers)
    rpm: Optional[int] = Field(None, ge=1, description="Requests per minute")
    tpm: Optional[int] = Field(None, ge=1, description="Tokens per minute")
    tpd: Optional[int] = Field(None, ge=1, description="Tokens per day")

    # Azure-specific
    rps: Optional[int] = Field(None, ge=1, description="Requests per second")
    tpm_quota: Optional[int] = Field(None, ge=1, description="Monthly token quota")
    concurrent: Optional[int] = Field(None, ge=1, description="Max concurrent requests")

    # Future types
    rpd: Optional[int] = Field(None, ge=1, description="Requests per day")
    rpm_burst: Optional[int] = Field(None, ge=1, description="Burst requests per minute")

    @model_validator(mode='after')
    def at_least_one_limit(self):
        """Ensure at least one rate limit is specified."""
        limits = [self.rpm, self.tpm, self.tpd, self.rps, self.tpm_quota,
                  self.concurrent, self.rpd, self.rpm_burst]
        if not any(limit is not None for limit in limits):
            raise ValueError("At least one rate limit must be specified")
        return self

    @field_validator('rpm', 'tpm', 'tpd', 'rps', 'rpd', 'rpm_burst', mode='before')
    @classmethod
    def validate_positive(cls, v):
        """Ensure all rate limits are positive."""
        if v is not None and v <= 0:
            raise ValueError(f"Rate limit must be positive (got {v})")
        return v

    @model_validator(mode='after')
    def validate_rps_rpm_consistency(self):
        """If both rps and rpm specified, rpm should be ~60*rps."""
        if self.rps is not None and self.rpm is not None:
            expected_rpm = self.rps * 60
            # Allow 10% variance
            if not (expected_rpm * 0.9 <= self.rpm <= expected_rpm * 1.1):
                raise ValueError(
                    f"Inconsistent rps ({self.rps}) and rpm ({self.rpm}). "
                    f"Expected rpm ~{expected_rpm}"
                )
        return self

    def to_dict(self) -> Dict[str, int]:
        """Export non-None limits as dict."""
        return {
            key: value
            for key, value in self.model_dump().items()
            if value is not None
        }


# ----- Backoff Strategy Types -----

class BackoffStrategyType(str, Enum):
    """Supported backoff strategies."""
    FIBONACCI = "fibonacci"
    EXPONENTIAL = "exponential"
    LINEAR = "linear"
    CONSTANT = "constant"


class BackoffConfig(BaseModel):
    """Backoff/retry strategy configuration.

    Controls how the rate limiter handles rate limit errors:
    - Strategy type (fibonacci, exponential, linear, constant)
    - Max backoff delay
    - Max retry attempts
    - Jitter (randomization)
    - Retry-After header handling
    """

    strategy: BackoffStrategyType = Field(
        BackoffStrategyType.FIBONACCI,
        description="Backoff strategy to use"
    )

    max_value: float = Field(
        70.0,
        ge=1.0,
        le=600.0,
        description="Maximum backoff delay in seconds"
    )

    max_tries: int = Field(
        10,
        ge=1,
        le=100,
        description="Maximum retry attempts"
    )

    jitter: bool = Field(
        True,
        description="Add random jitter to prevent thundering herd"
    )

    respect_retry_after: bool = Field(
        True,
        description="Use Retry-After header from API if present"
    )

    base_delay: float = Field(
        1.0,
        ge=0.1,
        le=60.0,
        description="Base delay for exponential/linear strategies"
    )

    multiplier: float = Field(
        2.0,
        ge=1.0,
        le=10.0,
        description="Multiplier for exponential strategy"
    )

    @field_validator('max_value')
    @classmethod
    def validate_max_value(cls, v):
        """Ensure max_value is reasonable."""
        if v > 600:
            raise ValueError("max_value cannot exceed 600s (10 minutes)")
        return v


# ----- Token Counter Configuration -----

class TokenCounterLibrary(str, Enum):
    """Supported token counting libraries."""
    TIKTOKEN = "tiktoken"  # OpenAI/Azure
    ANTHROPIC = "anthropic"  # Anthropic native
    GEMINI = "gemini"  # Google Gemini native
    HUGGINGFACE = "huggingface"  # HF transformers
    FALLBACK = "fallback"  # Character-based estimation


class TokenCounterConfig(BaseModel):
    """Token counting configuration.

    Controls how tokens are counted for rate limiting:
    - Library choice (tiktoken, anthropic, gemini, fallback)
    - Fallback estimation method
    - System message handling
    """

    library: TokenCounterLibrary = Field(
        TokenCounterLibrary.TIKTOKEN,
        description="Token counting library to use"
    )

    fallback_chars_per_token: float = Field(
        4.0,
        ge=1.0,
        le=10.0,
        description="Characters per token for fallback estimation"
    )

    count_system_messages: bool = Field(
        True,
        description="Include system message tokens in count"
    )

    use_mapped_model: bool = Field(
        False,
        description="Use mapped model name for counting (Azure)"
    )

    max_estimated_tokens: Optional[int] = Field(
        None,
        ge=1,
        description="Max tokens to estimate (HuggingFace)"
    )


# ----- Provider-Specific Configuration -----

class OpenAIProviderConfig(BaseModel):
    """OpenAI-specific rate limiting configuration."""

    rate_limits: Dict[str, RateLimitConfig] = Field(
        default_factory=dict,
        description="Rate limits per model (must include 'default')"
    )

    backoff: BackoffConfig = Field(
        default_factory=lambda: BackoffConfig(
            strategy=BackoffStrategyType.FIBONACCI,
            max_value=70.0,
            max_tries=10
        ),
        description="Backoff strategy configuration"
    )

    token_counter: TokenCounterConfig = Field(
        default_factory=lambda: TokenCounterConfig(
            library=TokenCounterLibrary.TIKTOKEN
        ),
        description="Token counting configuration"
    )

    extract_limits_from_headers: bool = Field(
        True,
        description="Extract rate limits from API response headers"
    )

    header_prefix: str = Field(
        "x-ratelimit-",
        description="Prefix for rate limit headers"
    )

    @model_validator(mode='after')
    def ensure_default_exists(self):
        """Ensure 'default' rate limit exists."""
        if 'default' not in self.rate_limits:
            # Add conservative default
            self.rate_limits['default'] = RateLimitConfig(
                rpm=3500,
                tpm=90000,
                tpd=200000
            )
        return self


class AzureProviderConfig(BaseModel):
    """Azure OpenAI-specific rate limiting configuration."""

    rate_limits: Dict[str, RateLimitConfig] = Field(
        default_factory=dict,
        description="Rate limits per deployment (must include 'default')"
    )

    model_mapping: Dict[str, str] = Field(
        default_factory=lambda: {
            "gpt-35-turbo": "gpt-3.5-turbo-0125",
            "gpt-4": "gpt-4-0613",
            "gpt-4o": "gpt-4o-2024-05-13"
        },
        description="Azure model name → OpenAI model name mapping"
    )

    backoff: BackoffConfig = Field(
        default_factory=lambda: BackoffConfig(
            strategy=BackoffStrategyType.FIBONACCI,
            max_value=70.0,
            max_tries=10
        ),
        description="Backoff strategy configuration"
    )

    token_counter: TokenCounterConfig = Field(
        default_factory=lambda: TokenCounterConfig(
            library=TokenCounterLibrary.TIKTOKEN,
            use_mapped_model=True
        ),
        description="Token counting configuration"
    )

    quota_tracking: Dict[str, Any] = Field(
        default_factory=lambda: {
            "enabled": True,
            "reset_day": 1,
            "warn_threshold": 0.9
        },
        description="Monthly quota tracking configuration"
    )

    @model_validator(mode='after')
    def ensure_default_exists(self):
        """Ensure 'default' rate limit exists."""
        if 'default' not in self.rate_limits:
            # Add conservative default
            self.rate_limits['default'] = RateLimitConfig(
                rps=6,
                tpm_quota=30000,
                concurrent=3
            )
        return self


class HuggingFaceProviderConfig(BaseModel):
    """HuggingFace-specific rate limiting configuration."""

    rate_limits: Dict[str, RateLimitConfig] = Field(
        default_factory=dict,
        description="Rate limits per endpoint type (must include 'default')"
    )

    backoff: BackoffConfig = Field(
        default_factory=lambda: BackoffConfig(
            strategy=BackoffStrategyType.FIBONACCI,
            max_value=125.0,
            max_tries=15,
            base_delay=2.0
        ),
        description="Backoff strategy configuration"
    )

    token_counter: TokenCounterConfig = Field(
        default_factory=lambda: TokenCounterConfig(
            library=TokenCounterLibrary.FALLBACK,
            fallback_chars_per_token=4.0,
            max_estimated_tokens=2048
        ),
        description="Token counting configuration"
    )

    endpoint_detection: Dict[str, str] = Field(
        default_factory=lambda: {
            "inference_api_pattern": r"^https://api-inference\.huggingface\.co/",
            "inference_endpoint_pattern": r"^https://.*\.endpoints\.huggingface\.cloud/"
        },
        description="Regex patterns for endpoint detection"
    )

    @model_validator(mode='after')
    def ensure_default_exists(self):
        """Ensure 'default' rate limit exists."""
        if 'default' not in self.rate_limits:
            # Add conservative default
            self.rate_limits['default'] = RateLimitConfig(
                rpm=60,
                rps=1
            )
        return self


class AnthropicProviderConfig(BaseModel):
    """Anthropic-specific rate limiting configuration (future)."""

    rate_limits: Dict[str, RateLimitConfig] = Field(
        default_factory=dict,
        description="Rate limits per model (must include 'default')"
    )

    backoff: BackoffConfig = Field(
        default_factory=lambda: BackoffConfig(
            strategy=BackoffStrategyType.EXPONENTIAL,
            base_delay=1.0,
            max_value=60.0,
            max_tries=10
        ),
        description="Backoff strategy configuration"
    )

    token_counter: TokenCounterConfig = Field(
        default_factory=lambda: TokenCounterConfig(
            library=TokenCounterLibrary.ANTHROPIC
        ),
        description="Token counting configuration"
    )

    @model_validator(mode='after')
    def ensure_default_exists(self):
        """Ensure 'default' rate limit exists."""
        if 'default' not in self.rate_limits:
            self.rate_limits['default'] = RateLimitConfig(
                rpm=1000,
                tpm=100000,
                tpd=1000000
            )
        return self


class GeminiProviderConfig(BaseModel):
    """Google Gemini-specific rate limiting configuration (future)."""

    rate_limits: Dict[str, RateLimitConfig] = Field(
        default_factory=dict,
        description="Rate limits per model (must include 'default')"
    )

    backoff: BackoffConfig = Field(
        default_factory=lambda: BackoffConfig(
            strategy=BackoffStrategyType.EXPONENTIAL,
            base_delay=2.0,
            max_value=120.0,
            max_tries=12
        ),
        description="Backoff strategy configuration"
    )

    token_counter: TokenCounterConfig = Field(
        default_factory=lambda: TokenCounterConfig(
            library=TokenCounterLibrary.GEMINI
        ),
        description="Token counting configuration"
    )

    @model_validator(mode='after')
    def ensure_default_exists(self):
        """Ensure 'default' rate limit exists."""
        if 'default' not in self.rate_limits:
            self.rate_limits['default'] = RateLimitConfig(
                rpm=60,
                rpd=1500
            )
        return self


# ----- System-Level Configuration -----

class RateLimitingSystemConfig(BaseModel):
    """System-level rate limiting configuration.

    Top-level configuration that controls global rate limiting behavior:
    - Global enable/disable flag
    - Safety margins
    - Sliding window parameters
    - Logging and monitoring
    - Fallback behavior
    """

    enabled: bool = Field(
        False,
        description="Global rate limiting enable flag (IMPORTANT: disabled by default)"
    )

    default_safety_margin: float = Field(
        0.9,
        ge=0.1,
        le=1.0,
        description="Use X% of stated limits (safety margin)"
    )

    window_size_seconds: int = Field(
        60,
        ge=1,
        le=3600,
        description="Sliding window size in seconds"
    )

    cleanup_interval_seconds: int = Field(
        10,
        ge=1,
        le=300,
        description="Interval to prune old entries from sliding window"
    )

    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR"] = Field(
        "INFO",
        description="Logging level for rate limiter"
    )

    metrics_enabled: bool = Field(
        True,
        description="Enable usage metrics tracking"
    )

    on_limit_exceeded: Literal["backoff", "error", "warn"] = Field(
        "backoff",
        description="Behavior when rate limit exceeded"
    )

    max_queue_wait_seconds: int = Field(
        300,
        ge=1,
        le=3600,
        description="Max wait time for acquire() before error"
    )

    @field_validator('default_safety_margin')
    @classmethod
    def validate_safety_margin(cls, v):
        """Ensure safety margin is reasonable."""
        if v < 0.1:
            raise ValueError("Safety margin too low (min 0.1)")
        if v > 1.0:
            raise ValueError("Safety margin cannot exceed 1.0")
        return v


# ----- Top-Level Configuration -----

class GeneratorsPluginConfig(BaseModel):
    """All generator plugins configuration."""

    openai: OpenAIProviderConfig = Field(
        default_factory=OpenAIProviderConfig,
        description="OpenAI provider configuration"
    )

    azure: AzureProviderConfig = Field(
        default_factory=AzureProviderConfig,
        description="Azure OpenAI provider configuration"
    )

    huggingface: HuggingFaceProviderConfig = Field(
        default_factory=HuggingFaceProviderConfig,
        description="HuggingFace provider configuration"
    )

    anthropic: AnthropicProviderConfig = Field(
        default_factory=AnthropicProviderConfig,
        description="Anthropic provider configuration"
    )

    gemini: GeminiProviderConfig = Field(
        default_factory=GeminiProviderConfig,
        description="Google Gemini provider configuration"
    )


class RateLimitingConfig(BaseModel):
    """Complete rate limiting configuration.

    Root configuration object that contains:
    - System-level settings
    - All provider configurations
    """

    system: RateLimitingSystemConfig = Field(
        default_factory=RateLimitingSystemConfig,
        description="System-level rate limiting configuration"
    )

    plugins: GeneratorsPluginConfig = Field(
        default_factory=GeneratorsPluginConfig,
        description="Per-provider rate limiting configuration"
    )

    def is_enabled(self) -> bool:
        """Check if rate limiting is globally enabled."""
        return self.system.enabled

    def get_provider_config(self, provider: str) -> Optional[Any]:
        """Get configuration for a specific provider.

        Args:
            provider: Provider name (openai, azure, huggingface, etc.)

        Returns:
            Provider-specific config object or None if not found
        """
        provider_lower = provider.lower()

        if provider_lower == "openai":
            return self.plugins.openai
        elif provider_lower == "azure":
            return self.plugins.azure
        elif provider_lower == "huggingface":
            return self.plugins.huggingface
        elif provider_lower == "anthropic":
            return self.plugins.anthropic
        elif provider_lower == "gemini":
            return self.plugins.gemini
        else:
            return None

    def get_rate_limits(
        self,
        provider: str,
        model_or_deployment: str
    ) -> Optional[RateLimitConfig]:
        """Get rate limits for a specific provider and model/deployment.

        Args:
            provider: Provider name
            model_or_deployment: Model name or deployment name

        Returns:
            RateLimitConfig or None if not found (falls back to 'default')
        """
        provider_config = self.get_provider_config(provider)
        if provider_config is None:
            return None

        # Try exact match
        if model_or_deployment in provider_config.rate_limits:
            return provider_config.rate_limits[model_or_deployment]

        # Fall back to 'default'
        return provider_config.rate_limits.get('default')
```

---

## Configuration Loader

### Loader Design

```python
import yaml
import logging
from pathlib import Path
from typing import Optional, Dict, Any
from functools import lru_cache
from pydantic import ValidationError


logger = logging.getLogger(__name__)


class RateLimitConfigLoader:
    """Loads and caches rate limiting configuration from YAML files.

    Features:
    - Load from garak.core.yaml
    - Validate with Pydantic models
    - Cache parsed configuration
    - Merge provider defaults with model overrides
    - Graceful error handling
    """

    _instance: Optional['RateLimitConfigLoader'] = None
    _config: Optional[RateLimitingConfig] = None
    _config_path: Optional[Path] = None

    def __new__(cls):
        """Singleton pattern."""
        if cls._instance is None:
            cls._instance = super().__new__(cls)
        return cls._instance

    def __init__(self):
        """Initialize loader (only once)."""
        if self._config is None:
            self._load_config()

    @classmethod
    def reset(cls):
        """Reset singleton (for testing)."""
        cls._instance = None
        cls._config = None
        cls._config_path = None

    def _find_config_file(self) -> Path:
        """Find garak.core.yaml configuration file.

        Search order:
        1. GARAK_CONFIG_PATH environment variable
        2. ./garak/resources/garak.core.yaml (relative to cwd)
        3. ~/.garak/garak.core.yaml (user home)
        4. /etc/garak/garak.core.yaml (system)

        Returns:
            Path to config file

        Raises:
            FileNotFoundError: If no config file found
        """
        import os

        # 1. Environment variable
        env_path = os.environ.get('GARAK_CONFIG_PATH')
        if env_path:
            path = Path(env_path)
            if path.exists():
                return path
            logger.warning(f"GARAK_CONFIG_PATH set but file not found: {path}")

        # 2. Relative to cwd
        cwd_path = Path.cwd() / "garak" / "resources" / "garak.core.yaml"
        if cwd_path.exists():
            return cwd_path

        # 3. User home
        home_path = Path.home() / ".garak" / "garak.core.yaml"
        if home_path.exists():
            return home_path

        # 4. System
        system_path = Path("/etc/garak/garak.core.yaml")
        if system_path.exists():
            return system_path

        raise FileNotFoundError(
            "Could not find garak.core.yaml. Searched:\n"
            f"  - {env_path or '(GARAK_CONFIG_PATH not set)'}\n"
            f"  - {cwd_path}\n"
            f"  - {home_path}\n"
            f"  - {system_path}"
        )

    def _load_yaml(self, path: Path) -> Dict[str, Any]:
        """Load YAML file.

        Args:
            path: Path to YAML file

        Returns:
            Parsed YAML as dict

        Raises:
            yaml.YAMLError: If YAML is invalid
        """
        with open(path, 'r') as f:
            return yaml.safe_load(f)

    def _extract_rate_limiting_section(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """Extract rate_limiting section from config.

        Expects structure:
        {
            "system": {"rate_limiting": {...}},
            "plugins": {"generators": {...}}
        }

        Args:
            data: Full config dict

        Returns:
            Rate limiting config dict
        """
        rate_limit_data = {}

        # Extract system.rate_limiting
        if "system" in data and "rate_limiting" in data["system"]:
            rate_limit_data["system"] = data["system"]["rate_limiting"]

        # Extract plugins.generators
        if "plugins" in data and "generators" in data["plugins"]:
            rate_limit_data["plugins"] = data["plugins"]["generators"]

        return rate_limit_data

    def _validate_config(self, data: Dict[str, Any]) -> RateLimitingConfig:
        """Validate configuration with Pydantic.

        Args:
            data: Config dict

        Returns:
            Validated RateLimitingConfig

        Raises:
            ValidationError: If validation fails
        """
        try:
            config = RateLimitingConfig(**data)
            logger.info("Rate limiting configuration validated successfully")
            return config
        except ValidationError as e:
            logger.error(f"Rate limiting configuration validation failed:\n{e}")
            raise

    def _load_config(self):
        """Load and validate configuration from file."""
        try:
            # Find config file
            self._config_path = self._find_config_file()
            logger.info(f"Loading rate limiting config from: {self._config_path}")

            # Load YAML
            data = self._load_yaml(self._config_path)

            # Extract rate_limiting section
            rate_limit_data = self._extract_rate_limiting_section(data)

            # Validate with Pydantic
            self._config = self._validate_config(rate_limit_data)

            # Log status
            if self._config.is_enabled():
                logger.info("Rate limiting is ENABLED")
            else:
                logger.info("Rate limiting is DISABLED (backward compatibility mode)")

        except FileNotFoundError:
            # No config file → use defaults (disabled)
            logger.warning("No garak.core.yaml found. Using default config (rate limiting disabled)")
            self._config = RateLimitingConfig()

        except ValidationError:
            # Invalid config → use defaults (disabled)
            logger.error("Configuration validation failed. Using default config (rate limiting disabled)")
            self._config = RateLimitingConfig()

        except Exception as e:
            # Unexpected error → use defaults (disabled)
            logger.error(f"Unexpected error loading config: {e}. Using defaults (rate limiting disabled)")
            self._config = RateLimitingConfig()

    def get_config(self) -> RateLimitingConfig:
        """Get loaded configuration.

        Returns:
            RateLimitingConfig (guaranteed non-None)
        """
        if self._config is None:
            self._load_config()
        return self._config

    def is_enabled(self) -> bool:
        """Check if rate limiting is globally enabled.

        Returns:
            True if enabled, False otherwise
        """
        return self.get_config().is_enabled()

    def get_rate_limits(
        self,
        provider: str,
        model_or_deployment: str
    ) -> Optional[RateLimitConfig]:
        """Get rate limits for a specific provider and model/deployment.

        Args:
            provider: Provider name (openai, azure, huggingface, etc.)
            model_or_deployment: Model name or deployment name

        Returns:
            RateLimitConfig or None if not found
        """
        config = self.get_config()
        return config.get_rate_limits(provider, model_or_deployment)

    def get_backoff_config(self, provider: str) -> Optional[BackoffConfig]:
        """Get backoff configuration for a provider.

        Args:
            provider: Provider name

        Returns:
            BackoffConfig or None if not found
        """
        config = self.get_config()
        provider_config = config.get_provider_config(provider)

        if provider_config is None:
            return None

        return provider_config.backoff

    def get_token_counter_config(self, provider: str) -> Optional[TokenCounterConfig]:
        """Get token counter configuration for a provider.

        Args:
            provider: Provider name

        Returns:
            TokenCounterConfig or None if not found
        """
        config = self.get_config()
        provider_config = config.get_provider_config(provider)

        if provider_config is None:
            return None

        return provider_config.token_counter

    def get_system_config(self) -> RateLimitingSystemConfig:
        """Get system-level configuration.

        Returns:
            RateLimitingSystemConfig
        """
        return self.get_config().system


# ----- Global Loader Instance -----

_global_loader: Optional[RateLimitConfigLoader] = None


def get_config_loader() -> RateLimitConfigLoader:
    """Get global configuration loader (singleton).

    Returns:
        RateLimitConfigLoader instance
    """
    global _global_loader
    if _global_loader is None:
        _global_loader = RateLimitConfigLoader()
    return _global_loader


def reset_config_loader():
    """Reset global loader (for testing)."""
    global _global_loader
    _global_loader = None
    RateLimitConfigLoader.reset()


# ----- Convenience Functions -----

def load_rate_limit_config(
    provider: str,
    model_or_deployment: str
) -> Optional[RateLimitConfig]:
    """Load rate limits for a provider and model.

    Convenience function that uses global loader.

    Args:
        provider: Provider name
        model_or_deployment: Model name or deployment name

    Returns:
        RateLimitConfig or None if not found

    Example:
        >>> config = load_rate_limit_config("openai", "gpt-4o")
        >>> if config:
        ...     print(f"RPM: {config.rpm}, TPM: {config.tpm}")
    """
    loader = get_config_loader()
    return loader.get_rate_limits(provider, model_or_deployment)


def is_rate_limiting_enabled() -> bool:
    """Check if rate limiting is globally enabled.

    Convenience function that uses global loader.

    Returns:
        True if enabled, False otherwise

    Example:
        >>> if is_rate_limiting_enabled():
        ...     rate_limiter.acquire()
    """
    loader = get_config_loader()
    return loader.is_enabled()


def get_backoff_strategy(provider: str) -> Optional[BackoffConfig]:
    """Get backoff configuration for a provider.

    Convenience function that uses global loader.

    Args:
        provider: Provider name

    Returns:
        BackoffConfig or None if not found

    Example:
        >>> backoff = get_backoff_strategy("openai")
        >>> if backoff:
        ...     print(f"Strategy: {backoff.strategy}, Max: {backoff.max_value}")
    """
    loader = get_config_loader()
    return loader.get_backoff_config(provider)


def get_safety_margin() -> float:
    """Get global safety margin.

    Returns:
        Safety margin (0.1 to 1.0)

    Example:
        >>> margin = get_safety_margin()
        >>> effective_limit = stated_limit * margin
    """
    loader = get_config_loader()
    return loader.get_system_config().default_safety_margin
```

---

## JSON Schema (IDE Support)

### JSON Schema Definition

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "$id": "https://garak.ai/schemas/rate-limiting-config.json",
  "title": "Garak Rate Limiting Configuration",
  "description": "Configuration schema for unified rate limiting handler",
  "type": "object",
  "properties": {
    "system": {
      "type": "object",
      "description": "System-level rate limiting configuration",
      "properties": {
        "rate_limiting": {
          "type": "object",
          "properties": {
            "enabled": {
              "type": "boolean",
              "default": false,
              "description": "Global rate limiting enable flag (disabled by default for backward compatibility)"
            },
            "default_safety_margin": {
              "type": "number",
              "minimum": 0.1,
              "maximum": 1.0,
              "default": 0.9,
              "description": "Use X% of stated limits (safety margin for clock skew, quota updates)"
            },
            "window_size_seconds": {
              "type": "integer",
              "minimum": 1,
              "maximum": 3600,
              "default": 60,
              "description": "Sliding window size in seconds (60s for RPM, 1s for RPS)"
            },
            "cleanup_interval_seconds": {
              "type": "integer",
              "minimum": 1,
              "maximum": 300,
              "default": 10,
              "description": "Interval to prune old entries from sliding window"
            },
            "log_level": {
              "type": "string",
              "enum": ["DEBUG", "INFO", "WARNING", "ERROR"],
              "default": "INFO",
              "description": "Logging level for rate limiter (DEBUG shows all acquire/release)"
            },
            "metrics_enabled": {
              "type": "boolean",
              "default": true,
              "description": "Enable usage metrics tracking"
            },
            "on_limit_exceeded": {
              "type": "string",
              "enum": ["backoff", "error", "warn"],
              "default": "backoff",
              "description": "Behavior when rate limit exceeded (backoff=retry, error=raise, warn=log)"
            },
            "max_queue_wait_seconds": {
              "type": "integer",
              "minimum": 1,
              "maximum": 3600,
              "default": 300,
              "description": "Max wait time for acquire() before timing out"
            }
          },
          "required": ["enabled"]
        }
      }
    },
    "plugins": {
      "type": "object",
      "description": "Per-provider rate limiting configuration",
      "properties": {
        "generators": {
          "type": "object",
          "properties": {
            "openai": {
              "$ref": "#/definitions/OpenAIProviderConfig"
            },
            "azure": {
              "$ref": "#/definitions/AzureProviderConfig"
            },
            "huggingface": {
              "$ref": "#/definitions/HuggingFaceProviderConfig"
            },
            "anthropic": {
              "$ref": "#/definitions/AnthropicProviderConfig"
            },
            "gemini": {
              "$ref": "#/definitions/GeminiProviderConfig"
            }
          }
        }
      }
    }
  },
  "definitions": {
    "RateLimitConfig": {
      "type": "object",
      "description": "Rate limit configuration (at least one limit type required)",
      "properties": {
        "rpm": {
          "type": "integer",
          "minimum": 1,
          "description": "Requests per minute"
        },
        "tpm": {
          "type": "integer",
          "minimum": 1,
          "description": "Tokens per minute"
        },
        "tpd": {
          "type": "integer",
          "minimum": 1,
          "description": "Tokens per day"
        },
        "rps": {
          "type": "integer",
          "minimum": 1,
          "description": "Requests per second (Azure)"
        },
        "tpm_quota": {
          "type": "integer",
          "minimum": 1,
          "description": "Monthly token quota (Azure)"
        },
        "concurrent": {
          "type": "integer",
          "minimum": 1,
          "description": "Max concurrent requests (Azure)"
        },
        "rpd": {
          "type": "integer",
          "minimum": 1,
          "description": "Requests per day (future)"
        },
        "rpm_burst": {
          "type": "integer",
          "minimum": 1,
          "description": "Burst requests per minute (future)"
        }
      },
      "minProperties": 1
    },
    "BackoffConfig": {
      "type": "object",
      "description": "Backoff/retry strategy configuration",
      "properties": {
        "strategy": {
          "type": "string",
          "enum": ["fibonacci", "exponential", "linear", "constant"],
          "default": "fibonacci",
          "description": "Backoff strategy type"
        },
        "max_value": {
          "type": "number",
          "minimum": 1,
          "maximum": 600,
          "default": 70,
          "description": "Maximum backoff delay in seconds"
        },
        "max_tries": {
          "type": "integer",
          "minimum": 1,
          "maximum": 100,
          "default": 10,
          "description": "Maximum retry attempts"
        },
        "jitter": {
          "type": "boolean",
          "default": true,
          "description": "Add random jitter to prevent thundering herd"
        },
        "respect_retry_after": {
          "type": "boolean",
          "default": true,
          "description": "Use Retry-After header from API if present"
        },
        "base_delay": {
          "type": "number",
          "minimum": 0.1,
          "maximum": 60,
          "default": 1.0,
          "description": "Base delay for exponential/linear strategies"
        },
        "multiplier": {
          "type": "number",
          "minimum": 1.0,
          "maximum": 10.0,
          "default": 2.0,
          "description": "Multiplier for exponential strategy"
        }
      },
      "required": ["strategy"]
    },
    "TokenCounterConfig": {
      "type": "object",
      "description": "Token counting configuration",
      "properties": {
        "library": {
          "type": "string",
          "enum": ["tiktoken", "anthropic", "gemini", "huggingface", "fallback"],
          "default": "tiktoken",
          "description": "Token counting library to use"
        },
        "fallback_chars_per_token": {
          "type": "number",
          "minimum": 1.0,
          "maximum": 10.0,
          "default": 4.0,
          "description": "Characters per token for fallback estimation"
        },
        "count_system_messages": {
          "type": "boolean",
          "default": true,
          "description": "Include system message tokens in count"
        },
        "use_mapped_model": {
          "type": "boolean",
          "default": false,
          "description": "Use mapped model name for counting (Azure)"
        },
        "max_estimated_tokens": {
          "type": "integer",
          "minimum": 1,
          "description": "Max tokens to estimate (HuggingFace)"
        }
      },
      "required": ["library"]
    },
    "OpenAIProviderConfig": {
      "type": "object",
      "description": "OpenAI-specific rate limiting configuration",
      "properties": {
        "rate_limits": {
          "type": "object",
          "description": "Rate limits per model (must include 'default')",
          "additionalProperties": {
            "$ref": "#/definitions/RateLimitConfig"
          },
          "required": ["default"]
        },
        "backoff": {
          "$ref": "#/definitions/BackoffConfig"
        },
        "token_counter": {
          "$ref": "#/definitions/TokenCounterConfig"
        },
        "extract_limits_from_headers": {
          "type": "boolean",
          "default": true,
          "description": "Extract rate limits from API response headers"
        },
        "header_prefix": {
          "type": "string",
          "default": "x-ratelimit-",
          "description": "Prefix for rate limit headers"
        }
      },
      "required": ["rate_limits"]
    },
    "AzureProviderConfig": {
      "type": "object",
      "description": "Azure OpenAI-specific rate limiting configuration",
      "properties": {
        "rate_limits": {
          "type": "object",
          "description": "Rate limits per deployment (must include 'default')",
          "additionalProperties": {
            "$ref": "#/definitions/RateLimitConfig"
          },
          "required": ["default"]
        },
        "model_mapping": {
          "type": "object",
          "description": "Azure model name → OpenAI model name mapping",
          "additionalProperties": {
            "type": "string"
          }
        },
        "backoff": {
          "$ref": "#/definitions/BackoffConfig"
        },
        "token_counter": {
          "$ref": "#/definitions/TokenCounterConfig"
        },
        "quota_tracking": {
          "type": "object",
          "properties": {
            "enabled": {
              "type": "boolean",
              "default": true
            },
            "reset_day": {
              "type": "integer",
              "minimum": 1,
              "maximum": 31,
              "default": 1
            },
            "warn_threshold": {
              "type": "number",
              "minimum": 0.0,
              "maximum": 1.0,
              "default": 0.9
            }
          }
        }
      },
      "required": ["rate_limits"]
    },
    "HuggingFaceProviderConfig": {
      "type": "object",
      "description": "HuggingFace-specific rate limiting configuration",
      "properties": {
        "rate_limits": {
          "type": "object",
          "description": "Rate limits per endpoint type (must include 'default')",
          "additionalProperties": {
            "$ref": "#/definitions/RateLimitConfig"
          },
          "required": ["default"]
        },
        "backoff": {
          "$ref": "#/definitions/BackoffConfig"
        },
        "token_counter": {
          "$ref": "#/definitions/TokenCounterConfig"
        },
        "endpoint_detection": {
          "type": "object",
          "properties": {
            "inference_api_pattern": {
              "type": "string"
            },
            "inference_endpoint_pattern": {
              "type": "string"
            }
          }
        }
      },
      "required": ["rate_limits"]
    },
    "AnthropicProviderConfig": {
      "type": "object",
      "description": "Anthropic-specific rate limiting configuration (future)",
      "properties": {
        "rate_limits": {
          "type": "object",
          "additionalProperties": {
            "$ref": "#/definitions/RateLimitConfig"
          },
          "required": ["default"]
        },
        "backoff": {
          "$ref": "#/definitions/BackoffConfig"
        },
        "token_counter": {
          "$ref": "#/definitions/TokenCounterConfig"
        }
      },
      "required": ["rate_limits"]
    },
    "GeminiProviderConfig": {
      "type": "object",
      "description": "Google Gemini-specific rate limiting configuration (future)",
      "properties": {
        "rate_limits": {
          "type": "object",
          "additionalProperties": {
            "$ref": "#/definitions/RateLimitConfig"
          },
          "required": ["default"]
        },
        "backoff": {
          "$ref": "#/definitions/BackoffConfig"
        },
        "token_counter": {
          "$ref": "#/definitions/TokenCounterConfig"
        }
      },
      "required": ["rate_limits"]
    }
  }
}
```

### Usage in IDE

**VS Code** (`.vscode/settings.json`):
```json
{
  "yaml.schemas": {
    ".claude/schemas/rate-limiting-config.json": "garak/resources/garak.core.yaml"
  }
}
```

**PyCharm** (Settings → Languages & Frameworks → Schemas and DTDs → JSON Schema Mappings):
- Schema file: `.claude/schemas/rate-limiting-config.json`
- File path pattern: `garak/resources/garak.core.yaml`

---

## Edge Cases & Validation

### Edge Case Handling

| Edge Case | Behavior | Validation |
|-----------|----------|------------|
| **No config file** | Use defaults (disabled) | ✅ FileNotFoundError caught |
| **Invalid YAML** | Use defaults (disabled) | ✅ yaml.YAMLError caught |
| **Missing 'system' section** | Use defaults (disabled) | ✅ Pydantic default_factory |
| **Missing 'plugins' section** | Use defaults per provider | ✅ Pydantic default_factory |
| **enabled: true, no rate_limits** | Use conservative defaults | ✅ ensure_default_exists validator |
| **Negative rate limit** | ValidationError raised | ✅ Field(ge=1) |
| **Zero rate limit** | ValidationError raised | ✅ Field(ge=1) |
| **No limits specified** | ValidationError raised | ✅ at_least_one_limit validator |
| **Inconsistent rps/rpm** | ValidationError raised | ✅ validate_rps_rpm_consistency |
| **Unknown provider** | Return None | ✅ get_provider_config returns None |
| **Unknown model** | Use 'default' limits | ✅ Fallback logic in get_rate_limits |
| **Safety margin > 1.0** | ValidationError raised | ✅ Field(le=1.0) |
| **Safety margin < 0.1** | ValidationError raised | ✅ Field(ge=0.1) |
| **Max backoff > 600s** | ValidationError raised | ✅ Field(le=600.0) |
| **Max tries > 100** | ValidationError raised | ✅ Field(le=100) |

### Validation Examples

#### Valid Configuration

```yaml
system:
  rate_limiting:
    enabled: true
    default_safety_margin: 0.9

plugins:
  generators:
    openai:
      rate_limits:
        gpt-4o: {rpm: 10000, tpm: 2000000}
        default: {rpm: 3500, tpm: 90000}
```

**Result**: ✅ Passes validation

#### Invalid: No Limits Specified

```yaml
plugins:
  generators:
    openai:
      rate_limits:
        gpt-4o: {}  # Empty!
```

**Result**: ❌ ValidationError: "At least one rate limit must be specified"

#### Invalid: Negative Limit

```yaml
plugins:
  generators:
    openai:
      rate_limits:
        gpt-4o: {rpm: -100}
```

**Result**: ❌ ValidationError: "rpm must be positive (got -100)"

#### Invalid: Inconsistent RPS/RPM

```yaml
plugins:
  generators:
    azure:
      rate_limits:
        my-deployment: {rps: 10, rpm: 100}  # Should be 600!
```

**Result**: ❌ ValidationError: "Inconsistent rps (10) and rpm (100). Expected rpm ~600"

#### Valid: Safety Margin

```yaml
system:
  rate_limiting:
    default_safety_margin: 0.95
```

**Result**: ✅ Passes validation (0.1 ≤ 0.95 ≤ 1.0)

#### Invalid: Safety Margin Too High

```yaml
system:
  rate_limiting:
    default_safety_margin: 1.5
```

**Result**: ❌ ValidationError: "Safety margin cannot exceed 1.0"

#### Invalid: Safety Margin Too Low

```yaml
system:
  rate_limiting:
    default_safety_margin: 0.05
```

**Result**: ❌ ValidationError: "Safety margin too low (min 0.1)"

#### Valid: Backoff Strategy

```yaml
plugins:
  generators:
    openai:
      backoff:
        strategy: "fibonacci"
        max_value: 70
        max_tries: 10
```

**Result**: ✅ Passes validation

#### Invalid: Max Backoff Too High

```yaml
plugins:
  generators:
    openai:
      backoff:
        max_value: 1000  # > 600!
```

**Result**: ❌ ValidationError: "max_value cannot exceed 600s (10 minutes)"

---

## Pseudo-code Implementation

### Complete Implementation Flow

```python
# ===== Initialization =====

# 1. Application startup
from garak.ratelimit.config import get_config_loader, is_rate_limiting_enabled

# Check if rate limiting enabled
if is_rate_limiting_enabled():
    print("Rate limiting is ENABLED")
else:
    print("Rate limiting is DISABLED (backward compatibility mode)")


# ===== Generator Registration =====

# 2. Generator __init__
class OpenAIGenerator(Generator):
    def __init__(self, name: str, **kwargs):
        super().__init__(name, **kwargs)

        # Register with rate limiter (only if enabled)
        if is_rate_limiting_enabled():
            from garak.ratelimit.config import load_rate_limit_config

            # Load rate limits for this model
            self.rate_limit_config = load_rate_limit_config(
                provider="openai",
                model_or_deployment=name  # e.g., "gpt-4o"
            )

            if self.rate_limit_config:
                logger.info(
                    f"Rate limiting enabled for {name}: "
                    f"RPM={self.rate_limit_config.rpm}, "
                    f"TPM={self.rate_limit_config.tpm}"
                )
            else:
                logger.warning(f"No rate limits found for {name}, using defaults")


# ===== Pre-Request Hook =====

# 3. Before API call
def _pre_generate_hook(self, prompt: str) -> None:
    """Hook called before generate()."""

    # Only check if rate limiting enabled
    if not is_rate_limiting_enabled():
        return

    # Get rate limiter
    from garak.ratelimit.factory import get_rate_limiter
    rate_limiter = get_rate_limiter()

    # Count tokens (if TPM tracking enabled)
    tokens = None
    if self.rate_limit_config and self.rate_limit_config.tpm:
        from garak.ratelimit.config import get_config_loader
        loader = get_config_loader()
        token_config = loader.get_token_counter_config(self.provider_name)

        if token_config:
            from garak.ratelimit.token_counter import count_tokens
            tokens = count_tokens(
                prompt=prompt,
                model=self.name,
                config=token_config
            )

    # Acquire rate limit slot
    rate_limiter.acquire(
        provider=self.provider_name,
        model=self.name,
        tokens=tokens
    )


# ===== Post-Request Hook =====

# 4. After API call
def _post_generate_hook(self, response: Any) -> None:
    """Hook called after generate()."""

    # Only track if rate limiting enabled
    if not is_rate_limiting_enabled():
        return

    # Get rate limiter
    from garak.ratelimit.factory import get_rate_limiter
    rate_limiter = get_rate_limiter()

    # Extract actual usage from response
    actual_tokens = self._extract_token_usage(response)

    # Record actual usage
    rate_limiter.record_usage(
        provider=self.provider_name,
        model=self.name,
        tokens=actual_tokens
    )


# ===== Configuration Loading =====

# 5. Load configuration
loader = get_config_loader()

# Get system config
system_config = loader.get_system_config()
print(f"Safety margin: {system_config.default_safety_margin}")
print(f"Window size: {system_config.window_size_seconds}s")

# Get provider config
openai_config = loader.get_config().plugins.openai
print(f"OpenAI backoff strategy: {openai_config.backoff.strategy}")

# Get rate limits for specific model
rate_limits = loader.get_rate_limits("openai", "gpt-4o")
if rate_limits:
    print(f"gpt-4o: RPM={rate_limits.rpm}, TPM={rate_limits.tpm}")

# Get backoff config
backoff = loader.get_backoff_config("openai")
if backoff:
    print(f"Backoff: strategy={backoff.strategy}, max={backoff.max_value}s")

# Get token counter config
token_config = loader.get_token_counter_config("openai")
if token_config:
    print(f"Token counter: library={token_config.library}")


# ===== Hierarchical Override Example =====

# 6. Override resolution
# Config file:
# plugins:
#   generators:
#     openai:
#       rate_limits:
#         gpt-4o: {rpm: 10000, tpm: 2000000}
#         gpt-3.5-turbo: {rpm: 10000, tpm: 2000000}
#         default: {rpm: 3500, tpm: 90000}

# Lookup gpt-4o
config_gpt4 = loader.get_rate_limits("openai", "gpt-4o")
# Returns: RateLimitConfig(rpm=10000, tpm=2000000)  # Exact match

# Lookup unknown model
config_unknown = loader.get_rate_limits("openai", "gpt-5-turbo")
# Returns: RateLimitConfig(rpm=3500, tpm=90000)  # Falls back to 'default'

# Lookup unknown provider
config_invalid = loader.get_rate_limits("invalid-provider", "some-model")
# Returns: None  # Provider not found


# ===== Azure Model Mapping =====

# 7. Azure deployment → model mapping
azure_config = loader.get_config().plugins.azure

# Get deployment rate limits
deployment_limits = loader.get_rate_limits("azure", "my-gpt4-prod")
# Returns: RateLimitConfig(rps=10, tpm_quota=120000, concurrent=5)

# Map Azure model name to OpenAI model name
azure_model_name = "gpt-35-turbo"
openai_model_name = azure_config.model_mapping.get(azure_model_name)
# Returns: "gpt-3.5-turbo-0125"

# Use mapped name for token counting
if token_config.use_mapped_model:
    tokens = count_tokens(prompt, model=openai_model_name)
else:
    tokens = count_tokens(prompt, model=azure_model_name)


# ===== Validation Error Handling =====

# 8. Handle validation errors
from pydantic import ValidationError

try:
    # Simulate loading invalid config
    invalid_data = {
        "plugins": {
            "openai": {
                "rate_limits": {
                    "gpt-4o": {"rpm": -100}  # Invalid!
                }
            }
        }
    }
    config = RateLimitingConfig(**invalid_data)
except ValidationError as e:
    # Log error, use defaults
    logger.error(f"Invalid config: {e}")
    config = RateLimitingConfig()  # Safe defaults


# ===== Caching Behavior =====

# 9. Configuration is cached (singleton)
loader1 = get_config_loader()  # Loads from file
loader2 = get_config_loader()  # Returns cached instance

assert loader1 is loader2  # Same object

# Reset cache (testing only)
from garak.ratelimit.config import reset_config_loader
reset_config_loader()

loader3 = get_config_loader()  # Reloads from file
assert loader1 is not loader3  # Different object


# ===== Safety Margin Application =====

# 10. Apply safety margin to limits
from garak.ratelimit.config import get_safety_margin

# Get configured safety margin
margin = get_safety_margin()  # Returns 0.9 (default)

# Apply to rate limits
rate_limits = loader.get_rate_limits("openai", "gpt-4o")
if rate_limits:
    effective_rpm = int(rate_limits.rpm * margin)
    effective_tpm = int(rate_limits.tpm * margin)

    print(f"Stated: RPM={rate_limits.rpm}, TPM={rate_limits.tpm}")
    print(f"Effective (90%): RPM={effective_rpm}, TPM={effective_tpm}")
    # Stated: RPM=10000, TPM=2000000
    # Effective (90%): RPM=9000, TPM=1800000


# ===== Dynamic Limit Updates (OpenAI Headers) =====

# 11. Extract limits from API response headers
def extract_openai_limits(headers: Dict[str, str]) -> Optional[RateLimitConfig]:
    """Extract rate limits from OpenAI API response headers."""

    prefix = "x-ratelimit-limit-"

    rpm = None
    tpm = None

    # Extract RPM
    rpm_key = f"{prefix}requests"
    if rpm_key in headers:
        rpm = int(headers[rpm_key])

    # Extract TPM
    tpm_key = f"{prefix}tokens"
    if tpm_key in headers:
        tpm = int(headers[tpm_key])

    if rpm or tpm:
        return RateLimitConfig(rpm=rpm, tpm=tpm)

    return None

# Example response
response_headers = {
    "x-ratelimit-limit-requests": "10000",
    "x-ratelimit-limit-tokens": "2000000",
    "x-ratelimit-remaining-requests": "9950",
    "x-ratelimit-remaining-tokens": "1995000"
}

dynamic_limits = extract_openai_limits(response_headers)
if dynamic_limits:
    print(f"Dynamic limits: RPM={dynamic_limits.rpm}, TPM={dynamic_limits.tpm}")
    # Update rate limiter with actual limits
    rate_limiter.update_limits(
        provider="openai",
        model="gpt-4o",
        limits=dynamic_limits
    )
```

---

## Migration Examples

### Example 1: Disabled (Default)

**Config:**
```yaml
system:
  rate_limiting:
    enabled: false  # Default
```

**Behavior:**
- `is_rate_limiting_enabled()` → False
- `_pre_generate_hook()` → No-op (returns immediately)
- `_post_generate_hook()` → No-op (returns immediately)
- Existing `@backoff` decorators still active
- Zero performance impact

### Example 2: Enabled for OpenAI Only

**Config:**
```yaml
system:
  rate_limiting:
    enabled: true

plugins:
  generators:
    openai:
      rate_limits:
        gpt-4o: {rpm: 10000, tpm: 2000000}
        default: {rpm: 3500, tpm: 90000}
```

**Behavior:**
- OpenAI generators use rate limiter
- Azure/HuggingFace use defaults (conservative limits)
- Gradual migration path

### Example 3: Full Production Config

**Config:**
```yaml
system:
  rate_limiting:
    enabled: true
    default_safety_margin: 0.95  # Conservative
    log_level: "INFO"

plugins:
  generators:
    openai:
      rate_limits:
        gpt-4o: {rpm: 10000, tpm: 2000000}
        gpt-4o-mini: {rpm: 30000, tpm: 10000000}
        default: {rpm: 3500, tpm: 90000}
      backoff:
        strategy: "fibonacci"
        max_value: 70
        jitter: true

    azure:
      rate_limits:
        prod-gpt4: {rps: 10, tpm_quota: 120000, concurrent: 5}
        dev-gpt35: {rps: 6, tpm_quota: 50000, concurrent: 3}
        default: {rps: 6, tpm_quota: 30000, concurrent: 3}
      model_mapping:
        gpt-35-turbo: "gpt-3.5-turbo-0125"
        gpt-4: "gpt-4-0613"
      backoff:
        strategy: "fibonacci"
        max_value: 70

    huggingface:
      rate_limits:
        default: {rpm: 60, rps: 1}
      backoff:
        strategy: "fibonacci"
        max_value: 125
        base_delay: 2.0
```

**Behavior:**
- All providers use rate limiting
- Provider-specific configurations respected
- Safety margin applied to all limits
- Monitoring enabled

---

## Testing Strategy

### Unit Tests

```python
import pytest
from pydantic import ValidationError
from garak.ratelimit.config import (
    RateLimitConfig,
    BackoffConfig,
    TokenCounterConfig,
    RateLimitingConfig,
    RateLimitConfigLoader,
    load_rate_limit_config,
    is_rate_limiting_enabled,
    reset_config_loader
)


class TestRateLimitConfig:
    """Test RateLimitConfig validation."""

    def test_valid_rpm_tpm(self):
        """Test valid RPM and TPM."""
        config = RateLimitConfig(rpm=10000, tpm=2000000)
        assert config.rpm == 10000
        assert config.tpm == 2000000

    def test_valid_rps_only(self):
        """Test valid RPS only."""
        config = RateLimitConfig(rps=10)
        assert config.rps == 10
        assert config.rpm is None

    def test_at_least_one_limit_required(self):
        """Test that at least one limit must be specified."""
        with pytest.raises(ValidationError, match="At least one rate limit"):
            RateLimitConfig()

    def test_negative_limit_rejected(self):
        """Test that negative limits are rejected."""
        with pytest.raises(ValidationError, match="positive"):
            RateLimitConfig(rpm=-100)

    def test_zero_limit_rejected(self):
        """Test that zero limits are rejected."""
        with pytest.raises(ValidationError, match="positive"):
            RateLimitConfig(rpm=0)

    def test_rps_rpm_consistency(self):
        """Test RPS/RPM consistency validation."""
        # Valid: 10 rps * 60 = 600 rpm
        config = RateLimitConfig(rps=10, rpm=600)
        assert config.rps == 10
        assert config.rpm == 600

        # Invalid: 10 rps but rpm=100 (should be 600)
        with pytest.raises(ValidationError, match="Inconsistent"):
            RateLimitConfig(rps=10, rpm=100)

    def test_to_dict(self):
        """Test conversion to dict."""
        config = RateLimitConfig(rpm=10000, tpm=2000000)
        d = config.to_dict()
        assert d == {"rpm": 10000, "tpm": 2000000}
        assert "rps" not in d  # None values excluded


class TestBackoffConfig:
    """Test BackoffConfig validation."""

    def test_valid_fibonacci(self):
        """Test valid Fibonacci backoff."""
        config = BackoffConfig(
            strategy="fibonacci",
            max_value=70,
            max_tries=10
        )
        assert config.strategy == "fibonacci"
        assert config.max_value == 70
        assert config.max_tries == 10

    def test_max_value_too_high(self):
        """Test that max_value > 600 is rejected."""
        with pytest.raises(ValidationError, match="cannot exceed 600"):
            BackoffConfig(max_value=1000)

    def test_defaults(self):
        """Test default values."""
        config = BackoffConfig()
        assert config.strategy == "fibonacci"
        assert config.max_value == 70.0
        assert config.jitter is True


class TestRateLimitConfigLoader:
    """Test configuration loader."""

    @pytest.fixture(autouse=True)
    def reset_loader(self):
        """Reset loader before each test."""
        reset_config_loader()
        yield
        reset_config_loader()

    def test_singleton_pattern(self):
        """Test that loader is singleton."""
        from garak.ratelimit.config import get_config_loader
        loader1 = get_config_loader()
        loader2 = get_config_loader()
        assert loader1 is loader2

    def test_default_config_disabled(self):
        """Test that default config has rate limiting disabled."""
        loader = RateLimitConfigLoader()
        assert not loader.is_enabled()

    def test_get_rate_limits_unknown_provider(self):
        """Test that unknown provider returns None."""
        loader = RateLimitConfigLoader()
        config = loader.get_rate_limits("invalid-provider", "some-model")
        assert config is None

    def test_get_rate_limits_fallback_to_default(self):
        """Test that unknown model falls back to 'default'."""
        loader = RateLimitConfigLoader()
        config = loader.get_rate_limits("openai", "unknown-model-123")

        # Should return 'default' config
        assert config is not None
        assert config.rpm == 3500  # Default OpenAI RPM

    def test_hierarchical_override(self, tmp_path):
        """Test hierarchical config override."""
        # Create test config
        config_file = tmp_path / "test.yaml"
        config_file.write_text("""
system:
  rate_limiting:
    enabled: true

plugins:
  generators:
    openai:
      rate_limits:
        gpt-4o: {rpm: 10000, tpm: 2000000}
        default: {rpm: 3500, tpm: 90000}
        """)

        # Load config
        loader = RateLimitConfigLoader()
        loader._config_path = config_file
        loader._load_config()

        # Test exact match
        config_gpt4 = loader.get_rate_limits("openai", "gpt-4o")
        assert config_gpt4.rpm == 10000

        # Test fallback to default
        config_unknown = loader.get_rate_limits("openai", "gpt-5")
        assert config_unknown.rpm == 3500


class TestConvenienceFunctions:
    """Test convenience functions."""

    @pytest.fixture(autouse=True)
    def reset_loader(self):
        """Reset loader before each test."""
        reset_config_loader()
        yield
        reset_config_loader()

    def test_is_rate_limiting_enabled_default(self):
        """Test that rate limiting is disabled by default."""
        assert not is_rate_limiting_enabled()

    def test_load_rate_limit_config(self):
        """Test load_rate_limit_config convenience function."""
        config = load_rate_limit_config("openai", "gpt-4o")
        assert config is not None
        # Should have default values
        assert config.rpm == 3500


# Integration test example
class TestEndToEndConfiguration:
    """Test end-to-end configuration loading."""

    def test_complete_config_loading(self, tmp_path):
        """Test loading complete configuration."""
        config_file = tmp_path / "garak.core.yaml"
        config_file.write_text("""
system:
  rate_limiting:
    enabled: true
    default_safety_margin: 0.95
    window_size_seconds: 60
    log_level: "INFO"

plugins:
  generators:
    openai:
      rate_limits:
        gpt-4o: {rpm: 10000, tpm: 2000000}
        default: {rpm: 3500, tpm: 90000}
      backoff:
        strategy: "fibonacci"
        max_value: 70

    azure:
      rate_limits:
        my-deployment: {rps: 10, tpm_quota: 120000}
        default: {rps: 6, tpm_quota: 30000}
      model_mapping:
        gpt-35-turbo: "gpt-3.5-turbo-0125"
        """)

        # Load config
        reset_config_loader()
        loader = RateLimitConfigLoader()
        loader._config_path = config_file
        loader._load_config()

        # Verify system config
        assert loader.is_enabled()
        assert loader.get_system_config().default_safety_margin == 0.95

        # Verify OpenAI config
        openai_limits = loader.get_rate_limits("openai", "gpt-4o")
        assert openai_limits.rpm == 10000
        assert openai_limits.tpm == 2000000

        # Verify Azure config
        azure_limits = loader.get_rate_limits("azure", "my-deployment")
        assert azure_limits.rps == 10
        assert azure_limits.tpm_quota == 120000

        # Verify backoff config
        openai_backoff = loader.get_backoff_config("openai")
        assert openai_backoff.strategy == "fibonacci"
        assert openai_backoff.max_value == 70
```

---

## Summary

### What We've Designed

1. **YAML Schema Structure**
   - System-level configuration (global enable, safety margin, logging)
   - Provider-level configuration (OpenAI, Azure, HuggingFace, future)
   - Hierarchical overrides (system → provider → model)
   - Extensible rate limit types (RPM, TPM, RPS, quota, future)

2. **Pydantic Validation Models**
   - `RateLimitConfig` - Rate limit types with validation
   - `BackoffConfig` - Retry strategy configuration
   - `TokenCounterConfig` - Token counting configuration
   - Provider-specific configs (OpenAI, Azure, HF, Anthropic, Gemini)
   - `RateLimitingConfig` - Top-level root config

3. **Configuration Loader**
   - Singleton pattern with caching
   - Load from multiple locations (env, cwd, home, system)
   - Validate with Pydantic at load time
   - Graceful error handling (invalid → defaults)
   - Hierarchical resolution (model → provider → default)

4. **JSON Schema**
   - IDE autocomplete support
   - Real-time validation in editors
   - Documentation for all fields

5. **Edge Case Handling**
   - Missing config → safe defaults
   - Invalid values → validation errors
   - Unknown providers → None returned
   - Unknown models → fall back to 'default'

6. **Testing Strategy**
   - Unit tests for all validation rules
   - Integration tests for loader
   - Edge case coverage
   - Backward compatibility verification

### Key Features

✅ **Declarative** - All config in YAML, no hardcoded values
✅ **Type-safe** - Pydantic catches errors at load time
✅ **Hierarchical** - Model overrides provider defaults
✅ **Extensible** - New limit types added to schema only
✅ **Optional** - Missing config → safe defaults
✅ **Cached** - Parse once, reuse across generators
✅ **Validated** - Comprehensive validation rules
✅ **IDE-friendly** - JSON Schema for autocomplete

### Next Steps

<function_calls>
<invoke name="TodoWrite">
<parameter name="todos">[{"content": "Create master task plan for configuration schema design", "status": "completed", "activeForm": "Creating master task plan for configuration schema design"}, {"content": "Design YAML schema structure with examples", "status": "completed", "activeForm": "Designing YAML schema structure with examples"}, {"content": "Create Pydantic validation models", "status": "completed", "activeForm": "Creating Pydantic validation models"}, {"content": "Design configuration loader with caching", "status": "completed", "activeForm": "Designing configuration loader with caching"}, {"content": "Create JSON Schema for IDE autocomplete", "status": "completed", "activeForm": "Creating JSON Schema for IDE autocomplete"}, {"content": "Document edge cases and validation rules", "status": "completed", "activeForm": "Documenting edge cases and validation rules"}, {"content": "Write pseudo-code implementations", "status": "completed", "activeForm": "Writing pseudo-code implementations"}]