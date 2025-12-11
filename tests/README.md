# Test Suite

This directory contains the test infrastructure for OS Optimization Scripts.

## Directory Structure

```
tests/
├── unit/              # Unit tests for individual functions
├── integration/       # Integration tests for full workflows
├── mocks/            # Mock system commands for testing
├── fixtures/         # Test data and expected outputs
├── performance/       # Performance benchmarks
├── ci/               # CI/CD setup scripts
├── environments/      # Test VM/container configurations
└── run_tests.sh      # Master test runner
```

## Running Tests

### Run All Tests

```bash
./tests/run_tests.sh
```

### Run Specific Test Categories

```bash
# Unit tests only
TEST_CATEGORY=unit ./tests/run_tests.sh

# Integration tests only
TEST_CATEGORY=integration ./tests/run_tests.sh
```

### Run with Shellcheck

```bash
# Shellcheck is automatically run if available
./tests/run_tests.sh
```

## Test Requirements

- **Bash**: 4.0+
- **Shellcheck**: For linting (optional but recommended)
- **BATS**: Bash Automated Testing System (optional, for structured tests)

### Installing Dependencies

**macOS:**
```bash
brew install shellcheck
brew install bats-core
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get install shellcheck
sudo apt-get install bats
```

**Linux (Fedora):**
```bash
sudo dnf install ShellCheck
sudo dnf install bats
```

## Writing Tests

### Unit Tests

Create unit tests in `tests/unit/`:

```bash
#!/usr/bin/env bash
# tests/unit/test_common.sh

source ../../lib/common.sh

test_color_echo() {
    # Test color output
    local output=$(color_echo red "test")
    # Assertions...
}
```

### Integration Tests

Create integration tests in `tests/integration/`:

```bash
#!/usr/bin/env bash
# tests/integration/test_optimize_all.sh

test_full_workflow() {
    # Test complete optimization workflow
    ./mac/optimize-all.sh --dry-run
    # Assertions...
}
```

## Test Coverage

Current test coverage:
- Shellcheck linting: ✅
- Unit tests: 🚧 In progress
- Integration tests: 🚧 In progress
- Performance benchmarks: 🚧 In progress

## CI/CD

Tests are designed to run in CI/CD environments:
- GitHub Actions (see `.github/workflows/test.yml`)
- Local development
- Test VMs/containers

## Contributing

When adding new features:
1. Write tests first (TDD approach)
2. Ensure all tests pass
3. Run shellcheck on new scripts
4. Update test documentation
