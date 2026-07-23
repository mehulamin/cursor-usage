import Foundation

enum UsageClientError: LocalizedError {
    case noToken
    case tokenInvalid
    case emptyResponse(String)
    case missingField(String, String)
    case httpStatus(String, Int)
    case allFailed([String])
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .noToken:
            return "paste a session token in Settings"
        case .tokenInvalid:
            return "token invalid — update it in Settings"
        case .emptyResponse(let source):
            return "\(source): empty response"
        case .missingField(let source, let key):
            return "\(source): missing \(key)"
        case .httpStatus(let source, let code):
            return "\(source): HTTP \(code)"
        case .allFailed(let errors):
            return errors.isEmpty ? "could not load usage" : errors.joined(separator: " · ")
        case .decoding(let message):
            return message
        }
    }
}

struct UsageClient {
    private let session: URLSession
    private let timeout: TimeInterval = 8

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchUsage(token: String) async throws -> UsageSnapshot {
        let normalized = TokenStore.normalizeToken(token)
        var errors: [String] = []

        do {
            let data = try await fetchPeriodUsageApi2(bearer: TokenStore.bearerFromToken(normalized))
            return try normalizeUsage(data, source: "api2/GetCurrentPeriodUsage")
        } catch {
            errors.append("api2: \(error.localizedDescription)")
        }

        do {
            let (status, body) = try await httpRaw(
                host: "cursor.com",
                path: "/api/dashboard/get-current-period-usage",
                token: normalized,
                method: "POST",
                body: Data("{}".utf8)
            )
            if (200..<300).contains(status) {
                let json = try JSONSerialization.jsonObject(with: body)
                return try normalizeUsage(json, source: "cursor.com/period-usage")
            }
            errors.append("cursor.com/period-usage: HTTP \(status)")
        } catch {
            errors.append("cursor.com/period-usage: \(error.localizedDescription)")
        }

        do {
            let (status, body) = try await httpRaw(
                host: "cursor.com",
                path: "/api/usage-summary",
                token: normalized,
                method: "GET",
                body: nil
            )
            if (200..<300).contains(status) {
                let json = try JSONSerialization.jsonObject(with: body)
                return try normalizeUsage(json, source: "cursor.com/usage-summary")
            }
            errors.append("cursor.com/usage-summary: HTTP \(status)")
        } catch {
            errors.append("cursor.com/usage-summary: \(error.localizedDescription)")
        }

        throw UsageClientError.allFailed(errors)
    }

    private func fetchPeriodUsageApi2(bearer: String) async throws -> Any {
        var request = URLRequest(url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("cursor-usage-app/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageClientError.emptyResponse("api2")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw UsageClientError.tokenInvalid
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UsageClientError.httpStatus("api2", http.statusCode)
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private func httpRaw(
        host: String,
        path: String,
        token: String,
        method: String,
        body: Data?
    ) async throws -> (Int, Data) {
        var request = URLRequest(url: URL(string: "https://\(host)\(path)")!)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("WorkosCursorSessionToken=\(token)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 cursor-usage-app/1.0", forHTTPHeaderField: "User-Agent")
        if method == "POST" {
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
            request.setValue("https://cursor.com/dashboard", forHTTPHeaderField: "Referer")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageClientError.emptyResponse(host)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw UsageClientError.tokenInvalid
        }
        return (http.statusCode, data)
    }

    private func normalizeUsage(_ data: Any, source: String) throws -> UsageSnapshot {
        guard let root = data as? [String: Any] else {
            throw UsageClientError.emptyResponse(source)
        }
        if let error = root["error"] {
            let message: String
            if let s = error as? String {
                message = s
            } else if let json = try? JSONSerialization.data(withJSONObject: error),
                      let s = String(data: json, encoding: .utf8) {
                message = s
            } else {
                message = "unknown error"
            }
            throw UsageClientError.decoding("\(source): \(message)")
        }

        if let plan = root["planUsage"] as? [String: Any] {
            let auto = try requireNumber(plan, key: "autoPercentUsed", source: source)
            let api = try requireNumber(plan, key: "apiPercentUsed", source: source)
            let total = optionalNumber(plan, key: "totalPercentUsed") ?? max(auto, api)
            return UsageSnapshot(
                autoPercent: auto,
                apiPercent: api,
                totalPercent: total,
                totalSpendCents: optionalNumber(plan, key: "totalSpend") ?? 0,
                includedSpendCents: optionalNumber(plan, key: "includedSpend") ?? 0,
                bonusSpendCents: optionalNumber(plan, key: "bonusSpend") ?? 0,
                limitCents: optionalNumber(plan, key: "limit") ?? 0,
                billingCycleStart: parseTime(root["billingCycleStart"]),
                billingCycleEnd: parseTime(root["billingCycleEnd"]),
                fetchedAt: Date()
            )
        }

        if let individual = root["individualUsage"] as? [String: Any],
           let plan = individual["plan"] as? [String: Any] {
            let breakdown = plan["breakdown"] as? [String: Any] ?? [:]
            let auto = try requireNumber(plan, key: "autoPercentUsed", source: source)
            let api = try requireNumber(plan, key: "apiPercentUsed", source: source)
            let total = optionalNumber(plan, key: "totalPercentUsed") ?? max(auto, api)
            return UsageSnapshot(
                autoPercent: auto,
                apiPercent: api,
                totalPercent: total,
                totalSpendCents: optionalNumber(breakdown, key: "total") ?? optionalNumber(plan, key: "used") ?? 0,
                includedSpendCents: optionalNumber(breakdown, key: "included") ?? optionalNumber(plan, key: "limit") ?? 0,
                bonusSpendCents: optionalNumber(breakdown, key: "bonus") ?? 0,
                limitCents: optionalNumber(plan, key: "limit") ?? 0,
                billingCycleStart: parseTime(root["billingCycleStart"]),
                billingCycleEnd: parseTime(root["billingCycleEnd"]),
                fetchedAt: Date()
            )
        }

        throw UsageClientError.decoding("\(source): no usage percentages in response")
    }

    private func requireNumber(_ obj: [String: Any], key: String, source: String) throws -> Double {
        if let n = optionalNumber(obj, key: key) { return n }
        throw UsageClientError.missingField(source, key)
    }

    private func optionalNumber(_ obj: [String: Any], key: String) -> Double? {
        guard let v = obj[key] else { return nil }
        if let n = v as? Double { return n }
        if let n = v as? Int { return Double(n) }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String, let n = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)), !s.isEmpty {
            return n
        }
        return nil
    }

    private func parseTime(_ value: Any?) -> Date? {
        guard let value else { return nil }
        if let n = value as? Double {
            return Date(timeIntervalSince1970: n / 1000)
        }
        if let n = value as? Int {
            return Date(timeIntervalSince1970: Double(n) / 1000)
        }
        if let n = value as? NSNumber {
            return Date(timeIntervalSince1970: n.doubleValue / 1000)
        }
        if let s = value as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            if trimmed.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil,
               let n = Double(trimmed) {
                return Date(timeIntervalSince1970: n / 1000)
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = formatter.date(from: trimmed) { return d }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: trimmed)
        }
        return nil
    }
}
