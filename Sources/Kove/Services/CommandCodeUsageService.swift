import Foundation
import SwiftUI

final class CommandCodeUsageService: ObservableObject, @unchecked Sendable {

    enum State: Equatable {
        case idle
        case loading
        case ready
        case unavailable(String)
    }

    struct WindowLimit {
        let used: Double
        let cap: Double
        let exceeded: Bool
        let resetsAt: Date?
    }

    struct Snapshot {
        let planName: String?
        let periodEnd: Date?
        let cancelsAtPeriodEnd: Bool
        let fiveHour: WindowLimit?
        let weekly: WindowLimit?
        let creditsRemaining: Double
        let requestCount: Int?
        let successRate: Double?
        let updatedAt: Date

        var isExceeded: Bool {
            (fiveHour?.exceeded ?? false) || (weekly?.exceeded ?? false)
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var snapshot: Snapshot?

    private var timer: Timer?
    private var isRefreshing = false

    private static let baseURL = "https://api.commandcode.ai"

    func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        if snapshot == nil { state = .loading }

        Task { [weak self] in
            guard let self else { return }
            let result = await Self.fetch()
            DispatchQueue.main.async {
                switch result {
                case .success(let snapshot):
                    self.snapshot = snapshot
                    self.state = .ready
                case .failure(let error):
                    if self.snapshot == nil {
                        self.state = .unavailable(error.message)
                    }
                }
                self.isRefreshing = false
            }
        }
    }

    private static func fetch() async -> Result<Snapshot, FetchError> {
        guard let key = apiKey() else {
            return .failure(FetchError(message: "No Command Code login found. Run cmd login to connect this Mac."))
        }

        do {
            let credits: CreditsEnvelope = try await get("/alpha/billing/credits", key: key)
            let subscription: SubscriptionEnvelope? = try? await get("/alpha/billing/subscriptions", key: key)
            let summary: Summary? = try? await get("/alpha/usage/summary", key: key)

            let planId = subscription?.data?.planId
            let creditsRemaining = max(0, credits.credits.monthlyCredits ?? 0)
                + max(0, credits.credits.purchasedCredits ?? 0)
                + max(0, credits.credits.freeCredits ?? 0)

            let snapshot = Snapshot(
                planName: planName(for: planId),
                periodEnd: parseDate(subscription?.data?.currentPeriodEnd),
                cancelsAtPeriodEnd: subscription?.data?.cancelAtPeriodEnd ?? false,
                fiveHour: window(credits.windowLimits?.fiveHour),
                weekly: window(credits.windowLimits?.weekly),
                creditsRemaining: creditsRemaining,
                requestCount: summary?.totalCount,
                successRate: summary?.successRate,
                updatedAt: Date()
            )
            return .success(snapshot)
        } catch let error as FetchError {
            return .failure(error)
        } catch {
            return .failure(FetchError(message: "Usage is unavailable right now."))
        }
    }

    private static func get<T: Decodable>(_ path: String, key: String) async throws -> T {
        guard let url = URL(string: baseURL + path) else {
            throw FetchError(message: "Invalid Command Code endpoint.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FetchError(message: "Usage is unavailable right now.")
        }
        if http.statusCode == 401 {
            throw FetchError(message: "Command Code session expired. Run cmd login again.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw FetchError(message: "Command Code returned HTTP \(http.statusCode).")
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw FetchError(message: "Unexpected usage response from Command Code.")
        }
    }

    private static func apiKey() -> String? {
        if let key = ProcessInfo.processInfo.environment["COMMAND_CODE_API_KEY"], !key.isEmpty {
            return key
        }

        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".commandcode/auth.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["apiKey"] as? String,
              !key.isEmpty
        else { return nil }

        return key
    }

    private static func window(_ window: CreditsEnvelope.Window?) -> WindowLimit? {
        guard let window, window.cap > 0 else { return nil }
        return WindowLimit(
            used: max(0, window.used),
            cap: window.cap,
            exceeded: window.exceeded ?? false,
            resetsAt: window.resetAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        )
    }

    private static func planName(for id: String?) -> String? {
        guard let id else { return nil }
        let normalized = id.lowercased().replacingOccurrences(of: "_", with: "-")
        let names = [
            ("individual-provider", "Provider"),
            ("individual-ultra", "Ultra"),
            ("individual-goat", "GOAT"),
            ("individual-max", "Max"),
            ("individual-pro", "Pro"),
            ("individual-go", "Go"),
            ("teams-pro", "Teams Pro")
        ]
        for (prefix, name) in names where normalized.hasPrefix(prefix) {
            return name
        }
        return id.uppercased()
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private struct FetchError: Error {
        let message: String
    }

    private struct CreditsEnvelope: Decodable {
        struct Credits: Decodable {
            let monthlyCredits: Double?
            let purchasedCredits: Double?
            let freeCredits: Double?
        }

        struct WindowLimits: Decodable {
            let fiveHour: Window?
            let weekly: Window?
        }

        struct Window: Decodable {
            let used: Double
            let cap: Double
            let exceeded: Bool?
            let resetAt: Double?
        }

        let credits: Credits
        let windowLimits: WindowLimits?
    }

    private struct SubscriptionEnvelope: Decodable {
        struct Subscription: Decodable {
            let planId: String?
            let currentPeriodEnd: String?
            let cancelAtPeriodEnd: Bool?
        }

        let data: Subscription?
    }

    private struct Summary: Decodable {
        let totalCount: Int?
        let successRate: Double?
    }
}
