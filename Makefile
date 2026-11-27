SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help format format-lint static-check build build-release test coverage tsan package check

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*##"; printf "Available targets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

format: ## Auto-format Swift sources and tests in place
	swift format format --in-place --recursive Sources Tests

format-lint: ## Strictly check Swift formatting
	swift format lint --strict --recursive Sources Tests

static-check: ## Check l10n parity, plists, and Swift 6 architecture guardrails
	bash scripts/check_static.sh

build: ## Debug build with warnings as errors
	swift build -Xswiftc -warnings-as-errors

build-release: ## Release build with warnings as errors
	swift build -c release -Xswiftc -warnings-as-errors

test: ## Run Swift Testing suite
	swift test

coverage: ## Run tests with code coverage and print MagicBorderKit report
	swift test --enable-code-coverage
	@BIN_DIR="$$(swift build --show-bin-path)"; \
	XCTEST_BUNDLE="$$(find "$$BIN_DIR" -maxdepth 1 -name '*.xctest' | head -n 1)"; \
	TEST_BIN="$$(find "$$XCTEST_BUNDLE/Contents/MacOS" -maxdepth 1 -type f | head -n 1)"; \
	PROF_DATA="$$BIN_DIR/codecov/default.profdata"; \
	xcrun llvm-cov report "$$TEST_BIN" -instr-profile="$$PROF_DATA" --ignore-filename-regex="\.build|Tests"

tsan: ## Run tests under Thread Sanitizer
	swift test --sanitize=thread

package: ## Build Universal .app and DMG bundle in dist/
	ARCH_MODE=universal CREATE_DMG=1 bash scripts/release_package.sh

check: static-check format-lint build test tsan ## Run full local CI verification suite
