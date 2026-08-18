import SwiftUI

/// 设置窗口:粘贴 / 保存 / 修改 accessToken,或一键从 Cursor 本地自动读取。
struct SettingsView: View {
    @State private var token: String
    @State private var statusMessage: String = ""
    @State private var showToken = false
    var onClose: () -> Void
    var onTokenSaved: () -> Void

    init(initialToken: String, onClose: @escaping () -> Void, onTokenSaved: @escaping () -> Void) {
        _token = State(initialValue: initialToken)
        self.onClose = onClose
        self.onTokenSaved = onTokenSaved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("设置 Cursor accessToken")
                .font(.headline)
            Text("Token 只保存在本机 macOS 钥匙串中(兜底:Application Support 下 0600 权限文件),不会写入项目仓库。")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                if showToken {
                    TextField("accessToken", text: $token)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("accessToken", text: $token)
                        .textFieldStyle(.roundedBorder)
                }
                Button(showToken ? "隐藏" : "显示") { showToken.toggle() }
            }

            HStack(spacing: 8) {
                Button("保存到钥匙串") {
                    if TokenStore.save(token) {
                        statusMessage = "已保存 ✓ 并刷新用量。"
                        onTokenSaved()
                    } else {
                        statusMessage = "保存失败:token 为空或钥匙串不可用。"
                    }
                }
                .keyboardShortcut(.defaultAction)

                Button("从 Cursor 自动读取") {
                    if let t = TokenStore.readFromCursorVscdb() {
                        token = t
                        statusMessage = "已读取 Cursor 当前 token(尚未保存,点击「保存到钥匙串」持久化)。"
                    } else {
                        statusMessage = "未找到 Cursor 本地 token(state.vscdb 不存在或读取失败)。"
                    }
                }

                Spacer()

                Button("关闭") { onClose() }
                    .keyboardShortcut(.cancelAction)
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Token 来源:Cursor 的 ~/Library/Application Support/Cursor/User/globalStorage/state.vscdb(键 cursorAuth/accessToken)。也可打开 Cursor → Settings → Accounts 复制会话令牌。Token 为约 2 个月有效期的 JWT,过期后在 Cursor 里重新登录即可,再点「从 Cursor 自动读取」。")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 480)
    }
}
