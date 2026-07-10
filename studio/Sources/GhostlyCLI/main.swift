import Foundation
import GhostlyCore
import GhostlyDomain
import GhostlyFCPXML
import GhostlySubtitles
import GhostlyDetection
import GhostlyDirector
import GhostlyLearning
import GhostlyExport
import GhostlyTranscription

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
      ghostly edit <subtitles.srt|.vtt> --duration <seconds> --command "<editing command>" [--lang th] [--name clip] [--project name] [--out file.fcpxml]
      ghostly edit --wav <clip.wav> --command "<editing command>" [<subtitles.srt|.vtt>] [--lang th] [--name clip] [--project name] [--out file.fcpxml]
      ghostly captions <subtitles.srt|.vtt> --style <TikTok|YouTube|Instagram|Broadcast> [--shift seconds] [--out file]
      ghostly validate <file.fcpxml>
      ghostly analyze <file.fcpxml>
      ghostly styles
      ghostly export <input> --preset <name> --out <output> [--title T] [--artist A]
      ghostly presets
      ghostly analyze-audio <file.wav>          Speech ranges + beats/BPM from a WAV file
      ghostly extract-audio <video> [--out file.wav] [--rate 16000]   Print the ffmpeg command that produces an analysis WAV
      ghostly demo-audio [--out file.wav]       Write a deterministic demo WAV (speech + 120 BPM beats)
      ghostly demo-thai [--out file.fcpxml]
      ghostly transcribe <audio> --model <ggml.bin> [--lang th] [--out subs.srt] [--whisper path]
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

