# AdapterFactory Architecture Diagram

## Factory Registration Flow

```
Module Import
    |
    v
garak.ratelimit.adapters.__init__
    |
    v
_register_builtin_adapters()
    |
    +-- Import OpenAIAdapter --> AdapterFactory.register('openai', OpenAIAdapter)
    |
    +-- Import AzureAdapter --> AdapterFactory.register('azure', AzureAdapter)
    |
    +-- Import HuggingFaceAdapter --> AdapterFactory.register('huggingface', HuggingFaceAdapter)
    |
    +-- Try Import AnthropicAdapter --> AdapterFactory.register('anthropic', AnthropicAdapter)
    |                                    [Skipped if SDK not installed]
    |
    +-- Try Import GeminiAdapter --> AdapterFactory.register('gemini', GeminiAdapter)
                                      [Skipped if SDK not installed]

Result: AdapterFactory._adapters = {
    'openai': OpenAIAdapter,
    'azure': AzureAdapter,
    'huggingface': HuggingFaceAdapter,
    'anthropic': AnthropicAdapter,  # if SDK available
    'gemini': GeminiAdapter,        # if SDK available
}
```

## Adapter Creation Flow

```
Generator.__init__(name='gpt-4o')
    |
    v
Detect provider from generator_family_name: 'openai'
    |
    v
Extract config from _config.plugins.generators.openai
    |
    v
AdapterFactory.create('openai', model_or_deployment='gpt-4o', config=...)
    |
    v
Lookup: AdapterFactory._adapters['openai'] --> OpenAIAdapter class
    |
    v
Build kwargs: {'model': 'gpt-4o', 'config': {...}}
    |
    v
Instantiate: OpenAIAdapter(model='gpt-4o', config={...})
    |
    v
Return adapter instance to generator
    |
    v
Generator stores: self._provider_adapter = adapter
```

## UnifiedRateLimiter Adapter Usage

```
UnifiedRateLimiter.__init__(config={
    'openai': {'rate_limits': {...}},
    'azure': {'rate_limits': {...}},
})
    |
    v
For each provider in config:
    |
    +-- Check: AdapterFactory.is_registered('openai') --> True
    |       |
    |       v
    |   AdapterFactory.create('openai', config=openai_config)
    |       |
    |       v
    |   self.adapters['openai'] = adapter
    |
    +-- Check: AdapterFactory.is_registered('azure') --> True
    |       |
    |       v
    |   AdapterFactory.create('azure', config=azure_config)
    |       |
    |       v
    |   self.adapters['azure'] = adapter
    |
    v
Result: self.adapters = {
    'openai': OpenAIAdapter instance,
    'azure': AzureAdapter instance,
}
```

## Adapter Method Call Flow

```
Generator._pre_generate_hook()
    |
    v
rate_limiter.acquire(provider='openai', model='gpt-4o', estimated_tokens=100)
    |
    v
Get adapter: self.adapters['openai']
    |
    v
Call: adapter.estimate_tokens(prompt, model='gpt-4o')
    |   (OpenAIAdapter uses tiktoken)
    |
    v
Check limits using estimated tokens
    |
    v
Return True/False


Generator._post_generate_hook(response)
    |
    v
rate_limiter.record_usage(provider='openai', model='gpt-4o', response=...)
    |
    v
Get adapter: self.adapters['openai']
    |
    v
Call: adapter.extract_usage_from_response(response)
    |   (OpenAIAdapter reads response.usage.total_tokens)
    |
    v
Update sliding window with actual token usage
```

## Class Hierarchy

```
ProviderAdapter (ABC)
    |
    +-- OpenAIAdapter
    |       |
    |       +-- AzureAdapter (extends OpenAI)
    |
    +-- HuggingFaceAdapter
    |
    +-- AnthropicAdapter
    |
    +-- GeminiAdapter
    |
    +-- RESTAdapter
```

## Method Call Matrix

