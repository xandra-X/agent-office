import AppKit
import WebKit
import SQLite3

struct LocalSession: Codable, Equatable {
    enum State: String, Codable { case working, waiting, idle, stale, unknown }
    let id: String
    var provider = "Codex"
    var directory: String?
    var action: String?
    let title: String
    let project: String
    let modifiedAt: Double
    let state: State
}

struct Activity: Codable, Equatable {
    var sources: [String] = []
    var sessions: [LocalSession] = []
    var active: Int { sessions.filter { $0.state == .working }.count }
}

struct CodexActivity {
    let home: URL
    let maxSilence: TimeInterval = 45 * 60

    init() {
        let override = ProcessInfo.processInfo.environment["CODEX_HOME"]
        let path = override.map { ($0 as NSString).expandingTildeInPath }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        home = URL(fileURLWithPath: path, isDirectory: true)
    }

    func snapshot(now: Date = .now) -> Activity {
        let fm = FileManager.default
        let root = home.appendingPathComponent("sessions")
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        let local = otherSessions(now: now)
        guard fm.isReadableFile(atPath: root.path),
              let files = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys),
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return Activity(sources: local.sources, sessions: sorted(local.sessions))
        }
        let titles = sessionTitles()
        var sessions: [String: LocalSession] = [:]
        for case let file as URL in files where file.pathExtension == "jsonl" {
            guard let info = try? file.resourceValues(forKeys: keys), info.isRegularFile == true,
                  let modified = info.contentModificationDate, now.timeIntervalSince(modified) < 86400,
                  let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            guard let head = try? handle.read(upToCount: 64_000), let first = head.split(separator: 10).first,
                  let meta = decoded(first), meta["type"] as? String == "session_meta",
                  let payload = meta["payload"] as? [String: Any],
                  let rawID = payload["id"] as? String, let uuid = UUID(uuidString: rawID) else { continue }
            // Helper rollouts share their parent project, but may have no desktop thread to open.
            if let source = payload["source"] as? [String: Any], source["subagent"] != nil { continue }
            if let source = payload["source"] as? String, source == "exec" { continue }
            let id = uuid.uuidString.lowercased()
            let cwd = payload["cwd"] as? String
            let project = cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
            let (state, action) = codexTurn(handle)
            let session = LocalSession(id: id, action: action, title: titles[id] ?? "Codex session " + id.suffix(6),
                                       project: project, modifiedAt: modified.timeIntervalSince1970,
                                       state: state == .working && now.timeIntervalSince(modified) >= maxSilence ? .stale : state)
            if sessions[id]?.modifiedAt ?? -.infinity < session.modifiedAt { sessions[id] = session }
        }
        return Activity(sources: ["Codex"] + local.sources, sessions: sorted(Array(sessions.values) + local.sessions))
    }

    private func sorted(_ sessions: [LocalSession]) -> [LocalSession] {
        sessions.sorted {
            if ($0.state == .working) != ($1.state == .working) { return $0.state == .working }
            return $0.modifiedAt == $1.modifiedAt ? $0.id < $1.id : $0.modifiedAt > $1.modifiedAt
        }
    }

    private enum Provider: String {
        case claude = "Claude Code", copilot = "Copilot CLI", gemini = "Gemini CLI"
        case cursor = "Cursor", antigravity = "Antigravity", opencode = "OpenCode"
    }

    private func otherSessions(now: Date) -> Activity {
        let fm = FileManager.default
        let user = fm.homeDirectoryForCurrentUser
        let env = ProcessInfo.processInfo.environment
        func root(_ key: String, _ fallback: String) -> URL {
            env[key].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
                ?? user.appendingPathComponent(fallback)
        }

        let geminiHome = root("GEMINI_CLI_HOME", "").appendingPathComponent(".gemini")
        let providers: [(Provider, URL)] = [
            (.claude, root("CLAUDE_CONFIG_DIR", ".claude").appendingPathComponent("projects")),
            (.copilot, root("COPILOT_HOME", ".copilot").appendingPathComponent("session-state")),
            (.gemini, geminiHome.appendingPathComponent("tmp")),
            (.cursor, user.appendingPathComponent(".cursor/projects")),
            (.antigravity, user.appendingPathComponent(".gemini/antigravity/brain")),
            (.antigravity, user.appendingPathComponent(".gemini/antigravity-cli/brain")),
            (.opencode, root("XDG_DATA_HOME", ".local/share").appendingPathComponent("opencode/storage/session"))
        ]
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        var result = Activity()
        var sessions: [String: LocalSession] = [:]
        for (provider, folder) in providers {
            guard fm.isReadableFile(atPath: folder.path),
                  let files = fm.enumerator(at: folder, includingPropertiesForKeys: Array(keys),
                                            options: [.skipsPackageDescendants]) else { continue }
            if !result.sources.contains(provider.rawValue) { result.sources.append(provider.rawValue) }
            for case let file as URL in files {
                let name = file.lastPathComponent
                let parent = file.deletingLastPathComponent().lastPathComponent
                let transcript = file.pathExtension == "jsonl"
                let isSession = switch provider {
                case .claude: transcript && UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil && parent != "subagents"
                case .copilot: transcript && name == "events.jsonl"
                case .gemini: (transcript || file.pathExtension == "json") && parent == "chats" && name.hasPrefix("session-")
                case .cursor: transcript && file.pathComponents.contains("agent-transcripts")
                    && !file.pathComponents.contains("subagents") && !file.pathComponents.contains("subagent-transcripts")
                case .antigravity: parent == "logs" && (name == "transcript.jsonl" || name == "transcript_full.jsonl")
                case .opencode: file.pathExtension == "json" && name.hasPrefix("ses_")
                }
                guard isSession, let info = try? file.resourceValues(forKeys: keys), info.isRegularFile == true,
                      let modified = info.contentModificationDate, now.timeIntervalSince(modified) < 86400,
                      let session = readSession(provider, file: file, modified: modified, now: now) else { continue }
                if sessions[session.id]?.modifiedAt ?? -.infinity < session.modifiedAt { sessions[session.id] = session }
            }
        }
        let openCodeDB = root("XDG_DATA_HOME", ".local/share").appendingPathComponent("opencode/opencode.db")
        if let databaseSessions = openCodeSessions(openCodeDB, now: now) {
            if !result.sources.contains(Provider.opencode.rawValue) { result.sources.append(Provider.opencode.rawValue) }
            for session in databaseSessions { sessions[session.id] = session }
        }
        result.sessions = Array(sessions.values)
        return result
    }

    private func openCodeSessions(_ url: URL, now: Date) -> [LocalSession]? {
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        var database: OpaquePointer?
        let opened = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(database) }
        guard opened == SQLITE_OK else { return nil }
        let query = """
            SELECT s.id, s.title, s.directory, s.time_updated,
              (SELECT m.data FROM message m WHERE m.session_id = s.id
               ORDER BY m.time_created DESC, m.id DESC LIMIT 1)
            FROM session s WHERE s.parent_id IS NULL AND s.time_updated >= ? ORDER BY s.time_updated DESC
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64((now.timeIntervalSince1970 - 86400) * 1000))
        func text(_ index: Int32) -> String? {
            sqlite3_column_text(statement, index).map { String(cString: $0) }
        }
        var sessions: [LocalSession] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = text(0) else { continue }
            let directory = text(2)
            let modified = Double(sqlite3_column_int64(statement, 3)) / 1000
            let message = text(4).flatMap { decoded(Data($0.utf8)) }
            let role = message?["role"] as? String
            let time = message?["time"] as? [String: Any]
            let state: LocalSession.State
            if role == "assistant" && (time?["completed"] is NSNumber || message?["error"] != nil) { state = .idle }
            else if role == "user" || role == "assistant" {
                state = now.timeIntervalSince1970 - modified < maxSilence ? .working : .stale
            } else { state = .unknown }
            sessions.append(LocalSession(id: "OpenCode:" + id, provider: "OpenCode", directory: directory,
                                         title: String((text(1) ?? "OpenCode session").prefix(160)),
                                         project: directory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "",
                                         modifiedAt: modified, state: state))
        }
        return sessions
    }

    private func readSession(_ provider: Provider, file: URL, modified: Date, now: Date) -> LocalSession? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var title: String?
        var directory: String?
        var state = LocalSession.State.unknown
        var action: String?
        var id = file.deletingPathExtension().lastPathComponent
        if provider == .copilot || provider == .antigravity {
            let parents = file.deletingLastPathComponent()
            id = provider == .copilot ? parents.lastPathComponent
                : parents.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        }

        let legacyJSON = file.pathExtension == "json"
        if legacyJSON {
            guard let data = try? handle.read(upToCount: 8_000_000), let record = decoded(data) else { return nil }
            if provider == .gemini {
                if record["kind"] as? String == "subagent" { return nil }
                id = record["sessionId"] as? String ?? id
                title = record["summary"] as? String
                state = geminiState((record["messages"] as? [[String: Any]])?.last ?? [:]) ?? .unknown
            } else {
                directory = record["directory"] as? String
                title = record["title"] as? String
            }
        } else {
            guard let head = try? handle.read(upToCount: 64_000) else { return nil }
            let metadata = head.split(separator: 10).prefix(40).compactMap(decoded)
            for record in metadata {
                directory = directory ?? record["cwd"] as? String
                if provider == .gemini {
                    if record["kind"] as? String == "subagent" { return nil }
                    id = record["sessionId"] as? String ?? id
                    title = record["summary"] as? String ?? title
                } else if provider == .copilot, record["type"] as? String == "session.start",
                          let data = record["data"] as? [String: Any] {
                    directory = (data["context"] as? [String: Any])?["cwd"] as? String ?? directory
                }
            }
            var signal: LocalSession.State?
            for line in tail(handle, limit: 512_000).reversed() {
                guard let record = decoded(line) else { continue }
                directory = directory ?? record["cwd"] as? String
                if provider == .claude, title == nil { title = record["customTitle"] as? String }
                if signal == nil {
                    action = action ?? agentAction(provider, record: record)
                    signal = observedState(provider, record: record)
                }
                if signal != nil && (provider != .claude || title != nil) { break }
            }
            state = signal ?? .unknown
        }
        if state == .working && now.timeIntervalSince(modified) >= maxSilence { state = .stale }
        let project = directory.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
        return LocalSession(id: provider.rawValue + ":" + id, provider: provider.rawValue,
                            directory: directory, action: action, title: String((title ?? "Session " + id.suffix(6)).prefix(160)),
                            project: project, modifiedAt: modified.timeIntervalSince1970, state: state)
    }

    private func geminiState(_ record: [String: Any]) -> LocalSession.State? {
        switch record["type"] as? String {
        case "user": return .working
        case "gemini":
            let calls = record["toolCalls"] as? [[String: Any]] ?? []
            return calls.isEmpty ? .idle : nil
        case "error": return .idle
        default: return nil
        }
    }

    private func observedState(_ provider: Provider, record: [String: Any]) -> LocalSession.State? {
        let kind = record["type"] as? String
        switch provider {
        case .claude:
            if record["isSidechain"] as? Bool == true || record["isMeta"] as? Bool == true { return nil }
            if kind == "user" { return .working }
            if kind == "assistant", let message = record["message"] as? [String: Any] {
                switch message["stop_reason"] as? String {
                case "end_turn", "stop_sequence", "refusal": return .idle
                case "tool_use": return .working
                default: break
                }
            }
        case .copilot:
            if kind == "session.shutdown" || kind == "assistant.turn_end" || kind == "session.error" { return .idle }
            if kind == "permission.requested" { return .waiting }
            if kind == "assistant.turn_start" || kind == "user.message" || kind == "permission.completed" { return .working }
        case .gemini:
            return geminiState(record)
        case .cursor:
            // Transcript roles expose activity, while turn-completion events require hooks.
            if record["role"] as? String == "user" { return .working }
            if record["role"] as? String == "assistant" { return .unknown }
        case .antigravity:
            if kind == "USER_INPUT" { return .working }
            if kind == "PLANNER_RESPONSE" {
                let toolCalls = record["tool_calls"] as? [Any] ?? []
                if record["status"] as? String == "DONE", toolCalls.isEmpty { return .idle }
                return .working
            }
        case .opencode:
            break
        }
        return nil
    }

    private func decoded(_ line: Data.SubSequence) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any]
    }

    private func sessionTitles() -> [String: String] {
        guard let handle = try? FileHandle(forReadingFrom: home.appendingPathComponent("session_index.jsonl")) else { return [:] }
        defer { try? handle.close() }
        var titles: [String: String] = [:]
        for line in tail(handle, limit: 1_000_000) {
            guard let record = decoded(line), let id = record["id"] as? String,
                  let title = record["thread_name"] as? String, !title.isEmpty else { continue }
            titles[id.lowercased()] = String(title.prefix(160))
        }
        return titles
    }

    private func tail(_ handle: FileHandle, limit: Int) -> [Data.SubSequence] {
        guard let length = try? handle.seekToEnd() else { return [] }
        let start = length > UInt64(limit) ? length - UInt64(limit) : 0
        guard (try? handle.seek(toOffset: start)) != nil, let bytes = try? handle.read(upToCount: limit) else { return [] }
        let lines = bytes.split(separator: 10)
        return start == 0 ? lines : Array(lines.dropFirst())
    }

    private func toolAction(_ name: String?, completed: Bool = false) -> String {
        if completed { return "Processing a tool result" }
        switch name?.lowercased() {
        case "exec_command", "bash", "terminal", "shell", "run_shell_command": return "Running a command"
        case "apply_patch", "edit", "multiedit", "write", "edit_file", "write_file", "replace": return "Editing files"
        case "read", "read_file", "read_many_files", "view": return "Reading files"
        case "grep", "glob", "grep_search", "list_directory": return "Searching the project"
        case "websearch", "webfetch", "web_search", "web.run", "google_web_search": return "Checking online sources"
        case "task", "agent", "spawn_agent": return "Delegating work"
        default: return "Using a tool"
        }
    }

    private func agentAction(_ provider: Provider, record: [String: Any]) -> String? {
        let kind = record["type"] as? String
        switch provider {
        case .claude:
            if record["isSidechain"] as? Bool == true || record["isMeta"] as? Bool == true { return nil }
            let message = record["message"] as? [String: Any]
            let blocks = message?["content"] as? [[String: Any]] ?? []
            if kind == "user" {
                return blocks.contains(where: { $0["type"] as? String == "tool_result" })
                    ? "Processing a tool result" : "Reading the request"
            }
            if let tool = blocks.last(where: { $0["type"] as? String == "tool_use" }) {
                return toolAction(tool["name"] as? String)
            }
            if kind == "assistant" { return "Preparing a response" }
        case .copilot:
            if kind == "tool.execution_start" {
                return toolAction((record["data"] as? [String: Any])?["toolName"] as? String)
            }
            if kind == "tool.execution_complete" { return "Processing a tool result" }
            if kind == "assistant.message" { return "Preparing a response" }
        case .gemini:
            if let tools = record["toolCalls"] as? [[String: Any]], let tool = tools.last {
                return toolAction(tool["name"] as? String)
            }
        case .antigravity:
            if kind == "PLANNER_RESPONSE" {
                if let tools = record["tool_calls"] as? [[String: Any]], let tool = tools.last {
                    return toolAction(tool["name"] as? String)
                }
                return "Preparing a response"
            }
        default: break
        }
        return nil
    }

    private func codexTurn(_ handle: FileHandle) -> (LocalSession.State, String?) {
        var action: String?
        for line in tail(handle, limit: 512_000).reversed() {
            guard let record = decoded(line), let payload = record["payload"] as? [String: Any],
                  let type = payload["type"] as? String else { continue }
            if record["type"] as? String == "event_msg" {
                switch type {
                case "task_started", "turn_started": return (.working, action)
                case "task_complete", "turn_complete", "turn_aborted": return (.idle, nil)
                default: break
                }
            }
            guard action == nil else { continue }
            switch type {
            case "function_call", "custom_tool_call": action = toolAction(payload["name"] as? String)
            case "function_call_output", "custom_tool_call_output": action = "Processing a tool result"
            case "web_search_call": action = "Checking online sources"
            case "reasoning": action = "Working through the task"
            case "item_completed":
                let item = payload["item"] as? [String: Any]
                switch item?["type"] as? String {
                case "CommandExecution": action = "Command finished"
                case "FileChange": action = "File changes written"
                case "AgentMessage": action = "Preparing a response"
                default: break
                }
            default: break
            }
        }
        return (.unknown, nil)
    }
}

final class OfficePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

final class NotchButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class OfficeApp: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler {
    private let monitor = CodexActivity()
    private var activity = Activity()
    private var poll: Timer?
    private var busy = false
    private var webReady = false
    private let menuItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var hoverTimer: Timer?
    private var enteredAt: TimeInterval?
    private var exitedAt: TimeInterval?
    private var notchPrompt: NSPanel!
    private let notchPromptHeight: CGFloat = 34
    private var ignoreUntilExit = false
    private var outsideClicks: Any?
    private var panel: OfficePanel!
    private var web: WKWebView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        makeOffice()
        makeNotchPrompt()
        let menu = NSMenu()
        menu.addItem(withTitle: "Toggle Agent Office", action: #selector(toggleOffice), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Agent Office", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        menuItem.menu = menu
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkNotchHover() }
        }
        timer.tolerance = 0.008
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
        updateDisplay()
        poll = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshActivity() }
        }
        refreshActivity()
    }

    func applicationDidChangeScreenParameters(_ notification: Notification) {
        if panel.isVisible { placeOffice() }
        hideNotchPrompt()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !panel.isVisible { toggleOffice() }
        return true
    }

    private var officeScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func checkNotchHover() {
        guard !panel.isVisible, let screen = officeScreen,
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else { return }

        // Use the reachable strip under the camera cutout as part of the hover target.
        let top = screen.frame.maxY
        let bottom = top - screen.safeAreaInsets.top - 9
        let notch = NSRect(x: left.maxX, y: bottom, width: right.minX - left.maxX, height: top - bottom)
        let pointer = NSEvent.mouseLocation
        let overNotch = notch.contains(pointer)
        let now = ProcessInfo.processInfo.systemUptime

        if ignoreUntilExit {
            if !overNotch { ignoreUntilExit = false }
            return
        }

        if notchPrompt.isVisible {
            let overPrompt = notchPrompt.frame.insetBy(dx: -4, dy: -8).contains(pointer)
            if overNotch || overPrompt || NSEvent.pressedMouseButtons != 0 {
                exitedAt = nil
            } else if let exitedAt {
                if now - exitedAt >= 0.28 { hideNotchPrompt() }
            } else {
                exitedAt = now
            }
        } else if !overNotch || NSEvent.pressedMouseButtons != 0 {
            enteredAt = nil
        } else if let enteredAt {
            if now - enteredAt >= 0.15 {
                revealNotchPrompt(centerX: notch.midX, width: max(110, notch.width),
                                  top: top - screen.safeAreaInsets.top)
                self.enteredAt = nil
            }
        } else {
            enteredAt = now
        }
    }

    private func revealNotchPrompt(centerX: CGFloat, width: CGFloat, top: CGFloat) {
        let expanded = NSRect(x: centerX - width / 2, y: top - notchPromptHeight,
                              width: width, height: notchPromptHeight)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            notchPrompt.setFrame(expanded, display: true)
            notchPrompt.orderFrontRegardless()
            return
        }

        let collapsed = NSRect(x: expanded.minX, y: top - 2, width: width, height: 2)
        notchPrompt.setFrame(collapsed, display: true)
        notchPrompt.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.19
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            notchPrompt.animator().setFrame(expanded, display: true)
        }
    }

    private func makeNotchPrompt() {
        let size = NSSize(width: 110, height: notchPromptHeight)
        notchPrompt = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        notchPrompt.level = .statusBar
        notchPrompt.isOpaque = false
        notchPrompt.backgroundColor = .clear
        notchPrompt.hasShadow = false
        notchPrompt.hidesOnDeactivate = false
        notchPrompt.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let button = NotchButton(frame: NSRect(origin: .zero, size: size))
        button.title = ""
        button.isBordered = false
        button.setAccessibilityLabel("Open Agent Office")
        button.toolTip = nil
        button.target = self
        button.action = #selector(openOffice)
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.black.cgColor
        button.layer?.cornerRadius = 8
        button.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]

        let symbol = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: nil)!
        let attachment = NSTextAttachment()
        attachment.image = symbol.withSymbolConfiguration(.init(pointSize: 9, weight: .medium))
        attachment.bounds = NSRect(x: 0, y: -1, width: 10, height: 10)
        let caption = NSMutableAttributedString(attachment: attachment)
        caption.append(NSAttributedString(string: "  Agent Office"))
        caption.addAttributes([
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.93, alpha: 1)
        ], range: NSRange(location: 0, length: caption.length))
        button.attributedTitle = caption
        button.alignment = .center
        notchPrompt.contentView = button
    }

    private func hideNotchPrompt() {
        notchPrompt.orderOut(nil)
        enteredAt = nil
        exitedAt = nil
    }

    private func makeOffice() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(self, name: "officeReady")
        config.userContentController.add(self, name: "openSession")
        web = WKWebView(frame: .zero, configuration: config)
        panel = OfficePanel(contentRect: NSRect(x: 0, y: 0, width: 870, height: 660),
                            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "Agent Office"
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = web
        if let index = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Office") {
            web.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        }
    }

    private func placeOffice() {
        guard let screen = officeScreen else { return }
        let safe = screen.visibleFrame
        let width = min(870, safe.width - 24)
        let height = min(680, safe.height - 12)
        panel.setFrame(NSRect(x: safe.midX - width/2, y: safe.maxY - height - 3, width: width, height: height), display: true)
    }

    @objc private func toggleOffice() {
        if panel.isVisible { closeOffice() }
        else { openOffice() }
    }

    @objc private func openOffice() {
        hideNotchPrompt()
        placeOffice()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if outsideClicks == nil {
            outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let self, self.panel.isVisible { self.closeOffice() }
                }
            }
        }
        updateVisibility()
        refreshActivity()
    }

    private func closeOffice() {
        if let outsideClicks {
            NSEvent.removeMonitor(outsideClicks)
            self.outsideClicks = nil
        }
        panel.orderOut(nil)
        ignoreUntilExit = true
        updateVisibility()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeOffice()
        return false
    }

    func applicationDidResignActive(_ notification: Notification) {
        if panel?.isVisible == true { closeOffice() }
    }

    func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self, self.panel.isVisible, !self.panel.isKeyWindow else { return }
            self.closeOffice()
        }
    }

    private func updateVisibility() {
        if webReady { web.evaluateJavaScript("window.setOfficeVisibility(\(panel.isVisible))", completionHandler: nil) }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func refreshActivity() {
        guard !busy else { return }
        busy = true
        let reader = monitor
        Task {
            let update = await Task.detached(priority: .utility) { reader.snapshot() }.value
            busy = false
            if update != activity { activity = update; updateDisplay() }
        }
    }

    private func updateDisplay() {
        menuItem.button?.title = activity.active > 0 ? "▦ \(activity.active)" : "▦"
        menuItem.button?.toolTip = activity.active > 0 ? "\(activity.active) active local agent sessions" : "Agent Office · No agents working"
        let live = Activity(sources: activity.sources, sessions: activity.sessions.filter { $0.state == .working })
        if webReady, let encoded = try? JSONEncoder().encode(live),
           let json = String(data: encoded, encoding: .utf8) {
            web.evaluateJavaScript("window.showLocalActivity(\(json))", completionHandler: nil)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true else { return }
        if message.name == "officeReady" {
            webReady = true
            updateDisplay()
            updateVisibility()
        } else if message.name == "openSession", let id = message.body as? String,
                  let session = activity.sessions.first(where: { $0.id == id }) {
            let target: URL?
            if session.provider == "Codex", UUID(uuidString: id) != nil {
                target = URL(string: "codex://threads/" + id)
            } else if let directory = session.directory, directory.hasPrefix("/"),
                      FileManager.default.fileExists(atPath: directory) {
                target = URL(fileURLWithPath: directory, isDirectory: true)
            } else {
                target = nil
            }
            if let target, NSWorkspace.shared.open(target) {
                closeOffice()
            } else {
                web.evaluateJavaScript("window.showSessionOpenError()", completionHandler: nil)
            }
        }
    }
}

if CommandLine.arguments.contains("--status") {
    let result = CodexActivity().snapshot()
    print("Local agent sessions: \(result.active) active, \(result.sessions.count) seen in the past 24 hours")
    for source in result.sources {
        let sessions = result.sessions.filter { $0.provider == source }
        print("\(source): \(sessions.filter { $0.state == .working }.count) active / \(sessions.count) recent")
    }
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = OfficeApp()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
