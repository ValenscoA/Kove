import SwiftUI

struct CommandCodeUsageView: View {
    @ObservedObject var usage: CommandCodeUsageService

    var body: some View {
        Group {
            switch usage.state {
            case .idle, .loading:
                loading
            case .unavailable(let message):
                unavailable(message)
            case .ready:
                if let snapshot = usage.snapshot {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        content(snapshot, now: context.date)
                    }
                } else {
                    loading
                }
            }
        }
        .frame(height: ExpandedView.contentRowHeight, alignment: .top)
    }

    private var loading: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.white)
            Text("Reading Command Code usage…")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func unavailable(_ message: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 4) {
                Text("Usage unavailable")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.primary)

                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }
            .frame(height: 96, alignment: .top)

            Spacer(minLength: 0)
        }
    }

    private func content(_ snapshot: CommandCodeUsageService.Snapshot, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text(snapshot.planName ?? "USAGE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(Theme.primary)

                if let detail = planDetail(snapshot) {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.tertiary)
                }

                Spacer(minLength: 8)

                Text("\(Self.credits(snapshot.creditsRemaining)) credits left")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.secondary)
            }

            HStack(alignment: .top, spacing: 24) {
                WindowColumn(title: "SESSION", window: snapshot.fiveHour, now: now)
                WindowColumn(title: "WEEK", window: snapshot.weekly, now: now)
            }
            .padding(.top, 13)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                if let count = snapshot.requestCount {
                    Text("\(count) requests")
                }
                if snapshot.requestCount != nil, snapshot.successRate != nil {
                    Text("·")
                }
                if let rate = snapshot.successRate {
                    Text(String(format: "%.1f%% success", rate))
                }

                Spacer(minLength: 8)

                Text("updated \(Self.clock.string(from: snapshot.updatedAt))")
            }
            .font(.system(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.tertiary)
        }
        .padding(.bottom, 12)
    }

    private func planDetail(_ snapshot: CommandCodeUsageService.Snapshot) -> String? {
        guard let end = snapshot.periodEnd else { return nil }
        let date = Self.day.string(from: end)
        return snapshot.cancelsAtPeriodEnd ? "ends \(date)" : "renews \(date)"
    }

    private static func credits(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()
}

private struct WindowColumn: View {
    let title: String
    let window: CommandCodeUsageService.WindowLimit?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Theme.secondary)

            if let window, window.cap > 0 {
                Text(Self.percent(window))
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(window.exceeded ? Color.orange : Theme.primary)
                    .padding(.top, 2)

                Text("\(Self.credits(window.used)) / \(Self.cap(window.cap)) credits")
                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.tertiary)
                    .padding(.top, 1)

                UsageProgressBar(fraction: window.used / window.cap)
                    .padding(.top, 7)

                Text(window.resetsAt.map { "resets in \(Self.remaining($0, now: now))" } ?? "resets —")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                    .padding(.top, 5)
            } else {
                Text("No cap")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .padding(.top, 2)

                Text("pay-as-you-go")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.tertiary)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func percent(_ window: CommandCodeUsageService.WindowLimit) -> String {
        String(format: "%.1f%%", max(0, window.used / window.cap * 100))
    }

    private static func credits(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func cap(_ value: Double) -> String {
        value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }

    private static func remaining(_ date: Date, now: Date) -> String {
        let minutes = Int(max(0, date.timeIntervalSince(now)) / 60)
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let mins = minutes % 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }
}

private struct UsageProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.track)
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(0, min(1, fraction)) * geometry.size.width)
            }
        }
        .frame(height: 3)
    }
}
