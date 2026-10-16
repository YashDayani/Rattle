# Rattle first-run onboarding: design

## Intent

Someone who has just installed Rattle and opened it for the first time should finish onboarding able to dictate straight away: hold a key, speak, and have text appear wherever their cursor is. Today a new user lands on the main window with a small "Set up Rattle" checklist and an Accessibility prompt that fires at launch with no explanation. Onboarding replaces that with a short, friendly, guided flow.

## Goals

- Six short screens, one job each, finished in about a minute (plus model download time).
- At the end, dictation works: microphone and Accessibility are granted, a speech engine is ready, and a hold key is chosen and tried once.
- Looks like Rattle and feels like Wispr Flow's onboarding: Rattle colours and fonts, hand-drawn illustrations.

## Non-goals

- AI server setup for meeting summaries, MCP, imports from Wispr Flow/Granola, launch at login, Flow Bar and dock options. These stay in Settings; the last screen points to them.
- Account creation or sign-in (Rattle has none).
- A tour of the main window.

## Anti-goals (what would make this a failure even if it works)

- Long text or instructions on any screen. Each screen gets a title, one short sentence and its control.
- Trapping the user: every screen except the first has Back, and the user can quit at any point. Skipping the remaining steps must leave Rattle usable (they fall back to Settings and the existing setup checklist).
- Off-brand art: no flat corporate vector people (unDraw was tried and rejected).

## The flow

All screens share one layout (see mockup v3 in `docs/superpowers/assets/2026-10-17-onboarding-mockup.html`):

- Rounded window in Rattle's window colour, 28pt corners like the main window.
- Top: illustration on a cream tile (`#fbf8f1` light; a dark equivalent in dark mode), about 210pt tall, 20pt corners.
- Below: serif title (EB Garamond, ~30pt), one muted sentence (Figtree 14pt), then the step's control.
- Footer: progress dots on the left (current dot widened), Back (text button) and the primary pill button on the right.

| # | Title | Control | Primary button enabled when |
|---|-------|---------|-----------------------------|
| 1 | Welcome to Rattle | Text field: "What should we call you?" prefilled with the macOS first name | name not blank |
| 2 | Pick a look | Three tiles: System / Light / Dark, each with a small swatch; applies live | always |
| 3 | Two quick permissions | Rows: Microphone ("To hear your voice"), Accessibility ("To type where your cursor is"); each shows Allow or ✓ Allowed and updates on its own when granted | both granted (see Skip below) |
| 4 | Where should speech become text? | Two cards: **On this Mac** (private, offline, model size) and **Groq cloud** (fastest, needs a free API key). Local: shows the default model's download progress, and the whisper.cpp install command with a Copy button if the engine is missing. Cloud: reveals an API key field. | local: model installed and engine found; cloud: key entered |
| 5 | Hold a key and speak | Key chips: fn, Right ⌥, Right ⌃ (selected one filled ink). A practice text box: "Hold fn and say 'Hello Rattle'"; when dictated text lands in it, show ✓ | always (trying it is encouraged, not required) |
| 6 | You're all set, {name} | One sentence: hold the key in any app; meetings, notes and AI summaries are in the sidebar | — ("Start using Rattle" opens the main window) |

Every setting chosen writes straight to the existing `Settings` fields (`userName`, `appearance` via `Theme.apply`, `speechEngine`, `model`, `groqKey`, `groqModel`, `shortcut`), so Settings shows the same values afterwards.

**Skip:** steps 3 and 4 show a small "Skip for now" text link when their condition isn't met, so a user without Homebrew or a Groq key can still finish. The main window's existing `SetupChecklist` keeps covering anything skipped.

## Illustrations

- Source: **Open Doodles** by Pablo Stanley, opendoodles.com, CC0 public domain ("Free for commercial and personal use. No need to credit"). Downloaded from the official S3 bucket.
- Recoloured at build time of the asset (not at runtime): ink `#000000` → Rattle ink `#1a1a1a`; skin `#FFFFFF` → cream `#FFF8EC`; accent `#FF5678` / shade `#CF536D` → one of three pastels per screen, rotating like Wispr Flow: lavender `#D9C8F5`/`#BFA8EC`, peach `#F8D2AE`/`#EDB585`, pink `#F6C9DD`/`#E9A6C4`.
- Per screen: 1 `loving` (lavender), 2 `swinging` (peach), 3 `unboxing` (pink), 4 `sitting-reading` (lavender), 5 `groovy` (peach), 6 `jumping` (pink).
- Shipped as six recoloured SVG files in the app bundle (e.g. `Resources/Onboarding/*.svg`), copied by `scripts/build.sh`, drawn with `NSImage(contentsOf:)`. In dark mode the ink must stay readable: the tile stays light cream so the art is unchanged (builder may instead ship dark variants with light ink; either is fine).
- Credit line added to the bundled licence notices file even though CC0 doesn't require it.

## When it shows

- On launch, if a new setting `onboardingDone` is false. Existing users: treat as done when settings.json already existed before this version (so current users never see it). Fresh installs: false.
- Finishing step 6 sets it true. Quitting mid-way leaves it false, so onboarding resumes from step 1 next launch (values already chosen are kept).
- While onboarding is showing, the main window isn't opened and the launch-time Accessibility prompt in `applicationDidFinishLaunching` is skipped (step 3 asks instead).
- A "Show onboarding again" button in Settings → General resets the flag and opens it.

## Decisions made after review (my calls, check these)

- **Closing the window early** (red button or ⌘W) counts as "skip the rest": the main window opens, `onboardingDone` stays false, and onboarding shows again on the next launch. While onboarding is open, a Dock click brings the onboarding window forward instead of opening the main window.
- **No Right ⌘ chip on step 5.** Right ⌘ is the default Command Mode key, and choosing it for dictation silently turns Command Mode off. Step 5 offers fn, Right ⌥ and Right ⌃; Right ⌘ stays available in Settings.
- **The practice dictation on step 5 is not saved** to history and doesn't count in Insights. `DictationController` gets a flag (e.g. `practiceMode`) that onboarding sets while step 5 is showing.

## Constraints (from the codebase)

- SwiftUI views hosted in AppKit windows, SwiftPM build, macOS 26, no Xcode project. Follow existing patterns: `Theme` colours/fonts/radii, `PillButton`, `ThemeSwitchStyle`, `@LocalState`, `Icon`.
- Local transcription needs `whisper-server`/`whisper-cli` from Homebrew (`brew install whisper-cpp`); it is not bundled. `Transcriber.enginePath` / `WhisperServer.serverPath` detect it. Model downloads go through `ModelDownloader.shared` (published progress).
- Permissions: `Permissions.requestMic`, `Permissions.requestAccessibility`, `Permissions.openPrivacy`; there is no change notification, so poll (the existing checklist polls every 1.5s). After Accessibility is granted, call `DictationController.shared.retryHotkey()`.
- The practice box relies on normal dictation: Rattle's own window is frontmost, so `Inserter` types into the focused text field. The builder should verify this works in Rattle's own window.

## Left to the builder

- Window type (separate `NSWindow` vs. a sheet over the hub) and exact size (~720×620 suggested, not resizable).
- Transitions between steps (a short slide or fade using `Theme.Motion`).
- Exact copy within the one-sentence limit.
- How "existing user" is detected.
