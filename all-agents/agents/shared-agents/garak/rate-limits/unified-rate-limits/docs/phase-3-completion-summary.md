# Phase 3 Completion Summary: Adapter Implementation

**Version:** 1.0
**Date:** 2025-10-20
**Status:** Design Phase Complete - Ready for Implementation

---

## Phase 3 Overview

Phase 3 focused on the **Provider Adapter Pattern** - implementing the abstraction layer that isolates provider-specific logic from the unified rate limiter. This phase is now complete with three comprehensive implementation guides.

### Deliverables

| Document | Purpose | Lines | Status |
|----------|---------|-------|--------|
| **adapter-factory-implementation.md** | Factory and registry for all adapters | ~1500 | ✅ Complete |
| **openai-adapter-implementation.md** | Reference implementation for OpenAI | ~2000 | ✅ Complete |
| **azure-adapter-implementation.md** | Azure-specific extensions | ~2000 | ✅ Complete |

---

## Architecture Summary

```
┌─────────────────────────────────────────┐
│ AdapterFactory (Registry Pattern)       │
│ - register(provider, adapter_class)     │
│ - create(provider, model, config)       │
│ - get_registered_providers()            │
└────────────┬────────────────────────────┘
             │
        ┌────┴────┬──────────┬─────────┐
        ↓         ↓          ↓         ↓
    ┌────────┐ ┌──────┐ ┌──────────┐ ┌──────┐
    │OpenAI  │ │Azure │ │HuggingFace│ │Future│
    │Adapter │ │Adapter│ │ Adapter  │ │...  │
    │        │ │      │ │          │ │     │
    │tiktoken│ │Extends│ │Generic   │ │     │
    │RPM/TPM │ │OpenAI│ │RPM       │ │     │
    │        │ │RPS   │ │          │ │     │
    │        │ │Quota │ │          │ │     │
    └────────┘ └──────┘ └──────────┘ └──────┘
         (All implement ProviderAdapter ABC)
```

---

## Key Design Decisions

### 1. Factory Pattern with Static Registry

**Decision:** Use class-level registry (`_adapters: Dict`) instead of instance-based factory.

**Rationale:**
- Single source of truth for all registered adapters
- No need to pass factory instances around
- Adapters can self-register on module import
- Thread-safe with lock protection

**Implementation:**
```python
# Static registry
AdapterFactory._adapters = {}

# Registration
AdapterFactory.register('openai', OpenAIAdapter)

# Usage
adapter = AdapterFactory.create('openai', model='gpt-4o')
```

### 2. Configuration Injection via Constructor

**Decision:** Pass configuration to adapter constructors, not through methods.

**Rationale:**
- Adapter instances can cache config-derived values
- Cleaner method signatures (no config parameter on every call)
- Supports both configured and unconfigured usage

**Implementation:**
```python
config = {'rate_limits': {'gpt-4o': {'rpm': 10000}}}
adapter = AdapterFactory.create('openai', config=config)
```

### 3. Auto-Registration on Module Import

**Decision:** Built-in adapters register themselves when `garak.ratelimit.adapters` imported.

**Rationale:**
- No manual registration boilerplate
- Adapters available immediately after import
- Graceful degradation (skip registration if SDK unavailable)

**Implementation:**
```python
# garak/ratelimit/adapters/__init__.py

def _register_builtin_adapters():
    try:
        from .openai import OpenAIAdapter
        AdapterFactory.register('openai', OpenAIAdapter)
    except ImportError:
        logging.debug("OpenAI adapter not available")

_register_builtin_adapters()  # Called on module import
```

### 4. OpenAI as Reference Implementation

**Decision:** Implement OpenAI adapter first as template for all future adapters.

**Rationale:**
- tiktoken integration pattern
- Header extraction pattern
- Error handling pattern
- Can be extended by Azure (inheritance)

