.PHONY: generate open build acceptance notes help

help:
	@echo "LocusUpdate"
	@echo "  make generate   - xcodegen → LocusUpdate.xcodeproj"
	@echo "  make open       - generate + open in Xcode"
	@echo "  make build      - unsigned local Debug build (macOS + Xcode required)"
	@echo "  make acceptance - print path to ACCEPTANCE.md checklist"
	@echo "  make notes      - same as acceptance (WI 16)"

generate:
	@command -v xcodegen >/dev/null || (echo "Install XcodeGen: brew install xcodegen" && exit 1)
	xcodegen generate

open: generate
	open LocusUpdate.xcodeproj

# Unsigned / ad-hoc local build. Cannot run on Linux CI boxes — macOS host only.
build: generate
	xcodebuild -scheme LocusUpdate -configuration Debug -destination 'platform=macOS' \
		CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES build

acceptance notes:
	@echo "Manual acceptance checklist: ACCEPTANCE.md"
	@echo "Covers work items 10–16 (open update URL, ignore/pin, menu bar scan,"
	@echo "notifications, detection cache, settings, unsigned build notes)."
	@echo "Sort 17 (Homebrew/CLI silent replace) is intentionally NOT implemented."
