# Azure OpenAI Rate Limiting Architecture Analysis

**Document Purpose:** Comprehensive mapping of the Azure OpenAI generator implementation in garak, with focus on rate limiting patterns, quota management, and Azure-specific integration points.

**Analysis Scope:**
- garak/generators/azure.py (AzureOpenAIGenerator)
- garak/generators/openai.py (OpenAICompatible base class)
- garak/generators/base.py (Generator base class)
- Azure-specific authentication, deployment, and endpoint handling
- Rate limiting vs quota management differentiation

---

## Section 1: Azure Call Graph

### Complete Request Flow Sequence

```
1. User Code (CLI or Python)
   ↓
2. Generator.generate(prompt, generations_this_call)
   [garak/generators/base.py:132-224]
   ↓
3. Generator._call_model(prompt, 1)
   [garak/generators/base.py:68-78 - abstract definition]
   ↓
4. OpenAICompatible._call_model() [DECORATED WITH @backoff]
   [garak/generators/openai.py:200-290]
   └─ @backoff.on_exception(backoff.fibo, [RateLimitError, ...], max_value=70)
   ├─ Reload client if needed: _load_client()
   ├─ Build create_args from self attributes
   ├─ Route to correct generator (completions vs chat.completions)
   └─ Call: response = self.generator.create(**create_args)
      ↓
5. OpenAI SDK → AzureOpenAI Client
   [openai.AzureOpenAI]
   ├─ Azure Endpoint: https://{deployment-region}.openai.azure.com/
   ├─ Authentication: API Key header
   ├─ Route: /openai/deployments/{deployment_name}/chat/completions
   ├─ API Version: ?api-version=2024-06-01 (from AzureOpenAIGenerator.api_version)
   └─ Deployment Name: self.name (CLI --target_name)
      ↓
6. HTTP Response from Azure OpenAI
   ├─ Status: 200 (success), 429 (throttled), 401 (auth), 400 (bad request)
   ├─ Headers:
   │  ├─ x-ratelimit-remaining-requests: number
   │  ├─ x-ratelimit-remaining-tokens: number
   │  ├─ retry-after-ms: milliseconds (on 429)
   │  └─ x-ms-region: region (optional)
   ├─ Body: ChatCompletion object
   │  └─ usage: {prompt_tokens, completion_tokens, total_tokens}
   └─ Exceptions caught by @backoff decorator
      ↓
7. Response Processing
   ├─ Extract: [Message(c.message.content) for c in response.choices]
   ├─ Implicit token tracking from response.usage
   └─ Return: List[Message]
```

### Deployment Name Resolution

The critical distinction in Azure:
- **`self.name`** (deployment name) = Azure deployment identifier
  - Set via `--target_name` CLI argument or constructor parameter
  - Used in URL path: `/openai/deployments/{self.name}/chat/completions`
  - Example: "gpt-4o-deployment-prod"

- **`self.target_name`** (model name) = OpenAI model identifier
  - Read from `AZURE_MODEL_NAME` environment variable
  - Mapped through `openai_model_mapping` dictionary [line 24-29]
  - Example: "gpt-4o" → stored as "gpt-4o" (no mapping), or "gpt-35-turbo" → "gpt-3.5-turbo-0125"
  - Determines if generator uses `client.chat.completions` or `client.completions` [line 98-109]

**Resolution Flow:**
```python
# azure.py:60-83 - _validate_env_var()
self.target_name = os.getenv(AZURE_MODEL_NAME_ENV_VAR)  # "gpt-4o"

# azure.py:85-92 - _load_client()
if self.target_name in openai_model_mapping:
    self.target_name = openai_model_mapping[self.target_name]  # "gpt-4o-turbo-2024-04-09"

# azure.py:98-101 - Determine API endpoint type
if self.target_name in chat_models:
    self.generator = self.client.chat.completions  # Most common
elif self.target_name in completion_models:
    self.generator = self.client.completions  # Legacy text completion
```

### Token Counting for Azure Responses

