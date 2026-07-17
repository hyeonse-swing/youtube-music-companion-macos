import XCTest
@testable import YTMusicCompanion

final class AppLanguageTests: XCTestCase {
    func testExplicitLanguageDoesNotDependOnSystemPreferences() {
        XCTAssertEqual(
            AppLanguage.english.resolvedIdentifier(preferredLanguages: ["ko-KR"]),
            "en"
        )
        XCTAssertEqual(
            AppLanguage.korean.resolvedIdentifier(preferredLanguages: ["en-US"]),
            "ko"
        )
    }

    func testSystemLanguageUsesFirstSupportedMacOSPreference() {
        XCTAssertEqual(
            AppLanguage.system.resolvedIdentifier(
                preferredLanguages: ["ja-JP", "ko-KR", "en-US"]
            ),
            "ko"
        )
        XCTAssertEqual(
            AppLanguage.system.resolvedIdentifier(
                preferredLanguages: ["fr-FR", "en-GB", "ko-KR"]
            ),
            "en"
        )
    }

    func testSystemLanguageFallsBackToEnglish() {
        XCTAssertEqual(
            AppLanguage.system.resolvedIdentifier(
                preferredLanguages: ["ja-JP", "fr-FR"]
            ),
            "en"
        )
    }

    func testKoreanLocalizationLoadsFromTargetResources() {
        XCTAssertEqual(
            AppLocalization.string("Settings", language: .korean),
            "설정"
        )
        XCTAssertEqual(
            AppLocalization.format(
                "Version %@ (%@)",
                language: .korean,
                arguments: "0.15.0",
                "19"
            ),
            "버전 0.15.0 (19)"
        )
    }

    func testMissingLocalizationUsesEnglishKeyAsFallback() {
        XCTAssertEqual(
            AppLocalization.string("Untranslated test value", language: .korean),
            "Untranslated test value"
        )
    }
}
