# SPDX-FileCopyrightText: 2026 homecla
# SPDX-License-Identifier: AGPL-3.0-or-later

PREFIX  ?= $(HOME)/.local
APPDIR  ?= $(HOME)/Applications
APP     := dist/Save My Space.app
# I test (Swift Testing) richiedono la toolchain di Xcode.
XCODE   ?= /Applications/Xcode.app/Contents/Developer

.PHONY: build release app install test clean

build:
	swift build

release:
	swift build -c release

app: release
	@BIN="$$(swift build -c release --show-bin-path)"; \
	rm -rf "$(APP)"; \
	mkdir -p "$(APP)/Contents/MacOS"; \
	cp "$$BIN/SaveMySpaceApp" "$(APP)/Contents/MacOS/SaveMySpaceApp"; \
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"; \
	mkdir -p "$(APP)/Contents/Resources"; \
	cp LICENSE THIRD_PARTY_NOTICES.md "$(APP)/Contents/Resources/"; \
	echo "Creata $(APP)"

install: app
	@BIN="$$(swift build -c release --show-bin-path)"; \
	mkdir -p "$(PREFIX)/bin" "$(APPDIR)"; \
	cp "$$BIN/smspace" "$(PREFIX)/bin/smspace"; \
	rm -rf "$(APPDIR)/Save My Space.app"; \
	cp -R "$(APP)" "$(APPDIR)/"; \
	echo "Installati $(PREFIX)/bin/smspace e $(APPDIR)/Save My Space.app"

test:
	DEVELOPER_DIR=$(XCODE) swift test

clean:
	swift package clean
	rm -rf dist
