# Bash Tests for Claude Ralph

This directory contains [bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System) tests for the ralph bash scripts.

## Prerequisites

### Installing bats-core

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install bats
```

**macOS (Homebrew):**
```bash
brew install bats-core
```

**From source (any platform):**
```bash
git clone https://github.com/bats-core/bats-core.git
cd bats-core
./install.sh /usr/local  # Or any directory in your PATH
```

**npm (Node.js):**
```bash
npm install -g bats
```

### Optional: Installing bats-support and bats-assert

These libraries provide enhanced assertion functions. Tests will work without them but have better diagnostics with them installed.

**Ubuntu/Debian:**
```bash
sudo apt-get install bats-support bats-assert
```

**macOS (Homebrew):**
```bash
brew tap kaos/shell
brew install bats-support bats-assert
```

**npm:**
```bash
npm install -g bats-support bats-assert
```

**From source (install as git submodules in this directory):**
```bash
cd scripts/ralph/tests/bash
git clone https://github.com/bats-core/bats-support.git
git clone https://github.com/bats-core/bats-assert.git
```

### Other Dependencies

The tests require:
- **jq** - JSON processor for parsing prd.json
- **git** - For version control operations (some tests may skip without it)

## Directory Structure

```
tests/bash/
├── README.md               # This file
├── test_helper.bash        # Shared test utilities, mocks, and fixtures
├── fixtures/               # Sample data files for testing
│   ├── prd-empty.json     # PRD with no user stories
│   ├── prd-partial.json   # PRD with some completed stories
│   ├── prd-complete.json  # PRD with all stories complete
│   ├── prd-with-claims.json # PRD with claimed stories
│   └── prd-invalid.json   # Invalid JSON for error testing
├── ralph-utils.bats        # Tests for ralph-utils.sh
├── ralph-status.bats       # Tests for ralph-status.sh
├── ralph-locks.bats        # Tests for ralph-locks.sh
├── ralph-cleanup.bats      # Tests for ralph-cleanup.sh
└── ralph-dashboard.bats    # Tests for ralph-dashboard.sh
```

## Running Tests

### Run All Tests

From the project root:
```bash
bats scripts/ralph/tests/bash/*.bats
```

Or from this directory:
```bash
bats *.bats
```

### Run a Single Test File

```bash
bats scripts/ralph/tests/bash/ralph-utils.bats
```

### Run Specific Tests by Name

```bash
bats --filter "get_prd_status" scripts/ralph/tests/bash/ralph-utils.bats
```

### Verbose Output

```bash
bats --verbose-run scripts/ralph/tests/bash/*.bats
```

### TAP Output (for CI)

```bash
bats --tap scripts/ralph/tests/bash/*.bats
```

### JUnit Output (for CI)

```bash
bats --formatter junit scripts/ralph/tests/bash/*.bats > test-results.xml
```

## Writing Tests

### Basic Test Structure

```bash
#!/usr/bin/env bats

# Load the test helper
load 'test_helper'

# Setup runs before each test
setup() {
    setup_test_environment
}

# Teardown runs after each test
teardown() {
    teardown_test_environment
}

@test "description of what is being tested" {
    # Arrange: set up test data
    create_prd_fixture "partial"

    # Act: run the code being tested
    source_ralph_utils
    run get_prd_status

    # Assert: verify the results
    assert_success
    assert_line "PRD_TOTAL=4"
}
```

### Using the Test Helper

The `test_helper.bash` provides several utilities:

#### Environment Setup/Teardown
- `setup_test_environment` - Creates temp directory structure
- `teardown_test_environment` - Cleans up temp directory
- `get_test_ralph_dir` - Returns path to test ralph directory

#### Fixture Creation
- `create_prd_fixture "type"` - Creates prd.json ("empty", "partial", "complete")
- `create_instance_fixture "id" "state" [heartbeat_age]` - Creates instance
- `create_lock_fixture "story_id" "owner" [lock_age]` - Creates lock

#### Mock Functions
- `mock_command "name" [return_val] [output]` - Mock any command
- `mock_git "subcommand" [output] [return_val]` - Mock git
- `get_mock_call_count "name"` - Check how many times mock was called
- `reset_mocks` - Clear all mocks

#### Assertions
- `assert_success` / `assert_failure` - Check exit code
- `assert_output "expected"` - Check exact output
- `assert_line "expected"` - Check output contains line
- `assert_file_exists "path"` - Check file exists
- `assert_dir_exists "path"` - Check directory exists
- `assert_file_contains "path" "content"` - Check file content
- `assert_json_value "path" ".jq.path" "expected"` - Check JSON value
- `assert_output_contains "substring"` - Check output substring
- `assert_output_not_contains "substring"` - Check output doesn't contain

#### Utility Functions
- `source_ralph_utils` - Source ralph-utils.sh in test context
- `skip_if_no_jq` - Skip test if jq not available
- `skip_if_no_git` - Skip test if git not available
- `capture_stderr` - Capture stderr from command

### Test Patterns

#### Testing Functions That Return Exit Codes
```bash
@test "function returns success on valid input" {
    source_ralph_utils
    create_prd_fixture "partial"

    run read_prd_json "$(get_test_ralph_dir)/prd.json"

    assert_success
}

@test "function returns failure on invalid input" {
    source_ralph_utils

    run read_prd_json "/nonexistent/file.json"

    assert_failure
}
```

#### Testing Functions That Output Data
```bash
@test "get_prd_status outputs correct values" {
    source_ralph_utils
    create_prd_fixture "partial"

    output=$(get_prd_status)

    [[ "$output" == *"PRD_TOTAL=4"* ]]
    [[ "$output" == *"PRD_COMPLETE=2"* ]]
}
```

#### Testing File Operations
```bash
@test "lock_ralph_story creates lock directory" {
    source_ralph_utils

    lock_ralph_story "US-001"

    assert_dir_exists "$(get_test_ralph_dir)/locks/US-001.lock"
    assert_file_exists "$(get_test_ralph_dir)/locks/US-001.lock/owner.txt"
}
```

#### Testing with Mocks
```bash
@test "handles git failure gracefully" {
    mock_git "status" "" 1  # Mock git status to fail

    run some_function_that_uses_git

    # Verify behavior when git fails
    assert_failure
    assert_output_contains "git error"
}
```

## Troubleshooting

### "bats: command not found"
Install bats using one of the methods above.

### "jq: command not found"
Install jq: `apt install jq` or `brew install jq`

### Tests fail with "permission denied"
Ensure test files are readable:
```bash
chmod +r scripts/ralph/tests/bash/*.bats
chmod +r scripts/ralph/tests/bash/test_helper.bash
```

### Tests are slow
If tests are slow, consider:
- Running specific test files instead of all tests
- Using `--jobs` flag for parallel execution: `bats --jobs 4 *.bats`

### "assert_success: command not found"
bats-assert is not installed. Either install it or the test_helper provides fallbacks.

## CI Integration

Example GitHub Actions workflow:

```yaml
name: Bash Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y bats jq

      - name: Run bats tests
        run: bats scripts/ralph/tests/bash/*.bats
```

Example GitLab CI:

```yaml
bash-tests:
  image: ubuntu:latest
  before_script:
    - apt-get update && apt-get install -y bats jq
  script:
    - bats scripts/ralph/tests/bash/*.bats
```
