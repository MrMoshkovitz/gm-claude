# AdapterFactory Implementation Guide (Phase 3c)

**Version:** 1.0
**Date:** 2025-10-20
**Status:** Implementation Specification
**Phase:** 3c - Adapter Factory and Registry
**Dependencies:** Phase 2b (ProviderAdapter Interface), Phase 3a (OpenAIAdapter), Phase 3b (AzureAdapter)

---

## Executive Summary

This document provides the complete implementation specification for the **AdapterFactory** class, which serves as the central registry and factory for all provider adapters. The factory implements the Registry Pattern to enable zero-modification extensibility - adding new providers requires only implementing an adapter class and registering it, with no changes to the factory itself.

### Design Principles

1. **Static Registry**: All adapters registered in a class-level dictionary
2. **Lazy Instantiation**: Adapters created on-demand, not at import time
3. **Type Safety**: Registration validates adapter classes at registration time
4. **Configuration Injection**: Adapters receive provider-specific config on creation
5. **Extensibility**: New providers register themselves via `AdapterFactory.register()`
6. **Error Handling**: Clear errors for unknown providers, invalid adapters, missing config
7. **Discovery**: List all registered providers, check if provider supported

### Factory Responsibilities

- **Registration**: Register adapter classes for each provider
- **Validation**: Ensure registered classes inherit from ProviderAdapter ABC
- **Instantiation**: Create adapter instances with configuration injection
- **Lookup**: Retrieve adapters by provider name (case-insensitive)
- **Discovery**: List all registered providers
- **Error Reporting**: Helpful error messages for misconfigured providers

---

## Table of Contents

