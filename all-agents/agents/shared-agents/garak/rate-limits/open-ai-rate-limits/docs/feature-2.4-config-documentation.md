# Feature 2.4: Rate Limiting Configuration Documentation

**Status**: ✅ COMPLETE
**Date**: 2025-10-20
**Audience**: End users, developers, system administrators
**Scope**: Complete configuration reference for rate limiting

---

## QUICK START

### Enable Rate Limiting (Default)

Rate limiting is **enabled by default** for OpenAI generators. No configuration needed:

```bash
garak --generator openai.OpenAIGenerator --target_name gpt-3.5-turbo
```

This will:
- Use free tier (3 RPM, 40k TPM)
- Enforce rate limits before each API call
- Record actual token usage from responses

### Disable Rate Limiting

```bash
garak --generator openai.OpenAIGenerator \
      --target_name gpt-3.5-turbo \
      --generator_options enable_rate_limiting=false
```

### Use Higher Tier

```bash
# Via command line
garak --generator openai.OpenAIGenerator \
      --target_name gpt-3.5-turbo \
      --generator_options tier=tier5

# Via environment variable
export OPENAI_TIER=tier5
garak --generator openai.OpenAIGenerator --target_name gpt-3.5-turbo

# Via YAML config
echo "
openai:
  tier: tier5
" > config.yaml
garak --config config.yaml --generator openai.OpenAIGenerator --target_name gpt-3.5-turbo
```

---

## CONFIGURATION PARAMETERS

### 1. enable_rate_limiting

**Type**: Boolean
**Default**: `True`
**Purpose**: Enable/disable rate limiting feature

**Valid Values**:
- `true`: Enable rate limiting (default)
- `false`: Disable rate limiting

**Behavior**:
- When `true`: Enforces RPM/TPM limits, may sleep before API calls
- When `false`: Disables rate limiter, no sleeping, no limit checking

**Examples**:
```bash
# CLI
--generator_options enable_rate_limiting=true

# YAML
enable_rate_limiting: true
```

**Use Cases**:
- Set to `false` for testing/development
- Set to `false` for local development without API rate concerns
- Set to `true` for production to prevent rate limit errors

---

### 2. tier

**Type**: String
**Default**: `free`
**Purpose**: Select rate limit tier

**Valid Values** (per model):

**OpenAI Models** (gpt-3.5-turbo, gpt-4o, etc.):
- `free` (3 RPM, varies by model)
- `tier1` (500 RPM, varies by model)
- `tier2` (5k-10k RPM, varies by model)
- `tier3` (10k-20k RPM, varies by model)
- `tier4` (30k RPM, varies by model)
- `tier5` (30k RPM, varies by model)

**Azure Models** (deployment-type specific):
- `global_standard` (deployment type with rates)
- `data_zone_standard` (deployment type with rates)
- `standard` (deployment type with rates)

**Examples**:
```bash
# Free tier (slowest, no cost concern)
--generator_options tier=free

# Tier 5 (fastest, requires paid account)
--generator_options tier=tier5

# Via environment
export OPENAI_TIER=tier1

# Via YAML
tier: tier2
```

**Supported Models**:
- `gpt-3.5-turbo`: All tiers supported
- `gpt-4o`: All tiers supported
- `gpt-4o-mini`: All tiers supported (Azure only)

**Model-Specific Limits**:
```
gpt-3.5-turbo / free:      3 RPM, 40k TPM
gpt-3.5-turbo / tier5:     30k RPM, 20M TPM

gpt-4o / free:             3 RPM, 150k TPM
gpt-4o / tier5:            30k RPM, 10M TPM

gpt-4o-mini / free (Azure): 12k RPM, 2M TPM
```

---

## CONFIGURATION METHODS

### Method 1: Command Line (Highest Priority)

Use `--generator_options` to pass options:

```bash
garak --generator openai.OpenAIGenerator \
      --target_name gpt-3.5-turbo \
      --generator_options enable_rate_limiting=true tier=tier5
```

**Multiple options**:
```bash
--generator_options enable_rate_limiting=true,tier=tier5,temperature=0.8
```

**Priority**: 1 (highest)

---

### Method 2: Environment Variables

Use environment variables for configuration:

```bash
export OPENAI_TIER=tier5
export OPENAI_API_KEY=sk-...
garak --generator openai.OpenAIGenerator --target_name gpt-3.5-turbo
```

**Supported Variables**:
- `OPENAI_TIER`: Sets tier (free, tier1-5)
- `OPENAI_API_KEY`: OpenAI API key (existing)
- `AZURE_OPENAI_API_KEY`: Azure API key (existing)

**Priority**: 2 (medium)

---

### Method 3: YAML Configuration File

Create a configuration file:

```yaml
# config.yaml
generators:
  openai:
    enable_rate_limiting: true
    tier: tier5
    temperature: 0.7
    top_p: 1.0
```

Usage:
```bash
garak --config config.yaml \
      --generator openai.OpenAIGenerator \
      --target_name gpt-3.5-turbo
```

**Priority**: 3 (lower)

---

### Method 4: Python API

When using garak programmatically:

