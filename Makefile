# Root Makefile — delegates to the macOS SwiftUI app.
.PHONY: build run clean debug

build run clean debug:
	$(MAKE) -C macos $@
