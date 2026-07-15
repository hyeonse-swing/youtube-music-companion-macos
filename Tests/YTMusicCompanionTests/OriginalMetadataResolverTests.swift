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
            "trackId": 101,
            "trackName": "僕は君の事が好きだけど君は僕を別に好きじゃないみたい",
            "artistName": "back number",
            "collectionName": "シャンデリア",
            "trackTimeMillis": 286_760,
        ]]

        let metadata = OriginalScriptMetadataResolver.chooseVerifiedMetadata(
            for: source,
            from: results,
            localizedResultsByTrackID: [101: [localizedResult(
                id: 101,
                artist: source.artist,
                title: source.title,
                duration: source.duration
            )]]
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
                "trackId": 201,
                "trackName": "ドライフラワー",
                "artistName": "優里",
                "collectionName": "ドライフラワー - Single",
                "trackTimeMillis": 285_587,
            ],
            [
                "trackId": 202,
                "trackName": "ドライフラワー",
                "artistName": "優里",
                "collectionName": "壱",
                "trackTimeMillis": 286_360,
            ],
        ]

        let metadata = OriginalScriptMetadataResolver.chooseVerifiedMetadata(
            for: source,
            from: results,
            localizedResultsByTrackID: [
                201: [localizedResult(
                    id: 201,
                    artist: source.artist,
                    title: source.title,
                    duration: 285.587
                )],
                202: [localizedResult(
                    id: 202,
                    artist: source.artist,
                    title: source.title,
                    duration: 286.360
                )],
            ]
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
                "trackId": 301,
                "trackName": "僕は君の事が好きだけど君は僕を別に好きじゃないみたい (Piano Ver.)",
                "artistName": "Piano Echoes",
                "collectionName": "Piano Covers",
                "trackTimeMillis": 286_700,
            ],
            [
                "trackId": 302,
                "trackName": "僕は君の事が好きだけど君は僕を別に好きじゃないみたい",
                "artistName": "back number",
                "collectionName": "シャンデリア",
                "trackTimeMillis": 286_760,
            ],
        ]

        let metadata = OriginalScriptMetadataResolver.chooseVerifiedMetadata(
            for: source,
            from: results,
            localizedResultsByTrackID: [
                301: [localizedResult(
                    id: 301,
                    artist: "Piano Echoes",
                    title: "Piano Cover",
                    duration: source.duration
                )],
                302: [localizedResult(
                    id: 302,
                    artist: source.artist,
                    title: source.title,
                    duration: source.duration
                )],
            ]
        )

        XCTAssertEqual(metadata?.artist, "back number")
        XCTAssertEqual(metadata?.album, "シャンデリア")
    }

    func testRejectsUnrelatedJapaneseResult() {
        let source = track(artist: "Unknown", title: "Unknown Song", duration: 180)
        let results: [[String: Any]] = [[
            "trackId": 401,
            "trackName": "別の曲",
            "artistName": "別のアーティスト",
            "collectionName": "別のアルバム",
            "trackTimeMillis": 260_000,
        ]]

        XCTAssertNil(OriginalScriptMetadataResolver.chooseVerifiedMetadata(
            for: source,
            from: results,
            localizedResultsByTrackID: [401: [localizedResult(
                id: 401,
                artist: "Different Artist",
                title: "Different Song",
                duration: 260
            )]]
        ))
    }

    func testRejectsDurationOnlySearchHitWhenCatalogIdentityDoesNotMatchSource() {
        let source = track(artist: "Aimer", title: "Ref:rain", duration: 290)
        let japaneseResults: [[String: Any]] = [[
            "trackId": 501,
            "trackName": "別の曲",
            "artistName": "別の歌手",
            "collectionName": "別のアルバム",
            "trackTimeMillis": 290_000,
        ]]

        let metadata = OriginalScriptMetadataResolver.chooseVerifiedMetadata(
            for: source,
            from: japaneseResults,
            localizedResultsByTrackID: [501: [localizedResult(
                id: 501,
                artist: "Different Artist",
                title: "Different Song",
                duration: 290
            )]]
        )

        XCTAssertNil(metadata)
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

    func testLookupUsesSameTrackIDInEnglishUSStorefront() throws {
        let url = try XCTUnwrap(OriginalScriptMetadataResolver.lookupURL(trackID: 1623304209))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(values["id"], "1623304209")
        XCTAssertEqual(values["country"], "US")
        XCTAssertEqual(values["lang"], "en_us")
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

    private func localizedResult(
        id: Int64,
        artist: String,
        title: String,
        duration: Double
    ) -> [String: Any] {
        [
            "trackId": id,
            "artistName": artist,
            "trackName": title,
            "trackTimeMillis": duration * 1_000,
        ]
    }
}
