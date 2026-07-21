import Foundation
import GhostlyCore
import GhostlyMCP

/// Entry point of `ghostly-mcp-server`: MCP over stdio.
///
/// Register with an MCP client (Claude Code, Cursor, VS Code, …) as:
///     { "command": "ghostly-mcp-server" }
/// Preferences live in ~/.ghostly by default; override with GHOSTLY_HOME.

let home = ProcessInfo.processInfo.environment["GHOSTLY_HOME"]
    .map(URL.init(fileURLWithPath:))
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ghostly")

let logger = Logger(subsystem: "ghostly-mcp-server")

do {
    let server = try await GhostlyMCPFactory.makeServer(preferencesDirectory: home)
    logger.info("ghostly-mcp-server ready (preferences: \(home.path))")
    await StdioTransport(server: server).run()
} catch {
    logger.error("fatal: \(error.localizedDescription)")
    exit(1)
}