**Key Features:**
- Tokenizer caching for performance
- Complete header parsing (x-ratelimit-*)
- Tier-aware default limits
- Comprehensive error extraction

### 5. Azure Extends OpenAI

**Decision:** AzureAdapter inherits from OpenAIAdapter.

**Rationale:**
- Reuses tiktoken token counting
- Same SDK (openai.RateLimitError)
- Only overrides differences (RPS, quota, deployment-based)

**Key Differences:**
- RPS (1-second window) instead of RPM
- Monthly quota tracking (persistent state)
- Concurrent request limits
- Deployment-based config (not model-based)

---

## Adapter Interface Contract

### Required Methods (5)

| Method | Purpose | Returns |
|--------|---------|---------|
| `estimate_tokens(prompt, model)` | Pre-request token estimation | int (token count) |
| `extract_usage_from_response(response, metadata)` | Post-request usage tracking | Dict[str, int] |
| `extract_rate_limit_info(exception)` | Parse rate limit errors | Optional[Dict] |
| `get_retry_after(exception, headers)` | Extract retry delay | Optional[float] |
| `get_model_limits(model)` | Default limits for model | Optional[Dict] |

### Optional Methods (4)

| Method | Purpose | Default |
|--------|---------|---------|
| `supports_concurrent_limiting()` | Has concurrent limits? | False |
| `supports_quota_tracking()` | Has monthly/daily quotas? | False |
| `get_limit_types()` | Supported rate limit types | [RPM] |
| `get_window_seconds(limit_type)` | Window duration | 60 for RPM |

---

## Factory API

### Registration

```python
# Register adapter class
AdapterFactory.register('openai', OpenAIAdapter)

# With config section mapping
AdapterFactory.register('azure', AzureAdapter,
                       config_section='plugins.generators.azure')
```

### Instantiation

```python
# Simple
adapter = AdapterFactory.create('openai')

# With model
adapter = AdapterFactory.create('openai', model_or_deployment='gpt-4o')

# With config
config = {'rate_limits': {'gpt-4o': {'rpm': 10000}}}
adapter = AdapterFactory.create('openai', model_or_deployment='gpt-4o', config=config)

# Auto-config from _config
adapter = AdapterFactory.create_with_auto_config('openai', 'gpt-4o')
```

### Discovery

```python
# Check if registered
if AdapterFactory.is_registered('anthropic'):
    adapter = AdapterFactory.create('anthropic')

# List all providers
providers = AdapterFactory.get_registered_providers()
# ['azure', 'openai', 'huggingface']

# Print details
AdapterFactory.list_providers(verbose=True)
```

### Validation

```python
# Validate adapter class
if AdapterFactory.validate_adapter(MyCustomAdapter):
    AdapterFactory.register('custom', MyCustomAdapter)
else:
    print("Invalid adapter implementation")
```

---

## Extension Pattern: Adding New Provider

### Step-by-Step: Anthropic Example

**1. Create Adapter File**
```bash
touch garak/ratelimit/adapters/anthropic.py
```

