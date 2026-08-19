# CursorUsage 菜单栏插件
# 版本号单一来源：VERSION 文件（SemVer），构建时注入 Info.plist

BUILD  := build
TMPDIR ?= /tmp/swiftwork
SWIFT  := swiftc
SOURCES := $(wildcard Sources/*.swift)
FRAMEWORKS := -framework AppKit -framework SwiftUI -framework Security -lsqlite3
APP := $(BUILD)/CursorUsage.app

# 版本维护：VERSION 文件为准；BUILD_NUM 用 git 提交数（CI/本地一致）
VERSION  := $(shell cat VERSION 2>/dev/null || echo 0.0.0)
BUILD_NUM := $(shell git rev-list --count HEAD 2>/dev/null || echo 1)

.PHONY: build version app icns package selfcheck screenshots run clean

build:
	@mkdir -p $(BUILD) $(TMPDIR)
	@sed -e 's/__VERSION__/$(VERSION)/g' -e 's/__BUILD__/$(BUILD_NUM)/g' \
		Sources/Info.plist.template > $(BUILD)/Info.plist
	@echo "VERSION=$(VERSION) BUILD=$(BUILD_NUM)"
	TMPDIR=$(TMPDIR) $(SWIFT) -O -swift-version 5 $(SOURCES) $(FRAMEWORKS) -o $(BUILD)/CursorUsage

version:
	@echo "VERSION=$(VERSION) BUILD=$(BUILD_NUM) TAG=v$(VERSION)"

# App 图标：进程内直接生成 .icns（16/32/64/128/256/512/1024，无需 iconutil/sips）
icns: build
	./$(BUILD)/CursorUsage --icns $(BUILD)/AppIcon.icns

app: build icns
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@cp $(BUILD)/CursorUsage $(APP)/Contents/MacOS/
	@cp $(BUILD)/AppIcon.icns $(APP)/Contents/Resources/
	@cp $(BUILD)/Info.plist $(APP)/Contents/
	@codesign --force --sign - $(APP) >/dev/null 2>&1 || echo "codesign skipped"
	@echo "built: $(APP) (v$(VERSION) build $(BUILD_NUM))"

# 发布包：zip + dmg（CI 的 release 流程也调用本目标）
package: app
	@rm -f $(BUILD)/CursorUsage-*.zip $(BUILD)/CursorUsage-*.dmg
	@ditto -c -k --keepParent $(APP) $(BUILD)/CursorUsage-$(VERSION)-macOS.zip
	@rm -rf $(BUILD)/dmg-staging
	@mkdir -p $(BUILD)/dmg-staging
	@cp -R $(APP) $(BUILD)/dmg-staging/
	@ln -sf /Applications $(BUILD)/dmg-staging/Applications
	@hdiutil create -volname "CursorUsage $(VERSION)" -srcfolder $(BUILD)/dmg-staging \
		-ov -format UDZO $(BUILD)/CursorUsage-$(VERSION)-macOS.dmg >/dev/null
	@rm -rf $(BUILD)/dmg-staging
	@echo "packaged:"
	@ls -lh $(BUILD)/CursorUsage-$(VERSION)-macOS.zip $(BUILD)/CursorUsage-$(VERSION)-macOS.dmg

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
