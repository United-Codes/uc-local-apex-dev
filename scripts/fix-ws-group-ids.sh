#!/bin/bash

# Script to remove group_ids values from APEX workspace export files
# This fixes the issue where group IDs from one instance don't match another

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
IMPORT_DIR="$PROJECT_DIR/backups/import/apex"

echo "Fixing p_group_ids in workspace SQL files..."
echo "Target directory: $IMPORT_DIR"
echo ""

# Check if import directory exists
if [ ! -d "$IMPORT_DIR" ]; then
    echo "Error: Import directory not found: $IMPORT_DIR"
    exit 1
fi

# Find all w*.sql files in schema subdirectories
file_count=0
changed_count=0

while IFS= read -r -d '' file; do
    file_count=$((file_count + 1))
    echo "Processing: ${file#$IMPORT_DIR/}"
    
    # Use awk to replace the pattern
    # Match p_group_ids followed by optional spaces, =>, and any combination of numbers and colons
    awk '{
        gsub(/p_group_ids[[:space:]]*=>[[:space:]]*'"'"'[0-9:]+'"'"'/, "p_group_ids => '"'"''"'"'")
        print
    }' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    
    changed_count=$((changed_count + 1))
done < <(find "$IMPORT_DIR" -type f -name "w[0-9]*.sql" -print0)

echo ""
echo "Summary:"
echo "  Files processed: $file_count"
echo "  Files modified: $changed_count"
echo ""
echo "Done!"
