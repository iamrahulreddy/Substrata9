# Substrata9 Makefile

PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
LIBDIR = $(PREFIX)/lib/substrata9
DOCDIR = $(PREFIX)/share/doc/substrata9

SCRIPTS = $(wildcard bin/s9-*)

# Version is sourced from lib/s9-common.sh as single source of truth
VERSION = $(shell grep 'S9_VERSION=' lib/s9-common.sh | cut -d'"' -f2)

.PHONY: all install uninstall clean clean-snapshots test lint help check-deps

all: help

help:
	@echo ""
	@echo "Substrata9 v$(VERSION)"
	@echo ""
	@echo "Targets:"
	@echo "  install      Install to $(PREFIX)"
	@echo "  uninstall    Remove installation"
	@echo "  test         Run full test suite"
	@echo "  lint         Run shellcheck on all scripts"
	@echo "  check-deps   Check for required dependencies"
	@echo "  clean        Clean build artifacts"
	@echo "  clean-snapshots  Remove all saved snapshots (with confirmation)"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX       Installation prefix (default: /usr/local)"
	@echo ""
	@echo "Examples:"
	@echo "  make install"
	@echo "  make install PREFIX=/opt/substrata9"
	@echo "  sudo make install"
	@echo ""

check-deps:
	@echo "Checking dependencies..."
	@command -v bash >/dev/null 2>&1 || { echo "❌ bash not found"; exit 1; }
	@echo "✓ bash found: $$(bash --version | head -1)"
	@command -v awk >/dev/null 2>&1 || { echo "❌ awk not found"; exit 1; }
	@echo "✓ awk found"
	@command -v grep >/dev/null 2>&1 || { echo "❌ grep not found"; exit 1; }
	@echo "✓ grep found"
	@command -v sed >/dev/null 2>&1 || { echo "❌ sed not found"; exit 1; }
	@echo "✓ sed found"
	@bc_path="$$(command -v bc 2>/dev/null || true)"; \
	if [ -z "$$bc_path" ] || [ ! -x "$$bc_path" ]; then \
		if [ -f "$(CURDIR)/bin/bc" ]; then \
			echo "⚠ bc not found; using local fallback via bash: $(CURDIR)/bin/bc"; \
		else \
			echo "❌ bc not found - install with: sudo apt install bc"; exit 1; \
		fi; \
	fi
	@echo "✓ bc available"
	@echo ""
	@echo "All dependencies satisfied!"

install: check-deps
	@echo ""
	@echo "Installing Substrata9 v$(VERSION) to $(PREFIX)..."
	@echo ""
	@# Create directories
	@mkdir -p "$(BINDIR)" "$(LIBDIR)" "$(DOCDIR)"
	@# Install binaries
	@for script in $(SCRIPTS); do \
		echo "  Installing $$script → $(BINDIR)/"; \
		install -m 755 "$$script" "$(BINDIR)/"; \
	done
	@# Install library
	@echo "  Installing lib/s9-common.sh → $(LIBDIR)/"
	@install -m 644 lib/s9-common.sh "$(LIBDIR)/"
	@# Install documentation
	@echo "  Installing documentation → $(DOCDIR)/"
	@install -m 644 README.md "$(DOCDIR)/"
	@install -m 644 docs/*.md "$(DOCDIR)/" 2>/dev/null || true
	@echo ""
	@echo "✓ Installation complete!"
	@echo ""
	@echo "Installed tools:"
	@ls -1 "$(BINDIR)"/s9-* 2>/dev/null | xargs -n1 basename | sed 's/^/  /'
	@echo ""
	@echo "Run 's9-inspect --help' to get started."
	@echo ""

uninstall:
	@echo "Removing Substrata9 from $(PREFIX)..."
	@for script in $(SCRIPTS); do \
		rm -f "$(BINDIR)/$$(basename $$script)"; \
	done
	@rm -rf "$(LIBDIR)"
	@rm -rf "$(DOCDIR)"
	@echo "✓ Uninstall complete."

test:
	@bash tests/run_tests.sh

lint:
	@echo "Running shellcheck..."
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not found. Install with: sudo apt install shellcheck"; exit 1; }
	@echo ""
	@echo "Checking bin/..."
	@shellcheck -x bin/s9-*
	@echo ""
	@echo "Checking lib/..."
	@shellcheck -x lib/s9-common.sh
	@echo ""
	@echo "Checking examples/..."
	@shellcheck -x examples/*.sh
	@echo ""
	@echo "✓ Lint passed - no errors found."

clean:
	@rm -rf *.log *.tmp
	@echo "✓ Cleaned build artifacts."

clean-snapshots:
	@echo "This will delete ALL snapshots in ~/.substrata9/snapshots/"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || { echo "Cancelled."; exit 1; }
	@rm -rf ~/.substrata9/snapshots/*.snap 2>/dev/null || true
	@echo "✓ Snapshots cleaned."
