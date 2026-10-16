import SwiftUI

/// A desktop app that can launch Rattle's MCP server, and where it keeps its config.
struct MCPClient: Identifiable {
    let id: String
    let name: String
    let configURL: URL
    /// The app/folder whose presence means the client is installed.
    let marker: URL

    private static let home = FileManager.default.homeDirectoryForCurrentUser
    static let all: [MCPClient] = [
        MCPClient(id: "claude", name: "Claude Desktop",
                  configURL: home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json"),
                  marker: URL(fileURLWithPath: "/Applications/Claude.app")),
        MCPClient(id: "cursor", name: "Cursor",
                  configURL: home.appendingPathComponent(".cursor/mcp.json"),
                  marker: URL(fileURLWithPath: "/Applications/Cursor.app")),
        MCPClient(id: "windsurf", name: "Windsurf",
                  configURL: home.appendingPathComponent(".codeium/windsurf/mcp_config.json"),
                  marker: URL(fileURLWithPath: "/Applications/Windsurf.app")),
    ]

    var installed: Bool {
        FileManager.default.fileExists(atPath: marker.path) || FileManager.default.fileExists(atPath: configURL.deletingLastPathComponent().path)
    }

    private func read() -> [String: Any]? {
        guard let data = try? Data(contentsOf: configURL) else { return [:] }       // no file yet: start fresh
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x09 || $0 == 0x0D }) { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]    // nil = unparseable, never overwrite
    }

    /// The command currently registered for Rattle in this client, if any.
    var registeredCommand: String? {
        ((read()?["mcpServers"] as? [String: Any])?["rattle"] as? [String: Any])?["command"] as? String
    }
    var connected: Bool { registeredCommand == MCPSetup.command }

    func connect() throws {
        guard var root = read() else { throw MCPSetup.Failure("\(configURL.lastPathComponent) isn't valid JSON, so Rattle left it alone.") }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers["rattle"] = ["command": MCPSetup.command, "args": ["--mcp"]]
        root["mcpServers"] = servers
        try write(root)
    }

    func disconnect() throws {
        guard var root = read() else { throw MCPSetup.Failure("\(configURL.lastPathComponent) isn't valid JSON, so Rattle left it alone.") }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers["rattle"] = nil
        root["mcpServers"] = servers
        try write(root)
    }

    private func write(_ root: [String: Any]) throws {
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: configURL, options: .atomic)
    }
}

enum MCPSetup {
    struct Failure: LocalizedError { let message: String; init(_ m: String) { message = m }; var errorDescription: String? { message } }

    /// The binary MCP clients should launch. Moving the app later means connecting again.
    static var command: String { Bundle.main.executablePath ?? CommandLine.arguments[0] }

    static var configSnippet: String {
        let cmd = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {
          "mcpServers": {
            "rattle": {
              "command": "\(cmd)",
              "args": ["--mcp"]
            }
          }
        }
        """
    }

    static var claudeCodeCommand: String { "claude mcp add rattle -- \"\(command)\" --mcp" }
}

struct MCPTab: View {
    @ObservedObject var store = AppStore.shared
    @LocalState private var refresh = 0
    @LocalState private var message = ""
    @LocalState private var copied = ""

    var body: some View {
        let _ = refresh
        VStack(alignment: .leading, spacing: 14) {
            Text("Rattle can run as a local MCP server so Claude Desktop, Cursor and other apps can search your notes, meetings and dictations. It runs on this Mac, is read-only unless you allow edits, and nothing is sent anywhere by Rattle.")
                .font(Theme.sans(13.5)).foregroundStyle(Theme.muted)

            Card {
                SettingRow(title: "Enable MCP server", detail: "When off, connected apps see no tools.", last: !store.settings.mcpEnabled) {
                    Toggle("", isOn: $store.settings.mcpEnabled.animation(Theme.Motion.standard)).toggleStyle(ThemeSwitchStyle()).labelsHidden()
                }
                // What connected apps can reach, and how to connect them, only matters while the server is on.
                if store.settings.mcpEnabled {
                    SettingRow(title: "Notes", detail: "list_notes, get_note", last: false) {
                        Toggle("", isOn: $store.settings.mcpNotes).toggleStyle(ThemeSwitchStyle()).labelsHidden()
                    }
                    SettingRow(title: "Meetings", detail: "Transcripts and AI summaries: list_meetings, get_meeting", last: false) {
                        Toggle("", isOn: $store.settings.mcpMeetings).toggleStyle(ThemeSwitchStyle()).labelsHidden()
                    }
                    SettingRow(title: "Dictation history", detail: "list_dictations", last: false) {
                        Toggle("", isOn: $store.settings.mcpDictations).toggleStyle(ThemeSwitchStyle()).labelsHidden()
                    }
                    SettingRow(title: "Snippets", detail: "list_snippets", last: false) {
                        Toggle("", isOn: $store.settings.mcpSnippets).toggleStyle(ThemeSwitchStyle()).labelsHidden()
                    }
                    SettingRow(title: "Allow edits", detail: "Let connected apps create, rename, edit and delete notes and meetings. Deletes can't be undone.", last: true) {
                        Toggle("", isOn: $store.settings.mcpAllowEdits).toggleStyle(ThemeSwitchStyle()).labelsHidden()
                    }
                }
            }

            if store.settings.mcpEnabled {
                Text("CONNECT").font(Theme.sans(11, .semibold)).foregroundStyle(Theme.muted).padding(.top, 4)
                Card {
                    ForEach(Array(MCPClient.all.enumerated()), id: \.element.id) { i, c in
                        SettingRow(title: c.name, detail: detail(c), last: i == MCPClient.all.count - 1) {
                            if c.connected { PillButton(title: "Disconnect") { run(c) { try c.disconnect() } } }
                            else { PillButton(title: c.registeredCommand == nil ? "Connect" : "Update", prominent: true) { run(c) { try c.connect() } } }
                        }
                    }
                }
                if !message.isEmpty { Text(message).font(Theme.sans(13)).foregroundStyle(Theme.muted) }

                Text("OTHER APPS").font(Theme.sans(11, .semibold)).foregroundStyle(Theme.muted).padding(.top, 4)
                Card {
                    SettingRow(title: "Config JSON", detail: "Paste into any app that supports MCP servers.", last: false) {
                        PillButton(title: copied == "json" ? "Copied" : "Copy") { copy(MCPSetup.configSnippet, "json") }
                    }
                    SettingRow(title: "Claude Code", detail: "Copy a one-line command to run in your terminal.", last: true) {
                        PillButton(title: copied == "cc" ? "Copied" : "Copy") { copy(MCPSetup.claudeCodeCommand, "cc") }
                    }
                }
                Text(MCPSetup.configSnippet)
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.ink).textSelection(.enabled)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.card))
                Text("Restart the app after connecting. If you move or rename Rattle, connect again so the path stays correct.")
                    .font(Theme.sans(12.5)).foregroundStyle(Theme.muted)
            }
        }
    }

    private func detail(_ c: MCPClient) -> String {
        if c.connected { return "Connected. Restart \(c.name) to pick up changes." }
        if c.registeredCommand != nil { return "Points at a different Rattle location." }
        return c.installed ? "Adds Rattle to its MCP config." : "Not detected, but you can still add the config."
    }

    private func run(_ c: MCPClient, _ op: () throws -> Void) {
        do { try op(); message = "" } catch { message = error.localizedDescription }
        refresh += 1
    }

    private func copy(_ text: String, _ key: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        copied = key
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { if copied == key { copied = "" } }
    }
}
