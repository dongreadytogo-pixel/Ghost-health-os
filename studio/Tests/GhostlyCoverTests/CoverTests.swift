import XCTest
import GhostlyCore
@testable import GhostlyCover

/// SUBTITLE Cover port: the battle-tested Python behavior, verified against
/// synthetic FCPXML exactly like the original project's methodology.
final class CoverTests: XCTestCase {
    private func write(_ xml: String, name: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cover-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(name).path
        try xml.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    /// One plain (Light) subtitle + one bold highlight + a Custom title
    /// that carries bold="1" with an ExtraLight face (the handoff §8 bug),
    /// nested inside a spine to exercise offset accumulation.
    private let sample = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE fcpxml>
    <fcpxml version="1.11">
      <resources>
        <format id="r1" frameDuration="100/2500s" width="1080" height="1920"/>
        <effect id="r2" name="Pop-up Text" uid="/Popup.moti"/>
        <asset id="r3" name="clip" duration="2000/2500s"/>
      </resources>
      <library>
        <event name="e">
          <project name="โปรเจกต์:ทดสอบ">
            <sequence format="r1" duration="2000/2500s" tcStart="0s" tcFormat="NDF">
              <spine>
                <asset-clip ref="r3" offset="0s" duration="2000/2500s" name="คลิป">
                  <title ref="r2" lane="1" offset="100/2500s" duration="250/2500s" name="ซับ1">
                    <text><text-style ref="ts1">อาการปวดเข่าดีขึ้นมากเลยครับ</text-style></text>
                    <text-style-def id="ts1"><text-style font="Prompt" fontFace="Light" fontSize="71"/></text-style-def>
                  </title>
                  <title ref="r2" lane="2" offset="150/2500s" duration="250/2500s" name="ไฮไลต์ราคา">
                    <text><text-style ref="ts2">ลด 50% วันนี้</text-style></text>
                    <text-style-def id="ts2"><text-style font="Anakotmai" fontFace="Bold" bold="1"/></text-style-def>
                  </title>
                  <title ref="r2" lane="3" offset="400/2500s" duration="250/2500s" name="ซับ Custom">
                    <text><text-style ref="ts3">หมอบอกว่าปลอดภัยมาก</text-style></text>
                    <text-style-def id="ts3"><text-style font="Prompt" fontFace="ExtraLight" bold="1"/></text-style-def>
                  </title>
                  <filter-video ref="r2" name="เอฟเฟกต์เดิม"/>
                </asset-clip>
              </spine>
            </sequence>
          </project>
        </event>
      </library>
    </fcpxml>
    """

    func testAnalyzeFindsPlainSubsSkipsBoldHighlight() throws {
        let path = try write(sample, name: "in.fcpxml")
        let (name, pairs) = try SubtitleCover.analyze(path: path)
        XCTAssertEqual(name, "โปรเจกต์ทดสอบ", "unsafe filename characters stripped")
        XCTAssertEqual(pairs.count, 2,
                       "Light sub + bold-but-ExtraLight Custom title (handoff §8 fix); bold highlight excluded")
        XCTAssertFalse(pairs.contains { $0.orange.contains("ลด 50%") },
                       "the bold price highlight must never become a cover")
    }

    func testRunLayersCoverBeforeFiltersOnLanes10And11() throws {
        let path = try write(sample, name: "in.fcpxml")
        let out = (path as NSString).deletingLastPathComponent + "/out_cover.fcpxml"
        let result = try SubtitleCover.run(path: path, outPath: out)
        XCTAssertEqual(result.coverCount, 2)
        let doc = try String(contentsOfFile: out, encoding: .utf8)
        XCTAssertTrue(doc.contains(" - COVER"))
        XCTAssertTrue(doc.contains("lane=\"10\""), "white line lane")
        XCTAssertTrue(doc.contains("lane=\"11\""), "orange line lane")
        XCTAssertTrue(doc.contains("Build In") && doc.contains("Build Out"),
                      "pop-in AND pop-out must both be enabled")
        XCTAssertTrue(doc.contains("Anakotmai"))
        XCTAssertTrue(doc.contains("ซับ1"), "original subtitles must remain untouched")
        // DTD order: the new titles must appear before the existing filter.
        let coverIndex = try XCTUnwrap(doc.range(of: " - COVER")).lowerBound
        let filterIndex = try XCTUnwrap(doc.range(of: "<filter-video")).lowerBound
        XCTAssertLessThan(coverIndex, filterIndex,
                          "covers must be inserted before filter children (import fails otherwise)")
    }

    func testMissingPopupTemplateGivesClearThaiError() throws {
        let noPopup = sample.replacingOccurrences(of: "Pop-up Text", with: "Other Effect")
        let path = try write(noPopup, name: "no-popup.fcpxml")
        XCTAssertThrowsError(try SubtitleCover.analyze(path: path)) { error in
            XCTAssertTrue("\(error)".contains("Pop-up Text"), "\(error)")
        }
    }

    func testOverridesCanDeleteACover() throws {
        let path = try write(sample, name: "in.fcpxml")
        let out = (path as NSString).deletingLastPathComponent + "/ov_cover.fcpxml"
        // Delete the first subtitle's cover, rewrite the second one's text.
        let result = try SubtitleCover.run(
            path: path,
            overrides: [0: ("", ""), 2: ("หมอบอกว่า", "ปลอดภัยมาก")],
            outPath: out)
        XCTAssertEqual(result.coverCount, 1)
        XCTAssertEqual(result.pairs[0].white, "หมอบอกว่า")
        XCTAssertEqual(result.pairs[0].orange, "ปลอดภัยมาก")
    }

    func testListTitlesDumpsEveryTitle() throws {
        let path = try write(sample, name: "in.fcpxml")
        let lines = try SubtitleCover.listTitles(path: path)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines.allSatisfy { $0.contains("effect=Pop-up Text") })
        XCTAssertTrue(lines.contains { $0.contains("bold=1") && $0.contains("fontFace=ExtraLight") })
    }

    // MARK: Pure math (identical to the calibrated Python)

    func testFitFillsButNeverOverflows() {
        XCTAssertEqual(SubtitleCover.fit("สั้น"), 120, "short lines cap at SIZE_MAX")
        let long = String(repeating: "ก", count: 40)
        XCTAssertEqual(SubtitleCover.fit(long), 32, "long lines floor at HARD_MIN")
        let mid = String(repeating: "ก", count: 12)
        let size = SubtitleCover.fit(mid)
        XCTAssertLessThanOrEqual(Double(12 * size), 1170, "never exceed MAX_UNITS")
    }

    func testBalanceCapsTheRatio() {
        let (sw, so) = SubtitleCover.balance(120, 40)
        XCTAssertLessThanOrEqual(Double(max(sw, so)) / Double(min(sw, so)), 1.9 + 0.01)
        XCTAssertEqual(SubtitleCover.balance(70, 68).0, 70, "already balanced stays put")
    }

    func testShortSentenceStaysSingleLine() {
        let (white, orange) = SubtitleCover.splitTwo("ชื่อน้อง ?")
        XCTAssertEqual(white, "")
        XCTAssertEqual(orange, "ชื่อน้อง ?")
    }

    func testSplitPreservesAllText() {
        let text = "อาการปวดเข่าที่เป็นมานาน ดีขึ้นมากเลยครับ"
        let (white, orange) = SubtitleCover.splitTwo(text)
        XCTAssertFalse(orange.isEmpty)
        let rejoined = (white + orange).replacingOccurrences(of: " ", with: "")
        XCTAssertEqual(rejoined, text.replacingOccurrences(of: " ", with: ""),
                       "no characters may be lost by the split")
    }

    func testValidateFlagsOverflow() {
        let bad = [SubtitleCover.Pair(index: 0, white: "", whiteSize: 0,
                                      orange: String(repeating: "ก", count: 40), orangeSize: 40)]
        XCTAssertFalse(SubtitleCover.validate(bad).isEmpty, "40×40=1600 > 1170 must be flagged")
        let good = [SubtitleCover.Pair(index: 0, white: "สวัสดี", whiteSize: 80,
                                       orange: "ดีมาก", orangeSize: 90)]
        XCTAssertTrue(SubtitleCover.validate(good).isEmpty)
    }
}