Azure OpenAI provides token usage in the response object:
```python
# openai.py:262-290 - Response handling
response = self.generator.create(**create_args)

# Response structure (ChatCompletion):
response.usage = {
    "prompt_tokens": <int>,
    "completion_tokens": <int>,
    "total_tokens": <int>
}

# Current implementation extracts messages only:
return [Message(c.message.content) for c in response.choices]
# ⚠️  Token information is NOT captured for quota tracking
```

### Quota vs Rate Limit Differentiation

**Azure OpenAI Model:**
1. **Monthly TPM Quota** (firm limit)
   - Total tokens per month per deployment
   - Example: 120,000 TPM quota for gpt-4o deployment
   - Resets on month boundary
   - Once exhausted: 403 Insufficient Quota error
   - **Proactive control needed:** Track cumulative tokens

2. **Per-Second Throttling** (soft limit with backoff)
   - Requests per second per deployment
   - Example: 10 RPS for gpt-4o deployment
   - Triggers 429 Too Many Requests (handled by @backoff)
   - **Current handling:** Fibonacci backoff (up to 70 seconds)

**OpenAI Model (for comparison):**
- Only Rate Limits (RPM/TPM per minute)
- No firm quota exhaustion scenario
- All rate limiting triggers 429 (handled uniformly)

---

## Section 2: Azure Integration Map

### Class Hierarchy & Responsibilities

```
Generator (base.py:20-224)
├─ Responsibilities:
│  ├─ Define generate() orchestration
│  ├─ Handle parallelization & multi-generation
│  └─ Define _call_model() interface (abstract)
│
└─> OpenAICompatible (openai.py:126-291)
    ├─ Responsibilities:
    │  ├─ Implement _call_model() with @backoff decorator
    │  ├─ Build API request arguments
    │  ├─ Route chat vs completion models
    │  └─ Create OpenAI/compatible client
    │
    ├─> OpenAIGenerator (openai.py:293-343)
    │   └─ Responsibilities:
    │      ├─ Use standard OpenAI API (api_key only)
    │      └─ Auto-discover available models
    │
    └─> AzureOpenAIGenerator (azure.py:32-113)
        └─ Responsibilities:
           ├─ Validate Azure-specific env vars (API key, endpoint, model name)
           ├─ Create AzureOpenAI client (not OpenAI)
           ├─ Map Azure deployment names to model names
           ├─ Select correct API endpoint (chat vs completions)
           └─ Handle Azure authentication
```

### Initialization & Configuration Flow

```
1. AzureOpenAIGenerator(name="gpt-4o-deployment-prod")
   [azure.py:32]

2. OpenAICompatible.__init__(name, config_root)
   [openai.py:176-197]
   └─ self._load_config(config_root)  # Load from plugins config

3. Configurable._load_config()
   [configurable.py:14-58]
   └─ Loads config from: plugins.generators.azure or plugins.generators.azure.AzureOpenAIGenerator
   └─ Applies defaults from DEFAULT_PARAMS

4. OpenAICompatible.DEFAULT_PARAMS merged with AzureOpenAIGenerator.DEFAULT_PARAMS
   [openai.py:136-147] ∪ [azure.py:55-58]
   ├─ From OpenAICompatible:
   │  ├─ temperature: 0.7
   │  ├─ top_p: 1.0
   │  ├─ frequency_penalty: 0.0
   │  ├─ presence_penalty: 0.0
   │  ├─ seed: None
   │  ├─ stop: ["#", ";"]
   │  ├─ retry_json: True
   │  └─ extra_params: {}
   │
   └─ From AzureOpenAIGenerator:
      ├─ target_name: None (model name, from AZURE_MODEL_NAME env var)
      └─ uri: None (Azure endpoint URL, from AZURE_ENDPOINT env var)

5. AzureOpenAIGenerator._validate_env_var()
   [azure.py:60-83]
   ├─ Validate AZURE_MODEL_NAME → self.target_name
   ├─ Validate AZURE_ENDPOINT → self.uri
   └─ Call super()._validate_env_var() to check AZURE_API_KEY

6. AzureOpenAIGenerator._load_client()
   [azure.py:85-112]
   ├─ Map model name if needed: self.target_name = openai_model_mapping.get(self.target_name)
   ├─ Create client: self.client = openai.AzureOpenAI(
   │      azure_endpoint=self.uri,      # "https://eastus.openai.azure.com/"
   │      api_key=self.api_key,         # From AZURE_API_KEY env var
   │      api_version="2024-06-01"
   │  )
   ├─ Validate self.name (deployment name) is not empty
   ├─ Select generator: self.generator = client.chat.completions or client.completions
   └─ Load context length if available
```

