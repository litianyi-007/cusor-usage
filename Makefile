# CursorUsage 菜单栏插件

BUILD  := build
TMPDIR ?= /tmp/swiftwork
SWIFT  := swiftc
SOURCES := $(wildcard Sources/*.swift)
FRAMEWORKS := -framework AppKit -framework SwiftUI -framework Security -lsqlite3
APP := $(BUILD)/CursorUsage.app

.PHONY: build app selfcheck screenshots icns run clean

build:
	@mkdir -p $(BUILD) $(TMPDIR)
	TMPDIR=$(TMPDIR) $(SWIFT) -O -swift-version 5 $(SOURCES) $(FRAMEWORKS) -o $(BUILD)/CursorUsage

# App 图标：进程内直接生成 .icns（16/32/64/128/256/512/1024，无需 iconutil/sips）
icns: build
	./$(BUILD)/CursorUsage --icns $(BUILD)/AppIcon.icns

app: build icns
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@cp $(BUILD)/CursorUsage $(APP)/Contents/MacOS/
	@cp $(BUILD)/AppIcon.icns $(APP)/Contents/Resources/
	@cp Sources/Info.plist $(APP)/Contents/
	@codesign --force --sign - $(APP) >/dev/null 2>&1 || echo "codesign skipped"
	@echo "built: $(APP)"

# 无头自测：真实 token 解析 + 真实 API + 钥匙串/文件存取
selfcheck: build
	./$(BUILD)/CursorUsage --selfcheck

# 产品截图（真实数据渲染）：docs/screenshots/{panel,panel-settings,menubar}.png
screenshots: build
	@mkdir -p docs/screenshots
	./$(BUILD)/CursorUsage --screenshot docs/screenshots --with-settings

run: app
	open $(APP)

clean:
	rm -rf $(BUILD)
