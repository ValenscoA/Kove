import Foundation

struct LyricLine: Equatable {
    var time: TimeInterval
    var text: String
}

/// Timed lyrics for the current track, from LRCLIB.
///
/// Deliberately platform neutral: no AppKit, no reference to playback state. It takes
/// the four fields any player can supply (artist, title, album, duration) and hands back
/// lines, so the Windows port can reuse this file with SMTC's metadata.
///
/// The API needs no key. It does ask callers to identify themselves and to cache, which
/// is what `userAgent` and the entry cache are for.
final class LyricsService: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case ready
        case instrumental
        case unavailable(String)
    }

    struct Request: Equatable {
        var title: String
        var artist: String
        var album: String
        var duration: Double
    }

    private enum Entry {
        case synced([LyricLine])
        case plain(String)
        case instrumental
        case empty
        case busy
        case unreachable
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var plainText: [String] = []
    @Published private(set) var isSynced = false
    @Published private(set) var activeIndex: Int?
    /// Set when the matched timing belongs to a different edit of the track, so the
    /// highlight still works but may sit a second or two off.
    @Published private(set) var timingMayDrift = false

    private let session: URLSession
    private let cacheLimit = 16

    private var request: Request?
    private var cache: [String: Entry] = [:]
    private var cacheOrder: [String] = []
    private var inFlight: URLSessionDataTask?
    private var attempts = 0

    private static let baseURL = "https://lrclib.net/api"
    private static let userAgent = "Kove/1.0 (https://github.com/ValenscoA/Kove)"

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Loading

    /// Called when the track changes. Passing nil clears the view.
    func load(_ request: Request?) {
        guard let request, !request.title.isEmpty else {
            clear()
            return
        }
        guard request != self.request else { return }
        self.request = request

        inFlight?.cancel()
        inFlight = nil
        reset()

        if let cached = cache[Self.key(for: request)] {
            apply(cached)
            return
        }

        attempts = 0
        state = .loading
        fetch(request, allowSearch: true)
    }

    /// Called on the display tick. Cheap: a binary search over a cached array.
    func update(position: TimeInterval) {
        guard isSynced, !lines.isEmpty else { return }

        var low = 0
        var high = lines.count - 1
        var found: Int?
        while low <= high {
            let middle = (low + high) / 2
            if lines[middle].time <= position {
                found = middle
                low = middle + 1
            } else {
                high = middle - 1
            }
        }

        if found != activeIndex { activeIndex = found }
    }

    private func clear() {
        inFlight?.cancel()
        inFlight = nil
        request = nil
        reset()
        state = .idle
    }

    private func reset() {
        lines = []
        plainText = []
        isSynced = false
        activeIndex = nil
        timingMayDrift = false
    }

    private func apply(_ entry: Entry) {
        switch entry {
        case .synced(let parsed):
            lines = parsed
            isSynced = true
            state = parsed.isEmpty ? .unavailable("No lyrics for this track") : .ready
        case .plain(let text):
            plainText = text
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            isSynced = false
            state = .ready
        case .instrumental:
            state = .instrumental
        case .empty:
            state = .unavailable("No lyrics for this track")
        case .busy:
            state = .unavailable("Lyrics service is busy")
        case .unreachable:
            state = .unavailable("Could not reach the lyrics service")
        }
    }

    // MARK: Network

    private func fetch(_ request: Request, allowSearch: Bool = true) {
        guard let url = Self.lookupURL(for: request) else {
            state = .unavailable("No lyrics for this track")
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.timeoutInterval = 10

        let task = session.dataTask(with: urlRequest) { [weak self] data, response, error in
            guard let self else { return }

            guard error == nil else {
                DispatchQueue.main.async {
                    self.commit(.unreachable, for: request, drift: 0)
                }
                return
            }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                let entry = Self.entry(from: data, status: status)
                DispatchQueue.main.async { self.commit(entry, for: request, drift: 0) }
                return
            }

            // The API answers 503 rather than 404 when the duration does not match, so any
            // non-200 on the exact lookup goes through search rather than being retried.
            if allowSearch {
                self.search(request)
            } else {
                self.retry(orCommit: .busy, for: request) { self.fetch(request, allowSearch: false) }
            }
        }

        inFlight = task
        task.resume()
    }

    private func search(_ request: Request) {
        var components = URLComponents(string: "\(Self.baseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "artist_name", value: request.artist),
            URLQueryItem(name: "track_name", value: request.title)
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.timeoutInterval = 10

        let task = session.dataTask(with: urlRequest) { [weak self] data, response, error in
            guard let self else { return }

            guard error == nil else {
                DispatchQueue.main.async {
                    self.commit(.unreachable, for: request, drift: 0)
                }
                return
            }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                self.retry(orCommit: .busy, for: request) { self.search(request) }
                return
            }

            let (entry, drift) = Self.bestMatch(from: data, duration: request.duration)
            DispatchQueue.main.async { self.commit(entry, for: request, drift: drift) }
        }

        inFlight = task
        task.resume()
    }

    /// One retry, then a terminal state: a free API that is down should not leave the
    /// panel spinning forever.
    private func retry(orCommit entry: Entry, for request: Request, _ again: @escaping () -> Void) {
        if attempts < 1 {
            attempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: again)
        } else {
            DispatchQueue.main.async { self.commit(entry, for: request, drift: 0) }
        }
    }

    private func commit(_ entry: Entry, for request: Request, drift: TimeInterval) {
        // A newer track may have been requested while this was in flight.
        guard request == self.request else { return }
        store(entry, for: request)
        timingMayDrift = drift > 3
        apply(entry)
    }

    private func store(_ entry: Entry, for request: Request) {
        let key = Self.key(for: request)
        if cache[key] == nil {
            cacheOrder.append(key)
            if cacheOrder.count > cacheLimit {
                cache[cacheOrder.removeFirst()] = nil
            }
        }
        cache[key] = entry
    }

    private static func key(for request: Request) -> String {
        "\(request.artist.lowercased())|\(request.title.lowercased())|\(request.album.lowercased())|\(Int(request.duration.rounded()))"
    }

    private static func lookupURL(for request: Request) -> URL? {
        var components = URLComponents(string: "\(baseURL)/get")!
        var items = [
            URLQueryItem(name: "artist_name", value: request.artist),
            URLQueryItem(name: "track_name", value: request.title)
        ]
        if !request.album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: request.album))
        }
        if request.duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(request.duration.rounded()))))
        }
        components.queryItems = items
        return components.url
    }

    // MARK: Parsing

    private static func entry(from data: Data?, status: Int) -> Entry {
        guard status == 200, let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .empty
        }
        return entry(from: object)
    }

    /// Search returns an array; pick the closest duration. A remaster will not match the
    /// duration exactly, which is why the tolerance is proportional rather than a few
    /// seconds: rejecting those would defeat the purpose of the fallback. The gap is
    /// returned so the view can admit the timing may drift.
    private static func bestMatch(from data: Data?, duration: Double) -> (Entry, TimeInterval) {
        guard let data,
              let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !results.isEmpty
        else { return (.empty, 0) }

        let best = results.min { first, second in
            let a = (first["duration"] as? Double) ?? 0
            let b = (second["duration"] as? Double) ?? 0
            return abs(a - duration) < abs(b - duration)
        }

        guard let best else { return (.empty, 0) }

        let matched = (best["duration"] as? Double) ?? 0
        let drift = abs(matched - duration)
        let tolerance = max(8, duration * 0.10)
        guard drift <= tolerance else { return (.empty, 0) }

        return (entry(from: best), drift)
    }

    private static func entry(from object: [String: Any]) -> Entry {
        if object["instrumental"] as? Bool == true { return .instrumental }

        if let synced = object["syncedLyrics"] as? String {
            let parsed = parseLRC(synced)
            if !parsed.isEmpty { return .synced(parsed) }
        }

        if let plain = object["plainLyrics"] as? String, !plain.isEmpty {
            return .plain(plain)
        }

        return .empty
    }

    /// LRC: `[mm:ss.xx] text`, several timestamps per line, `[ar:]`-style metadata, and an
    /// `[offset:±ms]` tag that shifts every line.
    static func parseLRC(_ text: String) -> [LyricLine] {
        let timestamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]"#)
        let metadata = try! NSRegularExpression(pattern: #"^\[([A-Za-z]+):(.*)\]\s*$"#)
        let wordTiming = try! NSRegularExpression(pattern: #"<[^>]*>"#)

        var offset: TimeInterval = 0
        var parsed: [(TimeInterval, String)] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)

            if let match = metadata.firstMatch(in: line, range: full) {
                let key = ns.substring(with: match.range(at: 1)).lowercased()
                if key == "offset", let milliseconds = Double(ns.substring(with: match.range(at: 2))) {
                    offset = milliseconds / 1000
                }
                continue
            }

            let stamps = timestamp.matches(in: line, range: full)
            guard let last = stamps.last else { continue }

            var lyric = ns.substring(from: last.range.location + last.range.length)
            lyric = wordTiming.stringByReplacingMatches(
                in: lyric,
                range: NSRange(location: 0, length: (lyric as NSString).length),
                withTemplate: ""
            )
            lyric = lyric.trimmingCharacters(in: .whitespaces)

            for stamp in stamps {
                let minutes = Double(ns.substring(with: stamp.range(at: 1))) ?? 0
                let seconds = Double(
                    ns.substring(with: stamp.range(at: 2)).replacingOccurrences(of: ":", with: ".")
                ) ?? 0
                parsed.append((minutes * 60 + seconds, lyric))
            }
        }

        return parsed
            .sorted { $0.0 < $1.0 }
            .filter { !$0.1.isEmpty }
            .map { LyricLine(time: max(0, $0.0 - offset), text: $0.1) }
    }
}
