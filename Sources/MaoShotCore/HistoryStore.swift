import Foundation

/// Keeps the most recent `limit` screenshots as PNG files on disk, newest first.
public final class HistoryStore {
    public let directory: URL
    public let limit: Int

    public init(directory: URL, limit: Int = 10) {
        self.directory = directory
        self.limit = limit
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MaoShot/History", isDirectory: true)
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return f
    }()

    @discardableResult
    public func add(pngData: Data, date: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory.appendingPathComponent("snap-\(Self.formatter.string(from: date)).png")
        var n = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("snap-\(Self.formatter.string(from: date))-\(n).png")
            n += 1
        }
        try pngData.write(to: url, options: .atomic)
        prune()
        return url
    }

    /// Newest first.
    public func items() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix("snap-") && $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    public func date(of url: URL) -> Date? {
        let stem = url.deletingPathExtension().lastPathComponent.dropFirst("snap-".count)
        return Self.formatter.date(from: String(stem.prefix(19)))
    }

    public func prune() {
        for url in items().dropFirst(limit) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func clear() {
        for url in items() { try? FileManager.default.removeItem(at: url) }
    }
}
