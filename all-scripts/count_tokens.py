#!/usr/bin/env python3
"""
Token Counter for Claude Code Context Window

Calculates how many tokens a file will consume in Claude Code's context window
using the Anthropic tokenizer API.

Usage:
    python scripts/count_tokens.py <file_path>
    python scripts/count_tokens.py src/integration_mapper/mapper.py
"""

import sys
import json
from pathlib import Path
from typing import Dict, Any


def count_tokens_simple(text: str) -> int:
    """
    Simple token estimation using character count.

    Anthropic's models use ~3.5 characters per token on average.
    This is a rough approximation when the API is unavailable.

    Args:
        text: Text content to count tokens for

    Returns:
        Estimated token count
    """
    return len(text) // 3


def count_tokens_accurate(text: str) -> int:
    """
    Accurate token counting using Anthropic's tokenizer.

    NOTE: This requires the 'anthropic' package to be installed:
          pip install anthropic

    Args:
        text: Text content to count tokens for

    Returns:
        Exact token count from Anthropic tokenizer
    """
    try:
        import anthropic

        # Create client (API key not needed for counting)
        client = anthropic.Anthropic(api_key="dummy-key-not-needed-for-counting")

        # Count tokens using the client's count_tokens method
        token_count = client.count_tokens(text)

        return token_count
    except ImportError:
        print("⚠️  Warning: 'anthropic' package not installed. Using simple estimation.", file=sys.stderr)
        print("   Install with: pip install anthropic", file=sys.stderr)
        print("", file=sys.stderr)
        return count_tokens_simple(text)
    except Exception as e:
        print(f"⚠️  Warning: Error using Anthropic tokenizer: {e}", file=sys.stderr)
        print("   Falling back to simple estimation.", file=sys.stderr)
        print("", file=sys.stderr)
        return count_tokens_simple(text)


def analyze_file(file_path: Path) -> Dict[str, Any]:
    """
    Analyze a file's token usage in Claude Code context.

    Args:
        file_path: Path to file to analyze

    Returns:
        Dictionary with analysis results
    """
    if not file_path.exists():
        raise FileNotFoundError(f"File not found: {file_path}")

    # Read file content
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except UnicodeDecodeError:
        # Try binary files
        with open(file_path, 'rb') as f:
            content = f.read().decode('utf-8', errors='replace')

    # Count tokens
    token_count = count_tokens_accurate(content)

    # Calculate statistics
    char_count = len(content)
    line_count = content.count('\n') + 1
    file_size_kb = file_path.stat().st_size / 1024

    # Claude Code context window limits
    CLAUDE_CODE_CONTEXT_WINDOW = 200_000  # tokens
    BUDGET_WARNING_THRESHOLD = 0.1  # 10%
    BUDGET_DANGER_THRESHOLD = 0.25  # 25%

    # Calculate percentage of context window
    context_percentage = (token_count / CLAUDE_CODE_CONTEXT_WINDOW) * 100

    # Determine status
    if context_percentage < BUDGET_WARNING_THRESHOLD * 100:
        status = "✅ SAFE"
        status_color = "green"
    elif context_percentage < BUDGET_DANGER_THRESHOLD * 100:
        status = "⚠️  WARNING"
        status_color = "yellow"
    else:
        status = "🔴 DANGER"
        status_color = "red"

    return {
        'file_path': str(file_path),
        'file_size_kb': round(file_size_kb, 2),
        'char_count': char_count,
        'line_count': line_count,
        'token_count': token_count,
        'chars_per_token': round(char_count / token_count, 2) if token_count > 0 else 0,
        'context_window_total': CLAUDE_CODE_CONTEXT_WINDOW,
        'context_percentage': round(context_percentage, 2),
        'tokens_remaining': CLAUDE_CODE_CONTEXT_WINDOW - token_count,
        'status': status,
        'status_color': status_color
    }


def print_analysis(analysis: Dict[str, Any]) -> None:
    """
    Print analysis results in a formatted way.

    Args:
        analysis: Analysis results dictionary
    """
    print("=" * 80)
    print("📊 CLAUDE CODE CONTEXT TOKEN ANALYSIS")
    print("=" * 80)
    print()

    print(f"📁 File: {analysis['file_path']}")
    print(f"   Size: {analysis['file_size_kb']} KB")
    print(f"   Lines: {analysis['line_count']:,}")
    print(f"   Characters: {analysis['char_count']:,}")
    print()

    print(f"🎯 Token Count: {analysis['token_count']:,} tokens")
    print(f"   Characters per token: {analysis['chars_per_token']}")
    print()

    print(f"💾 Context Window Usage:")
    print(f"   Total available: {analysis['context_window_total']:,} tokens")
    print(f"   This file uses: {analysis['token_count']:,} tokens ({analysis['context_percentage']}%)")
    print(f"   Remaining: {analysis['tokens_remaining']:,} tokens")
    print()

    print(f"📈 Status: {analysis['status']}")

    # Add recommendations
    if analysis['context_percentage'] >= 25:
        print()
        print("⚠️  RECOMMENDATION:")
        print("   This file consumes >25% of Claude Code's context window.")
        print("   Consider:")
        print("   - Breaking it into smaller modules")
        print("   - Using summarization for large files")
        print("   - Processing in chunks")
    elif analysis['context_percentage'] >= 10:
        print()
        print("💡 NOTE:")
        print("   This file consumes >10% of context window.")
        print("   It's usable but may limit available context for other files.")

    print()
    print("=" * 80)


def main():
    """CLI entry point."""
    if len(sys.argv) != 2:
        print("Usage: python scripts/count_tokens.py <file_path>")
        print()
        print("Examples:")
        print("  python scripts/count_tokens.py src/integration_mapper/mapper.py")
        print("  python scripts/count_tokens.py docs/WIKI.md")
        print("  python scripts/count_tokens.py README.md")
        sys.exit(1)

    file_path = Path(sys.argv[1])

    try:
        analysis = analyze_file(file_path)
        print_analysis(analysis)

        # Also output JSON for programmatic use
        json_output = file_path.with_suffix('.tokens.json')
        if '--json' in sys.argv:
            with open(json_output, 'w') as f:
                json.dump(analysis, f, indent=2)
            print(f"📄 JSON output saved to: {json_output}")

        # Exit code based on status
        if "DANGER" in analysis['status']:
            sys.exit(2)
        elif "WARNING" in analysis['status']:
            sys.exit(1)
        else:
            sys.exit(0)

    except FileNotFoundError as e:
        print(f"❌ Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"❌ Unexpected error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
