import Foundation

/// Numeric stable releases only; never compare versions lexicographically (0.10 > 0.9).
struct ReleaseVersion: Comparable, Equatable, Sendable {
    let parts: [Int]
    init?(_ value: String) {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let components = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(components.count), components.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              components.allSatisfy({ Int($0) != nil }) else { return nil }
        parts = components.map { Int($0)! } + Array(repeating: 0, count: 3 - components.count)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

struct GitHubRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let size: Int64
        let browserDownloadURL: URL
        let digest: String?
        enum CodingKeys: String, CodingKey { case name, size, digest; case browserDownloadURL = "browser_download_url" }
        var sha256: String? {
            guard let digest, digest.hasPrefix("sha256:") else { return nil }
            let hash = String(digest.dropFirst(7)).lowercased()
            return hash.count == 64 && hash.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } ? hash : nil
        }
    }
    let tagName: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
    enum CodingKeys: String, CodingKey { case body, draft, prerelease, assets; case tagName = "tag_name" }
    static let apiURL = URL(string: "https://api.github.com/repos/stivelcn/lumate/releases/latest")!

    func isNewer(than current: String) -> Bool {
        guard !draft, !prerelease, let latest = ReleaseVersion(tagName), let current = ReleaseVersion(current) else { return false }
        return latest > current
    }

    func dmg(architecture: String) -> Asset? {
        // Prefer universal; never accidentally install the opposite architecture or a different product.
        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        for suffix in ["universal", architecture] {
            let expected = "LuMate-\(version)-\(suffix).dmg"
            if let asset = assets.first(where: { asset in
                let url = asset.browserDownloadURL
                return asset.name == expected && asset.size > 0 && asset.sha256 != nil
                    && url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil
                    && url.port == nil && url.query == nil && url.fragment == nil
                    && url.path == "/stivelcn/lumate/releases/download/\(tagName)/\(expected)"
            }) { return asset }
        }
        return nil
    }
}

enum AppUpdateError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let key): NSLocalizedString(key, comment: "software update error") }
    }
}
