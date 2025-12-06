#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

echo "Installing git hooks..."

# Create pre-commit hook
cat > "$HOOKS_DIR/pre-commit" << 'HOOK'
#!/bin/bash
set -e

# Check if swiftformat is installed
if ! command -v swiftformat &> /dev/null; then
    echo "error: SwiftFormat not installed. Install with: brew install swiftformat"
    exit 1
fi

# Get staged Swift files
STAGED_SWIFT_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.swift$' || true)

if [ -z "$STAGED_SWIFT_FILES" ]; then
    exit 0
fi

echo "Running SwiftFormat on staged files..."

# Format each staged file
for file in $STAGED_SWIFT_FILES; do
    if [ -f "$file" ]; then
        swiftformat "$file"
        git add "$file"
    fi
done

echo "SwiftFormat completed."
HOOK

chmod +x "$HOOKS_DIR/pre-commit"

echo "Git hooks installed successfully!"
echo "  - pre-commit: runs SwiftFormat on staged .swift files"
