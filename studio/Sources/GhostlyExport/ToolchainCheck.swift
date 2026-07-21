import Foundation

/// First-run readiness check (Workflow Constitution v5: usable by one editor
/// with minimal setup). The studio's engines are pure Swift, but the
/// real-media pipeline shells out to two optional external tools —
/// `ffmpeg` (extract WAV/frames from video) and `whisper-cli` (Thai ASR).
/// This reports, in Thai, which are present and how to install what's
/// missing. The report formatting is pure and testable; the CLI supplies
/// the actual `which`-probe results.
public enum ToolchainCheck {
    public struct Tool: Sendable, Equatable {
        public let name: String
        /// What the studio uses it for (Thai).
        public let purpose: String
        /// How to install it (Thai + command).
        public let installHint: String
        /// True when the studio still works without it (degraded).
        public let optional: Bool

        public init(name: String, purpose: String, installHint: String, optional: Bool) {
            self.name = name
            self.purpose = purpose
            self.installHint = installHint
            self.optional = optional
        }
    }

    /// External tools the real-media workflow can use. Both are optional:
    /// the FCPXML/edit engine runs without them, but Thai audio → captions
    /// needs whisper-cli and video → WAV needs ffmpeg.
    public static let tools: [Tool] = [
        Tool(name: "ffmpeg",
             purpose: "แปลงวิดีโอเป็น WAV และดึงเฟรมสำหรับวิเคราะห์",
             installHint: "ติดตั้งด้วย Homebrew: brew install ffmpeg",
             optional: true),
        Tool(name: "whisper-cli",
             purpose: "ถอดเสียงภาษาไทยเป็นคำบรรยาย (whisper.cpp)",
             installHint: "ติดตั้ง whisper.cpp: brew install whisper-cpp (หรือ build เอง) แล้วดาวน์โหลดโมเดล ggml เช่น ggml-large-v3.bin",
             optional: true),
    ]

    public struct Report: Sendable, Equatable {
        public let lines: [String]
        /// True when every non-optional tool is present (currently always
        /// true, since both are optional — the engine core needs neither).
        public let coreReady: Bool
        /// True when every tool, including optional ones, is present.
        public let fullyEquipped: Bool
    }

    /// Builds the Thai readiness report from probe results (tool name → found).
    public static func report(found: [String: Bool]) -> Report {
        var lines: [String] = ["เครื่องมือภายนอกสำหรับสื่อจริง:"]
        var coreReady = true
        var fullyEquipped = true
        for tool in tools {
            let present = found[tool.name] ?? false
            let mark = present ? "✓" : "✗"
            lines.append("  \(mark) \(tool.name) — \(tool.purpose)")
            if !present {
                lines.append("      → \(tool.installHint)")
                fullyEquipped = false
                if !tool.optional { coreReady = false }
            }
        }
        if fullyEquipped {
            lines.append("พร้อมใช้งานเต็มรูปแบบ ✓ (วิดีโอ → ถอดเสียงไทย → ตัดต่อ → FCPXML)")
        } else {
            lines.append("เอนจินหลัก (ตัดต่อ/FCPXML/ซับจาก SRT) ใช้งานได้เลยโดยไม่ต้องมีเครื่องมือข้างต้น")
        }
        return Report(lines: lines, coreReady: coreReady, fullyEquipped: fullyEquipped)
    }
}
