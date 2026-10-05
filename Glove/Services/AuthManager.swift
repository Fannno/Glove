import Foundation
import Security

/// 定義全域 401 通知名稱
extension Notification.Name {
    static let didReceive401Unauthorized = Notification.Name("didReceive401Unauthorized")
}

/// 負責 JWT Token 的安全儲存、讀取與登入有效期限管理
final class AuthManager {
    static let shared = AuthManager()

    /// Keychain 服務名稱
    private let keychainService =
        Bundle.main.bundleIdentifier ?? "com.fannno.Glove"

    /// Keychain 中 JWT Token 的識別名稱
    private let tokenAccount = "user_auth_token"

    /// 舊版 UserDefaults Token Key，僅供版本升級時遷移
    private let legacyTokenKey = "user_auth_token"

    /// Token 儲存時間 Key
    private let saveTimeKey = "token_save_timestamp"

    /// App 端 Token 有效時間：24 小時
    private let expirationInterval: TimeInterval = 24 * 60 * 60

    private init() {}

    /// 將 JWT Token 安全儲存至 Keychain，並記錄登入時間
    func saveToken(_ token: String) {
        guard saveTokenToKeychain(token) else {
            AppLog.error("JWT Token 儲存至 Keychain 失敗")
            return
        }

        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: saveTimeKey
        )

        // 若使用者由舊版本升級，確保 UserDefaults 中不再保留 Token
        UserDefaults.standard.removeObject(forKey: legacyTokenKey)
    }

    /// 取得目前有效的 JWT Token
    func getToken() -> String? {
        migrateLegacyTokenIfNeeded()

        let saveTimestamp =
            UserDefaults.standard.double(forKey: saveTimeKey)

        // 沒有登入時間，視為無效登入狀態
        guard saveTimestamp > 0 else {
            clearToken()
            return nil
        }

        // 超過 App 端設定的有效時間
        let currentTimestamp = Date().timeIntervalSince1970
        if currentTimestamp - saveTimestamp > expirationInterval {
            AppLog.debug("Token 已過期")
            clearToken()
            return nil
        }

        return readTokenFromKeychain()
    }

    /// 清除 JWT Token 與登入時間
    func clearToken() {
        deleteTokenFromKeychain()

        // 同時清除舊版可能殘留於 UserDefaults 的 Token
        UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        UserDefaults.standard.removeObject(forKey: saveTimeKey)
    }

    /// 寫入或更新 Keychain 中的 JWT Token
    @discardableResult
    private func saveTokenToKeychain(_ token: String) -> Bool {
        guard let tokenData = token.data(using: .utf8) else {
            return false
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenAccount
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return true
        }

        guard updateStatus == errSecItemNotFound else {
            AppLog.error(
                "更新 Keychain Token 失敗，OSStatus: \(updateStatus)"
            )
            return false
        }

        var newItem = query
        attributes.forEach { key, value in
            newItem[key] = value
        }

        let addStatus = SecItemAdd(
            newItem as CFDictionary,
            nil
        )

        guard addStatus == errSecSuccess else {
            AppLog.error(
                "新增 Keychain Token 失敗，OSStatus: \(addStatus)"
            )
            return false
        }

        return true
    }

    /// 從 Keychain 讀取 JWT Token
    private func readTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?

        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )

        guard status == errSecSuccess,
              let tokenData = result as? Data,
              let token = String(data: tokenData, encoding: .utf8)
        else {
            if status != errSecItemNotFound {
                AppLog.error(
                    "讀取 Keychain Token 失敗，OSStatus: \(status)"
                )
            }

            return nil
        }

        return token
    }

    /// 刪除 Keychain 中的 JWT Token
    private func deleteTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenAccount
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess &&
            status != errSecItemNotFound
        {
            AppLog.error(
                "刪除 Keychain Token 失敗，OSStatus: \(status)"
            )
        }
    }

    /// 將舊版本存在 UserDefaults 的 JWT 自動遷移至 Keychain
    private func migrateLegacyTokenIfNeeded() {
        // Keychain 已有 Token，不需遷移
        if readTokenFromKeychain() != nil {
            UserDefaults.standard.removeObject(
                forKey: legacyTokenKey
            )
            return
        }

        guard let legacyToken =
            UserDefaults.standard.string(
                forKey: legacyTokenKey
            ),
            !legacyToken.isEmpty
        else {
            return
        }

        if saveTokenToKeychain(legacyToken) {
            UserDefaults.standard.removeObject(
                forKey: legacyTokenKey
            )

            AppLog.debug(
                "已將舊版 JWT Token 遷移至 Keychain"
            )
        }
    }
}
