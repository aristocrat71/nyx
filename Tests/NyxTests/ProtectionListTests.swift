import Carbon.HIToolbox
import Foundation
import Testing
@testable import Nyx

@Suite("protected.json decoding")
struct ProtectionListDecodingTests {
    private func decode(_ json: String) -> ProtectionList.Loaded {
        ProtectionList.decode(Data(json.utf8))
    }

    @Test func wellFormedFileLoads() {
        let result = decode("""
        {"apps":[{"bundleID":"com.apple.TextEdit","name":"TextEdit"}],
         "hotkey":{"keyCode":37,"carbonModifiers":4608},
         "protectionEnabled":true}
        """)
        #expect(!result.failed)
        #expect(result.apps.map(\.bundleID) == ["com.apple.TextEdit"])
        #expect(result.hotkey == HotkeySpec(keyCode: 37, carbonModifiers: 4608))
        #expect(result.droppedApps == 0)
    }

    @Test(arguments: ["", "{", "null", "[]", #"{"apps":"not an array"}"#, #"{"hotkey":{}}"#])
    func unparseableFileIsReportedRatherThanSilentlyEmpty(json: String) {
        #expect(decode(json).failed)
    }

    @Test func malformedEntriesAreDroppedWithoutLosingTheGoodOnes() {
        let result = decode("""
        {"apps":[{"bundleID":"com.apple.TextEdit","name":"TextEdit"},
                 {"bundleID":"../../etc/passwd","name":"traversal"},
                 {"bundleID":"","name":"empty"},
                 {"bundleID":"com.evil/../x","name":"slash"},
                 {"bundleID":"com.a b","name":"space"}]}
        """)
        #expect(!result.failed)
        #expect(result.apps.map(\.bundleID) == ["com.apple.TextEdit"])
        #expect(result.droppedApps == 4)
    }

    @Test func overlongFieldsAreRejected() {
        let longID = String(repeating: "a", count: 256)
        let longName = String(repeating: "b", count: 129)
        let result = decode("""
        {"apps":[{"bundleID":"\(longID)","name":"ok"},
                 {"bundleID":"com.ok.app","name":"\(longName)"}]}
        """)
        #expect(result.apps.isEmpty)
        #expect(result.droppedApps == 2)
    }

    @Test func appCountIsCapped() {
        let entries = (0..<500).map { #"{"bundleID":"com.app.n\#($0)","name":"n"}"# }.joined(separator: ",")
        let result = decode(#"{"apps":[\#(entries)]}"#)
        #expect(result.apps.count == 200)
        #expect(result.droppedApps == 300)
    }

    /// M3: a file must not be able to assert "protection off" for the next
    /// launch, so the field is never read back.
    @Test func storedProtectionOffIsNotHonoured() {
        let result = decode(#"{"apps":[],"protectionEnabled":false}"#)
        #expect(!result.failed)
        #expect(result == ProtectionList.Loaded())
    }

    @Test(arguments: [
        #"{"keyCode":99999,"carbonModifiers":4608}"#,    // not a virtual key code
        #"{"keyCode":37,"carbonModifiers":0}"#,          // no modifiers: a bare key
        #"{"keyCode":37,"carbonModifiers":512}"#,        // shift alone
        #"{"keyCode":37,"carbonModifiers":4294967295}"#, // undefined modifier bits
    ])
    func hostileHotkeyFallsBackToTheDefault(hotkey: String) {
        let result = decode(#"{"apps":[],"hotkey":\#(hotkey)}"#)
        #expect(result.rejectedHotkey)
        #expect(result.hotkey == HotkeySpec.standard)
    }

    @Test(arguments: [cmdKey, controlKey, optionKey, cmdKey | shiftKey, controlKey | shiftKey])
    func realModifierCombinationsAreAccepted(modifiers: Int) {
        #expect(HotkeySpec(keyCode: 37, carbonModifiers: UInt32(modifiers)).isWellFormed)
    }

    @Test func defaultHotkeyIsWellFormed() {
        #expect(HotkeySpec.standard.isWellFormed)
    }

    @Test func pinnedRequirementSurvivesARoundTrip() {
        let result = decode("""
        {"apps":[{"bundleID":"com.apple.TextEdit","name":"TextEdit",
                  "requirement":"identifier \\"com.apple.TextEdit\\" and anchor apple"}]}
        """)
        #expect(result.apps.first?.requirement == #"identifier "com.apple.TextEdit" and anchor apple"#)
    }

    @Test func overlongRequirementIsRejected() {
        let long = String(repeating: "x", count: 2049)
        let result = decode(#"{"apps":[{"bundleID":"com.ok.app","name":"n","requirement":"\#(long)"}]}"#)
        #expect(result.apps.isEmpty)
    }

    /// Files written before site rules existed carry no "sites" key at all.
    @Test func aFileWithoutSitesStillLoads() {
        let result = decode(#"{"apps":[{"bundleID":"com.apple.TextEdit","name":"TextEdit"}]}"#)
        #expect(!result.failed)
        #expect(result.sites.isEmpty)
        #expect(result.droppedSites == 0)
    }

    @Test func sitesRoundTripAndMalformedOnesAreDropped() {
        let result = decode("""
        {"apps":[],"sites":[{"host":"youtube.com"},{"host":"news.ycombinator.com"},
                            {"host":"UPPER.com"},{"host":"localhost"},{"host":""},
                            {"host":"a b.com"},{"host":"you/tube.com"},{"host":".com"}]}
        """)
        #expect(!result.failed)
        #expect(result.sites.map(\.host) == ["youtube.com", "news.ycombinator.com"])
        #expect(result.droppedSites == 6)
    }

    @Test func siteCountIsCapped() {
        let entries = (0..<500).map { #"{"host":"n\#($0).example.com"}"# }.joined(separator: ",")
        let result = decode(#"{"apps":[],"sites":[\#(entries)]}"#)
        #expect(result.sites.count == 200)
        #expect(result.droppedSites == 300)
    }
}

@Suite("Code identity pinning")
struct CodeIdentityTests {
    private let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
    private let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")

    @Test func designatedRequirementIsReadFromASystemBundle() throws {
        let requirement = try #require(CodeIdentity.designatedRequirement(ofBundleAt: textEdit))
        #expect(requirement.contains(#"identifier "com.apple.TextEdit""#))
    }

    @Test func aBundleSatisfiesItsOwnRequirementAndNotAnother() throws {
        let requirement = try #require(CodeIdentity.designatedRequirement(ofBundleAt: textEdit))
        #expect(CodeIdentity.bundle(at: textEdit, satisfies: requirement))
        #expect(!CodeIdentity.bundle(at: finder, satisfies: requirement))
    }

    @Test func anImpostorProcessDoesNotSatisfyAPinnedRequirement() throws {
        let requirement = try #require(CodeIdentity.designatedRequirement(ofBundleAt: textEdit))
        #expect(!CodeIdentity.process(ProcessInfo.processInfo.processIdentifier, satisfies: requirement))
    }

    /// Guards the flag mistake that made every live check fail: the dynamic API
    /// rejects kSecCSDoNotValidateResources, which reads as "not the same app".
    @Test func aLiveProcessSatisfiesItsOwnRequirement() throws {
        let executable = URL(fileURLWithPath: "/bin/cat")
        let requirement = try #require(CodeIdentity.designatedRequirement(ofBundleAt: executable))

        let process = Process()
        process.executableURL = executable
        process.standardInput = Pipe()
        process.standardOutput = Pipe()
        try process.run()
        defer { process.terminate() }

        #expect(CodeIdentity.process(process.processIdentifier, satisfies: requirement))
        #expect(!CodeIdentity.process(
            process.processIdentifier,
            satisfies: #"identifier "com.apple.TextEdit" and anchor apple"#
        ))
    }

    @Test func garbageRequirementIsRejectedRatherThanTrusted() {
        #expect(!CodeIdentity.bundle(at: textEdit, satisfies: "not a requirement ((("))
        #expect(!CodeIdentity.process(
            ProcessInfo.processInfo.processIdentifier, satisfies: "not a requirement ((("
        ))
    }
}