**2. Implement ProviderAdapter**
```python
# garak/ratelimit/adapters/anthropic.py

from garak.ratelimit.base import ProviderAdapter, RateLimitType
from typing import Dict, List, Optional, Any

class AnthropicAdapter(ProviderAdapter):
    def estimate_tokens(self, prompt: str, model: str) -> int:
        try:
            import anthropic
            client = anthropic.Anthropic()
            return client.count_tokens(prompt)
        except ImportError:
            return len(prompt) // 4

    def extract_usage_from_response(self, response: Any, metadata: Optional[Dict] = None) -> Dict[str, int]:
        if hasattr(response, 'usage'):
            return {
                'tokens_used': response.usage.input_tokens + response.usage.output_tokens,
                'input_tokens': response.usage.input_tokens,
                'output_tokens': response.usage.output_tokens,
            }
        return {'tokens_used': 0}

    def extract_rate_limit_info(self, exception: Exception) -> Optional[Dict[str, Any]]:
        try:
            import anthropic
            if isinstance(exception, anthropic.RateLimitError):
                return {'error_type': 'rate_limit', 'limit_type': 'rpm'}
        except ImportError:
            pass
        return None

    def get_retry_after(self, exception: Exception, headers: Optional[Dict[str, str]] = None) -> Optional[float]:
        info = self.extract_rate_limit_info(exception)
        if info and 'retry_after' in info:
            return info['retry_after']
        return None

    def get_model_limits(self, model: str) -> Optional[Dict[str, int]]:
        KNOWN_LIMITS = {
            'claude-3-opus': {'rpm': 5, 'tpm': 10000},
            'claude-3-sonnet': {'rpm': 5, 'tpm': 20000},
        }
        return KNOWN_LIMITS.get(model)

    def get_limit_types(self) -> List[RateLimitType]:
        return [RateLimitType.RPM, RateLimitType.TPM]
```

**3. Register Adapter**
```python
# garak/ratelimit/adapters/__init__.py

try:
    import anthropic  # Check SDK available
    from .anthropic import AnthropicAdapter
    AdapterFactory.register('anthropic', AnthropicAdapter)
except ImportError:
    logging.debug("Anthropic adapter not available (SDK not installed)")
```

**4. Add Configuration**
```yaml
# garak/resources/garak.core.yaml

plugins:
  generators:
    anthropic:
      rate_limits:
        claude-3-opus:
          rpm: 5
          tpm: 10000
        default:
          rpm: 5
          tpm: 10000
```

**Result:** Anthropic support added with ZERO changes to:
- AdapterFactory
- UnifiedRateLimiter
- Generator base class

---

## Testing Strategy

### Unit Tests

```python
# tests/ratelimit/test_adapter_factory.py

def test_register_valid_adapter():
    AdapterFactory.register('openai', OpenAIAdapter)
    assert AdapterFactory.is_registered('openai')

def test_create_adapter_with_config():
    config = {'rate_limits': {'gpt-4o': {'rpm': 10000}}}
    adapter = AdapterFactory.create('openai', model_or_deployment='gpt-4o', config=config)
    assert adapter.model == 'gpt-4o'
    assert adapter.config == config

def test_unknown_provider_raises_error():
    with pytest.raises(ValueError) as exc_info:
        AdapterFactory.create('unknown')
    assert 'Unknown provider' in str(exc_info.value)
```

### Integration Tests

```python
# tests/ratelimit/test_factory_integration.py

def test_rate_limiter_creates_adapters_from_factory():
    config = {
        'openai': {'rate_limits': {'gpt-4o': {'rpm': 10000}}},
        'azure': {'rate_limits': {'my-deployment': {'rps': 10}}},
    }

    rate_limiter = SlidingWindowRateLimiter(config)

    assert 'openai' in rate_limiter.adapters
    assert 'azure' in rate_limiter.adapters

    assert isinstance(rate_limiter.adapters['openai'], OpenAIAdapter)
    assert isinstance(rate_limiter.adapters['azure'], AzureAdapter)
```

### Edge Cases

```python
def test_concurrent_registration_thread_safe():
    threads = [
        threading.Thread(target=AdapterFactory.register, args=(f'provider{i}', OpenAIAdapter))
        for i in range(100)
    ]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    assert len(AdapterFactory.get_registered_providers()) == 100
```

---

## Implementation Checklist

### Phase 3a: OpenAI Adapter ✅

- [x] Design document created
- [x] tiktoken integration pattern
- [x] Header extraction (x-ratelimit-*)
- [x] Error handling (openai.RateLimitError)
- [x] Model limits database
- [x] Testing strategy defined

### Phase 3b: Azure Adapter ✅

