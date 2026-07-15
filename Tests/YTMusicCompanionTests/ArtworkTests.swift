import XCTest
@testable import YTMusicCompanion

/// Pure-helper tests for the iTunes cover resolver. The network call (`coverURL`) is
/// not exercised here — only the deterministic matching/normalization logic.
final class ArtworkTests: XCTestCase {

    // MARK: - normalizeSearchTerm

    func testNormalizeStripsDiacriticsAndPunctuation() {
        XCTAssertEqual(Artwork.normalizeSearchTerm("Café del Mar!"), "cafe del mar")
        XCTAssertEqual(Artwork.normalizeSearchTerm("Beyoncé"), "beyonce")
    }

    func testNormalizeCollapsesWhitespaceAndLowercases() {
        XCTAssertEqual(Artwork.normalizeSearchTerm("  Hello   WORLD  "), "hello world")
    }

    func testNormalizeTurnsPunctuationIntoSpaces() {
        // Punctuation becomes a separator, not a deletion — words stay split.
        XCTAssertEqual(Artwork.normalizeSearchTerm("Up&Down"), "up down")
    }

    func testNormalizePreservesJapaneseVoicingMarks() {
        XCTAssertEqual(Artwork.normalizeSearchTerm("パレード ヨルシカ"), "パレード ヨルシカ")
    }

    // MARK: - primaryArtist (consolidated lead-artist extractor, shared with lyrics)

    func testGetFirstArtistSplitsOnFeat() {
        XCTAssertEqual(LRCLIB.primaryArtist("A feat. B"), "A")
        XCTAssertEqual(LRCLIB.primaryArtist("A ft. B"), "A")
        XCTAssertEqual(LRCLIB.primaryArtist("A featuring B"), "A")
    }

    func testGetFirstArtistSplitsOnSeparators() {
        XCTAssertEqual(LRCLIB.primaryArtist("A, B"), "A")
        XCTAssertEqual(LRCLIB.primaryArtist("A & B"), "A")
        XCTAssertEqual(LRCLIB.primaryArtist("A x B"), "A")
    }

    func testGetFirstArtistKeepsSoloName() {
        XCTAssertEqual(LRCLIB.primaryArtist("Florence"), "Florence")
    }

    // MARK: - matchesResult

    func testMatchesExactArtistAndTitle() {
        XCTAssertTrue(Artwork.matchesResult(
            artist: "YOUHA", title: "Last Dance",
            resultArtist: "YOUHA", resultTitle: "Last Dance"))
    }

    func testMatchesWhenResultArtistContainsOurs() {
        // Our credit is the lead act; the result lists the full collaboration.
        XCTAssertTrue(Artwork.matchesResult(
            artist: "YOUHA", title: "Last Dance",
            resultArtist: "YOUHA feat. Someone", resultTitle: "Last Dance"))
    }

    func testMatchesOnSharedLongWord() {
        XCTAssertTrue(Artwork.matchesResult(
            artist: "The Beatles", title: "Hey Jude",
            resultArtist: "Beatles", resultTitle: "Hey Jude (Remastered)"))
    }

    func testRejectsWrongArtist() {
        XCTAssertFalse(Artwork.matchesResult(
            artist: "Adele", title: "Hello",
            resultArtist: "Lionel Richie", resultTitle: "Hello"))
    }

    func testRejectsWrongTitle() {
        XCTAssertFalse(Artwork.matchesResult(
            artist: "Adele", title: "Hello",
            resultArtist: "Adele", resultTitle: "Skyfall"))
    }

    func testRejectsResultThatOnlySharesOneGenericWord() {
        XCTAssertFalse(Artwork.matchesResult(
            artist: "Blue Archive", title: "Madder",
            resultArtist: "Archive Project", resultTitle: "Madder Than Ever"))
    }

}
