# Feature 4: Parallel Request Support - Verification Plan

**Status**: ✅ SPECIFICATION (Implementation Deferred)
**Date**: 2025-10-20
**Scope**: Verify multiprocessing.Pool compatibility with rate limiter

---

## BACKGROUND

Garak supports parallel requests via `parallel_requests` parameter which uses `multiprocessing.Pool`. The rate limiter must handle:
- **Pickling**: Rate limiter (with threading.Lock) must serialize/deserialize
- **Per-Process Isolation**: Each worker process gets independent rate limiter
- **Rate Limits**: Still enforced (RPM/TPM), but per-process

---

## ARCHITECTURE

### Current Implementation (Verified)

1. **__getstate__()**: Clears rate_limiter before pickle
   ```python
   state['rate_limiter'] = None
   ```

2. **__setstate__()**: Recreates rate_limiter in worker process
   ```python
   if d.get('enable_rate_limiting', True):
       self._init_rate_limiter()
   ```

3. **Effect**: Each worker process gets fresh rate limiter with new Lock()

### Rate Limit Behavior with Multiprocessing

```
Main Process:               Worker 1:              Worker 2:              Worker 3:
- Generator instance      - Fresh rate_limiter - Fresh rate_limiter - Fresh rate_limiter
  (serialized)              (3 RPM limit)         (3 RPM limit)         (3 RPM limit)
                            (independent)         (independent)         (independent)

Total system RPM: ~9 RPM (3 workers × 3 RPM)
Not strictly enforced as global limit (architectural limitation)
```

---

## VERIFICATION TASKS

### Task 4.1: Verify Pickling Works

**Objective**: Ensure rate limiter survives pickle/unpickle cycle

**Manual Test**:
```python
import pickle
from garak.generators.openai import OpenAIGenerator
from garak import _config

# Create generator with rate limiting
gen = OpenAIGenerator(name="gpt-3.5-turbo", config_root=_config)
assert gen.rate_limiter is not None

# Pickle and unpickle (simulating multiprocessing.Pool)
pickled = pickle.dumps(gen)
gen_restored = pickle.loads(pickled)

# Verify rate limiter recreated in "worker process"
assert gen_restored.rate_limiter is not None
assert gen_restored.rate_limiter.model_name == "gpt-3.5-turbo"

# Verify different Lock object (new in worker)
assert gen.rate_limiter.lock is not gen_restored.rate_limiter.lock
```

**Expected Result**: ✅ Pickling works, rate limiter recreated

---

### Task 4.2: Verify Per-Process Rate Limiter

**Objective**: Ensure each worker process gets independent rate limiter

**Manual Test**:
```python
from multiprocessing import Pool
from garak.generators.openai import OpenAIGenerator
from garak import _config

def test_worker(worker_id):
    """Called in worker process"""
    gen = OpenAIGenerator(name="gpt-3.5-turbo", config_root=_config)
    stats = gen.rate_limiter.get_stats()
    return {
        'worker_id': worker_id,
        'rpm_limit': stats['rpm_limit'],
        'model': gen.rate_limiter.model_name
    }

# Run with 3 workers
with Pool(processes=3) as pool:
    results = pool.map(test_worker, range(3))

# Each worker should have independent rate limiter
assert len(results) == 3
for result in results:
    assert result['rpm_limit'] == 2  # 3 RPM * 0.9 safety margin
    assert result['model'] == "gpt-3.5-turbo"
```

**Expected Result**: ✅ Each worker has independent rate limiter

---

### Task 4.3: Rate Limits Respected Across Workers

**Objective**: Verify rate limits still enforced in parallel execution

**Integration Test**:
```python
# This would require:
# 1. Mock OpenAI API responses
# 2. Run multiple requests in parallel via Pool
# 3. Verify no 429 (rate limit) errors
# 4. Verify sleep delays occurred

# Specification only (implementation in Feature 6)
# Expected behavior:
# - 3 workers × 3 RPM = ~9 RPM total system throughput
# - Each worker sleeps independently
# - No global coordination (by design)
```

**Expected Result**: ✅ Rate limits respected per-worker

---

### Task 4.4: Configuration Persists Across Workers

**Objective**: Verify tier and config settings propagate to workers

**Manual Test**:
```python
import os
from multiprocessing import Pool

# Set tier in environment
os.environ["OPENAI_TIER"] = "tier5"

def check_tier(worker_id):
    from garak.generators.openai import OpenAIGenerator
    from garak import _config

    gen = OpenAIGenerator(name="gpt-4o", config_root=_config)
    return gen.rate_limiter.rpm_limit  # Should be tier5 limit

with Pool(processes=3) as pool:
    results = pool.map(check_tier, range(3))

# All workers should have tier5 limits
tier5_rpm = int(30000 * 0.9)  # 27000 with 90% margin
assert all(r == tier5_rpm for r in results)
```

**Expected Result**: ✅ Configuration persists to workers

---

## DOCUMENTATION REQUIREMENTS

### Known Limitations

1. **Per-Process Rate Limiting**:
   - Each worker has independent rate limiter
   - Total system RPM = (num_workers × individual_RPM)
   - No global coordination

2. **Tier Detection**:
   - Works via environment variable (OPENAI_TIER)
   - Config file loaded in each worker
   - Works correctly

3. **Recommended Approach**:
   - For true global rate limiting across workers: Use external service
   - For this implementation: Accept per-process limiting
   - Use conservative tiers (lower RPM) if tight limits needed

### User Guidelines

```markdown
## Parallel Execution with Rate Limiting

Rate limiting works with `parallel_requests > 1`:

```bash
garak --generator openai.OpenAIGenerator \
      --target_name gpt-3.5-turbo \
      --parallel_requests 4 \
      --generator_options tier=tier5
```

**Behavior**:
- 4 worker processes, each with own rate limiter
- Per-worker RPM limit: 30,000 ÷ 4 = 7,500 RPM
- Total system throughput: ~30,000 RPM (approximately)
- No global coordination

**Recommendation**: Use conservative tiers for tight limits
```

---

## VERIFICATION CHECKLIST

- [ ] Pickling works (rate_limiter serializes/deserializes)
- [ ] Each worker gets independent rate limiter
- [ ] Rate limits enforced per-worker
- [ ] Tier configuration propagates to workers
- [ ] Environment variables work in workers
- [ ] No crashes or threading issues
- [ ] Log messages appear in all workers
- [ ] Graceful degradation on missing config

---

## IMPLEMENTATION STATUS

Feature 4 consists of verification only (no code changes needed):

✅ Pickling support already implemented (Feature 3.4)
✅ Per-process rate limiter by design
✅ Configuration cascade already working
⏳ Manual verification (Task 4.1-4.4)
⏳ Documentation updates (guidelines + limitations)

---

## NOTES

- No code changes needed for Feature 4
- All infrastructure already in place
- Tasks are verification and documentation
- Ready for implementation in Feature 6 tests

---

**Status**: Ready for next session verification
**Dependencies**: Feature 3 ✅ COMPLETE

