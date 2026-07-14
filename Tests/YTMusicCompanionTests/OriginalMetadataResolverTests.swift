import XCTest
@testable import YTMusicCompanion

final class OriginalMetadataResolverTests: XCTestCase {
    func testChoosesJapaneseMetadataForRomanizedTitle() {
        let source = track(
            artist: "back number",
            title: "Bokuwa Kiminokotoga Sukidakedo Kimiwa Bokuo Betsuni Sukijyanaimitai",
            album: "Chandelier",
            duration: 286.7
        )
        let results: [[String: Any]] = [[
            "trackName": "僕は君の事が好きだけど君は僕を別に好きじゃないみたい",
            "artistName": "back number",
            "collectionName": "シャンデリア",
            "trackTimeMillis": 286_760,
        ]]

        let metadata = OriginalScriptMetadataResolver.chooseMetadata(
            for: source,
            from: results
        )

        XCTAssertEqual(metadata?.title, "僕は君の事が好きだけど君は僕を別に好きじゃないみたい")
        XCTAssertEqual(metadata?.artist, "back number")
        XCTAssertEqual(metadata?.album, "シャンデリア")
    }

    func testClosestDurationSelectsTheCorrectRelease() {
        let source = track(
            artist: "Yuuri",
            title: "Dried Flower",
            album: "Ichi",
            duration: 286.3
        )
        let results: [[String: Any]] = [
            [
                "trackName": "ドライフラワー",
                "artistName": "優里",
                "collectionName": "ドライフラワー - Single",
                "trackTimeMillis": 285_587,
            ],
            [
                "trackName": "ドライフラワー",
                "artistName": "優里",
                "collectionName": "壱",
                "trackTimeMillis": 286_360,
            ],
        ]

        let metadata = OriginalScriptMetadataResolver.chooseMetadata(
            for: source,
            from: results
        )

        XCTAssertEqual(metadata?.album, "壱")
    }

    func testMatchingArtistBeatsACloserCoverVersion() {
        let source = track(
            artist: "back number",
            title: "Bokuwa Kiminokotoga Sukidakedo Kimiwa Bokuo Betsuni Sukijyanaimitai",
            duration: 286.7
        )
        let results: [[String: Any]] = [
            [
                "trackName": "僕は君の事が好きだけど君は僕を別に好きじゃないみたい (Piano Ver.)",
                "artistName": "Piano Echoes",
                "collectionName": "Piano Covers",
                "trackTimeMillis": 286_700,
            ],
            [
                "trackName": "僕は君の事が好きだけど君は僕を別に好きじゃないみたい",
                "artistName": "back number",
                "collectionName": "シャンデリア",
                "trackTimeMillis": 286_760,
            ],
        ]

        let metadata = OriginalScriptMetadataResolver.chooseMetadata(
            for: source,
            from: results
        )

        XCTAssertEqual(metadata?.artist, "back number")
        XCTAssertEqual(metadata?.album, "シャンデリア")
    }

    func testRejectsUnrelatedJapaneseResult() {
        let source = track(artist: "Unknown", title: "Unknown Song", duration: 180)
        let results: [[String: Any]] = [[
            "trackName": "別の曲",
            "artistName": "別のアーティスト",
            "collectionName": "別のアルバム",
            "trackTimeMillis": 260_000,
        ]]

        XCTAssertNil(OriginalScriptMetadataResolver.chooseMetadata(for: source, from: results))
    }

    func testJapaneseStorefrontQueryUsesJapaneseResponseLanguage() throws {
        let url = try XCTUnwrap(OriginalScriptMetadataResolver.queryURL(
            for: track(artist: "Kenshi Yonezu", title: "Shunrai", duration: 288.9)
        ))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(values["country"], "JP")
        XCTAssertEqual(values["lang"], "ja_jp")
        XCTAssertEqual(values["media"], "music")
        XCTAssertEqual(values["entity"], "song")
    }

    func testApplyingMetadataPreservesLivePlaybackState() {
        let source = track(artist: "Kenshi Yonezu", title: "Shunrai", duration: 288.9)
        let resolved = source.applying(TrackMetadata(
            title: "春雷",
            artist: "米津玄師",
            album: "BOOTLEG"
        ))

        XCTAssertEqual(resolved.title, "春雷")
        XCTAssertEqual(resolved.artist, "米津玄師")
        XCTAssertEqual(resolved.duration, source.duration)
        XCTAssertEqual(resolved.elapsed, source.elapsed)
        XCTAssertEqual(resolved.timestamp, source.timestamp)
        XCTAssertEqual(resolved.sourceBundle, source.sourceBundle)
    }

    private func track(
        artist: String,
        title: String,
        album: String = "",
        duration: Double
    ) -> NowPlaying {
        NowPlaying(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            elapsed: 42,
            timestamp: 1_000,
            isPlaying: true,
            rate: 1,
            sourceBundle: "com.google.Chrome.app.cinhimbnkkaeohfgghhklpknlkffjgod",
            sourcePID: 123
        )
    }
}
