import Foundation
import GhostlyCore

/// Routes AI tasks to the best-suited registered provider, with automatic
/// fallback when a provider fails: the "Multi-AI System".
public actor ModelRouter {
    public struct Registration: Sendable {
        public let provider: any LLMProvider
        /// Higher wins among providers with equal capability match.
        public let priority: Int

        public init(provider: any LLMProvider, priority: Int = 0) {
            self.provider = provider
            self.priority = priority
        }
    }

    public enum RoutingPolicy: Sendable {
        /// Prefer capability match, then priority.
        case bestMatch
        /// Prefer local providers when they can handle the task at all.
        case preferLocal
    }

    private var registrations: [Registration] = []
    private var policy: RoutingPolicy
    private let logger: GhostlyCore.Logger

    public init(policy: RoutingPolicy = .bestMatch,
                logger: GhostlyCore.Logger = .init(subsystem: "ModelRouter")) {
        self.policy = policy
        self.logger = logger
    }

    public func register(_ provider: any LLMProvider, priority: Int = 0) {
        registrations.append(Registration(provider: provider, priority: priority))
    }

    public func setPolicy(_ policy: RoutingPolicy) {
        self.policy = policy
    }

    public var providerNames: [String] {
        registrations.map(\.provider.name)
    }

    /// Providers able to serve `capability`, in routing order.
    public func candidates(for capability: AICapability) -> [any LLMProvider] {
        let capable = registrations.filter { $0.provider.capabilities.contains(capability) }
        let ordered: [Registration]
        switch policy {
        case .bestMatch:
            ordered = capable.sorted { $0.priority > $1.priority }
        case .preferLocal:
            ordered = capable.sorted {
                let aLocal = $0.provider.capabilities.contains(.local)
                let bLocal = $1.provider.capabilities.contains(.local)
                if aLocal != bLocal { return aLocal }
                return $0.priority > $1.priority
            }
        }
        return ordered.map(\.provider)
    }

    /// Sends the request to the best provider for the capability, falling
    /// back down the candidate list on provider errors.
    public func complete(_ request: LLMRequest,
                         capability: AICapability = .editing) async throws -> LLMResponse {
        let providers = candidates(for: capability)
        guard !providers.isEmpty else {
            throw StudioError.notFound(entity: "LLMProvider", id: capability.rawValue)
        }
        var lastError: Error = StudioError.invariant(detail: "router had no error")
        for provider in providers {
            do {
                let response = try await provider.complete(request)
                logger.debug("routed \(capability.rawValue) to \(provider.name)")
                return response
            } catch {
                logger.warning("provider \(provider.name) failed: \(error.localizedDescription); trying next")
                lastError = error
            }
        }
        throw lastError
    }
}

/// Prompt assembly for the studio's LLM calls: keeps system prompts in one
/// audited place instead of scattered string literals.
public enum PromptLibrary {
    public static func editPlanSystemPrompt() -> String {
        """
        You are the planning engine of a Final Cut Pro AI assistant. \
        Translate the user's editing request into a JSON array of intents. \
        Allowed intents: applyStyle(Marvel|TikTok|Documentary|Vlog|Podcast|Cinematic), \
        createDeliverable(tiktok|youtube|instagram|shorts|reel), \
        adjustPacing(faster|slower), generateCaptions(styleName), removeSilence, \
        cutToBeat, replaceMusic(query), addTransitions(name). \
        Respond with JSON only, no prose.
        """
    }

    public static func assetTaggingSystemPrompt() -> String {
        """
        You label video assets for an asset manager. Given a description of a \
        clip, respond with 3-8 lowercase keyword tags as a JSON string array. \
        Prefer concrete nouns and shot types (e.g. "close-up", "drone", \
        "interview"). Respond with JSON only.
        """
    }
}
