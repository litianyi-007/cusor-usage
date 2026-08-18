# 构建本机 macOS 菜单栏常驻应用(纯系统工具链,无第三方依赖)

SWIFT := swiftc
BUILD_DIR := build
APP := $(BUILD_DIR)/CursorUsage.app
FRAMEWORKS := -framework AppKit -framework SwiftUI -framework Security -framework Combine
SOURCES := $(wildcard Sources/*.swift)

all: bundle

$(BUILD_DIR)/CursorUsage: $(SOURCES)
	@mkdir -p $(BUILD_DIR)
	# TMPDIR 固定为 /tmp,规避部分环境默认临时目录无写权限的问题
	@TMPDIR=/tmp $(SWIFT) -O $(SOURCES) -o $@ $(FRAMEWORKS)

$(APP): $(BUILD_DIR)/CursorUsage Info.plist
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS
	@cp $(BUILD_DIR)/CursorUsage $(APP)/Contents/MacOS/
	@cp Info.plist $(APP)/Contents/
	@echo "bundle ready: $(APP)"

bundle: $(APP)

# 编译出可执行文件(不做 .app 打包)
build: $(BUILD_DIR)/CursorUsage

# 启动菜单栏应用
run: bundle
	open $(APP)

# 无 GUI 验证:真实拉取并打印当前周期用量(token 从 Cursor 本地读取)
test-dump: $(BUILD_DIR)/CursorUsage
	./$(BUILD_DIR)/CursorUsage --dump --from-cursor

# 安装到 /Applications(可选)
install: bundle
	@rm -rf /Applications/CursorUsage.app 2>/dev/null || true
	@cp -R $(APP) /Applications/
	@echo "installed: /Applications/CursorUsage.app"

clean:
	@rm -rf $(BUILD_DIR)

.PHONY: all build bundle run test-dump install clean
