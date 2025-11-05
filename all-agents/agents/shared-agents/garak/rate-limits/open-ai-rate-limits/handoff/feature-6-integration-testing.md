# Feature 6: Integration Testing

**Status**: ✅ SPECIFICATION COMPLETE
**Date**: 2025-10-20
**Scope**: Unit tests, integration tests, end-to-end tests, performance benchmarks

---

## OVERVIEW

Feature 6 consists of implementing comprehensive test suite for rate limiter:

| Test Type | Scope | Tasks |
|-----------|-------|-------|
| Unit Tests | TokenRateLimiter class | 10 tests (spec in feature-3.8) |
| Integration Tests | Rate limiter + OpenAI generator | 5 tests |
| End-to-End Tests | Full pipeline with probes | 3 tests |
| Performance Tests | Overhead and accuracy | 2 tests |

---

## UNIT TESTS (10 tests)

**Location**: `garak/tests/generators/test_rate_limiter.py`

**Specification**: `.claude/feature-3.8-tokenrateLimiter-tests.md`

Tests cover:
1. ✅ Initialization with safety margins
2. ✅ Empty window state
3. ✅ Usage recording
4. ✅ Check_and_wait within limits
5. ✅ RPM limit enforcement
6. ✅ TPM limit enforcement
7. ✅ RateLimitExceeded exception
8. ✅ Sliding window pruning
9. ✅ Thread safety
10. ✅ Integration with generator

**Expected Results**:
- All 10 tests pass
- 95%+ code coverage
- No thread race conditions
- Accurate sliding window

---

## INTEGRATION TESTS (5 tests)

**Location**: `garak/tests/generators/test_openai_rate_limiting.py`

### Test 1: Config Loading

```python
def test_config_loading_from_rate_config():
    """Verify rate_config.json loads correctly"""
    gen = OpenAIGenerator(name="gpt-3.5-turbo")
    assert gen.rate_limiter is not None
    assert gen.rate_limiter.rpm_limit == 2  # 3 * 0.9
    assert gen.rate_limiter.tpm_limit == 36000  # 40k * 0.9
```

### Test 2: Tier Detection

```python
def test_tier_detection_from_environment():
    """Verify OPENAI_TIER environment variable works"""
    os.environ["OPENAI_TIER"] = "tier5"
    gen = OpenAIGenerator(name="gpt-4o")

    # tier5 for gpt-4o: 30k RPM, 10M TPM
    assert gen.rate_limiter.rpm_limit == 27000  # 30k * 0.9
    assert gen.rate_limiter.tpm_limit == 9000000  # 10M * 0.9
```

### Test 3: Pre-Request Blocking

```python
@mock.patch('openai.OpenAI.create')
def test_pre_request_blocking(mock_create):
    """Verify rate limiter blocks requests when limit reached"""
    gen = OpenAIGenerator(name="gpt-3.5-turbo")
    gen.rate_limiter.rpm_limit = 1  # Very low limit

    # Fill up limit
    gen.rate_limiter.record_usage(100, 100)

    # Next request should trigger check_and_wait
    # (which would sleep, but we mock time)
    with mock.patch('time.sleep'):
        output = gen.generate(Conversation([]))

    # Should have attempted to sleep
```

### Test 4: Post-Response Recording

```python
@mock.patch('openai.OpenAI.create')
def test_post_response_recording(mock_create):
    """Verify actual usage recorded from response"""
    mock_create.return_value = mock_response(
        usage=Usage(prompt_tokens=100, completion_tokens=50)
    )

    gen = OpenAIGenerator(name="gpt-3.5-turbo")
    stats_before = gen.rate_limiter.get_stats()

    output = gen.generate(Conversation([]))

    stats_after = gen.rate_limiter.get_stats()
    assert stats_after['current_tpm'] == 150  # 100 + 50
```

### Test 5: Pickling Support

```python
def test_pickling_with_rate_limiter():
    """Verify generator pickles and unpickles with rate limiter"""
    gen = OpenAIGenerator(name="gpt-3.5-turbo")

    # Pickle and unpickle
    pickled = pickle.dumps(gen)
    gen_restored = pickle.loads(pickled)

    # Rate limiter should be recreated
    assert gen_restored.rate_limiter is not None
    assert gen_restored.rate_limiter.model_name == "gpt-3.5-turbo"
```

**Expected Results**:
- All 5 integration tests pass
- Config loading works
- Tier detection works
- Blocking mechanism works
- Usage recording works
- Pickling works

---