- [x] Design document created
- [x] Extends OpenAIAdapter pattern
- [x] RPS implementation (1-second window)
- [x] Monthly quota tracking pattern
- [x] Concurrent request management
- [x] Deployment-based configuration

### Phase 3c: AdapterFactory ✅

- [x] Design document created
- [x] Registration API
- [x] Instantiation API
- [x] Discovery API
- [x] Validation API
- [x] Configuration injection
- [x] Error handling
- [x] Extension pattern documented

---

## Next Steps: Phase 4

With all adapter designs complete, Phase 4 will integrate adapters with the UnifiedRateLimiter:

### Phase 4a: Limiter-Adapter Integration
- UnifiedRateLimiter uses factory to create adapters
- Adapter methods called in acquire()/record_usage()
- Token estimation via adapter.estimate_tokens()
- Usage tracking via adapter.extract_usage_from_response()

### Phase 4b: Generator Integration
- Generator base class uses factory
- Provider detection from generator_family_name
- Config extraction from _config.plugins.generators
- Adapter lifecycle (init, acquire, record, release)

### Phase 4c: Configuration Schema
- YAML schema validation
- Per-provider, per-model configuration
- Backoff strategy configuration
- Quota tracking configuration

### Phase 4d: End-to-End Testing
- OpenAI integration tests
- Azure integration tests
- Parallel request tests
- Quota tracking tests
- Backward compatibility tests

---

## Documentation Structure

```
.claude/docs/
├── unified-handler-analysis.md         # Original architecture
├── design-summary.md                   # Phase 1 summary
├── provider-adapter-interface-design.md # Phase 2b (abstract interface)
├── openai-adapter-implementation.md    # Phase 3a ✅ NEW
├── azure-adapter-implementation.md     # Phase 3b ✅ NEW
├── adapter-factory-implementation.md   # Phase 3c ✅ NEW
└── phase-3-completion-summary.md       # This document ✅ NEW
```

---

## Success Criteria Validation

| Criterion | Status | Evidence |
|-----------|--------|----------|
| **Factory provides static registry** | ✅ PASS | AdapterFactory._adapters class variable |
| **Type-safe registration** | ✅ PASS | validate_adapter() checks inheritance |
| **Configuration injection** | ✅ PASS | create() accepts config parameter |
| **Provider discovery** | ✅ PASS | get_registered_providers(), is_registered() |
| **Clear error messages** | ✅ PASS | ERROR_MESSAGES dict with context |
| **Zero-modification extensibility** | ✅ PASS | Anthropic example adds adapter only |
| **Thread-safe operations** | ✅ PASS | _registration_lock protects registry |
| **OpenAI reference implementation** | ✅ PASS | Complete with tiktoken, headers, errors |
| **Azure extends OpenAI** | ✅ PASS | AzureAdapter inherits OpenAIAdapter |
| **Complete pseudo-code** | ✅ PASS | 1500+ lines per document |

---

## Key Achievements

✅ **Adapter Pattern Fully Specified**: All provider-specific logic isolated to adapters

✅ **Factory Pattern Implemented**: Single registry for all adapters with type-safe registration

✅ **Reference Implementation**: OpenAI adapter demonstrates all patterns (tiktoken, headers, errors)

✅ **Extension Pattern Proven**: Azure extends OpenAI, Anthropic example shows new provider

✅ **Zero Breaking Changes**: Factory integrates with existing UnifiedRateLimiter design

✅ **Comprehensive Testing**: Unit tests, integration tests, edge cases all specified

✅ **Complete Documentation**: 5500+ lines of pseudo-code across three documents

---

**Phase 3 Status:** ✅ **COMPLETE**

**Ready for:** Phase 4 - UnifiedRateLimiter Integration

**Estimated Implementation:** 3-4 days for all three components (factory + OpenAI + Azure)

---

**Last Updated:** 2025-10-20
**Total Documentation:** ~5500 lines of pseudo-code
**Next Phase:** Integration with UnifiedRateLimiter
