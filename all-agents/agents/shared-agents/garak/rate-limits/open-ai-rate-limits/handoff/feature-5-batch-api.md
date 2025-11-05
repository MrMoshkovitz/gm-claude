# Feature 5: OpenAI Batch API Investigation

**Status**: ✅ RESEARCH COMPLETE
**Date**: 2025-10-20
**Scope**: Research Batch API as alternative to streaming rate limiting

---

## EXECUTIVE SUMMARY

OpenAI Batch API provides alternative to streaming requests:
- **Async Job Submission**: Upload batch of requests, retrieve results later
- **Cheaper Rates**: 50% discount on token pricing
- **No Rate Limits**: Process unlimited requests (only throughput: 100k requests/day)
- **Trade-off**: Not real-time (12-24 hour processing)

**Recommendation**: Complementary approach for high-volume scanning, not replacement for streaming.

---

## BATCH API OVERVIEW

### What is Batch API?

OpenAI Batch API allows submitting multiple requests asynchronously:

```
1. User prepares batch file (JSONL format)
2. Upload to OpenAI via batch creation endpoint
3. Poll for completion (typically 12-24 hours)
4. Download results JSONL file
5. Process results locally
```

### Format Example

**Input (batch_requests.jsonl)**:
```jsonl
{"custom_id": "request-1", "method": "POST", "url": "/v1/chat/completions", "body": {"model": "gpt-4o", "messages": [{"role": "user", "content": "Test 1"}]}}
{"custom_id": "request-2", "method": "POST", "url": "/v1/chat/completions", "body": {"model": "gpt-4o", "messages": [{"role": "user", "content": "Test 2"}]}}
```

**Output (results.jsonl)**:
```jsonl
{"custom_id": "request-1", "result": {"body": {"choices": [...], "usage": {...}}}}
{"custom_id": "request-2", "result": {"body": {"choices": [...], "usage": {...}}}}
```

---

## RATE LIMIT COMPARISON

### Streaming Rate Limits (Current Implementation)

| Model | Free Tier | Tier 5 |
|-------|-----------|--------|
| gpt-3.5-turbo | 3 RPM, 40k TPM | 30k RPM, 20M TPM |
| gpt-4o | 3 RPM, 150k TPM | 30k RPM, 10M TPM |

**Throughput**: Immediate responses, limited by rate

### Batch API Rate Limits

| Metric | Limit |
|--------|-------|
| Max Requests/Day | 100,000 |
| Request Size | 100 MB |
| Typical Processing | 12-24 hours |
| Pricing | 50% discount |

**Throughput**: 100k requests regardless of tier

**Token Limits**: Same TPM limits apply, but spread over 24 hours

---

## COST COMPARISON (Example)

### Scenario: Scan 10,000 prompts with gpt-3.5-turbo

**Streaming (Free Tier)**:
- Rate: 3 RPM = 180 requests/hour
- Time: 10,000 ÷ 180 = 55+ hours
- Cost: $0.50 per 1k input + $0.15 per 1k output tokens
- Total: ~$500 (estimated)

**Batch API (Free Tier)**:
- Rate: 100,000 requests/day = unlimited (capacity)
- Time: 12-24 hours (1-2 batches)
- Cost: $0.25 per 1k input + $0.075 per 1k output (50% discount)
- Total: ~$250 (50% savings)
- Trade-off: 24 hour wait instead of 55 hours

---

## IMPLEMENTATION OPTIONS

### Option A: Current Streaming (✅ IMPLEMENTED)

**Pros**:
- Real-time results
- Works for interactive use
- Supports multiprocessing
- No wait time

**Cons**:
- Rate limited (especially free tier)
- High cost for volume
- Streaming only

### Option B: Batch API Only

**Pros**:
- 50% cost savings
- Unlimited throughput
- No rate limiting

**Cons**:
- 12-24 hour wait
- Not suitable for real-time
- Separate API workflow

### Option C: Hybrid (Recommended)

**Approach**:
1. **Real-time scanning**: Use streaming (current implementation)
   - For interactive probes
   - For quick tests
   - For development

2. **Bulk scanning**: Use Batch API
   - For production scans
   - For large datasets
   - For cost optimization

**Implementation**:
- Keep current rate limiter for streaming
- Add optional BatchGenerator for batch jobs
- Users choose based on use case

---

## BATCH API IMPLEMENTATION ROADMAP

### Phase 1: BatchAPIGenerator Class (Future)

