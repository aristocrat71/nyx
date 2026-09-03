import AppKit
import Security

/// A bundle identifier is self-asserted: any process can claim one. Nyx records
/// the designated requirement of the app it was pointed at, so it can tell
/// whether the process claiming that identifier now is the same code.
enum CodeIdentity {
    /// Static checks skip per-resource hashing — this is an identity check, not
    /// an integrity audit, and hashing a large bundle stalls the UI. The flag is
    /// rejected outright by the dynamic check, which reads the kernel's record
    /// and is cheap anyway.
    private static let staticFlags = SecCSFlags(rawValue: kSecCSDoNotValidateResources)

    static func designatedRequirement(ofBundleAt url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement else { return nil }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess else { return nil }
        return text as String?
    }

    static func process(_ pid: pid_t, satisfies requirement: String) -> Bool {
        guard let parsed = parse(requirement) else { return false }
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else { return false }
        return SecCodeCheckValidity(code, [], parsed) == errSecSuccess
    }

    static func bundle(at url: URL, satisfies requirement: String) -> Bool {
        guard let parsed = parse(requirement) else { return false }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return false }
        return SecStaticCodeCheckValidity(staticCode, staticFlags, parsed) == errSecSuccess
    }

    private static func parse(_ requirement: String) -> SecRequirement? {
        var parsed: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &parsed) == errSecSuccess
        else { return nil }
        return parsed
    }
}
