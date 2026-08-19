import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case korean = "ko"

    var id: String { rawValue }

    var nativeDisplayName: String {
        switch self {
        case .system:
            "System Default"
        case .english:
            "English"
        case .korean:
            "한국어"
        }
    }

    var resolvedIdentifier: String {
        resolvedIdentifier(preferredLanguages: Locale.preferredLanguages)
    }

    var locale: Locale {
        Locale(identifier: resolvedIdentifier)
    }

    func resolvedIdentifier(preferredLanguages: [String]) -> String {
        guard self == .system else { return rawValue }

        for identifier in preferredLanguages {
            let normalized = identifier
                .replacingOccurrences(of: "_", with: "-")
                .lowercased()
            if normalized == "ko" || normalized.hasPrefix("ko-") {
                return AppLanguage.korean.rawValue
            }
            if normalized == "en" || normalized.hasPrefix("en-") {
                return AppLanguage.english.rawValue
            }
        }
        return AppLanguage.english.rawValue
    }
}

enum AppLocalization {
    static func string(
        _ key: String,
        language: AppLanguage,
        value: String? = nil
    ) -> String {
        let identifier = language.resolvedIdentifier
        guard
            let bundle = AppResources.localizationBundle(identifier)
        else {
            return value ?? key
        }
        return bundle.localizedString(
            forKey: key,
            value: value ?? key,
            table: nil
        )
    }

    static func format(
        _ key: String,
        language: AppLanguage,
        arguments: CVarArg...
    ) -> String {
        String(
            format: string(key, language: language),
            locale: language.locale,
            arguments: arguments
        )
    }
}
