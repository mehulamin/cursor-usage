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
