#!/bin/bash

# Script to remove version lines from Docker Compose files in top-level subdirectories
# Usage: ./remove-version-lines.sh [directory]
#   directory: Optional path to directory to scan (default: current directory)

set -e  # Exit on any error

# Function to show usage information
show_usage() {
    echo "Usage: $0 [directory]"
    echo ""
    echo "Remove version lines from Docker Compose files in top-level subdirectories"
    echo ""
    echo "Arguments:"
    echo "  directory    Path to directory to scan (default: current directory)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Scan current directory"
    echo "  $0 /path/to/docker/stacks    # Scan specific directory"
    echo "  $0 ~/projects                # Scan home projects directory"
    echo ""
    echo "The script will:"
    echo "  - Look for docker-compose.yml, compose.yml, docker-compose.yaml, compose.yaml"
    echo "  - Remove any lines starting with 'version:' (with optional whitespace)"
    echo "  - Create backups with .tmp extension during processing"
    echo "  - Provide detailed output of all operations"
}

# Parse command line arguments
TARGET_DIR="."
if [[ $# -eq 1 ]]; then
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        show_usage
        exit 0
    fi
    TARGET_DIR="$1"
elif [[ $# -gt 1 ]]; then
    echo "Error: Too many arguments provided"
    echo ""
    show_usage
    exit 1
fi

# Validate target directory
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: Directory '$TARGET_DIR' does not exist"
    exit 1
fi

# Convert to absolute path for cleaner output
TARGET_DIR=$(cd "$TARGET_DIR" && pwd)

# Function to process a single compose file
process_compose_file() {
    local file="$1"
    local temp_file="${file}.tmp"
    
    echo "Processing: $file"
    
    # Check if file contains version lines
    if grep -q "^[[:space:]]*version:" "$file"; then
        # Remove lines that start with "version:" (with optional leading whitespace)
        sed '/^[[:space:]]*version:/d' "$file" > "$temp_file"
        
        # Replace original file with modified version
        mv "$temp_file" "$file"
        echo "  ✓ Removed version line from $file"
    else
        echo "  - No version line found in $file"
    fi
}

# Function to find and process compose files in a directory
process_directory() {
    local dir="$1"
    local found_files=false
    
    echo "Checking directory: $dir"
    
    # Look for docker-compose.yml files
    if [[ -f "$dir/docker-compose.yml" ]]; then
        process_compose_file "$dir/docker-compose.yml"
        found_files=true
    fi
    
    # Look for compose.yml files
    if [[ -f "$dir/compose.yml" ]]; then
        process_compose_file "$dir/compose.yml"
        found_files=true
    fi
    
    # Look for docker-compose.yaml files (alternative extension)
    if [[ -f "$dir/docker-compose.yaml" ]]; then
        process_compose_file "$dir/docker-compose.yaml"
        found_files=true
    fi
    
    # Look for compose.yaml files (alternative extension)
    if [[ -f "$dir/compose.yaml" ]]; then
        process_compose_file "$dir/compose.yaml"
        found_files=true
    fi
    
    if [[ "$found_files" == false ]]; then
        echo "  - No Docker Compose files found in $dir"
    fi
}

# Main script execution
echo "Starting Docker Compose version line removal..."
echo "Target directory: $TARGET_DIR"
echo "----------------------------------------"

# Change to target directory
cd "$TARGET_DIR"

# Counter for processed directories
processed_dirs=0

# Iterate through all top-level subdirectories
for dir in */; do
    # Remove trailing slash
    dir="${dir%/}"
    
    # Skip if not a directory
    if [[ ! -d "$dir" ]]; then
        continue
    fi
    
    # Process the directory
    process_directory "$dir"
    processed_dirs=$((processed_dirs + 1))
    echo ""
done

echo "----------------------------------------"
echo "Completed! Processed $processed_dirs directories in $TARGET_DIR"

# Verify the changes by showing a summary
echo ""
echo "Summary of remaining version lines (should be empty):"
compose_files=$(find . -maxdepth 2 -name "docker-compose.yml" -o -name "compose.yml" -o -name "docker-compose.yaml" -o -name "compose.yaml" 2>/dev/null)
if [[ -n "$compose_files" ]]; then
    remaining_versions=$(echo "$compose_files" | xargs grep -l "^[[:space:]]*version:" 2>/dev/null || true)
    if [[ -n "$remaining_versions" ]]; then
        echo "⚠ Warning: Version lines still found in:"
        echo "$remaining_versions"
    else
        echo "✓ No version lines found in any Docker Compose files"
    fi
else
    echo "ℹ No Docker Compose files found to verify"
fi