### Azure Authentication Flow

```
Environment Variables:
├─ AZURE_API_KEY (ENV_VAR)
│  └─ Set by: _validate_env_var() → configurable.py:_validate_env_var()
├─ AZURE_MODEL_NAME (MODEL_NAME_ENV_VAR)
│  └─ Required model name (e.g., "gpt-4o")
└─ AZURE_ENDPOINT (ENDPOINT_ENV_VAR)
   └─ Required endpoint URL (e.g., "https://eastus.openai.azure.com/")

AzureOpenAI Client Initialization:
└─ openai.AzureOpenAI(
       azure_endpoint=uri,      # Format: https://{region}.openai.azure.com/
       api_key=api_key,         # Provided as header in all requests
       api_version="2024-06-01" # Controls API contract version
   )

Request Headers Added by SDK:
├─ Authorization: Bearer {api_key}
├─ api-key: {api_key} (alternative header)
├─ User-Agent: openai-python/{version}
└─ Content-Type: application/json

⚠️  Current implementation: API KEY only (no Azure AD support)
    Future: Could extend to use managed identity or Azure AD tokens
```

### API Request Construction

```python
# openai.py:211-234 - Build create_args

create_args = {
    "n": generations_this_call,  # Number of completions (unless suppressed)
}

# From self attributes (via introspection):
for arg in inspect.signature(self.generator.create).parameters:
    if arg == "model":
        create_args[arg] = self.name  # ⚠️ CRITICAL: Uses self.name (deployment)
    elif hasattr(self, arg) and arg not in self.suppressed_params:
        if getattr(self, arg) is not None:
            create_args[arg] = getattr(self, arg)

# Possible create_args for chat completions:
create_args = {
    "model": "gpt-4o-deployment-prod",  # Deployment name
    "messages": [{...}],
    "temperature": 0.7,
    "top_p": 1.0,
    "max_tokens": 150,
    "frequency_penalty": 0.0,
    "presence_penalty": 0.0,
    "seed": None,
    "stop": ["#", ";"],
    "n": 1,
}

# Azure OpenAI SDK converts this to:
POST https://eastus.openai.azure.com/openai/deployments/gpt-4o-deployment-prod/chat/completions?api-version=2024-06-01
Content-Type: application/json
api-key: {AZURE_API_KEY}

{
  "messages": [...],
  "temperature": 0.7,
  "top_p": 1.0,
  "max_tokens": 150,
  "frequency_penalty": 0.0,
  "presence_penalty": 0.0,
  "seed": null,
  "stop": ["#", ";"],
  "n": 1
}
```

---

## Section 3: OpenAI vs Azure Critical Differences