| Operation | Factory Method | Adapter Method | Called By |
|-----------|---------------|----------------|-----------|
| **Register** | `AdapterFactory.register()` | N/A | Module __init__ |
| **Create** | `AdapterFactory.create()` | `__init__()` | UnifiedRateLimiter, Generator |
| **Estimate Tokens** | N/A | `adapter.estimate_tokens()` | UnifiedRateLimiter.acquire() |
| **Extract Usage** | N/A | `adapter.extract_usage_from_response()` | UnifiedRateLimiter.record_usage() |
| **Parse Error** | N/A | `adapter.extract_rate_limit_info()` | Exception handler |
| **Get Retry Delay** | N/A | `adapter.get_retry_after()` | Backoff strategy |
| **Default Limits** | N/A | `adapter.get_model_limits()` | Config loading |

## Configuration Flow

```
garak.core.yaml
    |
    v
plugins:
  generators:
    openai:
      rate_limits:
        gpt-4o:
          rpm: 10000
          tpm: 2000000
    |
    v
_config.plugins.generators.openai = {...}
    |
    v
AdapterFactory.create('openai', config=_config.plugins.generators.openai)
    |
    v
OpenAIAdapter.__init__(config={
    'rate_limits': {
        'gpt-4o': {'rpm': 10000, 'tpm': 2000000}
    }
})
    |
    v
Adapter stores config for later use:
    self.config = config
```

## Extension Pattern: Adding Anthropic

```
Step 1: Create Adapter
    |
    v
garak/ratelimit/adapters/anthropic.py
    |
    class AnthropicAdapter(ProviderAdapter):
        def estimate_tokens(...): ...
        def extract_usage_from_response(...): ...
        def extract_rate_limit_info(...): ...
        def get_retry_after(...): ...
        def get_model_limits(...): ...
    |
    v
Step 2: Register Adapter
    |
    v
garak/ratelimit/adapters/__init__.py
    |
    try:
        import anthropic  # Check SDK available
        from .anthropic import AnthropicAdapter
        AdapterFactory.register('anthropic', AnthropicAdapter)
    except ImportError:
        pass
    |
    v
Step 3: Add Configuration
    |
    v
garak.core.yaml
    |
    plugins:
      generators:
        anthropic:
          rate_limits:
            claude-3-opus:
              rpm: 5
              tpm: 10000
    |
    v
DONE! Zero changes needed to:
    - AdapterFactory
    - UnifiedRateLimiter
    - Generator base class
```

## Error Handling Flow

```
API Call raises openai.RateLimitError
    |
    v
Exception caught by @backoff decorator (safety net)
    |
    v
rate_limiter.handle_error(exception)
    |
    v
Get adapter: self.adapters['openai']
    |
    v
Call: adapter.extract_rate_limit_info(exception)
    |   (Returns: {'limit_type': 'rpm', 'retry_after': 5.0})
    |
    v
Use retry_after for backoff delay
    |
    v
OR
    |
    v
Call: adapter.get_retry_after(exception)
    |   (Returns: 5.0)
    |
    v
Sleep for 5 seconds, then retry
```

## Thread Safety

```
Thread 1: AdapterFactory.register('openai', OpenAIAdapter)
Thread 2: AdapterFactory.register('azure', AzureAdapter)
    |
    v
Both threads acquire _registration_lock
    |
    +-- Thread 1 acquires lock first
    |       |
    |       v
    |   _adapters['openai'] = OpenAIAdapter
    |       |
    |       v
    |   Release lock
    |
    +-- Thread 2 waits for lock
            |
            v
        Thread 2 acquires lock
            |
            v
        _adapters['azure'] = AzureAdapter
            |
            v
        Release lock

Result: No race conditions, both registered correctly
```

## Factory Singleton Pattern

```
AdapterFactory (class-level state)
    |
    +-- _adapters = {}          # Shared across all instances
    +-- _config_sections = {}   # Shared across all instances
    +-- _registration_lock      # Shared across all instances
    |
    v
AdapterFactory.create('openai')  # No instance needed (class method)
    |
    v
Access shared _adapters registry
    |
    v
Return adapter instance (new instance each time)

Note: Factory itself is stateless (all methods are class methods)
      Registry is class-level state (shared singleton)
```
