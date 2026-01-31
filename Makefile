.PHONY: test test-app lint lint-app build build-app install-app uninstall-app clean setup help

VERSION := $(shell cat VERSION)
APP_BUNDLE := .build/PRs and Issues Preview.app

# Default target
help:
	@echo "PRs and Issues Preview - v$(VERSION)"
	@echo ""
	@echo "Usage:"
	@echo "  make test          Run all tests and linting"
	@echo "  make test-app      Run Swift app tests"
	@echo "  make lint          Run all linters"
	@echo "  make build-app     Build the macOS app bundle"
	@echo "  make install-app   Install app to /Applications"
	@echo "  make uninstall-app Remove app from /Applications"
	@echo "  make clean         Remove build artifacts"
	@echo "  make setup         Create config directories"

# Master test target (required by CLAUDE.md guidelines)
test: lint test-app
	@echo "All tests passed!"

# Linting
lint: lint-app

lint-app:
	@echo "==> Running SwiftLint..."
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --quiet; \
	else \
		echo "swiftlint not found, skipping Swift lint (install with: brew install swiftlint)"; \
	fi

# Testing
test-app:
	@echo "==> Running Swift tests..."
	@swift test --quiet 2>/dev/null || swift test

# Building
build: build-app

build-app:
	@echo "==> Building macOS app..."
	@swift build -c release
	@echo "==> Creating app bundle..."
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp .build/release/PRsAndIssuesPreview "$(APP_BUNDLE)/Contents/MacOS/"
	@cp Resources/Info.plist "$(APP_BUNDLE)/Contents/"
	@echo -n "APPL????" > "$(APP_BUNDLE)/Contents/PkgInfo"
	@echo "App bundle created at: $(APP_BUNDLE)"

install-app: build-app
	@echo "==> Installing to /Applications..."
	@rm -rf "/Applications/PRs and Issues Preview.app"
	@cp -r "$(APP_BUNDLE)" /Applications/
	@echo "Installed! Run with: open '/Applications/PRs and Issues Preview.app'"

uninstall-app:
	@echo "==> Removing from /Applications..."
	@rm -rf "/Applications/PRs and Issues Preview.app"
	@echo "Uninstalled PRs and Issues Preview.app"

# Cleanup
clean:
	@echo "==> Cleaning build artifacts..."
	@swift package clean 2>/dev/null || true
	@rm -rf .build .swiftpm "$(APP_BUNDLE)"

# Setup
setup:
	@echo "==> Creating config directories..."
	@mkdir -p ~/.config/pr-review
	@mkdir -p ~/.local/share/pr-review/repos
	@echo "Created:"
	@echo "  ~/.config/pr-review/"
	@echo "  ~/.local/share/pr-review/repos/"
	@echo ""
	@echo "Now create ~/.config/pr-review/config.json with your settings."