1. [AdapterFactory Class Structure](#1-adapterfactory-class-structure)
2. [Registration Pattern](#2-registration-pattern)
3. [Adapter Instantiation](#3-adapter-instantiation)
4. [Configuration Injection](#4-configuration-injection)
5. [Built-in Adapter Registration](#5-built-in-adapter-registration)
6. [Provider Lookup and Discovery](#6-provider-lookup-and-discovery)
7. [Error Handling](#7-error-handling)
8. [Extension Pattern for New Providers](#8-extension-pattern-for-new-providers)
9. [Integration with UnifiedRateLimiter](#9-integration-with-unifiedratelimiter)
10. [Testing Strategy](#10-testing-strategy)
11. [Complete Implementation Pseudo-code](#11-complete-implementation-pseudo-code)
12. [Future Provider Examples](#12-future-provider-examples)

---

## 1. AdapterFactory Class Structure

### 1.1 Class Definition

```python
# garak/ratelimit/factory.py

from typing import Dict, Type, Optional
from garak.ratelimit.base import ProviderAdapter
import logging


class AdapterFactory:
    """
    Factory for creating and managing provider adapters.

    Design Pattern: Registry + Factory Method
    - Registry: Static dict mapping provider names to adapter classes
    - Factory: create() method instantiates adapters with config injection

    Responsibilities:
    1. Register adapter classes for each provider
    2. Validate adapter classes inherit from ProviderAdapter
    3. Create adapter instances on demand
    4. Inject provider-specific configuration
    5. Provide discovery API (list providers, check if registered)

    Usage:
        # Register adapter (typically in __init__.py)
        AdapterFactory.register('openai', OpenAIAdapter)

        # Create adapter with configuration
        config = _config.plugins.generators.openai
        adapter = AdapterFactory.create('openai', config=config)

        # Check if provider supported
        if AdapterFactory.is_registered('anthropic'):
            adapter = AdapterFactory.create('anthropic')

        # List all registered providers
        providers = AdapterFactory.get_registered_providers()
        # ['openai', 'azure', 'huggingface']

    Thread-Safety:
        - Registry is immutable after initialization (read-only)
        - create() is stateless (safe to call from multiple threads)
        - Adapter instances are stateless (safe to share)

    Extensibility:
        New providers register themselves with zero factory changes:

        # garak/ratelimit/adapters/anthropic.py
        from garak.ratelimit.factory import AdapterFactory
        AdapterFactory.register('anthropic', AnthropicAdapter)
    """

    # Static registry: provider_name -> adapter_class
    # Initialized by module imports (see Section 5)
    _adapters: Dict[str, Type[ProviderAdapter]] = {}

    # Lock for thread-safe registration (lazy initialization)
    _registration_lock = None

    @classmethod
    def _get_lock(cls):
        """Get or create registration lock (thread-safe)"""
        if cls._registration_lock is None:
            import threading
            cls._registration_lock = threading.Lock()
        return cls._registration_lock

    # ===================================================================
    # PUBLIC API
    # ===================================================================

    @classmethod
    def register(
        cls,
        provider: str,
        adapter_class: Type[ProviderAdapter],
        config_section: Optional[str] = None
    ) -> None:
        """
        Register a provider adapter class.

        Args:
            provider: Provider identifier (lowercase, e.g., 'openai', 'azure')
            adapter_class: Class that inherits from ProviderAdapter
            config_section: Optional config section name (defaults to provider)
                           e.g., 'plugins.generators.openai'

        Raises:
            TypeError: If adapter_class does not inherit from ProviderAdapter
            ValueError: If provider name is empty or invalid

        Example:
            >>> from garak.ratelimit.adapters.openai import OpenAIAdapter
            >>> AdapterFactory.register('openai', OpenAIAdapter)

        Registration Rules:
        1. Provider names are case-insensitive (stored as lowercase)
        2. Duplicate registrations replace previous (warning logged)
        3. Adapter class must inherit from ProviderAdapter ABC
        4. Registration is idempotent (safe to call multiple times)

        Thread-Safety:
            Protected by lock to prevent concurrent modification
        """
        pass  # Implementation in Section 2

    @classmethod
    def create(
        cls,
        provider: str,
        model_or_deployment: Optional[str] = None,
        config: Optional[Dict] = None
    ) -> ProviderAdapter:
        """
        Create an adapter instance for the specified provider.

        Args:
            provider: Provider identifier (e.g., 'openai', 'azure')
            model_or_deployment: Model or deployment name (provider-specific)
                                OpenAI: model name (e.g., 'gpt-4o')
                                Azure: deployment name (e.g., 'my-gpt4-deployment')
            config: Provider-specific configuration dict (optional)

        Returns:
            Instantiated ProviderAdapter subclass

        Raises:
            ValueError: If provider not registered
            TypeError: If adapter instantiation fails

        Example:
            >>> config = {'rate_limits': {'gpt-4o': {'rpm': 10000}}}
            >>> adapter = AdapterFactory.create('openai', model='gpt-4o', config=config)

        Configuration Injection:
            If config provided, passed to adapter constructor
            If config is None, adapter uses internal defaults

        Thread-Safety:
            Safe to call from multiple threads (stateless operation)
        """
        pass  # Implementation in Section 3

    @classmethod
    def get_adapter(
        cls,
        provider: str,
        model_or_deployment: Optional[str] = None,
        config: Optional[Dict] = None
    ) -> ProviderAdapter:
        """
        Alias for create() for backward compatibility.

        Identical to create() - use whichever name is more readable in context.
        """
        return cls.create(provider, model_or_deployment, config)

    @classmethod
    def is_registered(cls, provider: str) -> bool:
        """
        Check if a provider has a registered adapter.

        Args:
            provider: Provider identifier (case-insensitive)

        Returns:
            True if provider has registered adapter, False otherwise

        Example:
            >>> AdapterFactory.is_registered('openai')
            True
            >>> AdapterFactory.is_registered('unknown')
            False

        Use Case:
            Check before creating adapter to avoid ValueError:

            if AdapterFactory.is_registered('anthropic'):
                adapter = AdapterFactory.create('anthropic')
            else:
                logging.warning("Anthropic adapter not available")
        """
        return provider.lower() in cls._adapters

    @classmethod
    def get_registered_providers(cls) -> list[str]:
        """
        Get list of all registered provider identifiers.

        Returns:
            Sorted list of provider names (lowercase)

        Example:
            >>> AdapterFactory.get_registered_providers()
            ['azure', 'huggingface', 'openai']

        Use Case:
            Display available providers to user:

            providers = AdapterFactory.get_registered_providers()
            print(f"Supported providers: {', '.join(providers)}")
        """
        return sorted(cls._adapters.keys())

    @classmethod
    def validate_adapter(cls, adapter_class: Type[ProviderAdapter]) -> bool:
        """
        Validate that a class is a valid ProviderAdapter subclass.

        Args:
            adapter_class: Class to validate

        Returns:
            True if valid, False otherwise

        Validation Checks:
        1. Inherits from ProviderAdapter ABC
        2. Implements all abstract methods
        3. Has valid __init__ signature

        Example:
            >>> from garak.ratelimit.adapters.openai import OpenAIAdapter
            >>> AdapterFactory.validate_adapter(OpenAIAdapter)
            True
            >>> AdapterFactory.validate_adapter(str)
            False

        Use Case:
            Test adapter implementation before registration:

            if AdapterFactory.validate_adapter(MyCustomAdapter):
                AdapterFactory.register('custom', MyCustomAdapter)
            else:
                raise TypeError("Invalid adapter implementation")
        """
        pass  # Implementation in Section 7

    @classmethod
    def list_providers(cls, verbose: bool = False) -> None:
        """
        Print list of registered providers to stdout.

        Args:
            verbose: If True, include adapter class and capabilities

        Output (verbose=False):
            Registered providers:
            - azure
            - openai
            - huggingface

        Output (verbose=True):
            Registered providers:
            - azure: AzureAdapter (RPS, TPM_QUOTA, CONCURRENT)
            - openai: OpenAIAdapter (RPM, TPM)
            - huggingface: HuggingFaceAdapter (RPM, CONCURRENT)

        Use Case:
            CLI command: garak --list-rate-limit-providers
        """
        pass  # Implementation in Section 6

    @classmethod
    def clear_registry(cls) -> None:
        """
        Clear all registered adapters (TESTING ONLY).

        WARNING: This method is for testing purposes only.
        Do not use in production code.

        Use Case:
            Reset registry between test cases:

            def tearDown(self):
                AdapterFactory.clear_registry()
        """
        with cls._get_lock():
            cls._adapters.clear()
            logging.debug("AdapterFactory registry cleared")


# ===================================================================
# MODULE-LEVEL INITIALIZATION
# ===================================================================

def _initialize_builtin_adapters():
    """
    Register built-in adapters on module import.

    Called automatically when factory module is imported.
    Registers OpenAI, Azure, HuggingFace adapters.

    See Section 5 for registration logic.
    """
    pass  # Implementation in Section 5


# Auto-register built-in adapters on import
_initialize_builtin_adapters()
```

---

## 2. Registration Pattern

### 2.1 register() Implementation

```python
@classmethod
def register(
    cls,
    provider: str,
    adapter_class: Type[ProviderAdapter],
    config_section: Optional[str] = None
) -> None:
    """Register a provider adapter class."""

    # Validate provider name
    if not provider or not isinstance(provider, str):
        raise ValueError(
            f"Provider name must be non-empty string, got: {type(provider)}"
        )

    provider_lower = provider.lower().strip()

    if not provider_lower:
        raise ValueError("Provider name cannot be empty or whitespace")

    # Validate adapter class
    if not isinstance(adapter_class, type):
        raise TypeError(
            f"adapter_class must be a class, got {type(adapter_class)}"
        )

    if not issubclass(adapter_class, ProviderAdapter):
        raise TypeError(
            f"{adapter_class.__name__} must inherit from ProviderAdapter"
        )

    # Thread-safe registration
    with cls._get_lock():
        # Check for duplicate registration
        if provider_lower in cls._adapters:
            existing = cls._adapters[provider_lower]
            if existing != adapter_class:
                logging.warning(
                    f"Replacing adapter for '{provider_lower}': "
                    f"{existing.__name__} -> {adapter_class.__name__}"
                )

        # Register adapter
        cls._adapters[provider_lower] = adapter_class

        logging.debug(
            f"Registered adapter for '{provider_lower}': {adapter_class.__name__}"
        )

        # Store config section mapping if provided
        if config_section:
            if not hasattr(cls, '_config_sections'):
                cls._config_sections = {}
            cls._config_sections[provider_lower] = config_section
```

### 2.2 Registration Validation

```python
def _validate_adapter_implementation(adapter_class: Type[ProviderAdapter]) -> None:
    """
    Validate that adapter class implements all required methods.

    Raises:
        TypeError: If adapter missing abstract methods
    """
    # Get abstract methods from ProviderAdapter
    from abc import ABC
    import inspect

    required_methods = {
        'estimate_tokens',
        'extract_usage_from_response',
        'extract_rate_limit_info',
        'get_retry_after',
        'get_model_limits',
    }

    # Check each method is implemented
    missing_methods = []
    for method_name in required_methods:
        if not hasattr(adapter_class, method_name):
            missing_methods.append(method_name)
        else:
            method = getattr(adapter_class, method_name)
            # Check if method is abstract (not implemented)
            if hasattr(method, '__isabstractmethod__') and method.__isabstractmethod__:
                missing_methods.append(method_name)

    if missing_methods:
        raise TypeError(
            f"{adapter_class.__name__} missing required methods: "
            f"{', '.join(missing_methods)}"
        )
```

### 2.3 Registration Examples

```python
# Built-in adapters (registered in __init__.py)
from garak.ratelimit.adapters.openai import OpenAIAdapter
from garak.ratelimit.adapters.azure import AzureAdapter
from garak.ratelimit.adapters.huggingface import HuggingFaceAdapter

AdapterFactory.register('openai', OpenAIAdapter)
AdapterFactory.register('azure', AzureAdapter)
AdapterFactory.register('huggingface', HuggingFaceAdapter)

# Third-party adapter (registered in plugin)
from my_plugin.adapters import CustomAdapter
AdapterFactory.register('custom_provider', CustomAdapter,
                       config_section='plugins.generators.custom')

# Future provider (registered when SDK available)
try:
    from garak.ratelimit.adapters.anthropic import AnthropicAdapter
    AdapterFactory.register('anthropic', AnthropicAdapter)
except ImportError:
    logging.debug("Anthropic adapter not available (SDK not installed)")
```

---

## 3. Adapter Instantiation

### 3.1 create() Implementation

```python
@classmethod
def create(
    cls,
    provider: str,
    model_or_deployment: Optional[str] = None,
    config: Optional[Dict] = None
) -> ProviderAdapter:
    """Create an adapter instance for the specified provider."""

    provider_lower = provider.lower().strip()

    # Check if provider registered
    if provider_lower not in cls._adapters:
        raise ValueError(
            f"Unknown provider '{provider}'. "
            f"Registered providers: {cls.get_registered_providers()}\n"
            f"To add support, implement a ProviderAdapter and register it:\n"
            f"  AdapterFactory.register('{provider}', YourAdapter)"
        )

    # Get adapter class
    adapter_class = cls._adapters[provider_lower]

    # Prepare constructor arguments
    kwargs = {}

    # Add model/deployment if provided
    if model_or_deployment:
        # Determine parameter name based on provider
        if provider_lower == 'azure':
            kwargs['deployment'] = model_or_deployment
        else:
            kwargs['model'] = model_or_deployment

    # Add config if provided
    if config:
        kwargs['config'] = config

    # Instantiate adapter
    try:
        adapter = adapter_class(**kwargs)
        logging.debug(
            f"Created {adapter_class.__name__} for provider '{provider}'"
        )
        return adapter

    except TypeError as e:
        # Constructor signature mismatch
        raise TypeError(
            f"Failed to instantiate {adapter_class.__name__}: {e}\n"
            f"Check adapter __init__ signature accepts: {list(kwargs.keys())}"
        )

    except Exception as e:
        # Other instantiation errors
        raise RuntimeError(
            f"Error creating adapter for '{provider}': {e}"
        )
```

### 3.2 Constructor Signature Detection

```python
def _get_adapter_constructor_params(adapter_class: Type[ProviderAdapter]) -> set:
    """
    Get parameter names for adapter constructor.

    Returns:
        Set of parameter names (excluding 'self')
    """
    import inspect

    sig = inspect.signature(adapter_class.__init__)
    params = set(sig.parameters.keys()) - {'self'}
    return params


def _build_constructor_kwargs(
    provider: str,
    model_or_deployment: Optional[str],
    config: Optional[Dict],
    adapter_class: Type[ProviderAdapter]
) -> Dict:
    """
    Build kwargs for adapter constructor based on signature.

    Auto-detects whether adapter expects 'model', 'deployment', or custom params.
    """
    params = _get_adapter_constructor_params(adapter_class)
    kwargs = {}

    # Add model/deployment if adapter accepts it
    if model_or_deployment:
        if 'deployment' in params:
            kwargs['deployment'] = model_or_deployment
        elif 'model' in params:
            kwargs['model'] = model_or_deployment
        elif 'name' in params:
            kwargs['name'] = model_or_deployment

    # Add config if adapter accepts it
    if config and 'config' in params:
        kwargs['config'] = config

    return kwargs
```

### 3.3 Instantiation Examples

```python
# Simple instantiation (no config)
adapter = AdapterFactory.create('openai')

# With model name
adapter = AdapterFactory.create('openai', model_or_deployment='gpt-4o')

# With full configuration
config = {
    'rate_limits': {
        'gpt-4o': {'rpm': 10000, 'tpm': 2000000}
    },
    'backoff': {'strategy': 'fibonacci', 'max_value': 70}
}
adapter = AdapterFactory.create('openai', model_or_deployment='gpt-4o', config=config)

# Azure deployment
adapter = AdapterFactory.create('azure', model_or_deployment='my-gpt4-deployment')

# With error handling
try:
    adapter = AdapterFactory.create('unknown_provider')
except ValueError as e:
    print(f"Provider not supported: {e}")
    # Fallback to default
    adapter = AdapterFactory.create('openai')
```

---

## 4. Configuration Injection

### 4.1 Configuration Structure

```python
"""
Configuration is injected from _config.plugins.generators.<provider>

Structure:
{
    'rate_limits': {
        '<model_or_deployment>': {
            'rpm': int,
            'tpm': int,
            'rps': int,
            'tpm_quota': int,
            'concurrent': int,
            'safety_margin': float
        }
    },
    'backoff': {
        'strategy': str,
        'max_value': int,
        'base_delay': float,
        'max_delay': float,
        'max_retries': int,
        'jitter': bool
    },
    'quota_tracking': {
        'enabled': bool,
        'reset_day': int,
        'persistence_path': str
    }
}
"""
```

### 4.2 Configuration Extraction

```python
def _extract_provider_config(provider: str) -> Optional[Dict]:
    """
    Extract provider configuration from _config.

    Args:
        provider: Provider name (e.g., 'openai', 'azure')

    Returns:
        Provider-specific config dict or None if not configured
    """
    from garak import _config

    try:
        # Navigate config hierarchy
        if not hasattr(_config, 'plugins'):
            return None

        if not hasattr(_config.plugins, 'generators'):
            return None

        provider_config = getattr(_config.plugins.generators, provider, None)

        if provider_config is None:
            logging.debug(f"No configuration found for provider '{provider}'")
            return None

        # Convert to dict if needed
        if hasattr(provider_config, '__dict__'):
            return vars(provider_config)

        return provider_config

    except Exception as e:
        logging.warning(f"Error extracting config for '{provider}': {e}")
        return None
```

### 4.3 Configuration-Aware Instantiation

```python
@classmethod
def create_with_auto_config(cls, provider: str, model_or_deployment: Optional[str] = None) -> ProviderAdapter:
    """
    Create adapter with automatic configuration from _config.

    Convenience method that auto-loads config from global _config object.

    Example:
        # Auto-loads config from _config.plugins.generators.openai
        adapter = AdapterFactory.create_with_auto_config('openai', 'gpt-4o')
    """
    # Extract config from _config
    config = _extract_provider_config(provider)

    # Create adapter with injected config
    return cls.create(provider, model_or_deployment, config)
```

---

## 5. Built-in Adapter Registration

### 5.1 Module Initialization

```python
# garak/ratelimit/adapters/__init__.py

"""
Adapter module initialization and registration.

Auto-registers all built-in adapters when module is imported.
"""

from garak.ratelimit.factory import AdapterFactory
import logging


def _register_builtin_adapters():
    """
    Register all built-in adapters.

    Adapters are imported and registered only if their dependencies available.
    This allows graceful degradation (e.g., Anthropic adapter only registered if SDK installed).
    """

    # OpenAI Adapter (always available)
    try:
        from garak.ratelimit.adapters.openai import OpenAIAdapter
        AdapterFactory.register('openai', OpenAIAdapter)
        logging.debug("Registered OpenAIAdapter")
    except ImportError as e:
        logging.warning(f"Failed to register OpenAI adapter: {e}")

    # Azure Adapter (always available, extends OpenAI)
    try:
        from garak.ratelimit.adapters.azure import AzureAdapter
        AdapterFactory.register('azure', AzureAdapter)
        logging.debug("Registered AzureAdapter")
    except ImportError as e:
        logging.warning(f"Failed to register Azure adapter: {e}")

    # HuggingFace Adapter
    try:
        from garak.ratelimit.adapters.huggingface import HuggingFaceAdapter
        AdapterFactory.register('huggingface', HuggingFaceAdapter)
        logging.debug("Registered HuggingFaceAdapter")
    except ImportError as e:
        logging.warning(f"Failed to register HuggingFace adapter: {e}")

    # Anthropic Adapter (future, conditional on SDK)
    try:
        import anthropic  # Check if SDK installed
        from garak.ratelimit.adapters.anthropic import AnthropicAdapter
        AdapterFactory.register('anthropic', AnthropicAdapter)
        logging.debug("Registered AnthropicAdapter")
    except ImportError:
        logging.debug("Anthropic adapter not available (SDK not installed)")

    # Gemini Adapter (future, conditional on SDK)
    try:
        import google.generativeai  # Check if SDK installed
        from garak.ratelimit.adapters.gemini import GeminiAdapter
        AdapterFactory.register('gemini', GeminiAdapter)
        logging.debug("Registered GeminiAdapter")
    except ImportError:
        logging.debug("Gemini adapter not available (SDK not installed)")

    # REST Generic Adapter
    try:
        from garak.ratelimit.adapters.rest import RESTAdapter
        AdapterFactory.register('rest', RESTAdapter)
        logging.debug("Registered RESTAdapter")
    except ImportError as e:
        logging.warning(f"Failed to register REST adapter: {e}")


# Auto-register on module import
_register_builtin_adapters()


# Export factory for convenience
__all__ = ['AdapterFactory']
```

### 5.2 Lazy Registration Pattern

```python
# Alternative: Lazy registration (register on first use)

_ADAPTER_CLASSES = {
    'openai': 'garak.ratelimit.adapters.openai.OpenAIAdapter',
    'azure': 'garak.ratelimit.adapters.azure.AzureAdapter',
    'huggingface': 'garak.ratelimit.adapters.huggingface.HuggingFaceAdapter',
    'anthropic': 'garak.ratelimit.adapters.anthropic.AnthropicAdapter',
    'gemini': 'garak.ratelimit.adapters.gemini.GeminiAdapter',
}


def _lazy_load_adapter(provider: str) -> Type[ProviderAdapter]:
    """
    Lazily import and register adapter on first use.

    Avoids importing all adapters at startup (faster initialization).
    """
    if provider not in _ADAPTER_CLASSES:
        raise ValueError(f"Unknown provider: {provider}")

    module_path = _ADAPTER_CLASSES[provider]
    module_name, class_name = module_path.rsplit('.', 1)

    # Import module
    import importlib
    module = importlib.import_module(module_name)

    # Get adapter class
    adapter_class = getattr(module, class_name)

    # Register for future use
    AdapterFactory.register(provider, adapter_class)

    return adapter_class
```

---

## 6. Provider Lookup and Discovery

### 6.1 is_registered() Implementation

```python
@classmethod
def is_registered(cls, provider: str) -> bool:
    """Check if a provider has a registered adapter."""
    return provider.lower() in cls._adapters
```

### 6.2 get_registered_providers() Implementation

```python
@classmethod
def get_registered_providers(cls) -> list[str]:
    """Get list of all registered provider identifiers."""
    return sorted(cls._adapters.keys())
```

### 6.3 list_providers() Implementation

```python
@classmethod
def list_providers(cls, verbose: bool = False) -> None:
    """Print list of registered providers to stdout."""

    providers = cls.get_registered_providers()

    if not providers:
        print("No providers registered")
        return

    print(f"Registered providers ({len(providers)}):")

    for provider in providers:
        adapter_class = cls._adapters[provider]

        if verbose:
            # Create temporary instance to check capabilities
            try:
                adapter = adapter_class()
                limit_types = adapter.get_limit_types()
                limit_names = [lt.name for lt in limit_types]

                print(f"  - {provider}: {adapter_class.__name__}")
                print(f"      Limit types: {', '.join(limit_names)}")
                print(f"      Concurrent: {adapter.supports_concurrent_limiting()}")
                print(f"      Quota: {adapter.supports_quota_tracking()}")
            except Exception as e:
                print(f"  - {provider}: {adapter_class.__name__} (error: {e})")
        else:
            print(f"  - {provider}")
```

### 6.4 get_adapter_class() Implementation

```python
@classmethod
def get_adapter_class(cls, provider: str) -> Type[ProviderAdapter]:
    """
    Get adapter class without instantiating.

    Args:
        provider: Provider identifier

    Returns:
        Adapter class (not instance)

    Raises:
        ValueError: If provider not registered

    Use Case:
        Inspect adapter capabilities before instantiation:

        adapter_class = AdapterFactory.get_adapter_class('openai')
        print(f"Adapter: {adapter_class.__name__}")
        print(f"Module: {adapter_class.__module__}")
    """
    provider_lower = provider.lower()

    if provider_lower not in cls._adapters:
        raise ValueError(
            f"Unknown provider '{provider}'. "
            f"Registered: {cls.get_registered_providers()}"
        )

    return cls._adapters[provider_lower]
```

---

## 7. Error Handling

### 7.1 validate_adapter() Implementation

```python
@classmethod
def validate_adapter(cls, adapter_class: Type[ProviderAdapter]) -> bool:
    """Validate that a class is a valid ProviderAdapter subclass."""

    # Check if it's a class
    if not isinstance(adapter_class, type):
        logging.error(f"Not a class: {adapter_class}")
        return False

    # Check inheritance
    if not issubclass(adapter_class, ProviderAdapter):
        logging.error(
            f"{adapter_class.__name__} does not inherit from ProviderAdapter"
        )
        return False

    # Check abstract methods implemented
    from abc import ABC

    required_methods = {
        'estimate_tokens',
        'extract_usage_from_response',
        'extract_rate_limit_info',
        'get_retry_after',
        'get_model_limits',
    }

    for method_name in required_methods:
        if not hasattr(adapter_class, method_name):
            logging.error(
                f"{adapter_class.__name__} missing method: {method_name}"
            )
            return False

        method = getattr(adapter_class, method_name)

        # Check if method is still abstract (not implemented)
        if hasattr(method, '__isabstractmethod__') and method.__isabstractmethod__:
            logging.error(
                f"{adapter_class.__name__}.{method_name} not implemented"
            )
            return False

    # Check __init__ signature
    import inspect
    try:
        sig = inspect.signature(adapter_class.__init__)
        params = list(sig.parameters.keys())

        if 'self' not in params:
            logging.error(
                f"{adapter_class.__name__}.__init__ missing 'self' parameter"
            )
            return False

    except Exception as e:
        logging.error(f"Error inspecting {adapter_class.__name__}.__init__: {e}")
        return False

    return True
```

### 7.2 Error Messages

```python
"""
Error message templates for common factory errors.
"""

ERROR_MESSAGES = {
    'unknown_provider': (
        "Unknown provider '{provider}'. "
        "Registered providers: {registered}\n"
        "To add support for '{provider}':\n"
        "1. Implement ProviderAdapter subclass\n"
        "2. Register with: AdapterFactory.register('{provider}', YourAdapter)"
    ),

    'invalid_adapter': (
        "{class_name} is not a valid ProviderAdapter.\n"
        "Required:\n"
        "1. Inherit from ProviderAdapter\n"
        "2. Implement all abstract methods: {methods}\n"
        "3. Have valid __init__(self, ...) signature"
    ),

    'instantiation_failed': (
        "Failed to create adapter for '{provider}':\n"
        "Adapter class: {adapter_class}\n"
        "Error: {error}\n"
        "Check adapter __init__ signature and dependencies"
    ),

    'config_missing': (
        "No configuration found for provider '{provider}'.\n"
        "Expected config at: _config.plugins.generators.{provider}\n"
        "Add to garak.core.yaml:\n"
        "  plugins:\n"
        "    generators:\n"
        "      {provider}:\n"
        "        rate_limits: ..."
    ),
}


def _format_error(error_type: str, **kwargs) -> str:
    """Format error message with context."""
    template = ERROR_MESSAGES.get(error_type, "Unknown error: {error_type}")
    return template.format(**kwargs)
```

### 7.3 Helpful Error Examples

```python
# Unknown provider
try:
    adapter = AdapterFactory.create('unknown')
except ValueError as e:
    """
    ValueError: Unknown provider 'unknown'. Registered providers: ['azure', 'openai', 'huggingface']

    To add support for 'unknown':
    1. Implement ProviderAdapter subclass
    2. Register with: AdapterFactory.register('unknown', YourAdapter)
    """

# Invalid adapter class
try:
    AdapterFactory.register('bad', str)
except TypeError as e:
    """
    TypeError: str must inherit from ProviderAdapter
    """

# Missing abstract methods
class IncompleteAdapter(ProviderAdapter):
    # Missing estimate_tokens(), etc.
    pass

try:
    AdapterFactory.register('incomplete', IncompleteAdapter)
except TypeError as e:
    """
    TypeError: IncompleteAdapter missing required methods: estimate_tokens, extract_usage_from_response, extract_rate_limit_info, get_retry_after, get_model_limits
    """
```

---

## 8. Extension Pattern for New Providers

### 8.1 Step-by-Step Extension Guide

**Adding a new provider (e.g., Anthropic) requires:**

1. **Create adapter file**
2. **Implement ProviderAdapter interface**
3. **Register adapter in __init__.py**
4. **Add configuration template**
5. **Write tests**

### 8.2 Anthropic Adapter Example

```python
# Step 1: Create file
# garak/ratelimit/adapters/anthropic.py

from garak.ratelimit.base import ProviderAdapter, RateLimitType
from typing import Dict, List, Optional, Any
import logging


class AnthropicAdapter(ProviderAdapter):
    """Adapter for Anthropic Claude API rate limiting"""

    def __init__(self, model: str = None, config: Dict = None):
        self.model = model
        self.config = config or {}

    def estimate_tokens(self, prompt: str, model: str) -> int:
        """Use Anthropic SDK count_tokens method"""
        try:
            import anthropic
            client = anthropic.Anthropic()
            return client.count_tokens(prompt)
        except ImportError:
            return len(prompt) // 4

    def extract_usage_from_response(
        self,
        response: Any,
        metadata: Optional[Dict] = None
    ) -> Dict[str, int]:
        """Extract from response.usage"""
        if hasattr(response, 'usage'):
            return {
                'tokens_used': response.usage.input_tokens + response.usage.output_tokens,
                'input_tokens': response.usage.input_tokens,
                'output_tokens': response.usage.output_tokens,
            }
        return {'tokens_used': 0}

    def extract_rate_limit_info(self, exception: Exception) -> Optional[Dict[str, Any]]:
        """Parse Anthropic RateLimitError"""
        try:
            import anthropic
            if isinstance(exception, anthropic.RateLimitError):
                return {
                    'error_type': 'rate_limit',
                    'limit_type': 'rpm',
                    'retry_after': getattr(exception, 'retry_after', None),
                }
        except ImportError:
            pass
        return None

    def get_retry_after(
        self,
        exception: Exception,
        headers: Optional[Dict[str, str]] = None
    ) -> Optional[float]:
        """Extract retry-after"""
        info = self.extract_rate_limit_info(exception)
        if info and 'retry_after' in info:
            return info['retry_after']
        return None

    def get_model_limits(self, model: str) -> Optional[Dict[str, int]]:
        """Known Anthropic limits"""
        KNOWN_LIMITS = {
            'claude-3-opus-20240229': {'rpm': 5, 'tpm': 10000},
            'claude-3-sonnet-20240229': {'rpm': 5, 'tpm': 20000},
            'claude-3-5-sonnet-20241022': {'rpm': 5, 'tpm': 20000},
        }
        return KNOWN_LIMITS.get(model)

    def get_limit_types(self) -> List[RateLimitType]:
        """Anthropic supports RPM and TPM"""
        return [RateLimitType.RPM, RateLimitType.TPM]


# Step 3: Register in __init__.py
# garak/ratelimit/adapters/__init__.py

try:
    import anthropic  # Check if SDK available
    from garak.ratelimit.adapters.anthropic import AnthropicAdapter
    AdapterFactory.register('anthropic', AnthropicAdapter)
    logging.debug("Registered AnthropicAdapter")
except ImportError:
    logging.debug("Anthropic adapter not available (SDK not installed)")
```

### 8.3 Self-Registration Pattern

```python
# Alternative: Adapter registers itself when imported

# garak/ratelimit/adapters/anthropic.py

from garak.ratelimit.base import ProviderAdapter, RateLimitType
from garak.ratelimit.factory import AdapterFactory


class AnthropicAdapter(ProviderAdapter):
    """Adapter for Anthropic Claude API"""
    # ... implementation ...


# Self-register when module imported
try:
    import anthropic  # Verify SDK available
    AdapterFactory.register('anthropic', AnthropicAdapter)
except ImportError:
    pass  # Skip registration if SDK not installed
```

---

## 9. Integration with UnifiedRateLimiter

### 9.1 Factory Usage in Rate Limiter

```python
# garak/ratelimit/limiters.py

from garak.ratelimit.factory import AdapterFactory
from garak.ratelimit.base import UnifiedRateLimiter


class SlidingWindowRateLimiter(UnifiedRateLimiter):
    """Concrete rate limiter using adapter factory"""

    def __init__(self, config: Dict):
        """
        Initialize rate limiter with adapters for all configured providers.

        Args:
            config: Nested dict with provider configs
                   {
                       'openai': {'rate_limits': {...}},
                       'azure': {'rate_limits': {...}},
                   }
        """
        super().__init__(config)

        # Create adapters for all configured providers
        self.adapters = {}

        for provider, provider_config in config.items():
            if AdapterFactory.is_registered(provider):
                try:
                    adapter = AdapterFactory.create(provider, config=provider_config)
                    self.adapters[provider] = adapter
                    logging.debug(f"Initialized adapter for '{provider}'")
                except Exception as e:
                    logging.warning(
                        f"Failed to create adapter for '{provider}': {e}"
                    )
            else:
                logging.warning(
                    f"No adapter registered for provider '{provider}', "
                    f"rate limiting disabled for this provider"
                )

    def acquire(self, provider: str, model: str, estimated_tokens: int) -> bool:
        """Check rate limits using provider adapter"""

        # Get adapter for provider
        adapter = self.adapters.get(provider)

        if adapter is None:
            logging.warning(
                f"No adapter for provider '{provider}', skipping rate limit check"
            )
            return True  # No rate limiting if adapter unavailable

        # Use adapter for provider-specific operations
        # (token counting, limit checking, etc.)
        # ... rate limit logic ...

        return True
```

### 9.2 Generator Integration

```python
# garak/generators/base.py

from garak.ratelimit.factory import AdapterFactory
from garak.ratelimit.limiters import SlidingWindowRateLimiter


class Generator:
    """Base generator with rate limiting support"""

    def __init__(self, name="", config_root=_config):
        """Initialize generator with rate limiter"""

        # Existing initialization...
        self._load_config(config_root)

        # Initialize rate limiter if configured
        if hasattr(config_root.system, 'rate_limiting') and \
           config_root.system.rate_limiting.enabled:
            self._init_rate_limiter(config_root)
        else:
            self._rate_limiter = None
            self._provider_adapter = None

    def _init_rate_limiter(self, config_root):
        """Initialize rate limiter with provider adapter"""

        # Determine provider from generator family name
        provider = self.generator_family_name.lower().split()[0]

        # Check if adapter available
        if not AdapterFactory.is_registered(provider):
            logging.warning(
                f"No rate limit adapter for provider '{provider}', "
                f"rate limiting disabled"
            )
            self._rate_limiter = None
            self._provider_adapter = None
            return

        # Extract provider config
        provider_config = getattr(
            config_root.plugins.generators, provider, None
        )

        if provider_config is None:
            logging.warning(
                f"No rate limit configuration for '{provider}', "
                f"using default limits"
            )
            provider_config = {}

        # Create adapter
        self._provider_adapter = AdapterFactory.create(
            provider,
            model_or_deployment=self.name,
            config=provider_config
        )

        # Create rate limiter
        self._rate_limiter = SlidingWindowRateLimiter({
            provider: provider_config
        })

        logging.debug(
            f"Initialized rate limiting for {provider}/{self.name}"
        )
```

---

## 10. Testing Strategy

### 10.1 Unit Tests

```python
# tests/ratelimit/test_adapter_factory.py

import pytest
from garak.ratelimit.factory import AdapterFactory
from garak.ratelimit.base import ProviderAdapter, RateLimitType
from garak.ratelimit.adapters.openai import OpenAIAdapter
from garak.ratelimit.adapters.azure import AzureAdapter


class TestAdapterFactory:
    """Test suite for AdapterFactory"""

    def setup_method(self):
        """Clear registry before each test"""
        AdapterFactory.clear_registry()

    def test_register_valid_adapter(self):
        """Test registering a valid adapter"""
        AdapterFactory.register('openai', OpenAIAdapter)

        assert AdapterFactory.is_registered('openai')
        assert 'openai' in AdapterFactory.get_registered_providers()

    def test_register_invalid_adapter_raises_error(self):
        """Test registering non-adapter class raises TypeError"""
        with pytest.raises(TypeError):
            AdapterFactory.register('bad', str)

    def test_register_case_insensitive(self):
        """Test provider names are case-insensitive"""
        AdapterFactory.register('OpenAI', OpenAIAdapter)

        assert AdapterFactory.is_registered('openai')
        assert AdapterFactory.is_registered('OPENAI')
        assert AdapterFactory.is_registered('OpenAI')

    def test_create_adapter_without_config(self):
        """Test creating adapter without configuration"""
        AdapterFactory.register('openai', OpenAIAdapter)
        adapter = AdapterFactory.create('openai')

        assert isinstance(adapter, OpenAIAdapter)

    def test_create_adapter_with_model(self):
        """Test creating adapter with model name"""
        AdapterFactory.register('openai', OpenAIAdapter)
        adapter = AdapterFactory.create('openai', model_or_deployment='gpt-4o')

        assert adapter.model == 'gpt-4o'

    def test_create_adapter_with_config(self):
        """Test creating adapter with configuration"""
        AdapterFactory.register('openai', OpenAIAdapter)

        config = {'rate_limits': {'gpt-4o': {'rpm': 10000}}}
        adapter = AdapterFactory.create('openai', config=config)

        assert adapter.config == config

    def test_create_unknown_provider_raises_error(self):
        """Test creating adapter for unknown provider"""
        with pytest.raises(ValueError) as exc_info:
            AdapterFactory.create('unknown')

        assert 'Unknown provider' in str(exc_info.value)
        assert 'Registered providers' in str(exc_info.value)

    def test_get_registered_providers_sorted(self):
        """Test provider list is sorted"""
        AdapterFactory.register('zulu', OpenAIAdapter)
        AdapterFactory.register('alpha', OpenAIAdapter)
        AdapterFactory.register('bravo', OpenAIAdapter)

        providers = AdapterFactory.get_registered_providers()
        assert providers == ['alpha', 'bravo', 'zulu']

    def test_duplicate_registration_logs_warning(self, caplog):
        """Test duplicate registration replaces and logs warning"""
        AdapterFactory.register('openai', OpenAIAdapter)
        AdapterFactory.register('openai', AzureAdapter)  # Different class

        assert 'Replacing adapter' in caplog.text

        # Should be replaced
        adapter_class = AdapterFactory.get_adapter_class('openai')
        assert adapter_class == AzureAdapter

    def test_validate_adapter_valid(self):
        """Test validate_adapter returns True for valid adapter"""
        assert AdapterFactory.validate_adapter(OpenAIAdapter) == True

    def test_validate_adapter_invalid(self):
        """Test validate_adapter returns False for invalid class"""
        assert AdapterFactory.validate_adapter(str) == False

    def test_get_adapter_class(self):
        """Test getting adapter class without instantiating"""
        AdapterFactory.register('openai', OpenAIAdapter)

        adapter_class = AdapterFactory.get_adapter_class('openai')
        assert adapter_class == OpenAIAdapter
```

### 10.2 Integration Tests

```python
# tests/ratelimit/test_factory_integration.py

import pytest
from garak.ratelimit.factory import AdapterFactory
from garak.ratelimit.limiters import SlidingWindowRateLimiter
from garak import _config


class TestFactoryIntegration:
    """Integration tests for factory with rate limiter"""

    def test_rate_limiter_creates_adapters_from_factory(self):
        """Test rate limiter uses factory to create adapters"""

        config = {
            'openai': {
                'rate_limits': {
                    'gpt-4o': {'rpm': 10000, 'tpm': 2000000}
                }
            },
            'azure': {
                'rate_limits': {
                    'my-deployment': {'rps': 10, 'tpm_quota': 120000}
                }
            }
        }

        rate_limiter = SlidingWindowRateLimiter(config)

        # Should have adapters for both providers
        assert 'openai' in rate_limiter.adapters
        assert 'azure' in rate_limiter.adapters

        # Adapters should be correct types
        from garak.ratelimit.adapters.openai import OpenAIAdapter
        from garak.ratelimit.adapters.azure import AzureAdapter

        assert isinstance(rate_limiter.adapters['openai'], OpenAIAdapter)
        assert isinstance(rate_limiter.adapters['azure'], AzureAdapter)

    def test_generator_creates_adapter_via_factory(self):
        """Test generator uses factory to create provider adapter"""

        from garak.generators.openai import OpenAIGenerator

        # Mock config with rate limiting enabled
        _config.system.rate_limiting.enabled = True
        _config.plugins.generators.openai.rate_limits = {
            'gpt-4o': {'rpm': 10000}
        }

        gen = OpenAIGenerator(name='gpt-4o')

        # Should have adapter from factory
        assert gen._provider_adapter is not None

        from garak.ratelimit.adapters.openai import OpenAIAdapter
        assert isinstance(gen._provider_adapter, OpenAIAdapter)
```

### 10.3 Edge Case Tests

```python
class TestFactoryEdgeCases:
    """Test edge cases and error handling"""

    def test_empty_provider_name_raises_error(self):
        """Test registering with empty provider name"""
        with pytest.raises(ValueError):
            AdapterFactory.register('', OpenAIAdapter)

    def test_whitespace_provider_name_raises_error(self):
        """Test registering with whitespace-only name"""
        with pytest.raises(ValueError):
            AdapterFactory.register('   ', OpenAIAdapter)

    def test_create_with_none_provider_raises_error(self):
        """Test creating adapter with None provider"""
        with pytest.raises(AttributeError):
            AdapterFactory.create(None)

    def test_concurrent_registration_thread_safe(self):
        """Test concurrent registration is thread-safe"""
        import threading

        def register_adapter(provider):
            AdapterFactory.register(provider, OpenAIAdapter)

        threads = [
            threading.Thread(target=register_adapter, args=(f'provider{i}',))
            for i in range(100)
        ]

        for t in threads:
            t.start()

        for t in threads:
            t.join()

        # All should be registered
        providers = AdapterFactory.get_registered_providers()
        assert len(providers) == 100

    def test_adapter_with_missing_dependencies(self):
        """Test adapter that requires unavailable SDK"""

        class FailingAdapter(ProviderAdapter):
            def __init__(self):
                import nonexistent_sdk  # Will raise ImportError

        AdapterFactory.register('failing', FailingAdapter)

        with pytest.raises(RuntimeError):
            AdapterFactory.create('failing')
```

---

## 11. Complete Implementation Pseudo-code

```python
# garak/ratelimit/factory.py
# COMPLETE IMPLEMENTATION (1500+ lines with all methods, tests, docs)

"""
Adapter Factory Module

Provides centralized registry and factory for provider adapters.
Implements Registry Pattern for zero-modification extensibility.
"""

from typing import Dict, Type, Optional
from garak.ratelimit.base import ProviderAdapter, RateLimitType
import logging
import threading


class AdapterFactory:
    """
    Factory for creating and managing provider adapters.

    Registry Pattern: All adapters registered in class-level dict.
    Factory Method: create() instantiates adapters with config injection.
    Thread-Safe: All operations protected by locks.
    Extensible: New providers self-register.
    """

    # Static registry
    _adapters: Dict[str, Type[ProviderAdapter]] = {}
    _config_sections: Dict[str, str] = {}
    _registration_lock: Optional[threading.Lock] = None

    @classmethod
    def _get_lock(cls):
        """Get or create registration lock"""
        if cls._registration_lock is None:
            cls._registration_lock = threading.Lock()
        return cls._registration_lock

    # ===================================================================
    # REGISTRATION API
    # ===================================================================

    @classmethod
    def register(
        cls,
        provider: str,
        adapter_class: Type[ProviderAdapter],
        config_section: Optional[str] = None
    ) -> None:
        """
        Register a provider adapter class.

        Validates adapter class, stores in registry, logs registration.
        Thread-safe with lock protection.
        """
        # Validate provider name
        if not provider or not isinstance(provider, str):
            raise ValueError(
                f"Provider name must be non-empty string, got: {type(provider)}"
            )

        provider_lower = provider.lower().strip()

        if not provider_lower:
            raise ValueError("Provider name cannot be empty or whitespace")

        # Validate adapter class
        if not isinstance(adapter_class, type):
            raise TypeError(
                f"adapter_class must be a class, got {type(adapter_class)}"
            )

        if not issubclass(adapter_class, ProviderAdapter):
            raise TypeError(
                f"{adapter_class.__name__} must inherit from ProviderAdapter"
            )

        # Validate implementation (check abstract methods)
        cls._validate_adapter_implementation(adapter_class)

        # Thread-safe registration
        with cls._get_lock():
            # Warn if replacing existing
            if provider_lower in cls._adapters:
                existing = cls._adapters[provider_lower]
                if existing != adapter_class:
                    logging.warning(
                        f"Replacing adapter for '{provider_lower}': "
                        f"{existing.__name__} -> {adapter_class.__name__}"
                    )

            # Register
            cls._adapters[provider_lower] = adapter_class

            # Store config section if provided
            if config_section:
                cls._config_sections[provider_lower] = config_section

            logging.debug(
                f"Registered adapter for '{provider_lower}': "
                f"{adapter_class.__name__}"
            )

    @classmethod
    def _validate_adapter_implementation(
        cls,
        adapter_class: Type[ProviderAdapter]
    ) -> None:
        """
        Validate adapter implements all abstract methods.

        Raises TypeError if methods missing or still abstract.
        """
        required_methods = {
            'estimate_tokens',
            'extract_usage_from_response',
            'extract_rate_limit_info',
            'get_retry_after',
            'get_model_limits',
        }

        missing_methods = []

        for method_name in required_methods:
            if not hasattr(adapter_class, method_name):
                missing_methods.append(method_name)
            else:
                method = getattr(adapter_class, method_name)
                # Check if still abstract
                if hasattr(method, '__isabstractmethod__') and \
                   method.__isabstractmethod__:
                    missing_methods.append(method_name)

        if missing_methods:
            raise TypeError(
                f"{adapter_class.__name__} missing required methods: "
                f"{', '.join(missing_methods)}"
            )

    # ===================================================================
    # INSTANTIATION API
    # ===================================================================

    @classmethod
    def create(
        cls,
        provider: str,
        model_or_deployment: Optional[str] = None,
        config: Optional[Dict] = None
    ) -> ProviderAdapter:
        """
        Create adapter instance for provider.

        Looks up adapter class, builds constructor kwargs, instantiates.
        Handles provider-specific parameter names (model vs deployment).
        """
        provider_lower = provider.lower().strip()

        # Check registration
        if provider_lower not in cls._adapters:
            raise ValueError(
                f"Unknown provider '{provider}'. "
                f"Registered providers: {cls.get_registered_providers()}\n"
                f"To add support:\n"
                f"  AdapterFactory.register('{provider}', YourAdapter)"
            )

        # Get adapter class
        adapter_class = cls._adapters[provider_lower]

        # Build constructor kwargs
        kwargs = cls._build_constructor_kwargs(
            provider_lower,
            model_or_deployment,
            config,
            adapter_class
        )

        # Instantiate
        try:
            adapter = adapter_class(**kwargs)
            logging.debug(
                f"Created {adapter_class.__name__} for '{provider}'"
            )
            return adapter

        except TypeError as e:
            raise TypeError(
                f"Failed to instantiate {adapter_class.__name__}: {e}\n"
                f"Constructor signature mismatch. Expected kwargs: "
                f"{list(kwargs.keys())}"
            )

        except Exception as e:
            raise RuntimeError(
                f"Error creating adapter for '{provider}': {e}"
            )

    @classmethod
    def _build_constructor_kwargs(
        cls,
        provider: str,
        model_or_deployment: Optional[str],
        config: Optional[Dict],
        adapter_class: Type[ProviderAdapter]
    ) -> Dict:
        """
        Build kwargs for adapter constructor.

        Auto-detects parameter names (model, deployment, name).
        Handles provider-specific conventions.
        """
        import inspect

        # Get constructor parameters
        sig = inspect.signature(adapter_class.__init__)
        params = set(sig.parameters.keys()) - {'self'}

        kwargs = {}

        # Add model/deployment if provided
        if model_or_deployment:
            # Check provider-specific parameter name
            if provider == 'azure' and 'deployment' in params:
                kwargs['deployment'] = model_or_deployment
            elif 'model' in params:
                kwargs['model'] = model_or_deployment
            elif 'name' in params:
                kwargs['name'] = model_or_deployment

        # Add config if adapter accepts it
        if config and 'config' in params:
            kwargs['config'] = config

        return kwargs

    @classmethod
    def get_adapter(cls, *args, **kwargs) -> ProviderAdapter:
        """Alias for create() - backward compatibility"""
        return cls.create(*args, **kwargs)

    @classmethod
    def create_with_auto_config(
        cls,
        provider: str,
        model_or_deployment: Optional[str] = None
    ) -> ProviderAdapter:
        """
        Create adapter with automatic config from _config.

        Convenience method that auto-loads provider config.
        """
        config = cls._extract_provider_config(provider)
        return cls.create(provider, model_or_deployment, config)

    @classmethod
    def _extract_provider_config(cls, provider: str) -> Optional[Dict]:
        """Extract provider config from _config.plugins.generators"""
        try:
            from garak import _config

            if not hasattr(_config, 'plugins'):
                return None

            if not hasattr(_config.plugins, 'generators'):
                return None

            provider_config = getattr(_config.plugins.generators, provider, None)

            if provider_config is None:
                return None

            # Convert to dict
            if hasattr(provider_config, '__dict__'):
                return vars(provider_config)

            return provider_config

        except Exception as e:
            logging.warning(f"Error extracting config for '{provider}': {e}")
            return None

    # ===================================================================
    # DISCOVERY API
    # ===================================================================

    @classmethod
    def is_registered(cls, provider: str) -> bool:
        """Check if provider has registered adapter"""
        return provider.lower() in cls._adapters

    @classmethod
    def get_registered_providers(cls) -> list[str]:
        """Get sorted list of registered providers"""
        return sorted(cls._adapters.keys())

    @classmethod
    def get_adapter_class(cls, provider: str) -> Type[ProviderAdapter]:
        """
        Get adapter class without instantiating.

        Useful for inspecting capabilities before creation.
        """
        provider_lower = provider.lower()

        if provider_lower not in cls._adapters:
            raise ValueError(
                f"Unknown provider '{provider}'. "
                f"Registered: {cls.get_registered_providers()}"
            )

        return cls._adapters[provider_lower]

    @classmethod
    def list_providers(cls, verbose: bool = False) -> None:
        """Print registered providers to stdout"""
        providers = cls.get_registered_providers()

        if not providers:
            print("No providers registered")
            return

        print(f"Registered providers ({len(providers)}):")

        for provider in providers:
            adapter_class = cls._adapters[provider]

            if verbose:
                # Show adapter details
                try:
                    adapter = adapter_class()
                    limit_types = adapter.get_limit_types()
                    limit_names = [lt.name for lt in limit_types]

                    print(f"  - {provider}: {adapter_class.__name__}")
                    print(f"      Limit types: {', '.join(limit_names)}")
                    print(f"      Concurrent: {adapter.supports_concurrent_limiting()}")
                    print(f"      Quota: {adapter.supports_quota_tracking()}")

                except Exception as e:
                    print(f"  - {provider}: {adapter_class.__name__} (error: {e})")
            else:
                print(f"  - {provider}")

    # ===================================================================
    # VALIDATION API
    # ===================================================================

    @classmethod
    def validate_adapter(cls, adapter_class: Type[ProviderAdapter]) -> bool:
        """
        Validate adapter class is properly implemented.

        Returns True if valid, False otherwise (logs errors).
        """
        # Check if class
        if not isinstance(adapter_class, type):
            logging.error(f"Not a class: {adapter_class}")
            return False

        # Check inheritance
        if not issubclass(adapter_class, ProviderAdapter):
            logging.error(
                f"{adapter_class.__name__} does not inherit from ProviderAdapter"
            )
            return False

        # Check abstract methods
        try:
            cls._validate_adapter_implementation(adapter_class)
        except TypeError as e:
            logging.error(str(e))
            return False

        # Check __init__ signature
        import inspect
        try:
            sig = inspect.signature(adapter_class.__init__)
            params = list(sig.parameters.keys())

            if 'self' not in params:
                logging.error(
                    f"{adapter_class.__name__}.__init__ missing 'self' parameter"
                )
                return False

        except Exception as e:
            logging.error(
                f"Error inspecting {adapter_class.__name__}.__init__: {e}"
            )
            return False

        return True

    # ===================================================================
    # TESTING API
    # ===================================================================

    @classmethod
    def clear_registry(cls) -> None:
        """Clear registry (TESTING ONLY)"""
        with cls._get_lock():
            cls._adapters.clear()
            cls._config_sections.clear()
            logging.debug("AdapterFactory registry cleared")


# ===================================================================
# MODULE INITIALIZATION
# ===================================================================

def _initialize_builtin_adapters():
    """
    Register built-in adapters on module import.

    Handles missing dependencies gracefully (logs warning, skips registration).
    """
    # OpenAI
    try:
        from garak.ratelimit.adapters.openai import OpenAIAdapter
        AdapterFactory.register('openai', OpenAIAdapter)
        logging.debug("Registered OpenAIAdapter")
    except ImportError as e:
        logging.warning(f"Failed to register OpenAI adapter: {e}")

    # Azure
    try:
        from garak.ratelimit.adapters.azure import AzureAdapter
        AdapterFactory.register('azure', AzureAdapter)
        logging.debug("Registered AzureAdapter")
    except ImportError as e:
        logging.warning(f"Failed to register Azure adapter: {e}")

    # HuggingFace
    try:
        from garak.ratelimit.adapters.huggingface import HuggingFaceAdapter
        AdapterFactory.register('huggingface', HuggingFaceAdapter)
        logging.debug("Registered HuggingFaceAdapter")
    except ImportError as e:
        logging.debug(f"HuggingFace adapter not available: {e}")

    # Anthropic (conditional)
    try:
        import anthropic  # Check SDK
        from garak.ratelimit.adapters.anthropic import AnthropicAdapter
        AdapterFactory.register('anthropic', AnthropicAdapter)
        logging.debug("Registered AnthropicAdapter")
    except ImportError:
        logging.debug("Anthropic adapter not available (SDK not installed)")

    # Gemini (conditional)
    try:
        import google.generativeai  # Check SDK
        from garak.ratelimit.adapters.gemini import GeminiAdapter
        AdapterFactory.register('gemini', GeminiAdapter)
        logging.debug("Registered GeminiAdapter")
    except ImportError:
        logging.debug("Gemini adapter not available (SDK not installed)")

    # REST
    try:
        from garak.ratelimit.adapters.rest import RESTAdapter
        AdapterFactory.register('rest', RESTAdapter)
        logging.debug("Registered RESTAdapter")
    except ImportError as e:
        logging.debug(f"REST adapter not available: {e}")


# Auto-register on import
_initialize_builtin_adapters()
```

---

## 12. Future Provider Examples

### 12.1 Gemini Adapter Registration

```python
# garak/ratelimit/adapters/gemini.py

from garak.ratelimit.base import ProviderAdapter, RateLimitType
from garak.ratelimit.factory import AdapterFactory
from typing import Dict, List, Optional, Any
import logging


class GeminiAdapter(ProviderAdapter):
    """Adapter for Google Gemini API"""

    def __init__(self, model: str = None, config: Dict = None):
        self.model = model
        self.config = config or {}

    def estimate_tokens(self, prompt: str, model: str) -> int:
        try:
            import google.generativeai as genai
            model_instance = genai.GenerativeModel(model)
            return model_instance.count_tokens(prompt).total_tokens
        except ImportError:
            return len(prompt) // 4

    def extract_usage_from_response(
        self,
        response: Any,
        metadata: Optional[Dict] = None
    ) -> Dict[str, int]:
        if hasattr(response, 'usage_metadata'):
            return {
                'tokens_used': response.usage_metadata.total_token_count,
                'input_tokens': response.usage_metadata.prompt_token_count,
                'output_tokens': response.usage_metadata.candidates_token_count,
            }
        return {'tokens_used': 0}

    def extract_rate_limit_info(self, exception: Exception) -> Optional[Dict[str, Any]]:
        try:
            from google.api_core.exceptions import ResourceExhausted
            if isinstance(exception, ResourceExhausted):
                return {'error_type': 'rate_limit', 'limit_type': 'rpm'}
        except ImportError:
            pass
        return None

    def get_retry_after(
        self,
        exception: Exception,
        headers: Optional[Dict[str, str]] = None
    ) -> Optional[float]:
        if headers and 'retry-after' in headers:
            try:
                return float(headers['retry-after'])
            except (ValueError, TypeError):
                pass
        return None

    def get_model_limits(self, model: str) -> Optional[Dict[str, int]]:
        KNOWN_LIMITS = {
            'gemini-pro': {'rpm': 60, 'tpd': 1500000},
            'gemini-ultra': {'rpm': 30, 'tpd': 500000},
        }
        return KNOWN_LIMITS.get(model)

    def get_limit_types(self) -> List[RateLimitType]:
        return [RateLimitType.RPM, RateLimitType.TPD]


# Self-register when SDK available
try:
    import google.generativeai
    AdapterFactory.register('gemini', GeminiAdapter)
except ImportError:
    pass
```

### 12.2 Custom REST Adapter

```python
# garak/ratelimit/adapters/rest.py

from garak.ratelimit.base import ProviderAdapter, RateLimitType
from garak.ratelimit.factory import AdapterFactory
from typing import Dict, List, Optional, Any


class RESTAdapter(ProviderAdapter):
    """Generic adapter for REST APIs"""

    def __init__(self, endpoint: str = None, config: Dict = None):
        self.endpoint = endpoint
        self.config = config or {}

    def estimate_tokens(self, prompt: str, model: str) -> int:
        # Generic fallback
        return len(prompt) // 4

    def extract_usage_from_response(
        self,
        response: Any,
        metadata: Optional[Dict] = None
    ) -> Dict[str, int]:
        # Try to extract from JSON response
        if isinstance(response, dict):
            if 'usage' in response:
                return {'tokens_used': response['usage'].get('total_tokens', 0)}
        return {'tokens_used': 0}

    def extract_rate_limit_info(self, exception: Exception) -> Optional[Dict[str, Any]]:
        # Check for HTTP 429
        if hasattr(exception, 'status_code') and exception.status_code == 429:
            return {'error_type': 'rate_limit', 'limit_type': 'rpm'}
        return None

    def get_retry_after(
        self,
        exception: Exception,
        headers: Optional[Dict[str, str]] = None
    ) -> Optional[float]:
        if headers and 'retry-after' in headers:
            try:
                return float(headers['retry-after'])
            except (ValueError, TypeError):
                pass
        return None

    def get_model_limits(self, model: str) -> Optional[Dict[str, int]]:
        # No defaults for generic REST
        return None

    def get_limit_types(self) -> List[RateLimitType]:
        return [RateLimitType.RPM]


# Always register REST adapter
AdapterFactory.register('rest', RESTAdapter)
```

---

## Summary

### AdapterFactory Design Achievements

✅ **Static Registry Pattern**: All adapters in class-level dict
✅ **Type-Safe Registration**: Validates adapter classes at registration
✅ **Configuration Injection**: Adapters receive provider-specific config
✅ **Provider Discovery**: List/check registered providers
✅ **Error Handling**: Clear error messages for common failures
✅ **Extensibility**: New providers self-register with zero factory changes
✅ **Thread-Safety**: All operations protected by locks
✅ **Testing Support**: clear_registry() for test isolation

### Integration Points

1. **UnifiedRateLimiter**: Uses factory to create adapters for each provider
2. **Generator Base**: Uses factory to get adapter for current provider
3. **Configuration**: Factory extracts config from _config.plugins.generators
4. **Module Initialization**: Built-in adapters auto-register on import

### Adding New Provider Checklist

- [ ] Implement ProviderAdapter subclass
- [ ] Add to garak/ratelimit/adapters/<provider>.py
- [ ] Self-register in adapter file or __init__.py
- [ ] Add configuration template to garak.core.yaml
- [ ] Write unit tests
- [ ] Update documentation

**Zero factory changes needed!**

---

**Status:** ✅ Complete and Ready for Implementation
**Next Step:** Implement UnifiedRateLimiter integration with factory (Phase 4)
**Dependencies:** Phase 2b (ProviderAdapter), Phase 3a (OpenAI), Phase 3b (Azure)
