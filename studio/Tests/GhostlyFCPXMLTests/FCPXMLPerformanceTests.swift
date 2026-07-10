import XCTest
import GhostlyCore
import GhostlyDomain
@testable import GhostlyFCPXML

/// Phase 17 baselines: FCPXML generation and validation on a large,
/// realistic timeline (1,000 storyline clips + captions + markers).
final class FCPXMLPerformanceTests: XCTestCase {
    private static let bigProject: (Project, [Asset]) = {
        let asset = Asset(name: "src", url: URL(string: "file:///src.mov")!,
                          duration: RationalTime(seconds: 7200), kind: .video,
                          format: .hd1080p30)
        var timeline = Timeline(name: "Feature", format: .hd1080p30)
        for i in 0..<1000 {
            timeline.appendToStoryline(
                assetID: asset.id, name: "shot \(i)",
                sourceRange: TimeRange(
                    start: RationalTime(value: Int64(i * 6000), timescale: 3000),
                    duration: RationalTime(value: 6000, timescale: 3000)))
        }
        for i in 0..<200 {
            timeline.captions.append(Caption(
                text: "คำบรรยายที่ \(i)",
                range: TimeRange(start: RationalTime(seconds: Double(i) * 10),
                                 duration: RationalTime(seconds: 3)),
                language: "th"))
            timeline.markers.append(Marker(start: RationalTime(seconds: Double(i) * 10),
                                           text: "จุดที่ \(i)"))
        }
        return (Project(name: "Big", timeline: timeline), [asset])
    }()

    func testWriterPerformanceOn1000ClipTimeline() throws {
        let (project, assets) = Self.bigProject
        var document = ""
        measure {
            document = (try? FCPXMLWriter().document(for: project, assets: assets)) ?? ""
            XCTAssertFalse(document.isEmpty)
        }
        XCTAssertGreaterThan(document.components(separatedBy: "<asset-clip").count, 1000)
    }

    func testValidatorPerformanceOnLargeDocument() throws {
        let (project, assets) = Self.bigProject
        let document = try FCPXMLWriter().document(for: project, assets: assets)
        measure {
            let issues = FCPXMLValidator().validate(document)
            XCTAssertTrue(issues.filter { $0.severity == .error }.isEmpty)
        }
    }

    func testStructuralValidationPerformance() {
        let (project, _) = Self.bigProject
        measure {
            XCTAssertTrue(project.timeline.validate().isEmpty)
        }
    }
}
