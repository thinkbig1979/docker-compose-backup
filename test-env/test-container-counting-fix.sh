#!/bin/bash

# Test the specific container counting fix in docker-backup.sh
echo "Testing Container Counting Fix in docker-backup.sh"
echo "=================================================="

# Source the actual docker-backup.sh to get the is_stack_running function
# But first, let's extract just the function we need to test

cat > test_is_stack_running.sh << 'INNER_EOF'
#!/bin/bash

# Mock docker command for testing
docker() {
    case "$*" in
        "compose ps --services --filter status=running")
            echo "$MOCK_PS_OUTPUT"
            ;;
        *)
            echo "Mock docker: $*" >&2
            ;;
    esac
}

# Extract the is_stack_running function logic from docker-backup.sh
is_stack_running() {
    local dir_name="$1"
    local ps_output
    local running_containers
    
    # This is the actual logic from docker-backup.sh with our fix
    ps_output="$(docker compose ps --services --filter "status=running" 2>/dev/null)"
    running_containers=$(echo "$ps_output" | awk 'NF' | wc -l)
    
    echo "DEBUG: ps_output='$ps_output'" >&2
    echo "DEBUG: running_containers=$running_containers" >&2
    
    if [[ "$running_containers" -gt 0 ]]; then
        echo "Stack $dir_name is running ($running_containers containers)" >&2
        return 0  # Stack is running
    else
        echo "Stack $dir_name is not running (0 containers)" >&2
        return 1  # Stack is not running
    fi
}

# Test the function
is_stack_running "test-app"
INNER_EOF

chmod +x test_is_stack_running.sh

# Test scenarios
test_scenario() {
    local name="$1"
    local mock_output="$2"
    local expected_result="$3"
    
    echo ""
    echo "Testing: $name"
    echo "Mock output: '$mock_output'"
    echo "Expected: $expected_result (0=running, 1=not running)"
    
    export MOCK_PS_OUTPUT="$mock_output"
    local output
    local result
    output=$(./test_is_stack_running.sh 2>&1)
    result=$?
    
    echo "Output:"
    echo "$output" | sed 's/^/  /'
    echo "Result: $result"
    
    if [[ "$result" == "$expected_result" ]]; then
        echo "✅ PASS"
    else
        echo "❌ FAIL"
    fi
}

# Run the tests
test_scenario "Empty output (no containers)" "" 1
test_scenario "Single container" "web" 0
test_scenario "Multiple containers" $'web\ndb\nredis' 0
test_scenario "Whitespace only" $'   \n  \n' 1
test_scenario "Mixed empty/non-empty" $'web\n\ndb\n\n' 0

echo ""
echo "Container counting fix verification complete!"

# Cleanup
rm -f test_is_stack_running.sh
