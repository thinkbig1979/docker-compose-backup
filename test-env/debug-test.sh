#!/bin/bash

# Debug test to isolate the hanging issue

set -euo pipefail

echo "=== Debug Test ==="

# Test the dirlist loading function directly
echo "Testing dirlist loading..."

# Create a simple dirlist
cat > test-env/test-dirlist << 'EOF'
app1=true
app2=false
app3=false
EOF

echo "Created test dirlist:"
cat test-env/test-dirlist

# Test loading with a simple script
cat > test-env/test-load.sh << 'EOF'
#!/bin/bash
set -euo pipefail

declare -A test_array

echo "Starting load test..."

while IFS='=' read -r dir_name enabled; do
    echo "Processing line: $dir_name=$enabled"
    if [[ "$dir_name" =~ ^#.*$ ]] || [[ -z "$dir_name" ]]; then
        echo "Skipping comment/empty line"
        continue
    fi
    
    if [[ "$enabled" =~ ^(true|false)$ ]]; then
        test_array["$dir_name"]="$enabled"
        echo "Loaded: $dir_name=$enabled"
    else
        echo "Invalid format: $dir_name=$enabled"
    fi
done < test-env/test-dirlist

echo "Load completed. Array size: ${#test_array[@]}"

for key in "${!test_array[@]}"; do
    echo "Array entry: $key=${test_array[$key]}"
done

echo "Test completed successfully"
EOF

chmod +x test-env/test-load.sh
echo "Running load test..."
./test-env/test-load.sh

echo "=== Debug Test Completed ==="