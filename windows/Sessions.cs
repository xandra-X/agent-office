using System.Text;
using System.Text.Json;

namespace AgentOffice;

sealed record Session(string Id, string Provider, string? Directory, string Title, string Project, string Action)
{
    public string State => "working";
}

sealed record Snapshot(IReadOnlyList<string> Sources, IReadOnlyList<Session> Sessions);

static class Sessions
{
    static readonly TimeSpan MaxSilence = TimeSpan.FromMinutes(45);

    public static Snapshot Read()
    {
        var user = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var codex = Config("CODEX_HOME", Path.Combine(user, ".codex"));
        var claude = Config("CLAUDE_CONFIG_DIR", Path.Combine(user, ".claude"));
        var copilot = Config("COPILOT_HOME", Path.Combine(user, ".copilot"));
        var gemini = Config("GEMINI_CLI_HOME", user);
        var providers = new[]
        {
            ("Codex", Path.Combine(codex, "sessions")),
            ("Claude Code", Path.Combine(claude, "projects")),
            ("Copilot CLI", Path.Combine(copilot, "session-state")),
            ("Gemini CLI", Path.Combine(gemini, ".gemini", "tmp"))
        };
        var titles = Tail(Path.Combine(codex, "session_index.jsonl"), 1_000_000)
            .Select(Parse).Where(row => Get(row, "id").Text() is not null && Get(row, "thread_name").Text() is not null)
            .GroupBy(row => Get(row, "id").Text()!, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => Get(group.Last(), "thread_name").Text()!, StringComparer.OrdinalIgnoreCase);
        var sources = new List<string>();
        var active = new Dictionary<string, (Session Value, DateTime Modified)>();
        foreach (var (provider, directory) in providers)
        {
            if (!Directory.Exists(directory)) continue;
            sources.Add(provider);
            try
            {
                var options = new EnumerationOptions
                {
                    RecurseSubdirectories = true, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.ReparsePoint
                };
                foreach (var file in Directory.EnumerateFiles(directory, "*", options))
                {
                    if (!IsTranscript(provider, file)) continue;
                    try
                    {
                        var modified = File.GetLastWriteTimeUtc(file);
                        if (DateTime.UtcNow - modified > MaxSilence) continue;
                        var session = ReadSession(provider, file, titles);
                        if (session is not null && (!active.TryGetValue(session.Id, out var previous) || previous.Modified < modified))
                            active[session.Id] = (session, modified);
                    }
                    catch (IOException) { }
                    catch (UnauthorizedAccessException) { }
                }
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
        return new(sources, active.Values.OrderByDescending(item => item.Modified).ThenBy(item => item.Value.Id)
            .Select(item => item.Value).ToList());
    }

    static string Config(string key, string fallback)
    {
        var value = Environment.GetEnvironmentVariable(key);
        return string.IsNullOrWhiteSpace(value) ? fallback : value;
    }

    static bool IsTranscript(string provider, string file)
    {
        var name = Path.GetFileName(file);
        var extension = Path.GetExtension(file);
        var parent = Path.GetFileName(Path.GetDirectoryName(file));
        return provider switch
        {
            "Codex" => extension == ".jsonl",
            "Claude Code" => extension == ".jsonl" && parent != "subagents" && Guid.TryParse(Path.GetFileNameWithoutExtension(file), out _),
            "Copilot CLI" => name == "events.jsonl",
            "Gemini CLI" => (extension is ".jsonl" or ".json") && parent == "chats" && name.StartsWith("session-", StringComparison.Ordinal),
            _ => false
        };
    }

    static Session? ReadSession(string provider, string file, IReadOnlyDictionary<string, string> titles)
    {
        var id = Path.GetFileNameWithoutExtension(file);
        string? directory = null, title = null, action = null;
        bool? working = null;

        if (Path.GetExtension(file) == ".json")
        {
            if (new FileInfo(file).Length > 8_000_000) return null;
            var record = Parse(File.ReadAllText(file));
            if (Get(record, "kind").Text() == "subagent") return null;
            id = Get(record, "sessionId").Text() ?? id;
            title = Get(record, "summary").Text();
            working = Elements(Get(record, "messages")).Reverse().Select(GeminiState).FirstOrDefault(state => state.HasValue);
        }
        else
        {
            var metadata = Head(file).Take(40).Select(Parse).ToArray();
            if (provider == "Codex")
            {
                var meta = Get(metadata.FirstOrDefault(), "payload");
                var source = Get(meta, "source");
                if (!Guid.TryParse(Get(meta, "id").Text(), out var guid) ||
                    Get(source, "subagent").ValueKind != JsonValueKind.Undefined || source.Text() == "exec") return null;
                id = guid.ToString("D");
                directory = Get(meta, "cwd").Text();
                titles.TryGetValue(id, out title);
            }
            else if (provider == "Copilot CLI")
            {
                id = Path.GetFileName(Path.GetDirectoryName(file)) ?? id;
                var meta = metadata.FirstOrDefault(row => Get(row, "type").Text() == "session.start");
                directory = Get(Get(Get(meta, "data"), "context"), "cwd").Text();
            }
            else if (provider == "Gemini CLI")
            {
                var meta = metadata.FirstOrDefault(row => Get(row, "sessionId").Text() is not null);
                if (Get(meta, "kind").Text() == "subagent") return null;
                id = Get(meta, "sessionId").Text() ?? id;
                title = Get(meta, "summary").Text();
            }

            foreach (var line in Tail(file, 512_000).Reverse())
            {
                var row = Parse(line);
                directory ??= Get(row, "cwd").Text();
                if (provider == "Claude Code") title ??= Get(row, "customTitle").Text();
                if (!working.HasValue) (working, action) = Observe(provider, row, action);
                if (working.HasValue && (provider != "Claude Code" || title is not null)) break;
            }
        }

        if (working != true) return null;
        var project = directory is null ? "" : Path.GetFileName(Path.TrimEndingDirectorySeparator(directory));
        return new(provider == "Codex" ? id : provider + ":" + id, provider, directory,
            title ?? (project.Length > 0 ? project : "Session " + id[^Math.Min(id.Length, 6)..]),
            project, action ?? "Working on this task");
    }

    static (bool?, string?) Observe(string provider, JsonElement row, string? action)
    {
        var type = Get(row, "type").Text();
        if (provider == "Codex")
        {
            var payload = Get(row, "payload");
            var kind = Get(payload, "type").Text();
            if (type == "event_msg")
            {
                if (kind is "task_started" or "turn_started") return (true, action);
                if (kind is "task_complete" or "turn_complete" or "turn_aborted") return (false, null);
            }
            action ??= kind switch
            {
                "function_call" or "custom_tool_call" => ToolAction(Get(payload, "name").Text()),
                "function_call_output" or "custom_tool_call_output" => "Processing a tool result",
                "web_search_call" => "Checking online sources",
                _ => null
            };
        }
        else if (provider == "Claude Code")
        {
            if (Get(row, "isSidechain").ValueKind == JsonValueKind.True || Get(row, "isMeta").ValueKind == JsonValueKind.True)
                return (null, action);
            var message = Get(row, "message");
            if (type == "user") return (true, action ?? (Elements(Get(message, "content"))
                .Any(block => Get(block, "type").Text() == "tool_result") ? "Processing a tool result" : "Reading the request"));
            if (type == "assistant")
            {
                var reason = Get(message, "stop_reason").Text();
                if (reason is "end_turn" or "stop_sequence" or "refusal") return (false, null);
                if (reason == "tool_use")
                {
                    var tool = Elements(Get(message, "content")).LastOrDefault(block => Get(block, "type").Text() == "tool_use");
                    return (true, action ?? ToolAction(Get(tool, "name").Text()));
                }
            }
        }
        else if (provider == "Copilot CLI")
        {
            if (type is "assistant.turn_end" or "session.shutdown" or "session.error" or "permission.requested")
                return (false, null);
            if (type is "assistant.turn_start" or "user.message" or "permission.completed")
                return (true, action);
            if (type == "tool.execution_start") action ??= ToolAction(Get(Get(row, "data"), "toolName").Text());
            if (type == "tool.execution_complete") action ??= "Processing a tool result";
        }
        else if (provider == "Gemini CLI")
        {
            var tool = Elements(Get(row, "toolCalls")).LastOrDefault();
            if (tool.ValueKind != JsonValueKind.Undefined) action ??= ToolAction(Get(tool, "name").Text());
            return (GeminiState(row), action);
        }
        return (null, action);
    }

    static bool? GeminiState(JsonElement row) => Get(row, "type").Text() switch
    {
        "user" => true,
        "gemini" when !Elements(Get(row, "toolCalls")).Any() => false,
        "error" => false,
        _ => null
    };

    static string ToolAction(string? name) => name?.ToLowerInvariant() switch
    {
        "exec_command" or "bash" or "run_shell_command" => "Running a command",
        "apply_patch" or "edit" or "write" or "write_file" or "replace" => "Editing files",
        "read" or "read_file" or "read_many_files" or "view" => "Reading files",
        "glob" or "grep" or "grep_search" => "Searching the project",
        _ => "Using a tool"
    };

    static IEnumerable<JsonElement> Elements(JsonElement value) =>
        value.ValueKind == JsonValueKind.Array ? value.EnumerateArray() : [];

    internal static JsonElement Get(JsonElement value, string key) =>
        value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out var result) ? result : default;

    internal static string? Text(this JsonElement value) => value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    static JsonElement Parse(string line)
    {
        try { using var doc = JsonDocument.Parse(line); return doc.RootElement.Clone(); }
        catch (JsonException) { return default; }
    }

    static string[] Head(string path) => ReadLines(path, 64_000, fromEnd: false);
    static string[] Tail(string path, int bytes) => ReadLines(path, bytes, fromEnd: true);

    static string[] ReadLines(string path, int limit, bool fromEnd)
    {
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            var offset = fromEnd ? Math.Max(0, stream.Length - limit) : 0;
            stream.Position = offset;
            var bytes = new byte[Math.Min(limit, stream.Length - offset)];
            var count = stream.ReadAtLeast(bytes, bytes.Length, throwOnEndOfStream: false);
            var lines = Encoding.UTF8.GetString(bytes, 0, count).Split('\n');
            return offset > 0 ? lines[1..] : lines;
        }
        catch (IOException) { return []; }
        catch (UnauthorizedAccessException) { return []; }
    }
}