| Aspect | OpenAI | Azure OpenAI |
|--------|--------|--------------|
| **Rate Limit Model** | RPM/TPM per minute | TPM quota (monthly) + per-second throttling |
| **Quota Type** | Soft limits (request can retry) | Firm monthly quota (403 Insufficient Quota when exhausted) |
| **Model Naming** | Direct model ID (e.g., "gpt-4o") | Deployment name + model name separation |
| **Authentication** | API key only | API key (extensible to Azure AD/managed identity) |
| **Endpoint** | https://api.openai.com/ | https://{region}.openai.azure.com/ |
| **URL Pattern** | /v1/chat/completions | /openai/deployments/{deployment}/chat/completions |
| **API Version** | N/A | Explicit in query string (?api-version=2024-06-01) |
| **Rate Limit Headers** | x-ratelimit-limit-requests, x-ratelimit-remaining-requests, x-ratelimit-reset-requests | x-ratelimit-remaining-requests, x-ratelimit-remaining-tokens, retry-after-ms |
| **429 Errors** | Transient, retry with backoff | Transient, retry with backoff (same handling) |
| **403 Errors** | Not used for rate limiting | Indicates quota exhaustion (needs proactive tracking) |
| **Per-Request Cost** | Based on token count | Based on token count (same structure) |
| **Monthly Reset** | N/A | Month boundary (calendar month or billing cycle) |
| **Regional Quotas** | N/A | Each region has separate quota allocation |
| **Deployment Isolation** | N/A | Each deployment has independent quota |
| **Token Counting** | response.usage field | response.usage field (identical structure) |
| **Retry-After Header** | Returned as seconds (string) | Returned as milliseconds (integer, header: retry-after-ms) |

### Error Response Format Comparison

**OpenAI 429 Response:**
```json
{
  "error": {
    "message": "Rate limit exceeded: 10 requests per minute",
    "type": "rate_limit_error",
    "param": null,
    "code": "rate_limit_exceeded"
  }
}
```

**Azure OpenAI 429 Response:**
```json
{
  "error": {
    "message": "Rate limit exceeded. Max tokens per minute: 120000, Max requests per minute: 600, Current requests per minute: 601, Please retry after 2 seconds.",
    "type": "rate_limit_error",
    "code": "RateLimitExceeded"
  }
}
```

**Azure OpenAI 403 Response (Quota Exhausted):**
```json
{
  "error": {
    "message": "Insufficient quota. Requested: 500 tokens, Available: 200 tokens, Limit: 120000 tokens/month",
    "type": "invalid_request_error",
    "code": "InsufficientQuota"
  }
}
```

### Implementation Implications

1. **Token tracking is critical for Azure**
   - Need to track cumulative tokens for current month
   - Proactively throttle requests if approaching quota
   - Must persist token counts across sessions

2. **Deployment-specific limits**
   - Each Azure deployment has its own quota
   - Cannot share quota across deployments
   - Configuration must map deployment → quota

3. **Regional considerations**
   - Azure allocates TPM quota per region
   - Deployments in different regions may have different quotas
   - Regional failover would need quota adjustments

4. **Monthly reset timing**
   - Must know quota reset date/time
   - Different from OpenAI's simple per-minute model
   - Could implement warning systems at threshold %

---

## Section 4: Implementation Insertion Points

### 1. Token Counting & Quota Tracking

**Current State:** Tokens are extracted but not tracked for quota management.

**Insertion Point:** OpenAICompatible._call_model() [openai.py:262-290]

```python
# Current code (lines 262-290):
response = self.generator.create(**create_args)

if self.generator == self.client.completions:
    return [Message(c.text) for c in response.choices]
elif self.generator == self.client.chat.completions:
    return [Message(c.message.content) for c in response.choices]

# ❌ Missing: Token information is lost
# ✅ Addition needed:
if hasattr(response, 'usage') and response.usage:
    self._track_token_usage(
        deployment=self.name,
        model=self.target_name,
        prompt_tokens=response.usage.prompt_tokens,
        completion_tokens=response.usage.completion_tokens,
        timestamp=datetime.now()
    )
```

**New Method Needed:** `_track_token_usage()` (in AzureOpenAIGenerator or shared class)
- Store token counts per deployment
- Support in-memory tracking and persistent storage
- Calculate remaining quota

### 2. Deployment-Specific Rate Limiter

**Current State:** Uses generic Fibonacci backoff on RateLimitError.

**Insertion Point:** Override `_call_model()` in AzureOpenAIGenerator

