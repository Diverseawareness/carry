import SwiftUI
import UIKit

/// App-wide in-memory image cache for profile photos.
/// First fetch downloads from URL; subsequent fetches return instantly from NSCache.
/// Cache is per-session (cleared on app termination, not persisted to disk).
actor ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    /// Track in-flight downloads so multiple views requesting the same URL don't
    /// fire duplicate network requests.
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        // Allow up to ~50MB of cached images
        cache.totalCostLimit = 50 * 1024 * 1024
    }

    /// Returns a cached image immediately, or nil if not yet cached.
    func get(_ urlString: String) -> UIImage? {
        cache.object(forKey: urlString as NSString)
    }

    /// Fetches the image from cache or network. Returns nil on failure.
    func fetch(_ urlString: String) async -> UIImage? {
        // 1. Check cache
        if let cached = cache.object(forKey: urlString as NSString) {
            return cached
        }

        // 2. Join an in-flight request if one exists
        if let existing = inFlight[urlString] {
            return await existing.value
        }

        // 3. Start a new download
        let task = Task<UIImage?, Never> {
            guard let url = URL(string: urlString),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else {
                return nil
            }
            let cost = data.count
            cache.setObject(image, forKey: urlString as NSString, cost: cost)
            return image
        }
        inFlight[urlString] = task

        let result = await task.value

        inFlight.removeValue(forKey: urlString)

        return result
    }

    /// Pre-warm the cache for a batch of URLs (e.g. all players in a round).
    nonisolated func prefetch(_ urlStrings: [String]) {
        for urlString in urlStrings {
            Task { _ = await fetch(urlString) }
        }
    }
}
