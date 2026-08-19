import Foundation
import Security
import SQLite3

// MARK: - 本地 Cursor 登录态（只读）

struct LocalCursorAuth {
    var accessToken: String?
    var refreshToken: String?
    var email: String?
    var membershipType: String?
}

/// token 存取：
/// 1) macOS 钥匙串（首选，手动保存）
/// 2) ~/Library/Application Support/CursorUsage/config.json（兜底，chmod 600，仓库外）
/// 3) Cursor 桌面端本地状态库只读自动读取（默认模式）
final class TokenStore {

    private let service = "com.cursorusage.menubar"
    private let keychainAccount = "accessToken"
    private let fileManager = FileManager.default

    /// 兜底文件目录；可用环境变量 CURSORUSAGE_HOME 覆盖（自测用，避免写入真实用户目录）
    private var appSupportDir: URL {
        if let override = ProcessInfo.processInfo.environment["CURSORUSAGE_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("CursorUsage", isDirectory: true)
    }

    private var configFile: URL { appSupportDir.appendingPathComponent("config.json") }

    enum Source: String { case manual = "manual", auto = "auto", none = "none" }

    // MARK: - 钥匙串

    func saveTokenToKeychain(_ token: String) -> Bool {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(baseQuery as CFDictionary)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    func loadTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func clearTokenFromKeychain() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: keychainAccount,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // MARK: - 兜底文件（600）

    private func loadConfig() -> [String: String]? {
        guard let data = try? Data(contentsOf: configFile),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        return dict
    }

    func saveTokenToFile(_ token: String) -> Bool {
        do {
            try fileManager.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
            var dict = loadConfig() ?? [:]
            dict["accessToken"] = token
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
            try data.write(to: configFile, options: .atomic)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile.path)
            return true
        } catch {
            return false
        }
    }

    func loadTokenFromFile() -> String? { loadConfig()?["accessToken"] }

    func clearTokenFromFile() -> Bool {
        guard var dict = loadConfig() else { return false }
        dict.removeValue(forKey: "accessToken")
        do {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
            try data.write(to: configFile, options: .atomic)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile.path)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Cursor 本地状态库（只读 SQLite）

    private var cursorStateDBPaths: [String] {
        [
            NSHomeDirectory() + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
            NSHomeDirectory() + "/.config/Cursor/User/globalStorage/state.vscdb",
        ]
    }

    func readCursorLocalAuth() -> LocalCursorAuth? {
        guard let path = cursorStateDBPaths.first(where: { fileManager.fileExists(atPath: $0) }) else {
            return nil
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)

        func get(_ key: String) -> String? {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ? LIMIT 1", -1, &stmt, nil) == SQLITE_OK else {
                return nil
            }
            // SQLITE_TRANSIENT 是 C 宏，Swift 中需手动构造
            sqlite3_bind_text(stmt, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            guard sqlite3_step(stmt) == SQLITE_ROW, let col = sqlite3_column_text(stmt, 0) else {
                return nil
            }
            return String(cString: UnsafeRawPointer(col).assumingMemoryBound(to: CChar.self))
        }

        return LocalCursorAuth(
            accessToken: get("cursorAuth/accessToken"),
            refreshToken: get("cursorAuth/refreshToken"),
            email: get("cursorAuth/cachedEmail"),
            membershipType: get("cursorAuth/stripeMembershipType")
        )
    }

    // MARK: - 解析（优先级：手动钥匙串 → 兜底文件 → Cursor 本地自动）

    func resolveToken() -> (token: String?, source: Source, email: String?, plan: String?) {
        PanelModel.diagnose("resolveToken: 开始")
        if let kc = loadTokenFromKeychain(), !kc.isEmpty {
            PanelModel.diagnose("resolveToken: 命中钥匙串")
            return (kc, .manual, nil, nil)
        }
        PanelModel.diagnose("resolveToken: 钥匙串未命中，查本地文件")
        if let fileToken = loadTokenFromFile(), !fileToken.isEmpty {
            PanelModel.diagnose("resolveToken: 命中本地文件")
            return (fileToken, .manual, nil, nil)
        }
        PanelModel.diagnose("resolveToken: 文件未命中，读 Cursor 本地状态库")
        if let local = readCursorLocalAuth(), let t = local.accessToken, !t.isEmpty {
            PanelModel.diagnose("resolveToken: 命中 Cursor 本地")
            return (t, .auto, local.email, local.membershipType)
        }
        PanelModel.diagnose("resolveToken: 全部未命中")
        return (nil, .none, nil, nil)
    }
}

// MARK: - 诊断日志（进程内共用）

extension PanelModel {
    /// 极简诊断日志：只走 NSLog（不依赖文件写入，避免权限问题掩盖真相）
    nonisolated static func diagnose(_ message: String) {
        NSLog("[CursorUsage:diag] %@", message)
    }
}