```python
from garak.generators.openai import OpenAIGenerator
from garak import _config

# Method 1: Via constructor (not recommended)
gen = OpenAIGenerator(name="gpt-3.5-turbo", config_root=_config)
gen.enable_rate_limiting = True
gen.tier = "tier5"
gen._init_rate_limiter()  # Re-initialize

# Method 2: Via config dict (recommended)
import os
os.environ["OPENAI_TIER"] = "tier5"
gen = OpenAIGenerator(name="gpt-3.5-turbo", config_root=_config)
# rate_limiter initialized automatically
```

**Priority**: 4 (lowest - use other methods)

---

## CONFIGURATION CASCADE (Priority Order)

Configuration values are resolved in this order (first match wins):

```
1. Command Line        (--generator_options tier=tier5)
2. Environment Var     (export OPENAI_TIER=tier5)
3. YAML Config         (config.yaml: tier: tier5)
4. Default             (tier: "free", enable_rate_limiting: true)
```

**Example**:
```bash
# Environment set to tier1
export OPENAI_TIER=tier1

# Config file says tier2
# (config.yaml: tier: tier2)

# CLI says tier5
--generator_options tier=tier5

# Result: tier5 (CLI wins)
```

---

## COMPLETE EXAMPLES

### Example 1: Production Scan with Rate Limiting

Use high-tier limits with safety margins:

```bash
export OPENAI_TIER=tier5
export OPENAI_API_KEY=sk-...

garak --generator openai.OpenAIGenerator \
      --target_name gpt-4o \
      --probes continuation.Simple \
      --output-dir results/
```

**Configuration Applied**:
- enable_rate_limiting: true (default)
- tier: tier5 (from environment)
- Rate limits: 30k RPM, 10M TPM (with 90% safety margins)

---

### Example 2: Development/Testing Without Rate Limiting

Quick testing without rate limit concerns:

```bash
export OPENAI_API_KEY=sk-...

garak --generator openai.OpenAIGenerator \
      --target_name gpt-3.5-turbo \
      --generator_options enable_rate_limiting=false \
      --probes test.Simple
```

**Configuration Applied**:
- enable_rate_limiting: false (CLI override)
- tier: free (default, unused)
- Rate limiting: DISABLED

---

### Example 3: YAML Config for CI/CD

Create reusable configuration:

```yaml
# config/production.yaml
generators:
  openai:
    enable_rate_limiting: true
    tier: tier5
    temperature: 0.5
    retry_json: true
```

Usage:
```bash
garak --config config/production.yaml \
      --generator openai.OpenAIGenerator \
      --target_name gpt-4o \
      --probes all
```

---

### Example 4: Multi-Model Scanning

Scan multiple models with appropriate tiers:

```bash
#!/bin/bash

# Fast model with tier5 (many requests)
export OPENAI_TIER=tier5
garak --generator openai.OpenAIGenerator \
      --target_name gpt-3.5-turbo \
      --probes continuation.Simple \
      --output-dir results/fast/

# Slow model with tier2 (fewer requests)
export OPENAI_TIER=tier2
garak --generator openai.OpenAIGenerator \
      --target_name gpt-4o \
      --probes continuation.Simple \
      --output-dir results/slow/
```

---

## TROUBLESHOOTING

### Problem: "Rate limiter initialized for X (tier: free, RPM: 3, TPM: 40000)"

**Diagnosis**: Rate limiting is working correctly with free tier

**Solution**: No action needed. If you want higher limits:

```bash
export OPENAI_TIER=tier5
# Or
--generator_options tier=tier5
```

---

### Problem: "Rate limiting disabled" in logs

**Diagnosis**: Rate limiter not initialized

**Possible Causes**:
1. rate_config.json not found
2. Model not supported
3. Generator type not recognized
4. enable_rate_limiting=false

**Solution**:
```bash
# Check file exists
ls garak/resources/rate_config.json

# Verify model supported
cat garak/resources/rate_config.json | grep gpt-3.5-turbo

# Enable rate limiting explicitly
--generator_options enable_rate_limiting=true
```

---

### Problem: "Tier 'custom_tier' not found, defaulting to 'free'"

**Diagnosis**: Invalid tier name specified

**Possible Causes**:
1. Typo in tier name (e.g., "tier_5" instead of "tier5")
2. Tier not available for model
3. Azure tier/deployment confusion

**Solution**:
```bash
# Valid tiers
export OPENAI_TIER=free      # or tier1, tier2, tier3, tier4, tier5

# Check valid tiers in config
cat garak/resources/rate_config.json
```

---

### Problem: Requests seem to be sleeping/delaying

**Diagnosis**: Rate limiting is sleeping to enforce RPM limit

**Possible Causes**:
1. Too many requests for tier (expected behavior)
2. RPM limit too low for workload
3. Token estimation too conservative

**Solution**:
```bash
# Increase tier
export OPENAI_TIER=tier5

# Or disable for quick tests
--generator_options enable_rate_limiting=false
```

---

### Problem: "BadRequestError" or rate limit errors still occurring

**Diagnosis**: TPM limit might be violated (bytes/tokens exceeded)