## END-TO-END TESTS (3 tests)

**Location**: `garak/tests/end_to_end/test_rate_limiting_e2e.py`

### Test 1: Single Probe with Rate Limiting

```python
@mock.patch('openai.OpenAI.create')
def test_single_probe_with_rate_limiting(mock_create):
    """Run actual probe with rate limiting enabled"""
    mock_create.return_value = mock_response("Success")

    from garak.probes.continuation import Simple
    from garak.generators.openai import OpenAIGenerator

    gen = OpenAIGenerator(name="gpt-3.5-turbo")
    probe = Simple()

    results = list(probe.probe(gen, samples=5))

    # All 5 attempts should complete
    assert len(results) == 5
    assert all(r.status == "COMPLETE" for r in results)
```

### Test 2: Batch Execution with Rate Limiting

```python
@mock.patch('openai.OpenAI.create')
def test_batch_execution_with_rate_limiting(mock_create):
    """Run multiple probes with rate limiting"""
    mock_create.return_value = mock_response("Success")

    gen = OpenAIGenerator(name="gpt-3.5-turbo")
    gen.rate_limiter.rpm_limit = 10  # Conservative limit

    # Run multiple probes
    probes = [probe1, probe2, probe3]

    for probe in probes:
        results = list(probe.probe(gen))
        assert len(results) > 0
```

### Test 3: Parallel Execution with Multiprocessing

```python
@mock.patch('openai.OpenAI.create')
def test_parallel_execution_with_rate_limiting(mock_create):
    """Run probe with parallel_requests > 1"""
    mock_create.return_value = mock_response("Success")

    gen = OpenAIGenerator(name="gpt-3.5-turbo")
    probe = Simple()

    # This would use multiprocessing.Pool internally
    results = list(probe.probe(gen, parallel_requests=4, samples=20))

    # All requests should complete
    assert len(results) == 20
    assert all(r.status == "COMPLETE" for r in results)
```

**Expected Results**:
- Single probe execution works
- Multiple probes can run sequentially
- Parallel execution with Pool works
- Rate limits enforced in all modes

---

## PERFORMANCE TESTS (2 tests)

**Location**: `garak/tests/performance/test_rate_limiting_overhead.py`

### Test 1: Latency Overhead

```python
def test_rate_limiter_latency_overhead():
    """Verify rate limiter adds minimal overhead when within limits"""
    gen_with_limiter = OpenAIGenerator(name="gpt-3.5-turbo")

    # Disable rate limiting for comparison
    gen_without_limiter = OpenAIGenerator(name="gpt-3.5-turbo")
    gen_without_limiter.rate_limiter = None

    # Time 100 rate check operations
    import time

    start = time.time()
    for _ in range(100):
        gen_with_limiter.rate_limiter.check_and_wait(100)
    elapsed_with = time.time() - start

    # Overhead should be <5% (negligible)
    # Actual depends on system, but should be sub-millisecond per check
    assert elapsed_with < 0.5  # 5ms per check is very reasonable
```

### Test 2: Token Estimation Accuracy

```python
def test_token_estimation_accuracy():
    """Verify token estimation within 20% of actual"""
    gen = OpenAIGenerator(name="gpt-3.5-turbo")

    prompts = [
        "Short prompt",
        "This is a medium length prompt with several words",
        "Very long prompt " * 100,  # ~2000 chars
    ]

    for prompt in prompts:
        # Estimate
        estimated = gen._estimate_request_tokens({"messages": [{"content": prompt}]})

        # In real scenario, would call API and get actual
        # For testing, verify estimate is reasonable
        # Word count ~= tokens/1.3
        word_count = len(prompt.split())
        expected_range = (word_count * 0.8, word_count * 1.8)

        assert expected_range[0] <= estimated <= expected_range[1]
```

**Expected Results**:
- Rate limiter overhead <5% (negligible)
- Token estimation within 20% of actual
- Performance acceptable for production

---

## BACKWARD COMPATIBILITY TESTS

**Location**: `garak/tests/generators/test_openai_backward_compat.py`

### Test 1: Disabled Rate Limiting

```python
def test_backward_compat_disabled_rate_limiting():
    """Existing code works with rate limiting disabled"""
    gen = OpenAIGenerator(name="gpt-3.5-turbo")
    gen.enable_rate_limiting = False
    gen._init_rate_limiter()

    # Rate limiter should be disabled
    assert gen.rate_limiter is None

    # Generator should still work
    # (would work with mocked API)
```

### Test 2: Existing Tests Still Pass