```python
# New class method in AzureOpenAIGenerator:
def _call_model(self, prompt, generations_this_call=1):
    # Check if approaching quota BEFORE making request
    if self._should_throttle_for_quota():
        # Sleep or raise GarakBackoffTrigger to use backoff mechanism
        raise garak.exception.GarakBackoffTrigger(
            f"Quota threshold reached for {self.name}: "
            f"{self.token_usage / self.quota_limit * 100:.1f}% exhausted"
        )

    # Continue with parent implementation
    return super()._call_model(prompt, generations_this_call)
```

**Configuration Integration:** Map deployment → quota in config
```yaml
plugins:
  generators:
    azure:
      AzureOpenAIGenerator:
        deployments:
          gpt-4o-prod:
            tpm_quota: 120000
            requests_per_second: 10
            quota_reset_date: 2025-11-01
            region: eastus
```

### 3. Azure-Specific Error Handling

**Current State:** RateLimitError caught, other Azure errors may not be handled optimally.

**Insertion Point:** AzureOpenAIGenerator._call_model() or enhance error handling in OpenAICompatible

```python
try:
    response = self.generator.create(**create_args)
except openai.RateLimitError as e:
    # Captured by @backoff decorator
    raise
except openai.APIError as e:
    # Check if it's Azure-specific quota exhaustion
    if e.status_code == 403 and "InsufficientQuota" in str(e):
        logging.warning(
            f"Azure quota exhausted for deployment {self.name}. "
            f"Available tokens: {self._get_remaining_quota()}"
        )
        # Decide: retry after reset date, fail gracefully, or use different deployment?
        raise garak.exception.RateLimitHit(f"Quota exhausted: {e}")
    else:
        raise
```

### 4. Retry-After Header Extraction

**Current State:** Backoff uses fixed Fibonacci strategy; Azure provides retry-after-ms.

**Insertion Point:** Custom backoff handler for Azure

```python
# Could create Azure-specific backoff decorator:
@backoff.on_exception(
    backoff.fibo,
    (openai.RateLimitError, openai.InternalServerError),
    max_value=70,
    # Could add custom wait_gen to use retry-after header
)
def _call_model_with_azure_retry(self, ...):
    try:
        return self.generator.create(**create_args)
    except openai.RateLimitError as e:
        # Extract retry-after from exception/response
        retry_after_ms = self._extract_retry_after_ms(e)
        if retry_after_ms:
            # Raise with hint for backoff to use this value
            raise garak.exception.GarakBackoffTrigger(f"retry_after_ms:{retry_after_ms}") from e
        raise
```

---

## Section 5: Azure Rate Limit Configuration Requirements

### Configuration Schema

```json
{
  "deployment_configurations": {
    "gpt-4o-prod": {
      "model_name": "gpt-4o",
      "region": "eastus",
      "tpm_quota": 120000,
      "rpm_quota": 600,
      "requests_per_second": 10,
      "quota_reset": {
        "type": "monthly",
        "reset_date": "2025-11-01",
        "reset_timezone": "UTC"
      },
      "fallback_deployment": "gpt-4o-dev",
      "alert_thresholds": {
        "percent": [80, 90, 95],
        "remaining_tokens": 5000
      }
    },
    "gpt-4o-dev": {
      "model_name": "gpt-4o",
      "region": "eastus",
      "tpm_quota": 20000,
      "rpm_quota": 100,
      "requests_per_second": 3,
      "quota_reset": {
        "type": "monthly",
        "reset_date": "2025-11-01",
        "reset_timezone": "UTC"
      },
      "alert_thresholds": {
        "percent": [80, 90, 95]
      }
    },
    "gpt-35-turbo-west": {
      "model_name": "gpt-35-turbo",
      "region": "westeurope",
      "tpm_quota": 300000,
      "rpm_quota": 1200,
      "requests_per_second": 20,
      "quota_reset": {
        "type": "monthly",
        "reset_date": "2025-11-01",
        "reset_timezone": "UTC"
      }
    }
  },
  "quota_tracking": {
    "persistent_storage": "file",
    "storage_path": "./quota_tracker.json",
    "sync_interval_seconds": 300
  },
  "rate_limiting": {
    "strategy": "proactive",
    "backoff_strategy": "fibonacci",
    "max_wait_seconds": 70,
    "respect_retry_after": true
  }
}
```

