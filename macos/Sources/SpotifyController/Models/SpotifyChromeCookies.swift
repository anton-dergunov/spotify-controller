import CCommonCrypto
import Foundation
import Security

// Reads ALL spotify.com cookies from the user's browser SQLite store,
// decrypting them with AES-128-CBC (key derived from the browser's macOS Keychain entry).
// Mirrors what browser_cookie3 does in prototypes/spotify_liked.py.
enum SpotifyChromeCookies {

    static func readAllSpotifyCookies() -> [HTTPCookie] {
        let browsers: [(folder: String, service: String, account: String)] = [
            ("Google/Chrome",                 "Chrome Safe Storage",         "Chrome"),
            ("BraveSoftware/Brave-Browser",   "Brave Safe Storage",          "Brave"),
            ("Microsoft Edge",                "Microsoft Edge Safe Storage", "Microsoft Edge"),
        ]
        for b in browsers {
            let dbPath = "\(NSHomeDirectory())/Library/Application Support/\(b.folder)/Default/Cookies"
            log("checking \(b.folder) at \(dbPath)")
            guard FileManager.default.fileExists(atPath: dbPath) else {
                log("  → file does not exist, skipping")
                continue
            }
            // Probe: can we even read the file? TCC/FDA may block us silently otherwise.
            if !FileManager.default.isReadableFile(atPath: dbPath) {
                log("  → file exists but is not readable (TCC / Full Disk Access?)")
                continue
            }
            let cookies = readCookies(at: dbPath,
                                       keychainService: b.service,
                                       keychainAccount: b.account)
            if !cookies.isEmpty {
                log("  → using \(b.folder) (\(cookies.count) cookies)")
                return cookies
            }
        }
        log("no browser yielded any spotify.com cookies")
        return []
    }

    private static func log(_ message: String) {
        NSLog("[SpotifyCookies] %@", message)
    }

    // MARK: - SQLite reading

    private static func readCookies(at path: String,
                                     keychainService: String,
                                     keychainAccount: String) -> [HTTPCookie] {
        log("  reading from \(path)")
        guard let key = deriveAESKey(service: keychainService, account: keychainAccount) else {
            log("  ERROR: deriveAESKey returned nil (Keychain access failed or item not found for service '\(keychainService)')")
            return []
        }
        log("  derived AES key OK (length=\(key.count))")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = [
            "-separator", "|||",
            "file:\(path)?mode=ro&immutable=1",
            "SELECT name, hex(encrypted_value), host_key, path, is_secure FROM cookies WHERE host_key LIKE '%spotify.com';",
        ]
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError  = errPipe
        do { try proc.run() } catch {
            log("  ERROR: sqlite3 launch failed: \(error)")
            return []
        }
        proc.waitUntilExit()

        let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""

        log("  sqlite3 exit status=\(proc.terminationStatus) stdout=\(output.count) bytes stderr=\(stderr.count) bytes")
        if !stderr.isEmpty {
            log("  sqlite3 stderr: \(stderr.prefix(400))")
        }
        if output.isEmpty {
            log("  sqlite3 returned no output — likely permission denied (Full Disk Access?) or empty table")
            return []
        }

        var rowsParsed = 0
        var hexFailures = 0
        var decryptFailures = 0
        var cookieInitFailures = 0
        var cookies: [HTTPCookie] = []
        for line in output.split(whereSeparator: { $0 == "\n" }) {
            let parts = line.components(separatedBy: "|||")
            guard parts.count >= 5 else { continue }
            rowsParsed += 1

            let name     = parts[0]
            let hex      = parts[1]
            let hostKey  = parts[2]
            let cpath    = parts[3].isEmpty ? "/" : parts[3]
            let secure   = parts[4] == "1"

            guard let encrypted = Data(hexString: hex) else { hexFailures += 1; continue }
            guard let value     = decryptChromeValue(encrypted, key: key) else {
                decryptFailures += 1
                if decryptFailures <= 2 {
                    log("  decrypt failed for cookie '\(name)' (encrypted bytes=\(encrypted.count), prefix=\(encrypted.prefix(3).map { String(format: "%02x", $0) }.joined()))")
                }
                continue
            }
            guard !name.isEmpty, !value.isEmpty else { continue }

            var props: [HTTPCookiePropertyKey: Any] = [
                .name:    name,
                .value:   value,
                .domain:  hostKey,
                .path:    cpath,
                .expires: Date().addingTimeInterval(60 * 60 * 24 * 365),
            ]
            if secure { props[.secure] = "TRUE" }

            if let cookie = HTTPCookie(properties: props) {
                cookies.append(cookie)
            } else {
                cookieInitFailures += 1
            }
        }
        log("  rows=\(rowsParsed) hexFailures=\(hexFailures) decryptFailures=\(decryptFailures) cookieInitFailures=\(cookieInitFailures) → \(cookies.count) cookies")
        return cookies
    }

    // MARK: - Keychain + key derivation

    private static func deriveAESKey(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass       as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData  as String: true,
            kSecMatchLimit  as String: kSecMatchLimitOne,
        ]
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let pwData = item as? Data,
              let pw     = String(data: pwData, encoding: .utf8) else { return nil }
        return pbkdf2SHA1(password: pw, salt: "saltysalt", iterations: 1003, keyLength: 16)
    }

    private static func pbkdf2SHA1(password: String, salt: String,
                                    iterations: Int, keyLength: Int) -> Data? {
        guard let pw = password.data(using: .utf8),
              let st = salt.data(using: .utf8) else { return nil }
        var derived = Data(repeating: 0, count: keyLength)
        let status = derived.withUnsafeMutableBytes { dPtr in
            pw.withUnsafeBytes { pwPtr in
                st.withUnsafeBytes { stPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pwPtr.bindMemory(to: Int8.self).baseAddress, pw.count,
                        stPtr.bindMemory(to: UInt8.self).baseAddress, st.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        UInt32(iterations),
                        dPtr.bindMemory(to: UInt8.self).baseAddress!, keyLength
                    )
                }
            }
        }
        return status == kCCSuccess ? derived : nil
    }

    // MARK: - AES-128-CBC decryption (Chrome macOS "v10" format)

    private static func decryptChromeValue(_ data: Data, key: Data) -> String? {
        guard data.count > 3 else { return nil }
        if data.prefix(3) == Data("v10".utf8) {
            let ciphertext = data.dropFirst(3)
            let iv = Data(repeating: 0x20, count: 16) // 16 ASCII spaces
            var plaintext = Data(repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
            let capacity = plaintext.count
            var written  = 0
            let status: CCCryptorStatus = plaintext.withUnsafeMutableBytes { pt in
                key.withUnsafeBytes { k in
                    iv.withUnsafeBytes { iv in
                        ciphertext.withUnsafeBytes { ct in
                            CCCrypt(
                                CCOperation(kCCDecrypt),
                                CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                k.baseAddress!,  key.count,
                                iv.baseAddress!,
                                ct.baseAddress!, ciphertext.count,
                                pt.baseAddress!, capacity,
                                &written
                            )
                        }
                    }
                }
            }
            guard status == kCCSuccess else { return nil }
            return String(data: plaintext.prefix(written), encoding: .utf8)
        }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Helpers

private extension Data {
    init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
