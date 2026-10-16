# Rattle

Talk instead of typing, anywhere on your Mac. Rattle is a native macOS app for dictation and meeting notes: hold a key, speak, and the text lands wherever your cursor is. Speech is transcribed on your Mac with whisper.cpp, or in the cloud with Groq if you prefer.

## Features

- **Dictation everywhere.** Hold `fn` (or Right ⌥ / Right ⌘ / Right ⌃) and speak; press space while holding for hands-free, Esc cancels. Text is cleaned up and typed into the focused app.
- **Meetings.** Records your mic and the call audio, transcribes both sides, and writes notes with your AI model. With Gemini, notes are generated from the recording itself.
- **Notes.** Quick Markdown notes with folders, in a grid or a small floating window.
- **Dictionary and Snippets.** Words Rattle should never get wrong, and short triggers that expand into text you'd otherwise re-type.
- **Style and Transforms.** Per-app tone (casual, formal) and AI rewrites such as Polish, Make concise or Format as email. Command Mode applies a spoken instruction to the selected text.
- **Insights.** Streak, words dictated and speaking speed.
- **MCP server.** Lets Claude Desktop, Cursor, Claude Code and other MCP clients search your notes, meetings and dictations. Read-only unless you allow edits.
- **Migration.** Import from Wispr Flow and Granola, and export everything as CSV.
- **Onboarding.** A short first-run setup: name, appearance, permissions, speech engine and hold key.

## Requirements

- macOS 14.4 or later (built and tested on macOS 26)
- Xcode or the Xcode Command Line Tools (Swift 5.9+)
- For local transcription: `brew install whisper-cpp`. Rattle downloads the Whisper model itself.
- Optional: an OpenAI-compatible AI server for meeting notes and Transforms (LM Studio, Ollama, OpenAI, Gemini, Groq, Mistral, OpenRouter), and a Groq API key for cloud transcription.

## Build and run

```bash
./scripts/build.sh
```

```bash
open build/Rattle.app
```

`build.sh` builds a release binary with SwiftPM, assembles `build/Rattle.app` (icon, fonts, illustrations, Info.plist) and signs it. No Xcode project is needed.

macOS ties Microphone and Accessibility permissions to the app's signature. To keep those grants across rebuilds, create a stable local signing identity once:

```bash
./scripts/setup-signing.sh
```

Without it, builds are ad-hoc signed and macOS may ask for permissions again after each rebuild.

## Tests

```bash
swift test
```

## Connecting an MCP client

Turn on the server in **Settings → MCP**, then use **Connect** for Claude Desktop or Cursor, or copy the config. For Claude Code:

```bash
claude mcp add rattle -- "/path/to/Rattle.app/Contents/MacOS/Rattle" --mcp
```

## Where your data lives

Everything stays on your Mac in `~/Library/Application Support/Rattle`: history, notes, meetings, recordings, dictionary, snippets, settings and downloaded models. Audio and text only leave your Mac if you choose Groq for transcription or a hosted AI server.

## Project layout

| Path | What's there |
|------|--------------|
| `Sources/Rattle/` | The app (SwiftUI views hosted in AppKit windows) |
| `Tests/RattleTests/` | XCTest suite |
| `Illustrations/` | Recoloured Open Doodles used in onboarding and empty states |
| `Fonts/` | Figtree and EB Garamond |
| `Icon/` | App icon (Icon Composer) |
| `scripts/` | Build, signing, icon and illustration scripts, and a Wispr Flow import tool |
| `docs/superpowers/` | Design notes and implementation plans |

## Credits

- Icons: [Lucide](https://lucide.dev) (ISC) and the MCP icon from [Hugeicons](https://hugeicons.com) (MIT)
- Illustrations: [Open Doodles](https://www.opendoodles.com) by Pablo Stanley (CC0)
- Fonts: Figtree and EB Garamond (SIL Open Font License)
- Local transcription: [whisper.cpp](https://github.com/ggml-org/whisper.cpp)

Full notices ship inside the app bundle (`Contents/Resources/lucide-LICENSE.txt`, `Contents/Resources/Fonts/*-OFL.txt`).
