import XCTest
import GhostlyCore
import GhostlyDomain
@testable import GhostlyFCPXML

/// Phase 17 baselines: FCPXML generation and validation on a large,
/// realistic timeline (1,000 storyline clips + Thai captions + markers).
/// Best-of-N wall time against generous budgets (see CorePerformanceTests
/// for why XCTest `measure` is unsuitable on CI), with correctness asserted
/// inside each block.
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
        assertFCPXMLPerformance("write-1000-clips", budget: 10) {
            document = (try? FCPXMLWriter().document(for: project, assets: assets)) ?? ""
            XCTAssertFalse(document.isEmpty)
        }
        XCTAssertGreaterThan(document.components(separatedBy: "<asset-clip").count, 1000)
    }

    func testValidatorPerformanceOnLargeDocument() throws {
        let (project, assets) = Self.bigProject
        let document = try FCPXMLWriter().document(for: project, assets: assets)
        assertFCPXMLPerformance("validate-1000-clips", budget: 10) {
            let issues = FCPXMLValidator().validate(document)
            XCTAssertTrue(issues.filter { $0.severity == .error }.isEmpty)
        }
    }

    func testStructuralValidationPerformance() {
        let (project, _) = Self.bigProject
        assertFCPXMLPerformance("structural-validate-1000-clips", budget: 10) {
            XCTAssertTrue(project.timeline.validate().isEmpty)
        }
    }
}

/// Best-of-N wall clock vs a generous budget; prints the timing for humans.
private func assertFCPXMLPerformance(
    _ name: String, iterations: Int = 3, budget: TimeInterval,
    file: StaticString = #filePath, line: UInt = #line,
    _ block: () throws -> Void) rethrows {
    var best = Double.greatestFiniteMagnitude
    for _ in 0..<iterations {
        let start = DispatchTime.now().uptimeNanoseconds
        try block()
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        best = min(best, elapsed)
    }
    print("perf[\(name)]: best \(String(format: "%.3f", best))s of \(iterations) runs (budget \(budget)s)")
    XCTAssertLessThan(best, budget, "\(name) blew its performance budget",
                      file: file, line: line)
}
