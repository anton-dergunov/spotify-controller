APP_NAME := SpotifyController
CONFIG ?= release
BUILD_DIR := .build/$(CONFIG)
BINARY := $(BUILD_DIR)/$(APP_NAME)
COVER_SRC := ../cover.jpg
RESOURCE_COVER := Sources/SpotifyController/Resources/cover.jpg

.PHONY: all build run clean sync-cover

all: build

sync-cover:
	@mkdir -p Sources/SpotifyController/Resources
	@if [ -f "$(COVER_SRC)" ]; then \
		cp "$(COVER_SRC)" "$(RESOURCE_COVER)"; \
		echo "Copied cover.jpg into app resources."; \
	else \
		echo "Warning: $(COVER_SRC) not found — app will search at runtime or show placeholder."; \
	fi

build: sync-cover
	swift build -c $(CONFIG)

run: build
	@echo "Launching $(BINARY)…"
	@$(BINARY)

clean:
	swift package clean
	rm -f "$(RESOURCE_COVER)"

debug:
	$(MAKE) build CONFIG=debug
	$(MAKE) run CONFIG=debug
