VESC_TOOL ?= vesc_tool
PYTHON ?= python3
BASH ?= bash

GENERATED_DIR := generated
BINARY_STAMP := $(GENERATED_DIR)/binary_luts.stamp
LUT_BINARY := $(GENERATED_DIR)/display_lut.bin
DIST_FILES := README.dist.md ui.dist.qml

# Source files that should trigger a rebuild
SOURCE_FILES := blacktip_dpv.lisp ui.qml pkgdesc.qml README.md
ASSET_FILES := assets/display_lut.csv
BINARY_GENERATOR := tools/generate_lut_binary.py
VERSION_GENERATOR := tools/update_version.sh

# Track the current git branch to detect branch changes
CURRENT_BRANCH := $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
BRANCH_FILE := .git_branch_cache

all: blacktip_dpv.vescpkg

$(BINARY_STAMP): $(ASSET_FILES) $(BINARY_GENERATOR)
	@mkdir -p $(GENERATED_DIR)
	$(PYTHON) $(BINARY_GENERATOR)
	@touch $@

$(LUT_BINARY): $(BINARY_STAMP)

# Update branch cache if it doesn't exist or branch has changed
$(BRANCH_FILE): FORCE
	@OLD_BRANCH=$$(cat $@ 2>/dev/null || echo ""); \
	if [ "$$OLD_BRANCH" != "$(CURRENT_BRANCH)" ]; then \
		echo "$(CURRENT_BRANCH)" > $@; \
	fi

# Generate distribution README when source files or branch changes
dist_files: $(SOURCE_FILES) $(VERSION_GENERATOR) $(BRANCH_FILE)
	@$(BASH) $(VERSION_GENERATOR)

blacktip_dpv.vescpkg: dist_files $(LUT_BINARY)
	$(VESC_TOOL) --buildPkgFromDesc pkgdesc.qml --testPkgDesc 'vesc:test'

check-whitespace:
	@echo "Checking for trailing whitespace..."
	@if grep -nE '[[:space:]]+$$' blacktip_dpv.lisp; then \
		echo "Error: Trailing whitespace found (shown above)"; \
		exit 1; \
	else \
		echo "✓ No trailing whitespace found"; \
	fi

smoke-tests:
	@echo "Running smoke tests..."
	@$(PYTHON) tests/run_tests.py

binary: $(LUT_BINARY)

test: check-whitespace smoke-tests
	@echo "All checks passed"

clean:
	rm -f blacktip_dpv.vescpkg $(DIST_FILES) $(BRANCH_FILE)
	rm -rf $(GENERATED_DIR)

.PHONY: all test clean check-whitespace smoke-tests binary dist_files FORCE

FORCE:
