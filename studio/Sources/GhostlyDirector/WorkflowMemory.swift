import Foundation
import GhostlyCore
import GhostlyExport
import GhostlyLearning

/// AI memory for the workflow (Workflow Constitution v5): the studio learns
/// the editor's habits so nothing is configured twice. Running with memory
/// fills unspecified choices from learned favorites ("ใช้ค่าที่เคยใช้" —
/// use my usual) and records what actually got used back into the local
/// preference store.
extension Workflow {
    /// Runs the workflow with the editor's memory:
    /// - an unspecified export preset is pre-filled with the top learned
    ///   favorite (when it still exists),
    /// - the used export preset, caption style, and pacing style are
    ///   recorded so future recommendations improve.
    public static func run(_ request: Request,
                           memory store: PreferenceStore) async throws -> Result {
        var request = request
        if request.exportPresetName == nil,
           let usual = await store.recommendations(for: .exportPreset, limit: 1).first,
           RenderPreset.named(usual) != nil {
            request.exportPresetName = usual
        }

        let result = try run(request)

        // Recording failures must never break an edit that already
        // succeeded; memory is best-effort by design.
        try? await store.recordUse(of: result.exportPresetName, category: .exportPreset)
        try? await store.recordUse(of: result.edit.profileStyle, category: .pacingStyle)
        if let captionStyle = result.edit.captionStyleName {
            try? await store.recordUse(of: captionStyle, category: .captionStyle)
        }
        try? await store.recordPrompt(request.command)
        return result
    }
}
