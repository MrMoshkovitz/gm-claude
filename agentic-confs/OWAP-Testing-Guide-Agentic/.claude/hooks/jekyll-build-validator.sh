#!/bin/bash
# Jekyll Build Validator - PostToolUse Hook
# Validates Jekyll build and links after content changes

# Only run validation for content-modifying tools
if [[ "$CLAUDE_TOOL" == "Edit" || "$CLAUDE_TOOL" == "Write" || "$CLAUDE_TOOL" == "MultiEdit" ]]; then
    echo "🔧 Jekyll Build Validation Running..."

    # Check if bundle command is available
    if command -v bundle >/dev/null 2>&1; then
        # Validate Jekyll build (dry run)
        echo "   Testing Jekyll build..."
        if ! bundle exec jekyll build --dry-run >/dev/null 2>&1; then
            echo "⚠️ ALERT: Jekyll build validation failed after changes"
            echo ""
            echo "🔍 Common issues to check:"
            echo "   • YAML front matter syntax errors"
            echo "   • Markdown syntax issues"
            echo "   • Missing or incorrect file references"
            echo "   • Invalid Jekyll configuration"
            echo ""
            echo "🔧 Debug command: bundle exec jekyll build --verbose"
            exit 1
        fi
        echo "   ✅ Jekyll build validation passed"
    else
        echo "   ⚠️ Bundle not available - skipping Jekyll build validation"
    fi

    # Quick internal link validation for recently modified files
    echo "   Checking internal links..."

    # Find markdown files with internal links
    recent_files=$(find Document/content -name "*.md" -mtime -1 2>/dev/null | head -10)

    if [[ -n "$recent_files" ]]; then
        echo "$recent_files" | while read file; do
            if [[ -f "$file" ]]; then
                # Check for internal markdown links
                grep -o "](\.\.\/[^)]*)" "$file" 2>/dev/null | while read link; do
                    target=$(echo "$link" | sed 's/](\.\.\///' | sed 's/)$//')

                    # Check multiple possible locations
                    if [[ ! -f "Document/content/$target" && ! -f "Document/$target" && ! -f "$target" ]]; then
                        echo "   ⚠️ WARNING: Potential broken internal link"
                        echo "      File: $file"
                        echo "      Target: $target"
                        echo "      💡 Verify the target file exists and path is correct"
                    fi
                done

                # Check for image references
                grep -o "!\[.*\](\.\.\/[^)]*)" "$file" 2>/dev/null | while read imgref; do
                    imgpath=$(echo "$imgref" | grep -o "(\.\.\/[^)]*)" | sed 's/^(//' | sed 's/)$//')

                    # Construct full path relative to the file
                    filedir=$(dirname "$file")
                    fullimgpath="$filedir/$imgpath"

                    if [[ ! -f "$fullimgpath" ]]; then
                        echo "   ⚠️ WARNING: Missing image reference"
                        echo "      File: $file"
                        echo "      Image: $imgpath"
                        echo "      Expected: $fullimgpath"
                    fi
                done
            fi
        done
    fi

    # Check for AITG test ID consistency
    echo "   Validating AITG test references..."

    # Find references to AITG test IDs
    grep -r "AITG-[A-Z][A-Z][A-Z]-[0-9][0-9]" Document/content/ 2>/dev/null | while read -r line; do
        file=$(echo "$line" | cut -d: -f1)
        testid=$(echo "$line" | grep -o "AITG-[A-Z][A-Z][A-Z]-[0-9][0-9]")

        # Check if corresponding test file exists
        if ! ls Document/content/tests/${testid}_*.md >/dev/null 2>&1; then
            echo "   ⚠️ WARNING: Referenced test not found"
            echo "      File: $file"
            echo "      Referenced: $testid"
            echo "      💡 Ensure test file exists in Document/content/tests/"
        fi
    done

    echo "   ✅ Link validation complete"

    # Check for large files that might affect build performance
    echo "   Checking for large files..."
    find Document/ -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.pdf" \) -size +5M 2>/dev/null | while read largefile; do
        filesize=$(du -h "$largefile" | cut -f1)
        echo "   ℹ️ Large file detected: $largefile ($filesize)"
        echo "      💡 Consider optimizing large images for web display"
    done

    echo "✅ Jekyll build and link validation complete"

else
    echo "🔧 Skipping build validation for read-only operation ($CLAUDE_TOOL)"
fi