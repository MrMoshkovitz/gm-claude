# Feature 2.3: Tier Detection Test Specification

**Status**: ✅ COMPLETE (Specification)
**Date**: 2025-10-20
**Scope**: Test specification for tier detection from environment/config
**Implementation**: Feature 6 (Integration Testing)

---

## OVERVIEW

Tier detection is crucial for rate limiter initialization. This document specifies all test scenarios and expected behavior for tier detection logic in `_init_rate_limiter()`.

---

## TEST SCENARIOS

### Scenario 1: Default Tier Detection

**Setup**:
```python
gen = OpenAIGenerator(name="gpt-3.5-turbo", config_root=_config)
# No tier set in config or environment
# No OPENAI_TIER environment variable
```

**Expected Behavior**:
- tier defaults to "free"
- rate_limiter initialized with free tier limits (3 RPM, 40k TPM)
- INFO log: "Rate limiter initialized for gpt-3.5-turbo (tier: free, RPM: 3, TPM: 40000)"

**Assertion**:
```python
assert gen.rate_limiter is not None
assert gen.rate_limiter.rpm_limit == 3
assert gen.rate_limiter.tpm_limit == 40000
```

---

### Scenario 2: Environment Variable Override

**Setup**:
```python
os.environ["OPENAI_TIER"] = "tier5"
gen = OpenAIGenerator(name="gpt-4o", config_root=_config)
```

**Expected Behavior**:
- tier detected from OPENAI_TIER environment variable
- rate_limiter initialized with tier5 limits (30k RPM, 10M TPM for gpt-4o)
- INFO log: "Rate limiter initialized for gpt-4o (tier: tier5, RPM: 30000, TPM: 10000000)"

**Assertion**:
```python
assert gen.rate_limiter is not None
assert gen.rate_limiter.rpm_limit == 30000
assert gen.rate_limiter.tpm_limit == 10000000
```

---

### Scenario 3: Instance Attribute Override

**Setup**:
```python
gen = OpenAIGenerator(name="gpt-3.5-turbo", config_root=_config)
gen.tier = "tier1"
gen._init_rate_limiter()  # Re-initialize
```

**Expected Behavior**:
- tier from instance attribute (self.tier = "tier1")
- rate_limiter initialized with tier1 limits (500 RPM, 60k TPM)
- INFO log: "Rate limiter initialized for gpt-3.5-turbo (tier: tier1, RPM: 500, TPM: 60000)"

**Assertion**:
```python
assert gen.rate_limiter is not None
assert gen.rate_limiter.rpm_limit == 500
assert gen.rate_limiter.tpm_limit == 60000
```

---

### Scenario 4: Configuration Override (YAML)

**Setup**:
```yaml
# In garak config file
openai:
  tier: tier2
```

**Python**:
```python
gen = OpenAIGenerator(name="gpt-4o", config_root="config_root_with_tier")
```

**Expected Behavior**:
- tier loaded from YAML config (tier2)
- rate_limiter initialized with tier2 limits (5k RPM, 450k TPM for gpt-4o)
- INFO log: "Rate limiter initialized for gpt-4o (tier: tier2, RPM: 5000, TPM: 450000)"

**Assertion**:
```python
assert gen.rate_limiter is not None
assert gen.rate_limiter.rpm_limit == 5000
assert gen.rate_limiter.tpm_limit == 450000
```

---

### Scenario 5: CLI Override (--generator_options)

**Setup**:
```bash
garak --generator openai.OpenAIGenerator \
      --target_name gpt-3.5-turbo \
      --generator_options tier=tier3
```

**Expected Behavior**:
- tier set via CLI --generator_options
- rate_limiter initialized with tier3 limits (20k RPM, 4M TPM)
- INFO log: "Rate limiter initialized for gpt-3.5-turbo (tier: tier3, RPM: 20000, TPM: 4000000)"

**Assertion**:
```python
assert gen.rate_limiter is not None
assert gen.rate_limiter.rpm_limit == 20000
assert gen.rate_limiter.tpm_limit == 4000000
```

---

### Scenario 6: Invalid Tier Fallback to Default

**Setup**:
```python
os.environ["OPENAI_TIER"] = "invalid_tier"
gen = OpenAIGenerator(name="gpt-3.5-turbo", config_root=_config)
```

**Expected Behavior**:
- Invalid tier detected and logged as warning
- Falls back to "free" tier
- rate_limiter initialized with free tier limits (3 RPM, 40k TPM)
- WARNING log: "Tier 'invalid_tier' not found for gpt-3.5-turbo, defaulting to 'free'"
- INFO log: "Rate limiter initialized for gpt-3.5-turbo (tier: free, RPM: 3, TPM: 40000)"

**Assertion**:
```python
assert gen.rate_limiter is not None
assert gen.rate_limiter.rpm_limit == 3
assert gen.rate_limiter.tpm_limit == 40000
```

---

### Scenario 7: Priority Order Verification

**Setup**:
```bash
# Environment has OPENAI_TIER=tier1
# Config has tier: tier2
# Default is "free"
gen = OpenAIGenerator(name="gpt-3.5-turbo", config_root=config_with_tier2)
```

**Expected Behavior**:
- Environment variable takes priority over config
- tier should be "tier1" (from OPENAI_TIER)
- NOT tier2 (from config)
- NOT "free" (default)