case "edit":
    // End-to-end: transcript (or real WAV audio) → auto-edit → FCPXML.
    // Thai-first: --lang defaults to "th".
    guard arguments.count >= 2 else {
        fail("usage: ghostly edit <subtitles.srt|.vtt> --duration <seconds> --command \"...\"  |  ghostly edit --wav <clip.wav> --command \"...\"")
    }
    guard let editCommand = option("command", in: arguments) else {
        fail("--command \"<editing command>\" is required, e.g. --command \"create a tiktok with captions, remove silence\"")
    }
    // First non-flag argument after `edit` is the optional subtitle file.
    let subtitlePath: String? = arguments[1].hasPrefix("--") ? nil : arguments[1]
    let wavPath = option("wav", in: arguments)
    let language = option("lang", in: arguments) ?? "th"
    let projectName = option("project", in: arguments) ?? "AI Edit"
    do {
        let output: EditPipeline.Output
        if let wavPath {
            // Real audio: duration + speech ranges + tempo come from the WAV.
            let audio = try WAV.decode(contentsOf: URL(fileURLWithPath: wavPath))
            output = try EditPipeline.run(EditPipeline.AudioInput(
                audio: audio,
                subtitles: subtitlePath.map(readFile),
                command: editCommand,
                language: language,
                clipName: option("name", in: arguments) ?? (wavPath as NSString).lastPathComponent,
                projectName: projectName))
        } else {
            guard let subtitlePath else {
                fail("provide a subtitle file (with --duration) or --wav <clip.wav>")
            }
            guard let durationText = option("duration", in: arguments),
                  let durationSeconds = Double(durationText) else {
                fail("--duration <seconds> is required (declared length of the source clip)")
            }
            output = try EditPipeline.run(EditPipeline.Input(
                subtitles: readFile(subtitlePath),
                durationSeconds: durationSeconds,
                command: editCommand,
                language: language,
                clipName: option("name", in: arguments) ?? (subtitlePath as NSString).lastPathComponent,
                projectName: projectName))
        }
        if let outPath = option("out", in: arguments) {
            try output.fcpxml.write(toFile: outPath, atomically: true, encoding: .utf8)
            print("wrote \(outPath)")
        } else {
            print(output.fcpxml)
        }
        let bpmNote = output.detectedBPM.map { String(format: ", tempo ≈ %.0f BPM", $0) } ?? ""
        FileHandle.standardError.write(Data("""
        profile: \(output.profileStyle), language: \(output.language)\(bpmNote)
        clips: \(output.storylineClipCount), captions: \(output.captionCount), duration: \(String(format: "%.2f", output.durationSeconds))s, vertical: \(output.isVertical)
        valid FCPXML: \(output.isValid)\n
        """.utf8))
        if !output.isValid {
            for issue in output.issues { FileHandle.standardError.write(Data("\(issue)\n".utf8)) }
            exit(2)
        }
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

case "transcribe":
    guard arguments.count >= 2 else {
        fail("usage: ghostly transcribe <audio> --model <ggml.bin> [--lang th]")
    }
    guard let modelPath = option("model", in: arguments) else {
        fail("--model <path to whisper.cpp ggml model> is required")
    }
    let audioURL = URL(fileURLWithPath: arguments[1])
    let language = option("lang", in: arguments)
    let whisperPath = option("whisper", in: arguments) ?? "whisper-cli"
    let transcriber = WhisperCLITranscriber(executablePath: whisperPath, modelPath: modelPath)
    do {
        // Top-level await: main.swift supports an async entry point.
        let track = try await transcriber.transcribe(audioURL, language: language)
        let srt = SRT.serialize(track)
        if let outPath = option("out", in: arguments) {
            try srt.write(toFile: outPath, atomically: true, encoding: .utf8)
            print("wrote \(outPath) (\(track.cues.count) cues, language: \(track.language))")
        } else {
            print(srt, terminator: "")
        }
    } catch {
        fail(error.localizedDescription)
    }

case "analyze-audio":
    guard arguments.count >= 2 else { fail("usage: ghostly analyze-audio <file.wav>") }
    do {
        let audio = try WAV.decode(contentsOf: URL(fileURLWithPath: arguments[1]))
        print("duration: \(String(format: "%.2f", audio.duration.seconds))s @ \(audio.sampleRate)Hz")
        let segments = SilenceDetector().segments(samples: audio.samples,
                                                  sampleRate: audio.sampleRate)
        let speech = segments.filter(\.isSpeech)
        let speechSeconds = speech.reduce(0.0) { $0 + $1.range.duration.seconds }
        print("speech: \(speech.count) range(s), \(String(format: "%.2f", speechSeconds))s total")
        for segment in speech {
            print(String(format: "  %.2fs – %.2fs",
                         segment.range.start.seconds, segment.range.end.seconds))
        }
        let beats = BeatDetector().detect(samples: audio.samples, sampleRate: audio.sampleRate)
        if let bpm = beats.bpm {
            print("beats: \(beats.beats.count) onsets, tempo ≈ \(String(format: "%.0f", bpm)) BPM")
        } else {
            print("beats: \(beats.beats.count) onsets, tempo unknown")
        }
    } catch {
        fail(error.localizedDescription)
    }

case "extract-audio":
    guard arguments.count >= 2 else { fail("usage: ghostly extract-audio <video> [--out file.wav]") }
    let input = arguments[1]
    let output = option("out", in: arguments) ?? ((input as NSString).deletingPathExtension + ".wav")
    let rate = option("rate", in: arguments).flatMap(Int.init) ?? 16_000
    // Print the command; the studio does not assume ffmpeg is present.
    print(MediaExtraction().audioCommandLine(input: input, output: output, sampleRate: rate))

case "demo-audio":
    let fixture = AudioFixture.demo()
    let outPath = option("out", in: arguments) ?? "ghostly-demo.wav"
    do {
        try fixture.wavData().write(to: URL(fileURLWithPath: outPath))
        print("wrote \(outPath) (\(String(format: "%.1f", fixture.durationSeconds))s: narration pattern + 120 BPM beats)")
    } catch {
        fail("cannot write '\(outPath)': \(error.localizedDescription)")
    }

case "demo-thai":
    do {
        let result = try ThaiShortsExample.build()
        if let outPath = option("out", in: arguments) {
            try result.fcpxml.write(toFile: outPath, atomically: true, encoding: .utf8)
            print("wrote \(outPath)")
            print("  vertical: \(result.isVertical), duration: \(String(format: "%.1f", result.durationSeconds))s, captions: \(result.captionCount)")
            print("  valid FCPXML: \(result.isValid)")
        } else {
            print(result.fcpxml)
        }
        if !result.isValid {
            for issue in result.issues { FileHandle.standardError.write(Data("\(issue)\n".utf8)) }
            exit(2)
        }
    } catch {
        fail(error.localizedDescription)
    }

case "presets":
    for preset in RenderPreset.builtIn {
        print("\(preset.name): \(preset.container.rawValue) / \(preset.videoCodec.rawValue), \(preset.format.width)x\(preset.format.height) @ \(String(format: "%.3g", preset.format.frameRate.nominalFPS))fps, \(preset.videoBitrateKbps)kbps")
    }

case "export":
    guard arguments.count >= 2 else { fail("usage: ghostly export <input> --preset <name> --out <output>") }
    let input = arguments[1]
    let presetName = option("preset", in: arguments) ?? "YouTube 1080p"
    guard let preset = RenderPreset.named(presetName) else {
        fail("unknown preset '\(presetName)'; try: \(RenderPreset.builtIn.map(\.name).joined(separator: ", "))")
    }
    let output = option("out", in: arguments)
        ?? ((input as NSString).deletingPathExtension + "_\(preset.name.replacingOccurrences(of: " ", with: "")).\(preset.container.rawValue)")
    let metadata = ExportMetadata(title: option("title", in: arguments),
                                  artist: option("artist", in: arguments))
    let command = FFmpegCommandBuilder().commandLine(
        input: input, output: output, preset: preset, metadata: metadata)
    // Print the command by default; the studio does not assume ffmpeg is present.
    print(command)

default:
    fail("unknown command '\(command)'; run 'ghostly' for usage")
}
