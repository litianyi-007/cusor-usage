# CursorUsage 菜单栏插件

BUILD  := build
TMPDIR ?= /tmp/swiftwork
SWIFT  := swiftc
SOURCES := $(wildcard Sources/*.swift)
FRAMEWORKS := -framework AppKit -framework SwiftUI -framework Security -lsqlite3

.PHONY: build app selfcheck run clean

build:
	@mkdir -p $(BUILD) $(TMPDIR)
	TMPDIR=$(TMPDIR) $(SWIFT) -O -swift-version 5 $(SOURCES) $(FRAMEWORKS) -o $(BUILD)/CursorUsage

app: build
	@rm -rf $(BUILD)/CursorUsage.app
	@mkdir -p $(BUILD)/CursorUsage.app/Contents/MacOS
	@cp $(BUILD)/CursorUsage $(BUILD)/CursorUsage.app/Contents/MacOS/
	@cp Sources/Info.plist $(BUILD)/CursorUsage.app/Contents/
	@codesign --force --sign - $(BUILD)/CursorUsage.app >/dev/null 2>&1 || echo "codesign skipped"
	@echo "built: $(BUILD)/CursorUsage.app"

# 无头自测：真实 token 解析 + 真实 API + 钥匙串/文件存取
selfcheck: build
	./$(BUILD)/CursorUsage --selfcheck

run: app
	open $(BUILD)/CursorUsage.app

clean:
	rm -rf $(BUILD)
