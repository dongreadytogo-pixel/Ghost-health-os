import XCTest
import GhostlyCore
import GhostlyDomain
@testable import GhostlyFCPXML

final class FCPXMLTests: XCTestCase {
    // MARK: Fixtures

    private func fixtureLibrary() -> (Library, Asset, Asset) {
        let video = Asset(name: "Interview", url: URL(string: "file:///media/interview.mov")!,
                          duration: RationalTime(seconds: 120), kind: .video, format: .hd1080p30)
        let music = Asset(name: "Theme", url: URL(string: "file:///media/theme.wav")!,
                          duration: RationalTime(seconds: 180), kind: .audio)

        var timeline = Timeline(name: "Main Cut", format: .hd1080p30)
        timeline.appendToStoryline(assetID: video.id, name: "Opening",
            sourceRange: TimeRange(start: RationalTime(seconds: 10), duration: RationalTime(seconds: 5)))
        timeline.appendToStoryline(assetID: video.id, name: "Detail",
            sourceRange: TimeRange(start: RationalTime(seconds: 40), duration: RationalTime(seconds: 4)))
        timeline.transitions.append(.crossDissolve(offset: RationalTime(seconds: 5),
                                                   duration: RationalTime(seconds: 1)))
        timeline.clips.append(Clip(assetID: music.id, name: "Music",
                                   offset: .zero,
                                   sourceRange: TimeRange(start: .zero, duration: RationalTime(seconds: 9)),
                                   lane: -1, role: .music))
        timeline.captions.append(Caption(text: "Welcome back!",
            range: TimeRange(start: RationalTime(seconds: 1), duration: RationalTime(seconds: 2))))
        timeline.markers.append(Marker(start: RationalTime(seconds: 6), text: "beat drop", kind: .chapter))

        let project = Project(name: "Episode 12", timeline: timeline)
        let library = Library(name: "Show", events: [
            Event(name: "Episodes", projects: [project], assets: [video, music]),
        ])
        return (library, video, music)
    }

    // MARK: Writer

