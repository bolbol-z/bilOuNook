import Foundation

struct NowPlayingSnapshot: Equatable {
    var title: String
    var artist: String
    var album: String
    var artwork: Data? {
        didSet { artworkDigest = Self.digest(of: artwork) }
    }
    private(set) var artworkDigest: Int
    var artworkMimeType: String?
    var isPlaying: Bool
    var elapsed: TimeInterval
    var duration: TimeInterval
    var bundleIdentifier: String?
    var parentApplicationBundleIdentifier: String?
    var updatedAt: Date
    var sourceTimestamp: Date?
    var playbackRate: Double?

    init(
        title: String = "",
        artist: String = "",
        album: String = "",
        artwork: Data? = nil,
        artworkMimeType: String? = nil,
        isPlaying: Bool = false,
        elapsed: TimeInterval = 0,
        duration: TimeInterval = 0,
        bundleIdentifier: String? = nil,
        parentApplicationBundleIdentifier: String? = nil,
        updatedAt: Date = Date(),
        sourceTimestamp: Date? = nil,
        playbackRate: Double? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.artworkDigest = Self.digest(of: artwork)
        self.artworkMimeType = artworkMimeType
        self.isPlaying = isPlaying
        self.elapsed = elapsed
        self.duration = duration
        self.bundleIdentifier = bundleIdentifier
        self.parentApplicationBundleIdentifier = parentApplicationBundleIdentifier
        self.updatedAt = updatedAt
        self.sourceTimestamp = sourceTimestamp
        self.playbackRate = playbackRate
    }

    /// Elapsed as of `date`. While playing, extrapolates the snapshot's
    /// as-of timestamp by its playback rate (the adapter emits raw
    /// `elapsedTime` plus `playbackRate`/`timestampEpochMicros`); paused
    /// snapshots never extrapolate.
    func elapsedNow(at date: Date) -> TimeInterval {
        guard isPlaying else { return elapsed }
        let anchor = sourceTimestamp ?? updatedAt
        let age = max(0, date.timeIntervalSince(anchor))
        guard age > 0 else { return duration > 0 ? min(elapsed, duration) : elapsed }
        let rawRate = playbackRate ?? 1
        let rate = rawRate.isFinite && rawRate >= 0 ? rawRate : 1
        let raw = elapsed + age * rate
        return duration > 0 ? min(raw, duration) : raw
    }

    static func == (lhs: NowPlayingSnapshot, rhs: NowPlayingSnapshot) -> Bool {
        lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && (lhs.artwork?.count ?? 0) == (rhs.artwork?.count ?? 0)
            && lhs.artworkDigest == rhs.artworkDigest
            && lhs.artworkMimeType == rhs.artworkMimeType
            && lhs.isPlaying == rhs.isPlaying
            && lhs.elapsed == rhs.elapsed
            && lhs.duration == rhs.duration
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.parentApplicationBundleIdentifier == rhs.parentApplicationBundleIdentifier
            && lhs.updatedAt == rhs.updatedAt
            && lhs.sourceTimestamp == rhs.sourceTimestamp
            && lhs.playbackRate == rhs.playbackRate
    }

    private static func digest(of data: Data?) -> Int {
        guard let data else { return 0 }
        var hash = 5381
        for byte in data {
            hash = (hash &* 33) &+ Int(byte)
        }
        return hash
    }

    var hasContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var sourceBundleIdentifier: String {
        let parent = parentApplicationBundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !parent.isEmpty { return parent }
        return bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var trackIdentity: String {
        [sourceBundleIdentifier, title, artist, album].joined(separator: "\u{1F}")
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }
}