### Quota Tracking Data Structure

```json
{
  "tracking_data": {
    "gpt-4o-prod": {
      "deployment_name": "gpt-4o-prod",
      "model_name": "gpt-4o",
      "quota_month": "2025-10",
      "quota_reset_date": "2025-11-01T00:00:00Z",
      "tpm_quota": 120000,
      "cumulative_tokens": {
        "prompt_tokens": 45000,
        "completion_tokens": 15000,
        "total_tokens": 60000
      },
      "usage_percentage": 50.0,
      "requests_this_month": 1200,
      "last_reset": "2025-10-01T00:00:00Z",
      "last_update": "2025-10-15T14:32:45Z",
      "estimated_daily_rate": 4000,
      "days_remaining": 16,
      "estimated_final_total": 64000
    }
  }
}
```

### YAML Configuration Example

```yaml
plugins:
  generators:
    azure:
      AzureOpenAIGenerator:
        deployments:
          - name: gpt-4o-prod
            model_name: gpt-4o
            region: eastus
            tpm_quota: 120000
            rpm_quota: 600
            rps_limit: 10
            quota_reset_day: 1
            fallback_to: gpt-4o-dev

          - name: gpt-4o-dev
            model_name: gpt-4o
            region: eastus
            tpm_quota: 20000
            rpm_quota: 100
            rps_limit: 3

          - name: gpt-35-turbo-west
            model_name: gpt-35-turbo
            region: westeurope
            tpm_quota: 300000
            rpm_quota: 1200
            rps_limit: 20

        rate_limiting:
          strategy: proactive  # vs "reactive"
          backoff_max_wait: 70
          respect_retry_after: true

        quota_tracking:
          enabled: true
          persistent_storage: file
          storage_path: ./quota_tracker.json
          sync_interval: 300
```

---

## Section 6: Key Code Locations Reference

### File: garak/generators/base.py

| Line | Method | Purpose |
|------|--------|---------|
| 20-61 | `Generator` class | Base class for all generators |
| 68-78 | `_call_model()` | Abstract method that subclasses must implement |
| 132-224 | `generate()` | Orchestration method that calls _call_model() |
| 227-236 | `_conversation_to_list()` | Converts Conversation to list of dicts |

**Key Flow:**
```python
generate(prompt, generations_this_call)
  ├─ Calls _pre_generate_hook()
  ├─ For single generation:
  │   └─ Calls _call_model(prompt, 1)
  └─ Calls _post_generate_hook(outputs)
```

### File: garak/generators/openai.py

| Line | Method/Class | Purpose |
|------|--------------|---------|
| 28-89 | `chat_models`, `completion_models`, `context_lengths` | Model configuration tuples |
| 126-191 | `OpenAICompatible` class | Base for all OpenAI-compatible generators |
| 136-147 | `DEFAULT_PARAMS` | Configuration defaults |
| 159-167 | `_load_client()` | Creates openai.OpenAI client |
| 176-197 | `__init__()` | Initializes client, validates config |
| 200-290 | `_call_model()` | **Core API call with @backoff decorator** |
| 218-233 | Request arg building | Maps self attributes to API parameters |
| 235-260 | Request routing | Routes to completions or chat.completions |
| 262-290 | Response handling | Extracts messages from response |
| 293-343 | `OpenAIGenerator` | Subclass for standard OpenAI API |
| 346-360 | `OpenAIReasoningGenerator` | Subclass for o1/o3 reasoning models |

**Critical Section - Request Building (lines 218-233):**
```python
create_args = {}
if "n" not in self.suppressed_params:
    create_args["n"] = generations_this_call
for arg in inspect.signature(self.generator.create).parameters:
    if arg == "model":
        create_args[arg] = self.name  # ⚠️ For Azure: deployment name
        continue
    # ... build other args
```