    func testGeneratedDocumentShape() throws {
        let (library, _, _) = fixtureLibrary()
        let doc = try FCPXMLWriter().document(for: library)

        XCTAssertTrue(doc.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE fcpxml>"))
        XCTAssertTrue(doc.contains("<fcpxml version=\"1.11\">"))
        XCTAssertTrue(doc.contains("frameDuration=\"1/30s\""))
        XCTAssertTrue(doc.contains("<asset-clip"))
        XCTAssertTrue(doc.contains("<transition"))
        XCTAssertTrue(doc.contains("Welcome back!"))
        XCTAssertTrue(doc.contains("value=\"beat drop\""))
        XCTAssertTrue(doc.contains("lane=\"-1\""))
    }

    func testGeneratedDocumentIsDeterministic() throws {
        let (library, _, _) = fixtureLibrary()
        let a = try FCPXMLWriter().document(for: library)
        let b = try FCPXMLWriter().document(for: library)
        XCTAssertEqual(a, b)
    }

    func testGeneratedDocumentPassesValidator() throws {
        let (library, _, _) = fixtureLibrary()
        let doc = try FCPXMLWriter().document(for: library)
        let issues = FCPXMLValidator().validate(doc)
        XCTAssertTrue(issues.filter { $0.severity == .error }.isEmpty,
                      "unexpected errors: \(issues)")
    }

    func testWriterInsertsGapForStorylineHole() throws {
        let video = Asset(name: "V", url: URL(string: "file:///v.mov")!,
                          duration: RationalTime(seconds: 60), kind: .video, format: .hd1080p30)
        var timeline = Timeline(name: "Gappy", format: .hd1080p30)
        timeline.clips = [
            Clip(assetID: video.id, name: "A", offset: RationalTime(seconds: 2),
                 sourceRange: TimeRange(start: .zero, duration: RationalTime(seconds: 3))),
        ]
        let project = Project(name: "P", timeline: timeline)
        let doc = try FCPXMLWriter().document(for: project, assets: [video])
        XCTAssertTrue(doc.contains("<gap"))
        XCTAssertTrue(FCPXMLValidator().isAcceptable(doc), "\(FCPXMLValidator().validate(doc))")
    }

    func testWriterEscapesXMLSpecials() throws {
        let video = Asset(name: "Cats & <Dogs>", url: URL(string: "file:///v.mov")!,
                          duration: RationalTime(seconds: 60), kind: .video, format: .hd1080p30)
        var timeline = Timeline(name: "Esc", format: .hd1080p30)
        timeline.appendToStoryline(assetID: video.id, name: "Cats & <Dogs>",
            sourceRange: TimeRange(start: .zero, duration: RationalTime(seconds: 1)))
        timeline.captions.append(Caption(text: "a < b & c > d",
            range: TimeRange(start: .zero, duration: RationalTime(seconds: 1))))
        let doc = try FCPXMLWriter().document(for: Project(name: "P", timeline: timeline), assets: [video])
        XCTAssertFalse(doc.contains("Cats & <Dogs>"))
        XCTAssertTrue(doc.contains("Cats &amp; &lt;Dogs&gt;"))
        // Must still parse as XML.
        XCTAssertNoThrow(try XMLDocumentParser.parse(doc))
    }

    func testMissingAssetThrows() {
        var timeline = Timeline(name: "Broken", format: .hd1080p30)
        timeline.appendToStoryline(assetID: AssetID("nope"), name: "X",
            sourceRange: TimeRange(start: .zero, duration: RationalTime(seconds: 1)))
        XCTAssertThrowsError(try FCPXMLWriter().document(
            for: Project(name: "P", timeline: timeline), assets: [])) { error in
            guard case StudioError.notFound = error else {
                return XCTFail("expected notFound, got \(error)")
            }
        }
    }

    func testWriterEmitsTitleElement() throws {
        let video = Asset(name: "V", url: URL(string: "file:///v.mov")!,
                          duration: RationalTime(seconds: 60), kind: .video, format: .hd1080p30)
        var timeline = Timeline(name: "Titled", format: .hd1080p30)
        timeline.appendToStoryline(assetID: video.id, name: "A",
            sourceRange: TimeRange(start: .zero, duration: RationalTime(seconds: 10)))
        timeline.titles = [
            MotionTitle(text: "Hello World",
                        range: TimeRange(start: RationalTime(seconds: 2),
                                         duration: RationalTime(seconds: 3)),
                        lane: 2, kind: .titleCard),
        ]
        let doc = try FCPXMLWriter().document(
            for: Project(name: "P", timeline: timeline), assets: [video])

        XCTAssertTrue(doc.contains("<title"))
        XCTAssertTrue(doc.contains("Hello World"))
        XCTAssertTrue(doc.contains("<effect"), "title must register a Motion template effect resource")
        // Title anchored at timeline 2s inside clip A (offset 0, in-point 0) → source 2s.
        XCTAssertTrue(doc.contains("offset=\"2s\""))
        XCTAssertTrue(FCPXMLValidator().isAcceptable(doc), "\(FCPXMLValidator().validate(doc))")
    }

    func testThaiCaptionRoleLanguageRoundTrip() throws {
        let video = Asset(name: "V", url: URL(string: "file:///v.mov")!,
                          duration: RationalTime(seconds: 60), kind: .video, format: .hd1080p30)
        var timeline = Timeline(name: "Thai", format: .hd1080p30)
        timeline.appendToStoryline(assetID: video.id, name: "A",
            sourceRange: TimeRange(start: .zero, duration: RationalTime(seconds: 10)))
        timeline.captions.append(Caption(
            text: "สวัสดีครับ",
            range: TimeRange(start: RationalTime(seconds: 1), duration: RationalTime(seconds: 2)),
            format: .itt, language: "th"))

        let doc = try FCPXMLWriter().document(
            for: Project(name: "P", timeline: timeline), assets: [video])
        XCTAssertTrue(doc.contains("captionFormat=ITT.th"), "Thai caption role must be tagged .th")
        XCTAssertTrue(doc.contains("สวัสดีครับ"))
        XCTAssertTrue(FCPXMLValidator().isAcceptable(doc), "\(FCPXMLValidator().validate(doc))")

        let parsed = try FCPXMLReader().library(from: doc)
        let caption = try XCTUnwrap(parsed.events.first?.projects.first?.timeline.captions.first)
        XCTAssertEqual(caption.language, "th")
        XCTAssertEqual(caption.text, "สวัสดีครับ")
    }

    // MARK: Round trip

    func testRoundTripPreservesStructure() throws {
        let (library, _, _) = fixtureLibrary()
        let doc = try FCPXMLWriter().document(for: library)
        let parsed = try FCPXMLReader().library(from: doc)

        XCTAssertEqual(parsed.events.count, 1)
        let project = try XCTUnwrap(parsed.events.first?.projects.first)
        XCTAssertEqual(project.name, "Episode 12")

        let timeline = project.timeline
        XCTAssertEqual(timeline.storyline.map(\.name), ["Opening", "Detail"])
        XCTAssertEqual(timeline.storyline[0].sourceRange.start.seconds, 10)
        XCTAssertEqual(timeline.storyline[1].offset.seconds, 5)
        XCTAssertEqual(timeline.format.frameRate, .fps30)

        // Connected music clip restored to timeline coordinates.
        let music = try XCTUnwrap(timeline.connectedClips.first)
        XCTAssertEqual(music.lane, -1)
        XCTAssertEqual(music.offset.seconds, 0)
        XCTAssertEqual(music.role.name, "music")

        // Caption and chapter marker restored at their timeline positions.
        XCTAssertEqual(timeline.captions.count, 1)
        XCTAssertEqual(timeline.captions[0].text, "Welcome back!")
        XCTAssertEqual(timeline.captions[0].range.start.seconds, 1)
        XCTAssertEqual(timeline.markers.count, 1)
        XCTAssertEqual(timeline.markers[0].start.seconds, 6)

        // Transition center restored.
        XCTAssertEqual(timeline.transitions.count, 1)
        XCTAssertEqual(timeline.transitions[0].offset.seconds, 5)
    }

    func testRoundTripSourceTimeConversionForNonZeroInPoint() throws {
        // Caption at timeline 7s sits inside clip B (offset 5s, in-point 40s):
        // local position must be 42s in the document, then 7s again after parse.
        let video = Asset(name: "V", url: URL(string: "file:///v.mov")!,
                          duration: RationalTime(seconds: 120), kind: .video, format: .hd1080p30)
        var timeline = Timeline(name: "T", format: .hd1080p30)
        timeline.appendToStoryline(assetID: video.id, name: "A",
            sourceRange: TimeRange(start: .zero, duration: RationalTime(seconds: 5)))
        timeline.appendToStoryline(assetID: video.id, name: "B",
            sourceRange: TimeRange(start: RationalTime(seconds: 40), duration: RationalTime(seconds: 5)))
        timeline.captions.append(Caption(text: "inside B",
            range: TimeRange(start: RationalTime(seconds: 7), duration: RationalTime(seconds: 1))))

        let doc = try FCPXMLWriter().document(for: Project(name: "P", timeline: timeline), assets: [video])
        XCTAssertTrue(doc.contains("offset=\"42s\""), "caption must be written in source time")

        let parsed = try FCPXMLReader().library(from: doc)
        let caption = try XCTUnwrap(parsed.events.first?.projects.first?.timeline.captions.first)
        XCTAssertEqual(caption.range.start.seconds, 7, accuracy: 1e-9)
    }

    // MARK: Validator

    func testValidatorFlagsUndefinedReference() {
        let doc = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.11">
            <resources>
                <format id="r1" frameDuration="1/30s" width="1920" height="1080"/>
            </resources>
            <library>
                <event name="E">
                    <project name="P">
                        <sequence format="r1" duration="5s" tcStart="0s" tcFormat="NDF">
                            <spine>
                                <asset-clip ref="r99" offset="0s" duration="5s" start="0s" name="X"/>
                            </spine>
                        </sequence>
                    </project>
                </event>
            </library>
        </fcpxml>
        """
        let issues = FCPXMLValidator().validate(doc)
        XCTAssertTrue(issues.contains { $0.message.contains("undefined resource 'r99'") })
    }

    func testValidatorFlagsMalformedTimeAndSpineOverlap() {
        let doc = """
        <fcpxml version="1.11">
            <resources>
                <format id="r1" frameDuration="1/30s" width="1920" height="1080"/>
                <asset id="r2" name="A" start="0s" duration="60s" hasVideo="1"/>
            </resources>
            <library>
                <event name="E">
                    <project name="P">
                        <sequence format="r1" duration="bogus" tcStart="0s" tcFormat="NDF">
                            <spine>
                                <asset-clip ref="r2" offset="0s" duration="5s" start="0s" name="A"/>
                                <asset-clip ref="r2" offset="4s" duration="5s" start="0s" name="B"/>
                            </spine>
                        </sequence>
                    </project>
                </event>
            </library>
        </fcpxml>
        """
        let issues = FCPXMLValidator().validate(doc)
        XCTAssertTrue(issues.contains { $0.message.contains("malformed time") })
        XCTAssertTrue(issues.contains { $0.message.contains("overlaps") })
    }

    func testValidatorRejectsNonXML() {
        let issues = FCPXMLValidator().validate("this is not xml <")
        XCTAssertEqual(issues.first?.severity, .error)
    }

    func testValidatorAcceptsRealWorldStyleDocument() {
        // Snippet modeled on FCP 10.7 export structure.
        let doc = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.11">
            <resources>
                <format id="r1" name="FFVideoFormat1080p30" frameDuration="100/3000s" width="1920" height="1080" colorSpace="1-1-1"/>
                <asset id="r2" name="clip" uid="ABC" start="0s" duration="3600/600s" hasVideo="1" hasAudio="1" format="r1">
                    <media-rep kind="original-media" src="file:///Users/me/Movies/clip.mov"/>
                </asset>
            </resources>
            <library location="file:///Users/me/Movies/Lib.fcpbundle/">
                <event name="Event" uid="E1">
                    <project name="Project" uid="P1">
                        <sequence format="r1" duration="3600/600s" tcStart="0s" tcFormat="NDF" audioLayout="stereo" audioRate="48k">
                            <spine>
                                <asset-clip ref="r2" offset="0s" name="clip" duration="3600/600s" start="0s" tcFormat="NDF"/>
                            </spine>
                        </sequence>
                    </project>
                </event>
            </library>
        </fcpxml>
        """
        XCTAssertTrue(FCPXMLValidator().isAcceptable(doc),
                      "\(FCPXMLValidator().validate(doc))")
    }

    // MARK: XML infrastructure

    func testXMLEscaping() {
        XCTAssertEqual(XML.escape("a & b < c > \"d\"", forAttribute: true),
                       "a &amp; b &lt; c &gt; &quot;d&quot;")
        XCTAssertEqual(XML.escape("a & b", forAttribute: false), "a &amp; b")
    }

    func testXMLParserBuildsTree() throws {
        let tree = try XMLDocumentParser.parse("<a x=\"1\"><b>hello &amp; bye</b><b/></a>")
        XCTAssertEqual(tree.name, "a")
        XCTAssertEqual(tree[attribute: "x"], "1")
        XCTAssertEqual(tree.all("b").count, 2)
        XCTAssertEqual(tree.first("b")?.text, "hello & bye")
    }
}
