import Foundation

extension Bundle {
    // SwiftPM's generated `Bundle.module` looks for Nyx_Nyx.bundle beside Bundle.main.bundleURL,
    // which inside an .app is the bundle root — where codesign refuses to seal it.
    static let nyxResources: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Nyx_Nyx.bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        // swift run and the test bundle, where main's resources are the build directory itself.
        return .module
    }()
}
