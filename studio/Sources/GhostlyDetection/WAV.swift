import Foundation
import GhostlyCore

/// Minimal, dependency-free WAV (RIFF) codec. This is the studio's real-audio
/// doorway on every platform: decode any common PCM WAV into the mono Float
/// samples the detectors consume, and encode samples back out. Runs
/// identically on macOS, Linux, and CI — no AVFoundation required.
///
/// Supported on decode: PCM 8-bit unsigned, 16-bit, 24-bit, 32-bit signed,
/// and 32/64-bit IEEE float; any channel count (downmixed to mono by
/// averaging). Encode always writes 16-bit PCM mono.
public enum WAV {
    public struct Audio: Sendable, Equatable {
        /// Mono samples in −1…1.
        public let samples: [Float]
        public let sampleRate: Int

        public init(samples: [Float], sampleRate: Int) {
            self.samples = samples
            self.sampleRate = sampleRate
        }

        public var duration: RationalTime {
            RationalTime(value: Int64(samples.count), timescale: Int32(sampleRate))
        }
    }

    // MARK: Decode

    public static func decode(_ data: Data) throws -> Audio {
        func bail(_ detail: String) -> StudioError {
            .parseFailure(format: "WAV", detail: detail)
        }
        guard data.count >= 44 else { throw bail("file too small for a RIFF header") }
        guard tag(data, at: 0) == "RIFF", tag(data, at: 8) == "WAVE" else {
            throw bail("not a RIFF/WAVE file")
        }

        // Walk chunks: mandatory fmt before data.
        var formatCode: Int?
        var channels = 0
        var sampleRate = 0
        var bitsPerSample = 0
        var payload: Data?

        var cursor = 12
        while cursor + 8 <= data.count {
            let chunkID = tag(data, at: cursor)
            let chunkSize = Int(uint32(data, at: cursor + 4))
            let body = cursor + 8
            guard body + chunkSize <= data.count || chunkID == "data" else {
                throw bail("chunk '\(chunkID)' overruns the file")
            }
            switch chunkID {
            case "fmt ":
                guard chunkSize >= 16 else { throw bail("fmt chunk too small") }
                formatCode = Int(uint16(data, at: body))
                channels = Int(uint16(data, at: body + 2))
                sampleRate = Int(uint32(data, at: body + 4))
                bitsPerSample = Int(uint16(data, at: body + 14))
            case "data":
                payload = data.subdata(in: body..<min(body + chunkSize, data.count))
            default:
                break // LIST/fact/cue…: skip
            }
            // Chunks are word-aligned.
            cursor = body + chunkSize + (chunkSize % 2)
        }

        guard let formatCode else { throw bail("missing fmt chunk") }
        guard let payload, !payload.isEmpty else { throw bail("missing or empty data chunk") }
        guard channels >= 1 else { throw bail("no channels") }
        guard sampleRate > 0 else { throw bail("invalid sample rate") }

        let frames: [Float]
        switch (formatCode, bitsPerSample) {
        case (1, 8):
            frames = payload.map { Float($0) / 127.5 - 1 }
        case (1, 16):
            frames = stride(from: 0, to: payload.count - 1, by: 2).map { i in
                Float(Int16(bitPattern: UInt16(payload[payload.startIndex + i])
                    | UInt16(payload[payload.startIndex + i + 1]) << 8)) / 32768
            }
        case (1, 24):
            frames = stride(from: 0, to: payload.count - 2, by: 3).map { i in
                let raw = UInt32(payload[payload.startIndex + i])
                    | UInt32(payload[payload.startIndex + i + 1]) << 8
                    | UInt32(payload[payload.startIndex + i + 2]) << 16
                let signed = raw >= 0x80_0000 ? Int32(bitPattern: raw | 0xFF00_0000) : Int32(raw)
                return Float(signed) / 8_388_608
            }
        case (1, 32):
            frames = stride(from: 0, to: payload.count - 3, by: 4).map { i in
                Float(Int32(bitPattern: uint32(payload, at: i))) / 2_147_483_648
            }
        case (3, 32):
            frames = stride(from: 0, to: payload.count - 3, by: 4).map { i in
                Float(bitPattern: uint32(payload, at: i))
            }
        case (3, 64):
            frames = stride(from: 0, to: payload.count - 7, by: 8).map { i in
                let lo = UInt64(uint32(payload, at: i))
                let hi = UInt64(uint32(payload, at: i + 4))
                return Float(Double(bitPattern: hi << 32 | lo))
            }
        default:
            throw bail("unsupported format: code \(formatCode), \(bitsPerSample)-bit")
        }

        // Downmix interleaved channels to mono.
        let samples: [Float]
        if channels == 1 {
            samples = frames
        } else {
            let count = frames.count / channels
            samples = (0..<count).map { frame in
                var sum: Float = 0
                for c in 0..<channels { sum += frames[frame * channels + c] }
                return sum / Float(channels)
            }
        }
        guard !samples.isEmpty else { throw bail("data chunk holds no complete frames") }
        return Audio(samples: samples, sampleRate: sampleRate)
    }

    public static func decode(contentsOf url: URL) throws -> Audio {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw StudioError.io(path: url.path, detail: "cannot read WAV file")
        }
        return try decode(data)
    }

    // MARK: Encode (16-bit PCM mono)

    public static func encode(_ audio: Audio) -> Data {
        let sampleRate = UInt32(audio.sampleRate)
        let dataSize = UInt32(audio.samples.count * 2)
        var out = Data(capacity: 44 + Int(dataSize))
        out.append(contentsOf: Array("RIFF".utf8))
        appendUInt32(&out, 36 + dataSize)
        out.append(contentsOf: Array("WAVE".utf8))
        out.append(contentsOf: Array("fmt ".utf8))
        appendUInt32(&out, 16)
        appendUInt16(&out, 1)                    // PCM
        appendUInt16(&out, 1)                    // mono
        appendUInt32(&out, sampleRate)
        appendUInt32(&out, sampleRate * 2)       // byte rate
        appendUInt16(&out, 2)                    // block align
        appendUInt16(&out, 16)                   // bits per sample
        out.append(contentsOf: Array("data".utf8))
        appendUInt32(&out, dataSize)
        for sample in audio.samples {
            let clamped = max(-1, min(1, sample))
            // Round to nearest (not truncate) to keep quantization unbiased.
            let value = Int16((clamped * 32767).rounded())
            appendUInt16(&out, UInt16(bitPattern: value))
        }
        return out
    }

    // MARK: Little-endian helpers

    private static func tag(_ data: Data, at offset: Int) -> String {
        String(bytes: data[data.startIndex + offset ..< data.startIndex + offset + 4],
               encoding: .ascii) ?? ""
    }

    private static func uint16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[data.startIndex + offset])
            | UInt16(data[data.startIndex + offset + 1]) << 8
    }

    private static func uint32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[data.startIndex + offset])
            | UInt32(data[data.startIndex + offset + 1]) << 8
            | UInt32(data[data.startIndex + offset + 2]) << 16
            | UInt32(data[data.startIndex + offset + 3]) << 24
    }

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8(value >> 8))
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8(value >> 24))
    }
}
