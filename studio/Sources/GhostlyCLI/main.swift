import Foundation
import GhostlyCore
import GhostlyDomain
import GhostlyFCPXML
import GhostlySubtitles
import GhostlyDirector
import GhostlyLearning

/// `ghostly` — command-line access to the studio engines.
///
///     ghostly intent "<command>"                Parse an editing command
///     ghostly captions <in.srt|vtt> --style S   Restyle subtitles (SRT out)
///     ghostly validate <file.fcpxml>            Lint an FCPXML document
///     ghostly analyze <file.fcpxml>             Report timeline structure
///     ghostly styles                            List caption styles
///     ghostly version                           Print version

let ghostlyVersion = "1.0.0"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func readFile(_ path: String) -> String {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        fail("cannot read '\(path)'")
    }
    return content
}

func option(_ name: String, in args: [String]) -> String? {
    guard let index = args.firstIndex(of: "--\(name)"), index + 1 < args.count else { return nil }
    return args[index + 1]
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    print("""
    ghostly \(ghostlyVersion) — AI Final Cut Studio toolbox

    Usage:
      ghostly intent "<editing command>"
      ghostly captions <subtitles.srt|.vtt> --style <TikTok|YouTube|Instagram|Broadcast> [--shift seconds] [--out file]
      ghostly validate <file.fcpxml>
      ghostly analyze <file.fcpxml>
      ghostly styles
      ghostly version
    """)
    exit(0)
}

switch command {
case "version":
    print(ghostlyVersion)

case "intent":
    guard arguments.count >= 2 else { fail("usage: ghostly intent \"<command>\"") }
    let text = arguments[1]
    do {
        let plan = try Director().interpret(text)
        print("intents:")
        for intent in plan.intents { print("  • \(intent)") }
        print("profile: \(plan.profile.style.rawValue)")
        print("  shot length: \(plan.profile.minShotLength)s–\(plan.profile.maxShotLength)s")
        print("  format: \(plan.profile.format.width)x\(plan.profile.format.height)")
        print("  cut on beats: \(plan.profile.cutOnBeats)")
        print("  captions: \(plan.profile.captionStyleName ?? "none")")
    } catch {
        fail(error.localizedDescription)
    }

case "captions":
    guard arguments.count >= 2 else { fail("usage: ghostly captions <file> --style <name>") }
    let content = readFile(arguments[1])
    let styleName = option("style", in: arguments) ?? "Broadcast"
    guard let style = CaptionStyle.named(styleName) else {
        fail("unknown style '\(styleName)'; try: \(CaptionStyle.builtIn.map(\.name).joined(separator: ", "))")
    }
    do {
        var track = content.hasPrefix("WEBVTT") ? try WebVTT.parse(content) : try SRT.parse(content)
        if let shift = option("shift", in: arguments).flatMap(Double.init), shift != 0 {
            track = track.shifted(by: RationalTime(seconds: shift, preferredTimescale: 1000))
        }
        let output = SRT.serialize(style.styled(track))
        if let outPath = option("out", in: arguments) {
            try output.write(toFile: outPath, atomically: true, encoding: .utf8)
            print("wrote \(outPath)")
        } else {
            print(output, terminator: "")
        }
    } catch {
        fail(error.localizedDescription)
    }

case "validate":
    guard arguments.count >= 2 else { fail("usage: ghostly validate <file.fcpxml>") }
    let issues = FCPXMLValidator().validate(readFile(arguments[1]))
    if issues.isEmpty {
        print("✓ valid FCPXML, no issues")
    } else {
        for issue in issues { print(issue.description) }
        if issues.contains(where: { $0.severity == .error }) { exit(2) }
    }

case "analyze":
    guard arguments.count >= 2 else { fail("usage: ghostly analyze <file.fcpxml>") }
    do {
        let library = try FCPXMLReader().library(from: readFile(arguments[1]))
        print("library: \(library.name)")
        print("assets: \(library.allAssets.count)")
        for event in library.events {
            print("event: \(event.name)")
            for project in event.projects {
                let t = project.timeline
                print("  project: \(project.name)")
                print("    duration: \(String(format: "%.2f", t.duration.seconds))s")
                print("    storyline clips: \(t.storyline.count), connected: \(t.connectedClips.count)")
                print("    captions: \(t.captions.count), markers: \(t.markers.count), transitions: \(t.transitions.count)")
                let problems = t.validate()
                if problems.isEmpty {
                    print("    ✓ structurally sound")
                } else {
                    for problem in problems { print("    ✗ \(problem)") }
                }
            }
        }
    } catch {
        fail(error.localizedDescription)
    }

case "styles":
    for style in CaptionStyle.builtIn {
        print("\(style.name): \(style.fontName) \(Int(style.fontSize))pt, \(style.position.rawValue), \(style.animation.rawValue)\(style.allCaps ? ", ALL CAPS" : "")")
    }

default:
    fail("unknown command '\(command)'; run 'ghostly' for usage")
}
