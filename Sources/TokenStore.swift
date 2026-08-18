import Foundation
import Security

/// Token 存取设计:
/// 1. macOS Keychain(generic password;service = ai-goods.cursor-usage)—— 首选,系统级加密保管
/// 2. 兜底文件 ~/Library/Application Support/CursorUsage/token.txt(权限 0600)—— Keychain 不可用时
/// 3. 一键从 Cursor 本地状态库读取 —— 只读,绝不改写 Cursor 任何状态
///
/// Token 绝不写入项目仓库:仓库内没有任何 token 存储逻辑或文件。
enum TokenStore {

    static let service = "ai-goods.cursor-usage"
    static let account = "accessToken"

    // MARK: - Keychain

    @discardableResult
    static func saveToKeychain(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        if readFromKeychain() != nil {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let attrs: [String: Any] = [kSecValueData as String: data]
            return SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecSuccess
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - 兜底文件(Keychain 不可用时)

    static var fallbackFileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return dir.appendingPathComponent("CursorUsage", isDirectory: true)
            .appendingPathComponent("token.txt")
    }

    @discardableResult
    static func saveToFallbackFile(_ token: String) -> Bool {
        guard let url = fallbackFileURL else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try token.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                  ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    static func readFromFallbackFile() -> String? {
        guard let url = fallbackFileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        let s = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty ?? true) ? nil : s
    }

    // MARK: - 保存 / 读取总入口

    @discardableResult
    static func save(_ token: String) -> Bool {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        if saveToKeychain(t) { return true }
        return saveToFallbackFile(t)
    }

    /// 读取顺序:Keychain → 兜底文件 → Cursor 本地状态库(allowCursor 为 true 时)
    static func load(allowCursor: Bool) -> String? {
        if let t = readFromKeychain() { return t }
        if let t = readFromFallbackFile() { return t }
        if allowCursor { return readFromCursorVscdb() }
        return nil
    }

    // MARK: - 从 Cursor 本地状态库读取(只读)

    static var cursorVscdbPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
            .path
    }

    /// 通过 /usr/bin/sqlite3 只读查询 cursorAuth/accessToken。
    /// 只读当前有效的 token,不修改 Cursor 的 token、不触发刷新。
    static func readFromCursorVscdb() -> String? {
        let path = cursorVscdbPath
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-readonly",
            path,
            "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken';",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty ?? true) ? nil : s
    }
}
