# 构建本机 macOS 菜单栏常驻应用(纯系统工具链,零第三方依赖)
# 用法见 README.md「本地启动与验证」。

SWIFT := swiftc
BUILD_DIR := build
APP := $(BUILD_DIR)/CursorUsage.app
FRAMEWORKS := -framework AppKit -framework SwiftUI -framework Security -framework Combine
SOURCES := $(wildcard Sources/*.swift)

all: bundle

$(BUILD_DIR)/CursorUsage: $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	# TMPDIR 固定为 /tmp,规避部分环境默认临时目录无写权限导致 swiftc 报 permissionDenied
	@TMPDIR=/tmp $(SWIFT) -O $(SOURCES) -o $@ $(FRAMEWORKS)
	# ad-hoc 签名:未签名二进制在较新 macOS 上访问 Keychain 会返回 errSecMissingEntitlement
	@codesign --force --sign - $@

$(APP): $(BUILD_DIR)/CursorUsage Info.plist
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS
	@cp $(BUILD_DIR)/CursorUsage $(APP)/Contents/MacOS/
	@cp Info.plist $(APP)/Contents/
	@codesign --force --sign - $(APP)
	@echo "bundle ready: $(APP)"

bundle: $(APP)

# 只编译可执行文件(不做 .app 打包)
build: $(BUILD_DIR)/CursorUsage

# 启动菜单栏常驻应用
run: bundle
	open $(APP)

# 无 GUI 验证:真实拉取并打印解析结果(token 从 Cursor 本地读取,只读)
test-dump: $(BUILD_DIR)/CursorUsage
	./$(BUILD_DIR)/CursorUsage --dump --from-cursor

# 无 GUI 验证:输出原始 JSON + 两个池的美元拆分
dump-json: $(BUILD_DIR)/CursorUsage
	./$(BUILD_DIR)/CursorUsage --dump-json --from-cursor

# GUI 冒烟测试:启动菜单栏应用,4 秒后自动退出(验证 AppKit 路径无崩溃)
smoke-test: $(BUILD_DIR)/CursorUsage
	./$(BUILD_DIR)/CursorUsage --smoke-test

# 钥匙串存取自检(不涉及真实 token)
test-keychain: $(BUILD_DIR)/CursorUsage
	./$(BUILD_DIR)/CursorUsage --keychain-test

# 安装到 /Applications(可选)
install: bundle
	@rm -rf /Applications/CursorUsage.app 2>/dev/null || true
	@cp -R $(APP) /Applications/
	@echo "installed: /Applications/CursorUsage.app"

clean:
	@rm -rf $(BUILD_DIR)

.PHONY: all build bundle run test-dump dump-json smoke-test test-keychain install clean
