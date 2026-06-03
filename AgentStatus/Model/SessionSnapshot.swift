import Foundation

/// Provider-agnostic view of one live agent session at one moment in time.
/// `id` is namespaced (`"<providerId>:<sessionId>"`) so two providers can't collide.
struct SessionSnapshot: Identifiable, Hashable, Sendable {
    let id: String
    let providerId: String
    let pid: pid_t
    let sessionId: String
    let cwd: URL
    let startedAt: Date
    let updatedAt: Date
    /// Coarse status from the pid.json, possibly refined by `ClaudeCodeProvider`
    /// at merge time (e.g. inferred from the transcript when the file's `status`
    /// was null). `var` so the provider can fill it in once `enriched` is attached.
    var status: SessionStatus
    let waitingFor: String?
    let version: String?
    let kind: String?            // "interactive" | "oneshot" | ...
    let entrypoint: String?
    let isAlive: Bool
    /// Transcript-derived rich state (current tool, tokens, model, etc.).
    /// Nil for providers/sessions that don't expose a transcript.
    var enriched: EnrichedSession? = nil

    var cwdBasename: String {
        cwd.lastPathComponent.isEmpty ? cwd.path : cwd.lastPathComponent
    }

    /// Title to show when no AI title is available. Normally the cwd basename
    /// (the repo name), but some Claude embeddings run with a cwd whose last
    /// path component is a bare UUID (e.g. `.../projects/<uuid>`); there, fall
    /// back to the truncated last user prompt — far more recognizable than a UUID.
    var fallbackTitle: String {
        let base = cwdBasename
        guard UUID(uuidString: base) != nil else { return base }   // canonical 8-4-4-4-12, case-insensitive
        if let prompt = enriched?.lastUserPrompt?
            .trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
            return String(prompt.prefix(60))
        }
        return base   // UUID folder but no prompt yet → last resort
    }

    /// True if this session should get its own NSStatusItem when per-session items are enabled.
    var deservesPerSessionItem: Bool {
        isAlive && (kind == nil || kind == "interactive")
    }
}