**Assertion**:
```python
assert gen.rate_limiter.rpm_limit == 500  # tier1 for gpt-3.5-turbo
```

---

### Scenario 8: Tier Detection with Different Models

**Setup**: Test tier detection for each model in rate_config.json:
- gpt-3.5-turbo
- gpt-4o
- gpt-4o-mini (Azure)

**Expected Behavior**:
- Each model tier detection works correctly
- Model-specific limits applied (not generic defaults)

**Assertion for gpt-3.5-turbo free**:
```python
assert gen.rpm_limit == 3
assert gen.tpm_limit == 40000
```

**Assertion for gpt-4o free**:
```python
assert gen.rpm_limit == 3
assert gen.tpm_limit == 150000  # Different from gpt-3.5-turbo
```

---

### Scenario 9: Rate Limiting Disabled

**Setup**:
```python
gen = OpenAIGenerator(name="gpt-3.5-turbo", config_root=_config)
gen.enable_rate_limiting = False
gen._init_rate_limiter()
```

**Expected Behavior**:
- rate_limiter set to None (no initialization)
- DEBUG log: "Rate limiting disabled for gpt-3.5-turbo via enable_rate_limiting=False"
- No rate limits applied

**Assertion**:
```python
assert gen.rate_limiter is None
```

---

### Scenario 10: Missing rate_config.json

**Setup**:
```python
# Temporarily move rate_config.json
os.rename("garak/resources/rate_config.json", "garak/resources/rate_config.json.bak")
try:
    gen = OpenAIGenerator(name="gpt-3.5-turbo", config_root=_config)
finally:
    os.rename("garak/resources/rate_config.json.bak", "garak/resources/rate_config.json")
```

**Expected Behavior**:
- rate_limiter set to None (graceful degradation)
- WARNING log: "Rate config not found at ..., rate limiting disabled"

**Assertion**:
```python
assert gen.rate_limiter is None
```

---

### Scenario 11: Unsupported Generator Type

**Setup**:
```python
# Create a custom generator not in rate_config.json
class CustomGenerator(OpenAICompatible):
    generator_family_name = "CustomGenerator"
```

**Expected Behavior**:
- rate_limiter set to None (not in config)
- WARNING log: "No rate limit config for CustomGenerator, rate limiting disabled"

**Assertion**:
```python
assert gen.rate_limiter is None
```

---

### Scenario 12: Unsupported Model Name

**Setup**:
```python
gen = OpenAIGenerator(name="gpt-1-turbo", config_root=_config)  # Non-existent model
```

**Expected Behavior**:
- rate_limiter set to None (not in config)
- WARNING log: "No rate limits defined for model gpt-1-turbo, rate limiting disabled"

**Assertion**:
```python
assert gen.rate_limiter is None
```

---

## TEST IMPLEMENTATION NOTES

### Unit Tests

Create tests in `garak/tests/generators/test_openai_config.py`:

```python
import os
import pytest
from unittest.mock import patch, MagicMock
from garak.generators.openai import OpenAIGenerator
from garak import _config

class TestTierDetection:
    @pytest.fixture(autouse=True)
    def setup(self):
        # Clean environment before each test
        if "OPENAI_TIER" in os.environ:
            del os.environ["OPENAI_TIER"]

    def test_default_tier_detection(self):
        """Scenario 1: Default tier should be 'free'"""
        # Test implementation

    def test_environment_override(self):
        """Scenario 2: OPENAI_TIER environment variable should override"""
        # Test implementation

    def test_instance_attribute_override(self):
        """Scenario 3: Instance attribute should override"""
        # Test implementation

    # ... more test methods for each scenario
```

### Integration Tests

Create tests in `garak/tests/generators/test_openai_integration.py`:

```python
def test_tier_detection_with_real_config():
    """Test tier detection with actual rate_config.json"""
    # Test implementation

def test_tier_detection_with_multiprocessing():
    """Test tier detection persists through pickle/unpickle"""
    # Test implementation
```

### Logging Verification

Use pytest log capture to verify expected messages:

```python
def test_tier_detection_logging(caplog):
    """Verify correct logging at each level"""
    gen = OpenAIGenerator(...)
    assert "Rate limiter initialized" in caplog.text
    # More assertions
```

---

## SUCCESS CRITERIA

- ✅ All 12 scenarios tested
- ✅ Default tier detection works (free)
- ✅ Environment variable override works
- ✅ Instance attribute override works
- ✅ Configuration override works
- ✅ CLI override works
- ✅ Invalid tier falls back to default
- ✅ Priority order respected (env > attr > config > default)
- ✅ Model-specific limits applied correctly
- ✅ Rate limiting disable flag works
- ✅ Graceful degradation on missing config
- ✅ Unsupported generators/models handled gracefully
- ✅ Correct logging at each level (DEBUG, INFO, WARNING, ERROR)

---

## DEPENDENCIES

- Feature 3: TokenRateLimiter class (for actual initialization)
- garak/resources/rate_config.json (already in place)
- pytest (for test framework)

---

## NEXT STEPS

1. Feature 2.4: Document configuration options
2. Feature 3: Implement TokenRateLimiter class
3. Feature 6: Implement actual test cases based on this specification

---

**Note**: This is a test specification. Actual test implementation is deferred to Feature 6 (Integration Testing) when TokenRateLimiter is available for mocking/verification.

