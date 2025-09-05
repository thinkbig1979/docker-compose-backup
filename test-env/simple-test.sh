#!/bin/bash

# Simple test for directory discovery
BACKUP_DIR="/home/edwin/development/backup script/test-env/docker-stacks"

echo "=== Testing Directory Discovery ==="
echo "Backup directory: $BACKUP_DIR"
echo "Contents:"
ls -la "$BACKUP_DIR"

echo ""
echo "=== Finding compose directories ==="
found_count=0

for dir in "$BACKUP_DIR"/*; do
    if [[ -d "$dir" ]]; then
        dir_name="$(basename "$dir")"
        echo "Checking: $dir_name"
        
        if [[ -f "$dir/docker-compose.yml" ]] || [[ -f "$dir/docker-compose.yaml" ]] || [[ -f "$dir/compose.yml" ]] || [[ -f "$dir/compose.yaml" ]]; then
            echo "  ✓ Found compose directory: $dir_name"
            ((found_count++))
        else
            echo "  ✗ No compose files in: $dir_name"
        fi
    fi
done

echo ""
echo "Total compose directories found: $found_count"

echo ""
echo "=== Testing existing dirlist ==="
dirlist_file="./dirlist"
if [[ -f "$dirlist_file" ]]; then
    echo "Existing dirlist contents:"
    cat "$dirlist_file"
else
    echo "No existing dirlist file found"
fi