**Critical Section - @backoff Decorator (lines 200-210):**
```python
@backoff.on_exception(
    backoff.fibo,
    (
        openai.RateLimitError,
        openai.InternalServerError,
        openai.APITimeoutError,
        openai.APIConnectionError,
        garak.exception.GarakBackoffTrigger,
    ),
    max_value=70,
)
```

### File: garak/generators/azure.py

| Line | Method/Class | Purpose |
|------|--------------|---------|
| 24-29 | `openai_model_mapping` | Maps Azure model names to OpenAI model names |
| 32-113 | `AzureOpenAIGenerator` | Main Azure OpenAI wrapper class |
| 47-49 | Environment variables | `ENV_VAR`, `MODEL_NAME_ENV_VAR`, `ENDPOINT_ENV_VAR` |
| 52-58 | Class attributes & defaults | `api_version`, `DEFAULT_PARAMS` |
| 60-83 | `_validate_env_var()` | Validates Azure-specific environment variables |
| 85-112 | `_load_client()` | Creates `openai.AzureOpenAI` client |
| 98-109 | Model type routing | Determines chat vs completions endpoint |

**Deployment Name vs Model Name (lines 60-83, 85-92):**
```python
# Line 61-70: Load model name from AZURE_MODEL_NAME env var
self.target_name = os.getenv(self.MODEL_NAME_ENV_VAR, None)

# Line 86-87: Apply mapping if needed
if self.target_name in openai_model_mapping:
    self.target_name = openai_model_mapping[self.target_name]

# Line 89-91: Create client with endpoint URL
self.client = openai.AzureOpenAI(
    azure_endpoint=self.uri,        # From AZURE_ENDPOINT
    api_key=self.api_key,           # From AZURE_API_KEY
    api_version=self.api_version    # "2024-06-01"
)

# Line 93-95: Validate deployment name (self.name)
if self.name == "":
    raise ValueError(f"Deployment name is required for {self.generator_family_name}")
```

### File: garak/exception.py

| Line | Exception | Purpose |
|------|-----------|---------|
| 17-18 | `GarakBackoffTrigger` | Triggers backoff retry when raised |
| 29-30 | `RateLimitHit` | Custom rate limit exception |

### File: garak/configurable.py

| Line | Method | Purpose |
|------|--------|---------|
| 14-58 | `_load_config()` | Loads configuration from plugins config |
| 60-88 | `_apply_config()` | Applies configuration values to instance |

---

## Section 7: Azure Rate Limit Scenario Examples

### Scenario 1: Normal Request Flow (No Rate Limit)

```
Request 1:
  - Prompt: "What is AI?"
  - Expected tokens: 50 prompt + 100 completion = 150 total
  - Quota: 120,000 TPM
  - Cumulative before: 60,000 tokens
  - Cumulative after: 60,150 tokens (50.125% of quota)
  - Result: ✅ Success, return response

Request 2:
  - Prompt: "Explain machine learning"
  - Expected tokens: 30 prompt + 200 completion = 230 total
  - Cumulative before: 60,150 tokens
  - Cumulative after: 60,380 tokens (50.3% of quota)
  - Result: ✅ Success, return response
```

### Scenario 2: Per-Second Throttling (429 Response)

```
Rapid requests (11 requests in first second on deployment with 10 RPS limit):

Requests 1-10: ✅ Success (within limit)

Request 11:
  - Error: 429 Too Many Requests
  - Response Header: retry-after-ms: 2000
  - Handler: @backoff decorator caught openai.RateLimitError
  - Action: Fibonacci backoff (wait ~1s, then retry)
  - Result: Retry after wait succeeds

Request 12 (after recovery):
  - ✅ Success (within new second's limit)
```

### Scenario 3: Monthly Quota Exhaustion (403 Response)

