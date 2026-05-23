# Promet Makefile
# Version format: YYYY.MMDD.N+build (Flutter-compatible semver with date)
# Example: 2026.0522.1+1

APP_NAME := promet
PUBSPEC := pubspec.yaml
BUILD_DIR := build/app/outputs/flutter-apk

YEAR := $(shell date +%Y)
MMDD := $(shell date +%m%d)

CURRENT_VERSION := $(shell grep '^version:' $(PUBSPEC) | sed 's/version: //')
CURRENT_BUILD_NUMBER := $(shell echo $(CURRENT_VERSION) | cut -d'+' -f2)
CURRENT_MMDD := $(shell echo $(CURRENT_VERSION) | cut -d'.' -f2)

# Build number (version code) must ALWAYS increment for Android updates.
NEW_BUILD_NUMBER := $(shell echo $$(($(CURRENT_BUILD_NUMBER) + 1)))

# Daily sequence number resets each day for version-name readability.
DAILY_BUILD := $(shell \
	if [ "$(CURRENT_MMDD)" = "$(MMDD)" ]; then \
		echo $(CURRENT_VERSION) | cut -d'.' -f3 | cut -d'+' -f1 | awk '{print $$1 + 1}'; \
	else \
		echo 1; \
	fi)

NEW_VERSION := $(YEAR).$(MMDD).$(DAILY_BUILD)+$(NEW_BUILD_NUMBER)

# Git tag for the release (version name without the +build metadata).
NEW_VERSION_NAME := $(YEAR).$(MMDD).$(DAILY_BUILD)
TAG := v$(NEW_VERSION_NAME)

.PHONY: help version bump deps analyze test run icon build clean release

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-12s\033[0m %s\n", $$1, $$2}'

version: ## Show current and next version
	@echo "Current version: $(CURRENT_VERSION)"
	@echo "Next version:    $(NEW_VERSION)"

bump: ## Bump version in pubspec.yaml
	@echo "Bumping version to $(NEW_VERSION)..."
	@sed -i '' 's/^version: .*/version: $(NEW_VERSION)/' $(PUBSPEC)
	@echo "Version bumped to $(NEW_VERSION)"

deps: ## Install dependencies
	flutter pub get

analyze: ## Run Flutter analyze
	flutter analyze

test: ## Run tests
	flutter test

run: ## Run app in development mode
	flutter run

icon: ## Generate app icons from icon.png
	dart run flutter_launcher_icons

build: bump ## Build release APK (auto-bumps version)
	flutter build apk --release
	@ls -lh $(BUILD_DIR)/app-release.apk

clean: ## Clean build artifacts
	flutter clean

release: bump ## Bump version, push, and publish a GitHub release (CI builds the APKs)
	@command -v gh >/dev/null 2>&1 || { echo "Error: gh CLI not found — https://cli.github.com"; exit 1; }
	@gh auth status >/dev/null 2>&1 || { echo "Error: not logged in to gh — run 'gh auth login'"; exit 1; }
	@echo "Releasing $(TAG) (version $(NEW_VERSION))..."
	@git add $(PUBSPEC)
	@git commit -m "Release $(TAG)"
	@git push
	@gh release create $(TAG) --title "$(TAG)" --generate-notes
	@echo "Published release $(TAG). The Android Release workflow will build and attach the APKs."
