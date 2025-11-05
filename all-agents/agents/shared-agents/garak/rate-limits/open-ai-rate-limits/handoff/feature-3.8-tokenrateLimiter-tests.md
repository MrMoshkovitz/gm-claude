# Feature 3.8: TokenRateLimiter Basic Verification Tests

**Status**: ✅ SPECIFICATION (Implementation in Feature 6)
**Date**: 2025-10-20
**Scope**: Quick verification tests for TokenRateLimiter functionality

---

## BASIC VERIFICATION TESTS

### Test 1: Initialization

**Objective**: Verify TokenRateLimiter initializes correctly

```python
from garak.generators.rate_limiter import TokenRateLimiter

limiter = TokenRateLimiter(
    model_name="gpt-3.5-turbo",
    rpm_limit=10,
    tpm_limit=1000
)

# With 90% safety margin:
# rpm_limit = 10 * 0.9 = 9
# tpm_limit = 1000 * 0.9 = 900

assert limiter.rpm_limit == 9
assert limiter.tpm_limit == 900
assert limiter.model_name == "gpt-3.5-turbo"
```

### Test 2: Empty Window

**Objective**: Verify initial state has no requests

```python
stats = limiter.get_stats()
assert stats['current_rpm'] == 0
assert stats['current_tpm'] == 0
assert stats['rpm_available'] == 9
assert stats['tpm_available'] == 900
```

### Test 3: Record Usage

**Objective**: Verify usage recording updates state

```python
limiter.record_usage(prompt_tokens=100, completion_tokens=50)
stats = limiter.get_stats()

assert stats['current_rpm'] == 1  # One request
assert stats['current_tpm'] == 150  # Total tokens
assert stats['rpm_available'] == 8  # 9 - 1
assert stats['tpm_available'] == 750  # 900 - 150
```

### Test 4: Check and Wait - Within Limits

**Objective**: Verify no sleep when within limits

```python
import time

start = time.time()
limiter.check_and_wait(estimated_tokens=100)
elapsed = time.time() - start

assert elapsed < 1  # Should not sleep
```

### Test 5: Check and Wait - RPM Limit

**Objective**: Verify sleep on RPM limit

```python
# Fill up to RPM limit (9 requests)
for i in range(9):
    limiter.record_usage(10, 10)

# Next request should trigger sleep
start = time.time()
limiter.check_and_wait(estimated_tokens=100)
elapsed = time.time() - start

# Should have slept approximately 60 seconds
assert elapsed > 55 and elapsed < 65
```

### Test 6: Check and Wait - TPM Limit

**Objective**: Verify sleep on TPM limit

```python
limiter2 = TokenRateLimiter(
    model_name="gpt-3.5-turbo",
    rpm_limit=1000,  # High RPM limit
    tpm_limit=200    # Low TPM limit (180 after 90% margin)
)

# Record 100 tokens
limiter2.record_usage(50, 50)

# Try to use 100 more tokens (total would be 200 > 180 limit)
start = time.time()
limiter2.check_and_wait(estimated_tokens=100)
elapsed = time.time() - start

# Should have slept
assert elapsed > 55
```

### Test 7: RateLimitExceeded Exception

**Objective**: Verify exception on budget exhaustion

```python
from garak.generators.rate_limiter import RateLimitExceeded

limiter3 = TokenRateLimiter(
    model_name="gpt-3.5-turbo",
    rpm_limit=10,
    tpm_limit=100  # 90 after margin
)

# Record 85 tokens (near limit)
limiter3.record_usage(50, 35)

# Try to use 20 tokens (total would be 105 > 90 limit)
# Should raise exception after sleeping
with pytest.raises(RateLimitExceeded):
    limiter3.check_and_wait(estimated_tokens=20)
```

### Test 8: Sliding Window Pruning

**Objective**: Verify 60-second window pruning

```python
import time
from unittest.mock import patch

limiter4 = TokenRateLimiter(
    model_name="gpt-3.5-turbo",
    rpm_limit=10,
    tpm_limit=1000
)

# Record some usage
limiter4.record_usage(10, 10)
assert limiter4.get_stats()['current_rpm'] == 1

# Mock time to advance 61 seconds
with patch('time.time', return_value=time.time() + 61):
    stats = limiter4.get_stats()

# Old entry should be pruned
assert stats['current_rpm'] == 0
assert stats['current_tpm'] == 0
```

### Test 9: Thread Safety

**Objective**: Verify concurrent access safety

```python
import threading

limiter5 = TokenRateLimiter(
    model_name="gpt-3.5-turbo",
    rpm_limit=100,
    tpm_limit=10000
)

results = []

def worker():
    try:
        limiter5.check_and_wait(100)
        limiter5.record_usage(50, 50)
        results.append("success")
    except Exception as e:
        results.append(f"error: {e}")

threads = [threading.Thread(target=worker) for _ in range(5)]
for t in threads:
    t.start()
for t in threads:
    t.join()

# All threads should succeed
assert len(results) == 5
assert all(r == "success" for r in results)
```

### Test 10: Integration with OpenAI Generator

**Objective**: Verify rate limiter initializes in generator

```python
from garak.generators.openai import OpenAIGenerator
from garak import _config

# This would require mocking OpenAI API, so specification only
# Actual test in Feature 6

# Expected behavior:
# gen = OpenAIGenerator(name="gpt-3.5-turbo", config_root=_config)
# assert gen.rate_limiter is not None
# assert gen.rate_limiter.model_name == "gpt-3.5-turbo"
# assert gen.rate_limiter.rpm_limit == 3 * 0.9 = 2.7
```

---

## TEST IMPLEMENTATION NOTES

### Quick Unit Tests

Create `garak/tests/generators/test_rate_limiter.py`:

```python
import pytest
import time
from unittest.mock import patch
from garak.generators.rate_limiter import TokenRateLimiter, RateLimitExceeded

class TestTokenRateLimiter:
    # Test methods from above (1-9)
    pass
```

### Running Tests

```bash
# Run all tests
pytest garak/tests/generators/test_rate_limiter.py -v

# Run specific test
pytest garak/tests/generators/test_rate_limiter.py::TestTokenRateLimiter::test_initialization -v

# Run with coverage
pytest garak/tests/generators/test_rate_limiter.py --cov=garak.generators.rate_limiter
```

### Expected Results

✅ All 10 tests pass
✅ Code coverage > 95%
✅ No threading issues
✅ Sliding window works correctly
✅ Exception handling verified

---

## IMPLEMENTATION STATUS

✅ Feature 3.1: TokenRateLimiter class created
✅ Feature 3.2: Pre-request rate check integrated
✅ Feature 3.3: Post-response recording integrated
✅ Feature 3.4: Pickling support updated
✅ Feature 3.5: RateLimitExceeded handling added
✅ Feature 3.6: Backoff decorator confirmed
✅ Feature 3.7: Azure support verified
⏳ Feature 3.8: Unit tests (ready for Feature 6)

---

**Next Session**: Implement these tests in Feature 6 (Integration Testing)