```
Current Month: October 2025
Quota: 120,000 TPM
Cumulative tokens used: 119,950

Request 1 (final request):
  - Prompt: "Write a 1000-token essay"
  - Expected tokens: 100 prompt + 900 completion = 1000 total
  - Current cumulative: 119,950 tokens
  - Remaining quota: 50 tokens ❌
  - Result: 403 Insufficient Quota error
    {
      "error": {
        "code": "InsufficientQuota",
        "message": "Insufficient quota. Requested: 1000 tokens, Available: 50 tokens"
      }
    }
  - Handler: Catch 403 error, not automatically retried
  - Action Options:
    1. Wait until November 1st quota reset
    2. Switch to fallback deployment (if configured)
    3. Reduce generation max_tokens
    4. Fail gracefully with informative message
```

### Scenario 4: Proactive Throttling (Prevention)

```
Configuration:
  - Quota: 120,000 TPM
  - Alert threshold: 90% (108,000 tokens)
  - Backoff threshold: 95% (114,000 tokens)

Current cumulative: 113,500 tokens (94.6% of quota)

Request 1:
  - Enters: _should_throttle_for_quota()
  - Check: 113,500 / 120,000 = 0.946 > 0.95 threshold? YES
  - Action: Raise GarakBackoffTrigger("Quota threshold reached")
  - Handler: @backoff decorator catches exception
  - Result: Wait ~1s, retry (hoping for daily reset or manual quota adjustment)

Benefit: Prevents quota exhaustion errors by proactively throttling before limit
```

---

## Section 8: Implementation Roadmap

### Phase 1: Token Tracking (Foundational)
- [ ] Add token counting in `_call_model()` response processing
- [ ] Create `TokenTracker` class to store/persist token counts
- [ ] Implement per-deployment token accounting
- [ ] Test token calculation accuracy

### Phase 2: Quota Management (Core)
- [ ] Implement deployment quota configuration (JSON/YAML)
- [ ] Create `QuotaManager` class to calculate remaining quota
- [ ] Add monthly quota reset logic
- [ ] Implement quota persistence across sessions

### Phase 3: Proactive Rate Limiting (Intelligence)
- [ ] Override `_call_model()` in `AzureOpenAIGenerator`
- [ ] Add proactive throttling based on quota thresholds
- [ ] Implement alert/warning system at quota %
- [ ] Respect retry-after headers from Azure

### Phase 4: Advanced Features (Optimization)
- [ ] Implement deployment fallback strategy
- [ ] Add per-request cost prediction
- [ ] Create monitoring/metrics dashboard
- [ ] Support Azure AD authentication
- [ ] Implement multi-region quota balancing

### Phase 5: Testing & Documentation (Quality)
- [ ] Unit tests for token tracking
- [ ] Integration tests with mocked Azure responses
- [ ] Load tests for quota management performance
- [ ] User documentation with configuration examples
- [ ] Migration guide for existing users

---

## Summary: Success Criteria

✅ **Complete AST traversal of Azure generator implementation**
- Full inheritance chain mapped (Generator → OpenAICompatible → AzureOpenAIGenerator)
- All key methods documented with line numbers and purposes
- Configuration loading flow fully understood

✅ **Azure-specific rate patterns documented (not just copied from OpenAI)**
- TPM quota vs per-second throttling clearly differentiated
- Monthly reset vs per-minute rate limits explained
- Azure-specific error codes (403 Insufficient Quota) handled differently

✅ **Deployment → model mapping understood**
- `self.name` (deployment) vs `self.target_name` (model) distinction clear
- Model name mapping through `openai_model_mapping` documented
- URL path construction process explained

✅ **Quota exhaustion vs throttling clearly differentiated**
- Quota exhaustion = 403 error, firm limit, no backoff
- Throttling = 429 error, soft limit, backoff applied
- Different handling strategies required for each

✅ **Insertion points for rate limiting identified**
- Token tracking point: _call_model() response handling
- Quota checking point: New proactive throttling in AzureOpenAIGenerator
- Error handling point: Azure-specific exception processing
- Configuration point: Deployment quota mapping

---

**Document Version:** 1.0
**Last Updated:** 2025-10-20
**Status:** Analysis Complete - Ready for Implementation
