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
import GhostlyColor
import GhostlyAudio

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
      ghostly auto <video> [--command "..."] [--model ggml.bin] [--preset name] [--remember] [--diarize] [--clean] [--out file.fcpxml]   คลิกเดียวจบ: วิดีโอจริง → แตกเสียง (ffmpeg) → ซับ (whisper ถ้ามี --model) → ตัดต่อ → FCPXML เปิดใน FCP ได้ทันที
      ghostly intent "<editing command>"
      ghostly edit <subtitles.srt|.vtt> --duration <seconds> --command "<editing command>" [--media video.mp4] [--lang th] [--name clip] [--project name] [--out file.fcpxml]
      ghostly edit --wav <clip.wav> --command "<editing command>" [<subtitles.srt|.vtt>] [--media video.mp4] [--diarize] [--clean] [--lang th] [--name clip] [--project name] [--out file.fcpxml]
      ghostly chapters <subtitles.srt|.vtt> --duration <seconds> [--lang th] [--out chapters.txt]   YouTube chapter timestamps
      ghostly highlights <subtitles.srt|.vtt> --duration <seconds> [--lang th] [--limit 5]   ช่วงเด่น (hook/highlight/CTA) + คะแนน
      ghostly shorts <subtitles.srt|.vtt> --duration <seconds> --media <video> [--preset TikTok] [--limit 3]   คำสั่ง ffmpeg ตัดช่วงเด่นเป็นคลิปสั้นจากไฟล์จริง
      ghostly captions <subtitles.srt|.vtt> --style <TikTok|YouTube|Instagram|Broadcast> [--shift seconds] [--out file]
      ghostly validate <file.fcpxml>
      ghostly analyze <file.fcpxml>
      ghostly styles
      ghostly export <input> --preset <name> --out <output> [--title T] [--artist A]
      ghostly presets
      ghostly workflow --wav <clip.wav> --command "<editing command>" [<subs.srt>] [--media video.mp4] [--diarize] [--preset name] [--remember] [--out file.fcpxml]   Full chain: analyze → edit → captions → export command (--remember = ใช้/จำค่าที่เคยใช้)
      ghostly analyze-audio <file.wav> [--diarize]   Speech ranges + beats/BPM (+ speakers) from a WAV file
      ghostly extract-audio <video> [--out file.wav] [--rate 16000] [--run]   The ffmpeg command that produces an analysis WAV (--run executes it)
      ghostly demo-audio [--out file.wav]       Write a deterministic demo WAV (speech + 120 BPM beats)
      ghostly demo-thai [--out file.fcpxml]
      ghostly transcribe <audio> --model <ggml.bin> [--lang th] [--sentences] [--out subs.srt] [--whisper path]   (--sentences = จัดกลุ่มเป็นประโยคธรรมชาติ)
      ghostly lut [--exposure EV] [--contrast x] [--saturation x] [--temperature -1..1] [--tint -1..1] [--neutralize "r g b"] [--size 33] [--title name] [--out grade.cube]
      ghostly lut-info <file.cube>              Inspect/validate a .cube LUT
      ghostly normalize-audio <in.wav> [--target -16] [--lufs] [--peak -1] [--out out.wav]   Level a voice/music track (RMS dBFS or K-weighted LUFS, peak-safe)
      ghostly clean-audio <in.wav> [--highpass 80] [--dehum 50] [--gate -45] [--out out.wav]   ลดเสียงรบกวน: rumble + mains hum + noise floor
      ghostly doctor                            ตรวจเครื่องมือภายนอก (ffmpeg/whisper) + วิธีติดตั้ง
      ghostly version
    """)
    exit(0)
}

/// Runs an external tool to completion, throwing a Thai-facing error with the
/// tool's last stderr lines on a non-zero exit.
func runTool(_ name: String, _ args: [String]) throws {
    #if os(macOS) || os(Linux)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [name] + args
    let stderrPipe = Pipe()
    process.standardOutput = Pipe()
    process.standardError = stderrPipe
    try process.run()
    // Drain stderr before waiting so a chatty tool can't deadlock the pipe.
    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let tail = String(data: errData, encoding: .utf8)?
            .split(separator: "\n").suffix(5).joined(separator: "\n") ?? ""
        throw StudioError.validationFailure(
            detail: "\(name) ล้มเหลว (exit \(process.terminationStatus))\n\(tail)")
    }
    #else
    throw StudioError.validationFailure(detail: "\(name) รันไม่ได้บนแพลตฟอร์มนี้")
    #endif
}

/// Probes whether an external tool is on PATH (via `which`), for `doctor`.
func toolOnPath(_ name: String) -> Bool {
    #if os(macOS) || os(Linux)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["which", name]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
    #else
    return false
    #endif
}

switch command {
case "version":
    print(ghostlyVersion)

case "doctor":
    // First-run readiness check: which external media tools are installed,
    // and how to install what's missing (Thai). Report formatting is the
    // pure, tested ToolchainCheck.report; probing lives here.
    var found: [String: Bool] = [:]
    for tool in ToolchainCheck.tools { found[tool.name] = toolOnPath(tool.name) }
    let report = ToolchainCheck.report(found: found)
    for line in report.lines { print(line) }

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
        if let cap = plan.profile.maxTotalDuration {
            print("  max duration: \(String(format: "%.0f", cap))s")
        }
        if plan.profile.emphasizeHighlights {
            print("  emphasis: best sentences (เน้นประโยคสำคัญ)")
        }
    } catch {
        fail(error.localizedDescription)
    }

case "edit":
    // End-to-end: transcript (or real WAV audio) → auto-edit → FCPXML.
    // Thai-first: --lang defaults to "th".
    guard arguments.count >= 2 else {
        fail("usage: ghostly edit <subtitles.srt|.vtt> --duration <seconds> --command \"...\"  |  ghostly edit --wav <clip.wav> --command \"...\"  (add --media <clip.mov> so FCP opens the real footage)")
    }
    guard let editCommand = option("command", in: arguments) else {
        fail("--command \"<editing command>\" is required, e.g. --command \"create a tiktok with captions, remove silence\"")
    }
    // First non-flag argument after `edit` is the optional subtitle file.
    let subtitlePath: String? = arguments[1].hasPrefix("--") ? nil : arguments[1]
    let wavPath = option("wav", in: arguments)
    let language = option("lang", in: arguments) ?? "th"
    let projectName = option("project", in: arguments) ?? "AI Edit"
    // --media: the original footage the FCPXML must reference (absolute
    // path recommended) so the project opens online in Final Cut Pro.
    let mediaPath = option("media", in: arguments)
    let mediaURL = mediaPath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL }
    do {
        let clipName = option("name", in: arguments)
            ?? ((mediaPath ?? wavPath ?? subtitlePath ?? "clip") as NSString).lastPathComponent
        let output: EditPipeline.Output
        if let wavPath {
            // Real audio: duration + speech ranges + tempo come from the WAV.
            let audio = try WAV.decode(contentsOf: URL(fileURLWithPath: wavPath))
            output = try EditPipeline.run(EditPipeline.AudioInput(
                audio: audio,
                subtitles: subtitlePath.map(readFile),
                command: editCommand,
                language: language,
                clipName: clipName,
                projectName: projectName,
                diarize: arguments.contains("--diarize"),
                cleanAudio: arguments.contains("--clean"),
                mediaURL: mediaURL))
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
                clipName: clipName,
                projectName: projectName,
                mediaURL: mediaURL))
        }
        if let outPath = option("out", in: arguments) {
            try output.fcpxml.write(toFile: outPath, atomically: true, encoding: .utf8)
            print("wrote \(outPath)")
        } else {
            print(output.fcpxml)
        }
        let bpmNote = output.detectedBPM.map { String(format: ", tempo ≈ %.0f BPM", $0) } ?? ""
        let speakerNote = output.speakerCount.map { ", speakers: \($0)" } ?? ""
        let mediaNote = mediaURL.map { "media: \($0.path)" }
            ?? "media: placeholder — ใส่ --media <ไฟล์วิดีโอ> เพื่อให้ FCP เปิดฟุตเทจจริงได้ทันที"
        FileHandle.standardError.write(Data("""
        profile: \(output.profileStyle), language: \(output.language)\(bpmNote)\(speakerNote)
        clips: \(output.storylineClipCount), captions: \(output.captionCount), duration: \(String(format: "%.2f", output.durationSeconds))s, vertical: \(output.isVertical)
        \(mediaNote)
        valid FCPXML: \(output.isValid)\n
        """.utf8))
        if !output.isValid {
            for issue in output.issues { FileHandle.standardError.write(Data("\(issue)\n".utf8)) }
            exit(2)
        }
    } catch {
        fail(error.localizedDescription)
    }

case "chapters":
    // YouTube chapter timestamps from a transcript's cue timings. Cues
    // become speech ranges; HighlightPlanner derives chapter boundaries
    // (using transcript titles as labels), ChapterExport formats them.
    guard arguments.count >= 2 else {
        fail("usage: ghostly chapters <subtitles.srt|.vtt> --duration <seconds> [--lang th] [--out chapters.txt]")
    }
    guard let durationText = option("duration", in: arguments),
          let durationSeconds = Double(durationText) else {
        fail("--duration <seconds> is required (length of the video)")
    }
    do {
        let content = readFile(arguments[1])
        let parsed = content.hasPrefix("WEBVTT") ? try WebVTT.parse(content) : try SRT.parse(content)
        let transcript = SubtitleTrack(language: option("lang", in: arguments) ?? "th",
                                       cues: parsed.cues)
        let duration = RationalTime(seconds: durationSeconds, preferredTimescale: 3000)
        let asset = Asset(name: "video", url: URL(fileURLWithPath: "/media/video"),
                          duration: duration, kind: .video)
        let analysis = MediaAnalysis(assetID: asset.id, duration: duration,
                                     speechRanges: parsed.cues.map(\.range))
        let markers = HighlightPlanner().chapters(from: analysis, transcript: transcript)
        guard let description = ChapterExport.youTubeDescription(markers: markers, duration: duration) else {
            fail("ไม่สามารถสร้าง chapter ได้ (YouTube ต้องมีอย่างน้อย 3 บท เริ่มที่ 0:00 และแต่ละบทยาว ≥ 10 วินาที)")
        }
        if let outPath = option("out", in: arguments) {
            try description.write(toFile: outPath, atomically: true, encoding: .utf8)
            print("wrote \(outPath)")
        } else {
            print(description)
        }
    } catch {
        fail(error.localizedDescription)
    }

case "highlights":
    // Best moments (hook/highlight/CTA) from a transcript's cue timings —
    // what a short should lead with and which beats to keep. Prints each
    // with its timestamp, kind, and 0…1 score.
    guard arguments.count >= 2 else {
        fail("usage: ghostly highlights <subtitles.srt|.vtt> --duration <seconds> [--lang th] [--limit 5]")
    }
    guard let durationText = option("duration", in: arguments),
          let durationSeconds = Double(durationText) else {
        fail("--duration <seconds> is required (length of the video)")
    }
    do {
        let content = readFile(arguments[1])
        let parsed = content.hasPrefix("WEBVTT") ? try WebVTT.parse(content) : try SRT.parse(content)
        let transcript = SubtitleTrack(language: option("lang", in: arguments) ?? "th",
                                       cues: parsed.cues)
        let duration = RationalTime(seconds: durationSeconds, preferredTimescale: 3000)
        let asset = Asset(name: "video", url: URL(fileURLWithPath: "/media/video"),
                          duration: duration, kind: .video)
        let analysis = MediaAnalysis(assetID: asset.id, duration: duration,
                                     speechRanges: parsed.cues.map(\.range))
        let limit = option("limit", in: arguments).flatMap(Int.init) ?? 5
        let highlights = HighlightPlanner().highlights(
            from: analysis, transcript: transcript, limit: limit)
        guard !highlights.isEmpty else {
            fail("ไม่พบช่วงเด่น (ต้องมีช่วงเสียงพูดในไฟล์ซับ)")
        }
        for h in highlights {
            let start = ChapterExport.timestamp(h.range.start.seconds)
            print("\(start)  [\(h.kind.rawValue)] \(String(format: "%.2f", h.score))  \(h.label)")
        }
    } catch {
        fail(error.localizedDescription)
    }

case "shorts":
    // Highlights → ready-to-run ffmpeg commands that cut each best moment
    // out of the real footage as a platform-ready short (TikTok preset by
    // default). The bridge from "find best moments" to actual short files.
    guard arguments.count >= 2 else {
        fail("usage: ghostly shorts <subtitles.srt|.vtt> --duration <seconds> --media <video> [--preset TikTok] [--limit 3] [--lang th]")
    }
    guard let durationText = option("duration", in: arguments),
          let durationSeconds = Double(durationText) else {
        fail("--duration <seconds> is required (length of the video)")
    }
    guard let mediaPath = option("media", in: arguments) else {
        fail("--media <ไฟล์วิดีโอต้นฉบับ> is required (the file the shorts are cut from)")
    }
    do {
        let content = readFile(arguments[1])
        let parsed = content.hasPrefix("WEBVTT") ? try WebVTT.parse(content) : try SRT.parse(content)
        let transcript = SubtitleTrack(language: option("lang", in: arguments) ?? "th",
                                       cues: parsed.cues)
        let duration = RationalTime(seconds: durationSeconds, preferredTimescale: 3000)
        let analysis = MediaAnalysis(assetID: AssetID(), duration: duration,
                                     speechRanges: parsed.cues.map(\.range))
        let limit = option("limit", in: arguments).flatMap(Int.init) ?? 3
        let highlights = HighlightPlanner().highlights(
            from: analysis, transcript: transcript, limit: limit)
            .filter { $0.kind != .cta }
        guard !highlights.isEmpty else {
            fail("ไม่พบช่วงเด่น (ต้องมีช่วงเสียงพูดในไฟล์ซับ)")
        }
        let presetName = option("preset", in: arguments) ?? "TikTok"
        guard let preset = RenderPreset.named(presetName) else {
            fail("unknown preset '\(presetName)'; try: \(RenderPreset.builtIn.map(\.name).joined(separator: ", "))")
        }
        let base = ((mediaPath as NSString).lastPathComponent as NSString).deletingPathExtension
        let builder = FFmpegCommandBuilder()
        for (index, h) in highlights.enumerated() {
            let start = ChapterExport.timestamp(h.range.start.seconds)
            print("# \(start)  [\(h.kind.rawValue)]  \(h.label)")
            print(builder.commandLine(
                input: mediaPath,
                output: "\(base)-short\(index + 1).\(preset.container.rawValue)",
                preset: preset,
                metadata: ExportMetadata(title: h.label),
                trim: FFmpegCommandBuilder.Trim(startSeconds: h.range.start.seconds,
                                                endSeconds: h.range.end.seconds)))
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
        var track = try await transcriber.transcribe(audioURL, language: language)
        if arguments.contains("--sentences") {
            // จัดกลุ่มคำจาก ASR เป็นประโยคธรรมชาติ (ช่วงหยุด + ครับ/ค่ะ).
            track = track.groupedIntoSentences()
        }
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

case "workflow":
    // Agent mode: analyze → edit → captions → FCPXML → export command.
    guard let editCommand = option("command", in: arguments) else {
        fail("--command \"<editing command>\" is required")
    }
    let subtitlePath: String? = arguments.count >= 2 && !arguments[1].hasPrefix("--") ? arguments[1] : nil
    do {
        var request = Workflow.Request(
            command: editCommand,
            language: option("lang", in: arguments) ?? "th",
            diarize: arguments.contains("--diarize"),
            cleanAudio: arguments.contains("--clean"),
            projectName: option("project", in: arguments) ?? "AI Edit",
            exportPresetName: option("preset", in: arguments))
        // --media: the original footage — FCPXML references it (opens online
        // in FCP) and the printed ffmpeg export command reads from it.
        let workflowMediaPath = option("media", in: arguments)
        request.mediaURL = workflowMediaPath.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL
        }
        if let wavPath = option("wav", in: arguments) {
            request.audio = try WAV.decode(contentsOf: URL(fileURLWithPath: wavPath))
            request.clipName = option("name", in: arguments)
                ?? ((workflowMediaPath ?? wavPath) as NSString).lastPathComponent
        } else if let subtitlePath {
            guard let seconds = option("duration", in: arguments).flatMap(Double.init) else {
                fail("--duration <seconds> is required without --wav")
            }
            request.durationSeconds = seconds
            request.clipName = option("name", in: arguments)
                ?? ((workflowMediaPath ?? subtitlePath) as NSString).lastPathComponent
        } else {
            fail("provide --wav <clip.wav> or a subtitle file with --duration")
        }
        request.subtitles = subtitlePath.map(readFile)

        let result: Workflow.Result
        if arguments.contains("--remember") {
            // AI memory (ใช้ค่าที่เคยใช้): pre-fill from and record into the
            // local preference store (~/.ghostly, or GHOSTLY_HOME).
            let home = ProcessInfo.processInfo.environment["GHOSTLY_HOME"]
                .map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".ghostly")
            let store = try PreferenceStore(directory: home)
            result = try await Workflow.run(request, memory: store)
        } else {
            result = try Workflow.run(request)
        }
        let outPath = option("out", in: arguments) ?? "edit.fcpxml"
        try result.edit.fcpxml.write(toFile: outPath, atomically: true, encoding: .utf8)
        for step in result.steps { print("• \(step)") }
        print("fcpxml: \(outPath)")
        print("preset: \(result.exportPresetName)")
        print("export: \(result.exportCommand)")
        if !result.edit.isValid {
            for issue in result.edit.issues { FileHandle.standardError.write(Data("\(issue)\n".utf8)) }
            exit(2)
        }
    } catch {
        fail(error.localizedDescription)
    }

case "auto":
    // One-click (คลิกเดียวจบ): real video in → ffmpeg extracts analysis
    // audio → optional whisper Thai transcription → auto-edit → FCPXML that
    // references the original footage, so it opens online in Final Cut Pro.
    guard arguments.count >= 2, !arguments[1].hasPrefix("--") else {
        fail("usage: ghostly auto <video> [--command \"...\"] [--model ggml.bin] [--whisper path] [--preset name] [--remember] [--diarize] [--clean] [--lang th] [--project name] [--out file.fcpxml]")
    }
    let videoPath = (arguments[1] as NSString).expandingTildeInPath
    guard FileManager.default.fileExists(atPath: videoPath) else {
        fail("ไม่พบไฟล์วิดีโอ '\(videoPath)'")
    }
    do {
        let videoURL = URL(fileURLWithPath: videoPath).standardizedFileURL
        let base = (videoURL.lastPathComponent as NSString).deletingPathExtension
        let language = option("lang", in: arguments) ?? "th"

        // 1. Analysis audio straight off the real footage. Apple platforms
        // decode natively via AVFoundation — zero external tools — with
        // ffmpeg as the fallback (and the only path elsewhere). 16 kHz so
        // the same samples can feed whisper.cpp.
        var decodedAudio: WAV.Audio?
        #if canImport(AVFoundation)
        do {
            print("• แตกเสียงจากวิดีโอด้วยเอนจิน macOS (ไม่ต้องติดตั้งอะไรเพิ่ม)")
            let native = try await AVAudioSampleProvider(sampleRate: 16_000)
                .monoSamples(for: videoURL)
            decodedAudio = WAV.Audio(samples: native.samples, sampleRate: native.sampleRate)
        } catch {
            print("  เอนจิน macOS อ่านไฟล์นี้ไม่ได้ (\(error.localizedDescription)) — ลองใช้ ffmpeg แทน")
        }
        #endif
        let tempWAV = FileManager.default.temporaryDirectory
            .appendingPathComponent("ghostly-auto-\(UUID().uuidString).wav").path
        defer { try? FileManager.default.removeItem(atPath: tempWAV) }
        if decodedAudio == nil {
            guard toolOnPath("ffmpeg") else {
                fail("อ่านเสียงจากไฟล์นี้ไม่ได้ — ติดตั้ง ffmpeg แล้วลองใหม่ (ดูวิธีใน `ghostly doctor`)")
            }
            print("• แตกเสียงจากวิดีโอด้วย ffmpeg")
            try runTool("ffmpeg", ["-hide_banner", "-loglevel", "error"]
                + MediaExtraction().audioArguments(input: videoURL.path, output: tempWAV))
            decodedAudio = try WAV.decode(contentsOf: URL(fileURLWithPath: tempWAV))
        }
        guard let audio = decodedAudio else {
            fail("อ่านเสียงจากไฟล์นี้ไม่ได้")
        }

        // 2. Thai captions when a whisper.cpp model is provided.
        var srtContent: String?
        if let modelPath = option("model", in: arguments) {
            let whisperPath = option("whisper", in: arguments) ?? "whisper-cli"
            guard toolOnPath(whisperPath) else {
                fail("ไม่พบ \(whisperPath) — ติดตั้ง whisper.cpp หรือระบุ --whisper <path> (ดู `ghostly doctor`)")
            }
            print("• ถอดเสียงเป็นคำบรรยายด้วย whisper (\(language))")
            // whisper reads a WAV file; write one when the native decode
            // skipped the ffmpeg temp file.
            if !FileManager.default.fileExists(atPath: tempWAV) {
                try WAV.encode(audio).write(to: URL(fileURLWithPath: tempWAV))
            }
            let transcriber = WhisperCLITranscriber(executablePath: whisperPath,
                                                    modelPath: modelPath)
            let track = try await transcriber.transcribe(
                URL(fileURLWithPath: tempWAV), language: language)
            srtContent = SRT.serialize(track.groupedIntoSentences())
        } else {
            print("• ข้ามคำบรรยาย (ใส่ --model <ggml.bin> เพื่อถอดเสียงอัตโนมัติ)")
        }

        // 3–6. The full workflow, with the FCPXML pointing at the footage.
        let request = Workflow.Request(
            audio: audio,
            subtitles: srtContent,
            command: option("command", in: arguments) ?? "ตัดช่วงเงียบออก ใส่คำบรรยาย",
            language: language,
            diarize: arguments.contains("--diarize"),
            cleanAudio: arguments.contains("--clean"),
            clipName: videoURL.lastPathComponent,
            projectName: option("project", in: arguments) ?? base,
            exportPresetName: option("preset", in: arguments),
            mediaURL: videoURL)
        let result: Workflow.Result
        if arguments.contains("--remember") {
            let home = ProcessInfo.processInfo.environment["GHOSTLY_HOME"]
                .map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".ghostly")
            result = try await Workflow.run(request, memory: PreferenceStore(directory: home))
        } else {
            result = try Workflow.run(request)
        }
        let outPath = option("out", in: arguments) ?? "\(base).fcpxml"
        try result.edit.fcpxml.write(toFile: outPath, atomically: true, encoding: .utf8)
        for step in result.steps { print("• \(step)") }
        // Bonus when a transcript exists: the YouTube chapter block, written
        // next to the FCPXML whenever YouTube's validity rules are met.
        if let srtContent {
            let parsed = try SRT.parse(srtContent)
            let transcript = SubtitleTrack(language: language, cues: parsed.cues)
            let analysis = MediaAnalysis(assetID: AssetID(), duration: audio.duration,
                                         speechRanges: parsed.cues.map(\.range))
            let markers = HighlightPlanner().chapters(from: analysis, transcript: transcript)
            if let chapters = ChapterExport.youTubeDescription(markers: markers,
                                                               duration: audio.duration) {
                let chaptersPath = (outPath as NSString).deletingPathExtension + "-chapters.txt"
                try chapters.write(toFile: chaptersPath, atomically: true, encoding: .utf8)
                print("• เขียน YouTube chapters → \(chaptersPath)")
            }
        }
        print("fcpxml: \(outPath) — นำเข้า Final Cut Pro ได้ทันที ฟุตเทจออนไลน์")
        print("preset: \(result.exportPresetName)")
        print("export: \(result.exportCommand)")
        if !result.edit.isValid {
            for issue in result.edit.issues { FileHandle.standardError.write(Data("\(issue)\n".utf8)) }
            exit(2)
        }
    } catch {
        fail(error.localizedDescription)
    }

case "analyze-audio":
    guard arguments.count >= 2 else { fail("usage: ghostly analyze-audio <file.wav>") }
    do {
        let audio = try WAV.decode(contentsOf: URL(fileURLWithPath: arguments[1]))
        print("duration: \(String(format: "%.2f", audio.duration.seconds))s @ \(audio.sampleRate)Hz")
        let rms = Loudness.rmsDBFS(of: audio.samples)
        let lufs = Loudness.lufs(of: audio.samples, sampleRate: audio.sampleRate)
        func db(_ v: Double?, _ unit: String) -> String {
            v.map { String(format: "%.1f \(unit)", $0) } ?? "silence"
        }
        print("loudness: \(db(rms, "dBFS")) (RMS), \(db(lufs, "LUFS")) (K-weighted)")
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
        if arguments.contains("--diarize") {
            let turns = SpeakerDiarizer().turns(samples: audio.samples,
                                                sampleRate: audio.sampleRate,
                                                speechRanges: speech.map(\.range))
            print("speakers: \(SpeakerDiarizer.speakerCount(turns))")
            for turn in turns {
                let start = String(format: "%.2f", turn.range.start.seconds)
                let end = String(format: "%.2f", turn.range.end.seconds)
                print("  \(start)s – \(end)s  \(turn.speaker)")
            }
        }
    } catch {
        fail(error.localizedDescription)
    }

case "normalize-audio":
    guard arguments.count >= 2 else {
        fail("usage: ghostly normalize-audio <in.wav> [--target -16] [--lufs] [--peak -1]")
    }
    do {
        let audio = try WAV.decode(contentsOf: URL(fileURLWithPath: arguments[1]))
        let target = option("target", in: arguments).flatMap(Double.init) ?? -16
        let ceiling = option("peak", in: arguments).flatMap(Double.init) ?? -1
        let outPath = option("out", in: arguments)
            ?? ((arguments[1] as NSString).deletingPathExtension + "-normalized.wav")
        func db(_ v: Double?, _ unit: String) -> String {
            v.map { String(format: "%.1f \(unit)", $0) } ?? "silence"
        }
        let leveled: [Float]
        if arguments.contains("--lufs") {
            // K-weighted (perceptual) target — ใช้ LUFS แทน RMS แบบเรียบ ๆ.
            let before = Loudness.lufs(of: audio.samples, sampleRate: audio.sampleRate)
            leveled = Loudness.lufsNormalized(audio.samples, sampleRate: audio.sampleRate,
                                              targetLUFS: target, peakCeilingDBFS: ceiling)
            let after = Loudness.lufs(of: leveled, sampleRate: audio.sampleRate)
            print("lufs: \(db(before, "LUFS")) → \(db(after, "LUFS")) (target \(String(format: "%.1f", target)), peak ceiling \(String(format: "%.1f", ceiling)))")
        } else {
            let before = Loudness.rmsDBFS(of: audio.samples)
            leveled = Loudness.normalized(audio.samples, targetDBFS: target, peakCeilingDBFS: ceiling)
            let after = Loudness.rmsDBFS(of: leveled)
            print("rms: \(db(before, "dBFS")) → \(db(after, "dBFS")) (target \(String(format: "%.1f", target)), peak ceiling \(String(format: "%.1f", ceiling)))")
        }
        try WAV.encode(WAV.Audio(samples: leveled, sampleRate: audio.sampleRate))
            .write(to: URL(fileURLWithPath: outPath))
        print("wrote \(outPath)")
    } catch {
        fail(error.localizedDescription)
    }

case "clean-audio":
    guard arguments.count >= 2 else {
        fail("usage: ghostly clean-audio <in.wav> [--highpass 80] [--dehum 50|60] [--gate -45]")
    }
    do {
        let audio = try WAV.decode(contentsOf: URL(fileURLWithPath: arguments[1]))
        let value = { (name: String) in option(name, in: arguments).flatMap(Double.init) }
        var cleanup = AudioCleanup()
        if let hp = value("highpass") { cleanup.highPassHz = hp > 0 ? hp : nil }
        cleanup.humHz = value("dehum")
        if let gate = value("gate") { cleanup.gateThresholdDB = gate < 0 ? gate : nil }
        let cleaned = cleanup.process(audio.samples, sampleRate: audio.sampleRate)
        let outPath = option("out", in: arguments)
            ?? ((arguments[1] as NSString).deletingPathExtension + "-clean.wav")
        try WAV.encode(WAV.Audio(samples: cleaned, sampleRate: audio.sampleRate))
            .write(to: URL(fileURLWithPath: outPath))
        func db(_ v: Double?) -> String { v.map { String(format: "%.1f dBFS", $0) } ?? "silence" }
        print("wrote \(outPath)")
        print("rms: \(db(Loudness.rmsDBFS(of: audio.samples))) → \(db(Loudness.rmsDBFS(of: cleaned)))")
        var stages: [String] = []
        if let hp = cleanup.highPassHz { stages.append("high-pass \(Int(hp)) Hz") }
        if let hum = cleanup.humHz { stages.append("de-hum \(Int(hum)) Hz ×3") }
        if let gate = cleanup.gateThresholdDB { stages.append("gate \(String(format: "%.0f", gate)) dB") }
        print("stages: \(stages.joined(separator: ", "))")
    } catch {
        fail(error.localizedDescription)
    }

case "extract-audio":
    guard arguments.count >= 2 else { fail("usage: ghostly extract-audio <video> [--out file.wav] [--run]") }
    let input = arguments[1]
    let output = option("out", in: arguments) ?? ((input as NSString).deletingPathExtension + ".wav")
    let rate = option("rate", in: arguments).flatMap(Int.init) ?? 16_000
    if arguments.contains("--run") {
        // Actually produce the WAV instead of printing the recipe.
        guard toolOnPath("ffmpeg") else {
            fail("ต้องติดตั้ง ffmpeg ก่อน (ดูวิธีติดตั้งใน `ghostly doctor`)")
        }
        do {
            try runTool("ffmpeg", ["-hide_banner", "-loglevel", "error"]
                + MediaExtraction().audioArguments(input: input, output: output, sampleRate: rate))
            print("wrote \(output)")
        } catch {
            fail(error.localizedDescription)
        }
    } else {
        // Default prints the command; the studio does not assume ffmpeg.
        print(MediaExtraction().audioCommandLine(input: input, output: output, sampleRate: rate))
    }

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

case "lut":
    do {
        let value = { (name: String) in option(name, in: arguments).flatMap(Double.init) }
        var grade = ColorAdjustments(
            exposureEV: value("exposure") ?? 0,
            contrast: value("contrast") ?? 1,
            saturation: value("saturation") ?? 1,
            temperature: value("temperature") ?? 0,
            tint: value("tint") ?? 0)
        if let neutralize = option("neutralize", in: arguments) {
            // Gray-world auto white balance from a frame-average color.
            let parts = neutralize.split(separator: " ").compactMap { Double($0) }
            guard parts.count == 3 else {
                fail("--neutralize expects \"r g b\" in 0…1, e.g. \"0.55 0.45 0.35\"")
            }
            let wb = AutoWhiteBalance.estimate(averageColor: RGB(parts[0], parts[1], parts[2]))
            grade.temperature = wb.temperature
            grade.tint = wb.tint
        }
        let size = option("size", in: arguments).flatMap(Int.init) ?? 33
        let lut = try grade.lut(size: size, title: option("title", in: arguments))
        let cube = lut.serialized()
        if let outPath = option("out", in: arguments) {
            try cube.write(toFile: outPath, atomically: true, encoding: .utf8)
            print("wrote \(outPath) (size \(size), \(lut.table.count) entries)")
        } else {
            print(cube, terminator: "")
        }
    } catch {
        fail(error.localizedDescription)
    }

case "lut-info":
    guard arguments.count >= 2 else { fail("usage: ghostly lut-info <file.cube>") }
    do {
        let lut = try CubeLUT.parse(readFile(arguments[1]))
        print("title: \(lut.title ?? "(none)")")
        print("size: \(lut.size) (\(lut.table.count) entries)")
        let mid = lut.sample(RGB(0.5, 0.5, 0.5))
        print(String(format: "mid-gray → %.4f %.4f %.4f", mid.r, mid.g, mid.b))
        print("✓ valid 3D cube LUT")
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
