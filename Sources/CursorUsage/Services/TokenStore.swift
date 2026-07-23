import Foundation

enum TokenStore {
    private static let preferredKeys = [
        "cursorAuth/accessToken",
        "cursor.auth.accessToken",
        "cursorAuth/cachedCursorToken",
        "WorkosCursorSessionToken"
    ]

    static func normalizeToken(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return t }
        if t.range(of: "%[0-9A-Fa-f]{2}", options: .regularExpression) != nil {
            t = t.removingPercentEncoding ?? t
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract JWT from `userId::jwt` cookie, or return token if it already looks like a JWT.
    static func bearerFromToken(_ token: String) -> String {
        if token.contains("::") {
            let parts = token.components(separatedBy: "::")
            if let last = parts.last, last.contains(".") {
                return last
            }
        }
        return token
    }

    /// Decode JWT `exp` without verifying the signature (for display only).
    static func expirationDate(ofToken raw: String) -> Date? {
        let jwt = bearerFromToken(normalizeToken(raw))
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        guard let payloadData = base64URLDecode(String(parts[1])),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }
        let expValue: Double?
        if let n = json["exp"] as? Double {
            expValue = n
        } else if let n = json["exp"] as? Int {
            expValue = Double(n)
        } else if let s = json["exp"] as? String, let n = Double(s) {
            expValue = n
        } else {
            expValue = nil
        }
        guard let expValue else { return nil }
        return Date(timeIntervalSince1970: expValue)
    }

    static func expirationSummary(ofToken raw: String, now: Date = Date()) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "No token saved" }
        guard let exp = expirationDate(ofToken: trimmed) else {
            return "Expiration unknown"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let stamped = formatter.string(from: exp)
        if exp <= now {
            return "Expired \(stamped)"
        }
        let days = Calendar.current.dateComponents([.day], from: now, to: exp).day ?? 0
        if days == 0 {
            return "Expires today · \(stamped)"
        }
        if days == 1 {
            return "Expires tomorrow · \(stamped)"
        }
        return "Expires in \(days) days · \(stamped)"
    }

    static func isExpired(_ raw: String, now: Date = Date()) -> Bool {
        guard let exp = expirationDate(ofToken: raw) else { return false }
        return exp <= now
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }

    static func cursorStateDBPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    /// Resolve token off the main thread. Copies the DB first so a lock held by Cursor
    /// cannot hang the menu bar.
    static func resolveToken(manual: String) async -> String? {
        let trimmed = manual.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return normalizeToken(trimmed)
        }
        return await autoDetectToken()
    }

    static func autoDetectToken() async -> String? {
        await Task.detached(priority: .userInitiated) {
            Self.autoDetectTokenSync()
        }.value
    }

    private static func autoDetectTokenSync() -> String? {
        let dbPath = cursorStateDBPath()
        guard FileManager.default.fileExists(atPath: dbPath.path) else { return nil }

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("cursor-usage-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempDir) }

        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let tempDB = tempDir.appendingPathComponent("state.vscdb")
            // Copy so we never block on Cursor’s write lock.
            try fm.copyItem(at: dbPath, to: tempDB)
            // Sidecar WAL/SHM if present (best-effort).
            for suffix in ["-wal", "-shm"] {
                let side = URL(fileURLWithPath: dbPath.path + suffix)
                if fm.fileExists(atPath: side.path) {
                    try? fm.copyItem(at: side, to: URL(fileURLWithPath: tempDB.path + suffix))
                }
            }

            let keysSQL = preferredKeys.map { "'\($0)'" }.joined(separator: ",")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            process.arguments = [
                "-readonly",
                "-json",
                tempDB.path,
                "SELECT key, value FROM ItemTable WHERE key IN (\(keysSQL)) OR value LIKE 'user_%' OR value LIKE 'eyJ%' LIMIT 20;"
            ]
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
            try process.run()

            // Hard timeout — never freeze the app.
            let group = DispatchGroup()
            group.enter()
            DispatchQueue.global().async {
                process.waitUntilExit()
                group.leave()
            }
            if group.wait(timeout: .now() + 2) == .timedOut {
                process.terminate()
                return nil
            }

            let data = out.fileHandleForReading.readDataToEndOfFile()
            guard !data.isEmpty,
                  let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return nil
            }

            var map: [String: String] = [:]
            for row in rows {
                guard let key = row["key"] as? String,
                      let value = row["value"] as? String,
                      !value.isEmpty else { continue }
                map[key] = value
            }
            for key in preferredKeys {
                if let value = map[key] {
                    return normalizeToken(value)
                }
            }
            for (_, value) in map {
                if value.hasPrefix("user_") || value.hasPrefix("eyJ") {
                    return normalizeToken(value)
                }
            }
            return nil
        } catch {
            return nil
        }
    }
}
