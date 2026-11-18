# Agent Office

<img src="icon.png" alt="Pixel-art terminal and desk" width="112">

See which coding agents are working on your computer. Each working session gets a desk in a live 2D office. The sidebar shows the agent, task title when available, and its latest reported action. Completed and idle sessions disappear from the live view.

## Download

Get the ZIP for your system from [GitHub Releases](https://github.com/xandra-X/agent-office/releases). Extract the whole ZIP before launching the app.

| Platform | Open the office | Requirements |
| --- | --- | --- |
| macOS | Open **Agent Office.app**, then hover just under the notch and click **Agent Office**. You can also open it from the menu bar. | macOS 14 or later, Apple silicon or Intel |
| Windows | Open **AgentOffice.exe**, then click its icon in the system tray. Check the hidden-icons menu if you don't see it. | Windows 10 or 11, 64-bit, with the [Microsoft Edge WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/) |

These are early desktop builds. The macOS download is locally signed and has no Apple notarization. The Windows ZIP is portable and has no publisher signature.

## How it works

1. Start Agent Office.
2. Start a task in one of your coding agents as usual. Sign in through that agent if it asks.
3. Open the office to see what is working. The app checks local session activity every four seconds.

Agent Office needs no account or API key. Session detection is read-only and runs locally. The app reads the agents' on-disk session data and does not send that data to a server. **Open in Codex** hands the selected session back to Codex when its desktop link handler is installed. Other agents can open their project folder when the local session provides one.

## Agent coverage

| Agent | macOS | Windows |
| --- | --- | --- |
| Codex | Local sessions | Local sessions |
| Claude Code | Local sessions | Local sessions |
| GitHub Copilot CLI | Local sessions | Local sessions |
| Gemini CLI | Local sessions | Local sessions |
| Cursor | Local transcripts when enabled | — |
| Antigravity | Local transcripts when available | — |
| OpenCode | Local database and legacy session files | — |

Status comes from the entries each agent writes. Local file formats vary by version, and some agents expose more detail than others. Remote and cloud sessions only appear if they write a readable local record. If an agent is missing, start a fresh turn and check whether the agent is saving its session locally.

## Build from source

### macOS

Install Xcode Command Line Tools, then run from the repository root.

```bash
bash macos/build.sh "$PWD/build/Agent Office.app"
open "$PWD/build/Agent Office.app"
```

The script targets your Mac's architecture by default. Set `AGENT_OFFICE_MAC_ARCH` to `arm64` or `x86_64` to build for a specific architecture. Use the app executable's `--status` flag to check which local sessions the reader detects.

### Windows

Install the .NET 10 SDK and the WebView2 Runtime, then run from the repository root.

```powershell
dotnet run --project windows/AgentOffice.csproj
```

To create a portable Windows x64 distribution with the .NET runtime bundled:

```powershell
./windows/package.ps1
```

Keep the published files together. The WebView2 Runtime is installed separately.

## Contribute

Open an issue for a missing agent or an incorrect status. Include your operating system, agent name and version, and steps to reproduce. Remove tokens, prompts and private paths from logs before sharing them.

Agent Office is available under the [MIT License](LICENSE).