**Possible Causes**:
1. Token estimation off (pre-request)
2. Large responses exceed estimate
3. Actual tokens > estimated tokens

**Solution**:
```bash
# Check actual token usage in logs
# Look for: "Recorded usage for X: Y input + Z output"

# Use lower tier to be more conservative
export OPENAI_TIER=tier2
```

---

### Problem: Configuration not being applied

**Diagnosis**: Configuration cascade not working as expected

**Debug Steps**:
```bash
# 1. Check current environment
echo $OPENAI_TIER

# 2. Check config file syntax
cat config.yaml

# 3. Check CLI options
garak --help | grep -A 5 generator_options

# 4. Run with verbose logging
garak --generator openai.OpenAIGenerator \
      --target_name gpt-3.5-turbo \
      --generator_options tier=tier5,enable_rate_limiting=true \
      --seed 0 2>&1 | grep -i "rate\|tier"
```

---

## ADVANCED CONFIGURATION

### Custom Model Addition

To add support for new OpenAI models:

1. Add model to `garak/resources/rate_config.json`:
```json
{
  "OpenAIGenerator": {
    "models": {
      "new-model": {
        "cost_per_1k_input": 0.0001,
        "cost_per_1k_output": 0.0002,
        "rates": {
          "free": {"rpm": 3, "tpm": 10000},
          "tier1": {"rpm": 100, "tpm": 100000}
        }
      }
    }
  }
}
```

2. Reload configuration:
```python
gen = OpenAIGenerator(name="new-model", config_root=_config)
```

---

### Per-Process Rate Limiting (Multiprocessing)

When using `parallel_requests > 1`:

```bash
garak --generator openai.OpenAIGenerator \
      --target_name gpt-3.5-turbo \
      --probes continuation.Simple \
      --parallel_requests 4 \
      --generator_options tier=tier5
```

**Behavior**:
- Each worker process gets own rate limiter instance
- Per-process limits: 30k RPM ÷ 4 = 7.5k RPM per worker
- Total rate limit still respected (approximately)

---

## TECHNICAL DETAILS

### Configuration File Loading

Configuration is loaded in `_load_config()` which cascades:

1. Load garak defaults (Generator.DEFAULT_PARAMS)
2. Merge OpenAICompatible.DEFAULT_PARAMS
3. Merge model-specific DEFAULT_PARAMS (e.g., OpenAIReasoningGenerator)
4. Override with YAML config values
5. Override with environment variables (at runtime)
6. Override with CLI --generator_options

### Rate Config File Structure

```json
{
  "GeneratorClass": {
    "models": {
      "model_name": {
        "rates": {
          "tier_name": {
            "rpm": 3,
            "tpm": 40000,
            "rate_limit_rps": 0.045,
            "description": "Free tier (90% safety)"
          }
        }
      }
    }
  }
}
```

### Default Parameter Values

```python
DEFAULT_PARAMS = {
    "enable_rate_limiting": True,
    "tier": "free",
    # ... other params
}
```

---

## REFERENCE

### Supported Models

**OpenAI** (via openai.OpenAIGenerator):
- gpt-3.5-turbo
- gpt-4o
- gpt-4o-mini
- gpt-4-turbo
- o1-mini
- o1-preview

**Azure** (via openai.AzureOpenAIGenerator):
- gpt-4o
- gpt-4o-mini

### Rate Limit Tiers (Free Model)

| Tier | RPM | TPM | Description |
|------|-----|-----|-------------|
| free | 3 | 40k | Free tier (90% safety = 2.7 RPM, 36k TPM) |
| tier1 | 500 | 60k | Tier 1 (90% safety = 450 RPM, 54k TPM) |
| tier2 | 10k | 2M | Tier 2 (90% safety = 9k RPM, 1.8M TPM) |
| tier3 | 20k | 4M | Tier 3 (90% safety = 18k RPM, 3.6M TPM) |
| tier4 | 30k | 10M | Tier 4 (90% safety = 27k RPM, 9M TPM) |
| tier5 | 30k | 20M | Tier 5 (90% safety = 27k RPM, 18M TPM) |

*Note: RPM/TPM values shown are the applied limits (90% safety margins already calculated)*

### Environment Variables

| Variable | Type | Default | Purpose |
|----------|------|---------|---------|
| OPENAI_TIER | string | free | Rate limit tier |
| OPENAI_API_KEY | string | (required) | OpenAI API key |
| AZURE_OPENAI_API_KEY | string | (required) | Azure API key |

---

## SUPPORT

### Getting Help

1. Check logs for rate limiting messages:
   ```bash
   garak ... 2>&1 | grep -i "rate\|limiter\|tier"
   ```

2. Verify configuration:
   ```bash
   echo "OPENAI_TIER=$OPENAI_TIER"
   cat garak/resources/rate_config.json | python -m json.tool
   ```

3. Consult troubleshooting section above

4. Report issues with:
   - garak version
   - Python version
   - Model used
   - Configuration settings
   - Error logs

---

**Last Updated**: 2025-10-20
**Version**: 1.0
**Status**: Complete