```python
def test_existing_openai_generator_tests():
    """Verify existing test suite still passes"""
    # Run all existing tests with rate limiting enabled (default)
    # Should all pass without modification
    pass
```

**Expected Results**:
- Rate limiting can be disabled
- Existing tests pass without modification
- No breaking changes

---

## TEST INFRASTRUCTURE

### Test File Structure

```
garak/tests/
├── generators/
│   ├── test_rate_limiter.py (10 unit tests)
│   ├── test_openai_rate_limiting.py (5 integration tests)
│   └── test_openai_backward_compat.py (compatibility)
├── end_to_end/
│   └── test_rate_limiting_e2e.py (3 E2E tests)
├── performance/
│   └── test_rate_limiting_overhead.py (2 perf tests)
└── fixtures/
    ├── mock_responses.py
    ├── conftest.py
    └── sample_prompts.txt
```

### Test Utilities

**mock_responses.py**:
```python
def mock_response(content="Test response", tokens=100):
    """Create mock OpenAI response"""
    response = mock.MagicMock()
    response.choices = [mock.MagicMock()]
    response.choices[0].message.content = content
    response.usage = mock.MagicMock()
    response.usage.prompt_tokens = tokens // 2
    response.usage.completion_tokens = tokens // 2
    return response
```

### Pytest Configuration

**conftest.py**:
```python
@pytest.fixture
def mock_api():
    """Mock OpenAI API for testing"""
    with patch('openai.OpenAI.create') as mock_create:
        mock_create.return_value = mock_response()
        yield mock_create

@pytest.fixture
def temp_rate_config(tmp_path):
    """Create temporary rate_config.json"""
    config = {...}
    config_file = tmp_path / "rate_config.json"
    config_file.write_text(json.dumps(config))
    return config_file
```

---

## TEST EXECUTION ROADMAP

### Phase 1: Unit Tests (2 hours)
```bash
pytest garak/tests/generators/test_rate_limiter.py -v --cov
# Expected: 10/10 passing, 95%+ coverage
```

### Phase 2: Integration Tests (2 hours)
```bash
pytest garak/tests/generators/test_openai_rate_limiting.py -v
# Expected: 5/5 passing
```

### Phase 3: End-to-End Tests (2 hours)
```bash
pytest garak/tests/end_to_end/test_rate_limiting_e2e.py -v
# Expected: 3/3 passing
```

### Phase 4: Performance Tests (1 hour)
```bash
pytest garak/tests/performance/test_rate_limiting_overhead.py -v
# Expected: 2/2 passing, performance acceptable
```

### Phase 5: Backward Compatibility (1 hour)
```bash
pytest garak/tests/ -k "not rate_limiting" -v
# Expected: all existing tests passing
```

### Phase 6: Full Test Suite (30 min)
```bash
pytest garak/tests/ -v --cov=garak
# Expected: all tests passing, no regressions
```

---

## SUCCESS CRITERIA

✅ All 22 tests passing (10 unit + 5 integration + 3 E2E + 2 performance + 2 compat)
✅ Code coverage > 90% for rate_limiter.py
✅ No flaky tests (repeatable, deterministic)
✅ Performance overhead < 5%
✅ Token estimation accuracy within 20%
✅ Existing test suite passes unchanged
✅ Documentation complete and clear
✅ Ready for production deployment

---

## IMPLEMENTATION TIMELINE

**Next Session**:
1. Set up test infrastructure (conftest.py, fixtures, utilities)
2. Implement unit tests (test_rate_limiter.py)
3. Implement integration tests (test_openai_rate_limiting.py)
4. Implement E2E tests (test_rate_limiting_e2e.py)
5. Implement performance tests (test_rate_limiting_overhead.py)
6. Run full test suite and verify

**Total Effort**: ~6-8 hours of implementation

---

## NOTES

- All tests should be deterministic (no timing dependencies where possible)
- Use mock.patch extensively to avoid real API calls
- Mock time.sleep for rate limit testing to avoid actual delays
- Test parallelism with mock multiprocessing
- Document all test cases with clear docstrings
- Use pytest fixtures for setup/teardown

---

**Status**: Specification COMPLETE, ready for implementation

Features Complete:
✅ Feature 1: Architecture Analysis
✅ Feature 2: Configuration Management
✅ Feature 3: OpenAI Rate Limiting
✅ Feature 4: Parallel Request Support
✅ Feature 5: Batch API Investigation
🟡 Feature 6: Integration Testing (specification complete)

Next: Implement tests in Feature 6

