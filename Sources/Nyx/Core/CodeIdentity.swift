import AppKit
import Security

/// A bundle identifier is self-asserted, so Nyx pins the designated requirement
/// of the app it was pointed at and checks later claimants against it.
enum CodeIdentity {
    /// An identity check, not an integrity audit: hashing every resource of a
    /// large bundle stalls the UI, and the dynamic check rejects the flag anyway.
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