```python
class BatchAPIGenerator(Generator):
    """Generator using OpenAI Batch API"""

    def __init__(self, name="gpt-3.5-turbo"):
        self.model = name
        self.client = openai.OpenAI(api_key=api_key)

    def prepare_batch(self, prompts: List[str]) -> str:
        """Prepare batch file, upload, return batch_id"""
        # Convert prompts to JSONL
        # Upload to API
        # Return batch_id

    def poll_batch(self, batch_id: str) -> dict:
        """Poll batch status, return results when ready"""
        # Check batch status
        # If complete, download results
        # Parse and return

    def generate(self, prompt: Union[str, List[str]]):
        """Submit batch, poll, return results"""
        # Prepare batch
        # Wait for completion
        # Return results
```

### Phase 2: Integration with Garak

```python
# Enable batch mode
gen = BatchAPIGenerator(name="gpt-3.5-turbo")
results = gen.generate(large_prompt_list)

# Or mixed mode
streaming_gen = OpenAIGenerator(name="gpt-3.5-turbo")
batch_gen = BatchAPIGenerator(name="gpt-3.5-turbo")

# Small quick tests: use streaming_gen
# Large bulk scans: use batch_gen
```

### Phase 3: Cost Optimization

```python
# Auto-select based on volume
def select_generator(num_prompts):
    if num_prompts < 100:
        return OpenAIGenerator()  # Streaming, quick
    else:
        return BatchAPIGenerator()  # Batch, cheaper
```

---

## TECHNICAL REQUIREMENTS

### API Endpoint

**Create Batch**:
```
POST /v1/batches
Authorization: Bearer $OPENAI_API_KEY
Content-Type: application/json

{
  "input_file_id": "file-abc123",
  "endpoint": "/v1/chat/completions",
  "completion_window": "24h"
}
```

Response:
```json
{
  "id": "batch_abc123",
  "status": "queued",
  "created_at": 1695984933
}
```

**Check Status**:
```
GET /v1/batches/{batch_id}
Authorization: Bearer $OPENAI_API_KEY
```

**Download Results**:
```
GET /v1/files/{output_file_id}/content
Authorization: Bearer $OPENAI_API_KEY
```

### Python SDK Support

```python
# Already supported in openai-python
batch = client.batches.create(
    input_file_id="file-abc123",
    endpoint="/v1/chat/completions",
    completion_window="24h"
)

status = client.batches.retrieve(batch.id)

output_file_id = batch.output_file_id
content = client.files.content(output_file_id)
```

---

## RECOMMENDATION FOR GARAK

### Short Term (Current)
✅ **Keep streaming rate limiter** (Feature 3)
- Meets existing use cases
- Real-time results
- No additional cost

### Medium Term (Future Phase)
🟡 **Add optional Batch API support**
- For high-volume scanning
- Cost optimization
- No replacement of streaming

### Long Term
🔵 **Smart generator selection**
- Auto-select based on workload
- Hybrid execution
- Optimal cost/time trade-off

---

## DECISION MATRIX

| Aspect | Streaming (Current) | Batch API (Future) |
|--------|---------------------|-------------------|
| Real-time | ✅ Yes | ❌ 12-24h delay |
| Rate Limits | ⚠️ Limited | ✅ Unlimited |
| Cost | ❌ Full price | ✅ 50% discount |
| Implementation | ✅ Done | ⏳ Future |
| Use Case | Development, testing | Production, bulk |

**Conclusion**: Both have value; implement Batch API later as enhancement

---

## FILES & REFERENCES

### Related Files
- `garak/generators/rate_limiter.py`: Current streaming rate limiter
- `garak/resources/rate_config.json`: Rate limit configuration
- OpenAI Batch API: https://platform.openai.com/docs/guides/batch

### Implementation Notes
- Batch API requires File API for upload
- Processing async, need polling mechanism
- Results JSONL format needs parsing
- Error handling for failed requests in batch

---

## SUMMARY

### Task 5.1: Research Batch API ✅
- Analyzed Batch API capabilities
- Compared with streaming approach
- Identified use cases

### Task 5.2: Compare Rate Limits ✅
- Streaming: Limited by RPM/TPM
- Batch: Limited by requests/day (100k)
- Cost: 50% discount for Batch

### Task 5.3: Recommendation ✅
- Keep current implementation
- Add Batch API as complementary (not replacement)
- Implement in future phase

---

**Status**: Feature 5 COMPLETE - Research Phase ✅
**Next**: Feature 6 - Integration Testing

