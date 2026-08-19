import Foundation

/// Resolves resources without depending on SwiftPM's build-directory fallback.
///
/// `Bundle.module` is correct for `swift run` and `swift test`, but its generated
/// accessor expects a resource bundle beside the development executable. A
/// standalone `.app` instead owns resources under `Contents/Resources`, so an
/// installed build must never evaluate that accessor.
enum AppResources {
    static let packageBundleName = "YTMusicCompanion_YTMusicCompanion.bundle"

    static var sourceDescription: String {
        isApplicationBundleURL(Bundle.main.bundleURL)
            ? "application bundle"
            : "SwiftPM module"
    }

    static var missingRequiredResources: [String] {
        var missing: [String] = []
        if url(forResource: "tray-icon", withExtension: "png") == nil {
            missing.append("tray-icon.png")
        }
        for identifier in ["en", "ko"] where localizationBundle(identifier) == nil {
            missing.append("\(identifier).lproj")
        }
        return missing
    }

    static func url(
        forResource name: String,
        withExtension extensionName: String?
    ) -> URL? {
        for bundle in packagedResourceBundles() {
            if let url = bundle.url(
                forResource: name,
                withExtension: extensionName
            ) {
                return url
            }
        }

        guard !isApplicationBundleURL(Bundle.main.bundleURL) else {
            return nil
        }
        return Bundle.module.url(
            forResource: name,
            withExtension: extensionName
        )
    }

    static func localizationBundle(_ identifier: String) -> Bundle? {
        for bundle in packagedResourceBundles() {
            if let path = bundle.path(
                forResource: identifier,
                ofType: "lproj"
            ), let localization = Bundle(path: path) {
                return localization
            }
        }

        guard !isApplicationBundleURL(Bundle.main.bundleURL) else {
            return nil
        }
        guard
            let path = Bundle.module.path(
                forResource: identifier,
                ofType: "lproj"
            )
        else { return nil }
        return Bundle(path: path)
    }

    static func isApplicationBundleURL(_ url: URL) -> Bool {
        url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }

    private static func packagedResourceBundles() -> [Bundle] {
        let main = Bundle.main
        guard isApplicationBundleURL(main.bundleURL) else {
            return []
        }

        var bundles = [main]
        if let resourceURL = main.resourceURL {
            let nestedURL = resourceURL.appendingPathComponent(
                packageBundleName,
                isDirectory: true
            )
            if let nested = Bundle(url: nestedURL) {
                bundles.append(nested)
            }
        }
        return bundles
    }
}
