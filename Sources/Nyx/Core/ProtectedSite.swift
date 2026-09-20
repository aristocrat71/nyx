import Foundation

/// A host to cover whenever it is the browser's front tab. Stored bare — no
/// scheme, no "www.", no port — so one spelling covers every way it was typed.
struct ProtectedSite: Codable, Equatable, Identifiable {
    let host: String
    var id: String { host }

    static let maxHostLength = 253
    private static let hostScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")

    var isWellFormed: Bool {
        guard host.count >= 4, host.count <= Self.maxHostLength,
              host.contains("."), !host.hasPrefix("."), !host.hasSuffix("."),
              !host.hasPrefix("-"), !host.contains("..")
        else { return false }
        return host.unicodeScalars.allSatisfy(Self.hostScalars.contains)
    }

    /// Takes whatever the user pasted — a bare host or a whole URL — and
    /// reduces it to the stored form, or nil if nothing host-like is left.
    static func normalize(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = text.range(of: "://") { text = String(text[scheme.upperBound...]) }
        if let end = text.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            text = String(text[..<end])
        }
        if let credentials = text.lastIndex(of: "@") { text = String(text[text.index(after: credentials)...]) }
        if let port = text.firstIndex(of: ":") { text = String(text[..<port]) }
        while text.hasSuffix(".") { text.removeLast() }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        return ProtectedSite(host: text).isWellFormed ? text : nil
    }

    /// Whole labels only, so "youtube.com" covers "m.youtube.com" but never
    /// "notyoutube.com" or "youtube.com.example.net".
    func matches(host candidate: String) -> Bool {
        let candidate = Self.canonical(candidate)
        return candidate == host || candidate.hasSuffix("." + host)
    }

    private static func canonical(_ raw: String) -> String {
        var text = raw.lowercased()
        if let port = text.firstIndex(of: ":") { text = String(text[..<port]) }
        while text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// The brand label a page title is likely to carry: "youtube.com" and
    /// "bbc.co.uk" both reduce to the label left of the public suffix.
    var titleKeyword: String? {
        var labels = host.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return nil }
        labels.removeLast()
        if labels.count >= 2, labels[labels.count - 1].count <= 2 { labels.removeLast() }
        guard let keyword = labels.last, keyword.count >= 3 else { return nil }
        return keyword
    }

    /// Used only where no URL is available, which today means Firefox. Coarser
    /// than host matching by design: over-covering beats not covering at all.
    func matches(title: String) -> Bool {
        guard let keyword = titleKeyword else { return false }
        return title.lowercased().contains(keyword)
    }
}

extension Array where Element == ProtectedSite {
    func match(host: String) -> ProtectedSite? { first { $0.matches(host: host) } }
    func match(title: String) -> ProtectedSite? { first { $0.matches(title: title) } }
}
