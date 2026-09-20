import Foundation
import Testing
@testable import Nyx

@Suite("site rule normalisation")
struct ProtectedSiteNormalisationTests {
    @Test(arguments: [
        ("youtube.com", "youtube.com"),
        ("  YouTube.com  ", "youtube.com"),
        ("www.youtube.com", "youtube.com"),
        ("https://www.youtube.com/watch?v=abc", "youtube.com"),
        ("http://m.youtube.com", "m.youtube.com"),
        ("youtube.com.", "youtube.com"),
        ("youtube.com:8443", "youtube.com"),
        ("https://user:pass@youtube.com/x", "youtube.com"),
        ("https://news.ycombinator.com/item?id=1#c", "news.ycombinator.com"),
        ("bbc.co.uk", "bbc.co.uk"),
        ("youtube.com/../etc", "youtube.com"),
    ])
    func acceptedInputsReduceToABareHost(input: String, expected: String) {
        #expect(ProtectedSite.normalize(input) == expected)
    }

    @Test(arguments: ["", "   ", "localhost", "youtube", ".com", "youtube..com", "-youtube.com",
                      "you tube.com", "https://", "a.b", "café.com"])
    func inputsWithoutAUsableHostAreRejected(input: String) {
        #expect(ProtectedSite.normalize(input) == nil)
    }

    @Test func overlongHostsAreRejected() {
        let long = String(repeating: "a", count: 250) + ".com"
        #expect(ProtectedSite.normalize(long) == nil)
    }
}

@Suite("site rule matching")
struct ProtectedSiteMatchingTests {
    private let youtube = ProtectedSite(host: "youtube.com")

    @Test(arguments: ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
                      "YouTube.com", "youtube.com.", "youtube.com:443"])
    func theHostAndItsSubdomainsMatch(candidate: String) {
        #expect(youtube.matches(host: candidate))
    }

    /// The whole point of matching on labels: a look-alike host must not be
    /// treated as the real one, in either direction.
    @Test(arguments: ["notyoutube.com", "youtube.com.example.net", "myyoutube.com",
                      "youtube.co", "example.com", "xyoutube.com"])
    func lookAlikeHostsDoNotMatch(candidate: String) {
        #expect(!youtube.matches(host: candidate))
    }

    @Test func deeperRulesDoNotLeakUpwards() {
        let mail = ProtectedSite(host: "mail.google.com")
        #expect(mail.matches(host: "mail.google.com"))
        #expect(!mail.matches(host: "google.com"))
        #expect(!mail.matches(host: "docs.google.com"))
    }

    @Test(arguments: [("youtube.com", "youtube"), ("bbc.co.uk", "bbc"),
                      ("news.ycombinator.com", "ycombinator"), ("web.whatsapp.com", "whatsapp")])
    func theTitleKeywordIsTheLabelLeftOfThePublicSuffix(host: String, keyword: String) {
        #expect(ProtectedSite(host: host).titleKeyword == keyword)
    }

    @Test func aTooShortKeywordIsNotUsedForTitleMatching() {
        #expect(ProtectedSite(host: "x.com").titleKeyword == nil)
        #expect(!ProtectedSite(host: "x.com").matches(title: "Extra — Box of things"))
    }

    @Test func titlesMatchOnTheBrandLabel() {
        #expect(youtube.matches(title: "Some video - YouTube"))
        #expect(youtube.matches(title: "youtube"))
        #expect(!youtube.matches(title: "Inbox (3) - Mail"))
    }

    @Test func theFirstMatchingRuleIsReported() {
        let sites = [ProtectedSite(host: "example.com"), youtube]
        #expect(sites.match(host: "m.youtube.com") == youtube)
        #expect(sites.match(host: "unrelated.net") == nil)
        #expect(sites.match(title: "Clip — YouTube") == youtube)
    }
}
