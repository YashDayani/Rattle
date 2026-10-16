# Rattle Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A six-screen first-run onboarding that leaves a new user able to dictate: name, look, permissions, speech engine, hold key with a practice box, done.

**Architecture:** A pure `OnboardingFlow` model decides step order and when Continue/Skip are available, from a snapshot of checks (permissions, engine, key). A SwiftUI `OnboardingView` renders the steps in its own `NSWindow`, managed by `OnboardingWindowController`. `AppDelegate` shows it instead of the main window while `settings.onboardingDone` is false.

**Tech Stack:** Swift 5.9 SwiftPM, SwiftUI hosted in AppKit, macOS 14.4+ target (runs on macOS 26), XCTest via `swift test` (Xcode is installed).

**Spec:** `docs/superpowers/specs/2026-10-17-onboarding-design.md` (mockup: `docs/superpowers/assets/2026-10-17-onboarding-mockup.html`)

## Global Constraints

- Six steps in this order: name, look, permissions, engine, key, done.
- Each screen: illustration tile, serif title (`Theme.serif(30)`), one muted sentence (`Theme.sans(14)`), its control; footer with progress dots, Back (not on step 1), primary pill.
- Copy: titles exactly "Welcome to Rattle", "Pick a look", "Two quick permissions", "Where should speech become text?", "Hold a key and speak", "You're all set, {name}". Final button "Start using Rattle".
- Key choices on step 5: fn, Right ⌥, Right ⌃ only (no Right ⌘).
- Illustrations: Open Doodles (CC0) `loving`, `swinging`, `unboxing`, `sitting-reading`, `groovy`, `jumping`; ink `#1a1a1a`, skin `#FFF8EC`, accents lavender `#D9C8F5`/`#BFA8EC`, peach `#F8D2AE`/`#EDB585`, pink `#F6C9DD`/`#E9A6C4` (rotating in that order); tile `#fbf8f1` in both appearances.
- Window corners 28pt; tile corners 20pt. Use `Theme` colours, fonts, radii, `PillButton`, `Icon`; no new dependencies.
- Settings writes go to existing fields: `userName`, `appearance` (+ `Theme.apply`), `speechEngine`, `model`, `groqKey`, `shortcut`.
- Build with `./scripts/build.sh`; never `git` write commands (use `but`).

## Review Focus

1. Existing users upgrading: settings.json without `onboardingDone` must never show onboarding → Task 1 test `testExistingSettingsFileSkipsOnboarding`.
2. Blank or whitespace-only name must not continue → Task 2 test `testNameStepNeedsNonBlankName`.
3. Cloud engine chosen with an empty or whitespace key must not continue (Skip still offered) → Task 2 test `testCloudNeedsKey`.
4. Permission granted while the window is open (in System Settings) must update without reopening → Task 5 polls every 1.5 s; verified in Task 6 manual check.
5. Closing the window mid-way opens the main window and onboarding returns next launch → Task 6 manual check.

---

### Task 1: Test target and `onboardingDone` setting

**Files:**
- Modify: `Package.swift` (add test target)
- Modify: `Sources/Rattle/Store.swift` (Settings: field, decoder, `Keys`)
- Create: `Tests/RattleTests/SettingsOnboardingTests.swift`

**Interfaces:**
- Produces: `Settings.onboardingDone: Bool` — `Settings()` gives `false`; decoding JSON that lacks the key gives `true`.

- [ ] **Step 1:** Add `.testTarget(name: "RattleTests", dependencies: ["Rattle"], path: "Tests/RattleTests")` to `Package.swift`.
- [ ] **Step 2: Write the failing tests**

```swift
import XCTest
@testable import Rattle

final class SettingsOnboardingTests: XCTestCase {
    func testFreshSettingsNeedOnboarding() { XCTAssertFalse(Settings().onboardingDone) }
    func testExistingSettingsFileSkipsOnboarding() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"userName":"Ana"}"#.utf8))
        XCTAssertTrue(s.onboardingDone)
    }
    func testOnboardingFlagRoundTrips() throws {
        var s = Settings(); s.onboardingDone = false
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        XCTAssertFalse(back.onboardingDone)
    }
}
```

- [ ] **Step 3:** Run `swift test --filter SettingsOnboardingTests` — expected: compile failure, `onboardingDone` not found.
- [ ] **Step 4:** Add `var onboardingDone: Bool = false` to `Settings`, `onboardingDone = try c.decodeIfPresent(Bool.self, forKey: .onboardingDone) ?? true` in `init(from:)` (comment: a settings file from before onboarding means an existing user), and `onboardingDone` to `Keys`.
- [ ] **Step 5:** Run `swift test --filter SettingsOnboardingTests` — expected: 3 tests pass.
- [ ] **Step 6:** Commit: `but commit -b notes-grid-folders -m "Onboarding: add onboardingDone setting and test target"`

### Task 2: `OnboardingFlow` model

**Files:**
- Create: `Sources/Rattle/OnboardingFlow.swift`
- Create: `Tests/RattleTests/OnboardingFlowTests.swift`

**Interfaces:**
- Produces:
  - `enum OnboardingStep: Int, CaseIterable { case name, look, permissions, engine, key, done }`
  - `struct OnboardingChecks { var name: String; var micGranted: Bool; var axGranted: Bool; var engine: SpeechEngine; var localModelInstalled: Bool; var whisperInstalled: Bool; var groqKey: String }`
  - `enum OnboardingFlow { static func canContinue(_ step: OnboardingStep, _ c: OnboardingChecks) -> Bool; static func canSkip(_ step: OnboardingStep, _ c: OnboardingChecks) -> Bool; static func next(_ step: OnboardingStep) -> OnboardingStep?; static func back(_ step: OnboardingStep) -> OnboardingStep? }`
  - `OnboardingFlow.keyChoices: [Shortcut] = [.fn, .rightOption, .rightControl]`

- [ ] **Step 1: Write the failing tests** — one `XCTestCase` with a `ready` fixture (`name: "Yash"`, both permissions true, `.local`, model and whisper installed, key `""`):
  - `testNameStepNeedsNonBlankName`: `canContinue(.name)` false for `""` and `"   "`, true for `"Yash"`.
  - `testLookAndKeyAlwaysContinue`: `canContinue(.look, ...)` and `canContinue(.key, ...)` true even with everything false.
  - `testPermissionsNeedBoth`: false with either flag false; true with both; `canSkip(.permissions)` true when not both, false when both.
  - `testLocalNeedsModelAndWhisper`: false if either missing; true with both.
  - `testCloudNeedsKey`: `.cloud` with `""` or `"  "` → false and `canSkip(.engine)` true; with `"gsk_x"` → true.
  - `testOnlyPermissionsAndEngineSkip`: `canSkip` false for `.name, .look, .key, .done` in every state.
  - `testNavigation`: `next(.name) == .look`, `next(.done) == nil`, `back(.name) == nil`, `back(.key) == .engine`.
  - `testNoRightCommandChoice`: `OnboardingFlow.keyChoices == [.fn, .rightOption, .rightControl]`.
- [ ] **Step 2:** Run `swift test --filter OnboardingFlowTests` — expected: compile failure.
- [ ] **Step 3:** Implement the types above in `OnboardingFlow.swift` (no SwiftUI/AppKit imports; `canSkip` = step is `.permissions` or `.engine` and `!canContinue`).
- [ ] **Step 4:** Run `swift test --filter OnboardingFlowTests` — expected: all pass.
- [ ] **Step 5:** Commit: `but commit -b notes-grid-folders -m "Onboarding: step model with continue/skip rules"`

### Task 3: Illustrations in the bundle

**Files:**
- Create: `scripts/make-onboarding-art.py` (recolours downloaded Open Doodles; documents the source URL `https://opendoodles.s3-us-west-1.amazonaws.com/<name>.svg`)
- Create: `Onboarding/loving.svg`, `swinging.svg`, `unboxing.svg`, `sitting-reading.svg`, `groovy.svg`, `jumping.svg` (recoloured output, committed)
- Modify: `scripts/build.sh` (copy `Onboarding/*.svg` to `Contents/Resources/Onboarding/`)
- Modify: `scripts/lucide-LICENSE.txt` (append Open Doodles CC0 credit)
- Create: `Tests/RattleTests/OnboardingArtTests.swift`

**Interfaces:**
- Produces: `OnboardingArt.image(for step: OnboardingStep) -> NSImage?` in `Sources/Rattle/OnboardingArt.swift`, loading `Bundle.main.resourceURL/Onboarding/<file>.svg`, falling back to `<package root>/Onboarding/<file>.svg` when run unbundled (`swift run`/tests). Mapping: name→loving, look→swinging, permissions→unboxing, engine→sitting-reading, key→groovy, done→jumping.

- [ ] **Step 1: Failing test** `testEveryStepHasArt`: for each `OnboardingStep.allCases`, `OnboardingArt.image(for:)` is non-nil and its size is non-zero; and `testArtUsesRattleInk`: each SVG file's text contains `#1a1a1a` and none contains `#FF5678` or `#000000`.
- [ ] **Step 2:** Run `swift test --filter OnboardingArtTests` — expected: fail.
- [ ] **Step 3:** Write the script (python3, stdlib only): strip XML header/comments/title/desc and the root `width`/`height`; map `#000000`→`#1a1a1a`, `#FFFFFF`→`#FFF8EC`, `#FF5678`/`#CF536D` → the step's accent/shade per Global Constraints. Run it to produce `Onboarding/*.svg`. Implement `OnboardingArt`. Add the build.sh copy line next to the Fonts copy. Append the credit: "Onboarding illustrations: Open Doodles by Pablo Stanley (https://www.opendoodles.com), CC0 1.0 public domain. Recoloured for Rattle."
- [ ] **Step 4:** Run `swift test --filter OnboardingArtTests` — pass. Run `./scripts/build.sh` and `ls build/Rattle.app/Contents/Resources/Onboarding` — six files.
- [ ] **Step 5:** Commit: `but commit -b notes-grid-folders -m "Onboarding: recoloured Open Doodles illustrations"`

### Task 4: Practice dictation stays out of history

**Files:**
- Modify: `Sources/Rattle/Dictation.swift` (around line 163)

**Interfaces:**
- Produces: `DictationController.practiceMode: Bool` (default false). While true, a finished dictation is inserted as usual but `store.history.insert(...)` is skipped, and `lastPracticeText: String?` (`@Published`) is set to the inserted text.

- [ ] **Step 1:** Add the two properties; guard the history insert with `if !practiceMode`; set `lastPracticeText = text` when `practiceMode`.
- [ ] **Step 2:** Run `swift build` — expected: success. (Behaviour is verified with the real mic in Task 6; it needs audio input, so no unit test.)
- [ ] **Step 3:** Commit: `but commit -b notes-grid-folders -m "Dictation: practice mode skips history"`

### Task 5: `OnboardingView`

**Files:**
- Create: `Sources/Rattle/OnboardingView.swift`

**Interfaces:**
- Consumes: `OnboardingStep`, `OnboardingChecks`, `OnboardingFlow` (Task 2); `OnboardingArt.image(for:)` (Task 3); `DictationController.practiceMode`/`lastPracticeText` (Task 4); `Permissions`, `ModelDownloader.shared`, `WhisperModel.all`, `Transcriber.enginePath`, `CloudSpeech.models`, `Theme.apply`, `DictationController.shared.applyShortcut()`/`retryHotkey()`.
- Produces: `struct OnboardingView: View { init(finish: @escaping () -> Void) }` — calls `finish()` from "Start using Rattle".

- [ ] **Step 1:** Build the shell: `@LocalState var step: OnboardingStep`, art tile (210pt high, `#fbf8f1`, 20pt corners, `Theme.line` border), title/sentence, step content, footer (dots: current 18×6 ink capsule, others 6×6 `Theme.switchOff`; "Back" text button when `back(step) != nil`; "Skip for now" text button when `canSkip`; primary `PillButton(prominent: true)` disabled unless `canContinue`). Step change animates with `Theme.Motion.standard` opacity+offset. Rebuild `OnboardingChecks` every 1.5 s with a `Timer.publish` (permissions, model installed, whisper path) and on every edit.
- [ ] **Step 2:** Step contents, writing straight to `AppStore.shared.settings`:
  - name: `TextField` bound to `userName`, initial value already prefilled by `Settings`; focused on appear.
  - look: three tiles (System half/half swatch, Light `#f5f4f0`, Dark `#202020`), selected tile 1.5pt ink border; tap sets `appearance` and calls `Theme.apply`.
  - permissions: two rows (Microphone / "To hear your voice", Accessibility / "To type where your cursor is"); Allow buttons call `Permissions.requestMic` and `Permissions.requestAccessibility()` + `openPrivacy("Privacy_Accessibility")`; granted rows show a check and "Allowed"; when Accessibility flips to granted, call `DictationController.shared.retryHotkey()`.
  - engine: two selectable cards. Local: subtitle with the default model's size (`WhisperModel.all` entry for `settings.model`); if not installed show Download (`ModelDownloader.shared.download`) and a progress bar from `ModelDownloader.shared.progress[id]`; if `Transcriber.enginePath == nil` show "Install whisper.cpp" with `brew install whisper-cpp` and a Copy button. Cloud: `SecureField` for `groqKey`. Selecting a card sets `speechEngine`.
  - key: chips for `OnboardingFlow.keyChoices` (selected = ink fill, white text); tap sets `shortcut` and calls `applyShortcut()`. Practice `TextEditor`/`TextField` with placeholder "Hold {key} and say “Hello Rattle”"; `practiceMode = true` on appear, false on disappear; when `lastPracticeText` changes show a green check and "Nice, that works."
  - done: title uses the name; sentence "Hold {key} in any app to dictate. Meetings, notes and AI summaries are in the sidebar whenever you want them."; button "Start using Rattle" → `finish()`.
- [ ] **Step 3:** Run `swift build` — success.
- [ ] **Step 4:** Commit: `but commit -b notes-grid-folders -m "Onboarding: six-step view"`

### Task 6: Window, launch wiring, and "Show onboarding again"

**Files:**
- Create: `Sources/Rattle/OnboardingWindow.swift`
- Modify: `Sources/Rattle/main.swift` (`applicationDidFinishLaunching`, `applicationShouldHandleReopen`)
- Modify: `Sources/Rattle/Settings.swift` (General tab row)

**Interfaces:**
- Produces: `@MainActor final class OnboardingWindowController: NSObject, NSWindowDelegate { static let shared; var isOpen: Bool; func show(); }` — 720×620 fixed-size titled window, transparent background with 28pt rounded clip (same technique as the hub), centred. Finishing sets `settings.onboardingDone = true`, closes it, then `showHub()`. `windowWillClose` without finishing: leaves the flag false, sets `practiceMode = false`, then `showHub()`.

- [ ] **Step 1:** Implement the controller.
- [ ] **Step 2:** In `applicationDidFinishLaunching`: if `!store.settings.onboardingDone`, call `OnboardingWindowController.shared.show()` instead of `showHub()` and skip the Accessibility prompt line. In `applicationShouldHandleReopen`: if `OnboardingWindowController.shared.isOpen`, bring it forward instead of `showHub()`.
- [ ] **Step 3:** Settings → General: add a last `SettingRow(title: "Onboarding", detail: "Walk through setup again.")` with `PillButton(title: "Show again")` that sets `onboardingDone = false`, closes Settings, and calls `OnboardingWindowController.shared.show()`.
- [ ] **Step 4:** Run `swift test` (all pass) and `./scripts/build.sh`; restart Rattle.
- [ ] **Step 5: Manual check** (screenshot each step): Settings → General → Show again opens the window; name blank disables Continue; look tiles switch theme live; permissions rows show Allowed; engine Local shows ready; key step dictating "Hello Rattle" fills the box and no new history row appears on the Dictation page; closing mid-way opens the main window; "Start using Rattle" opens the main window and a relaunch does not show onboarding.
- [ ] **Step 6:** Commit: `but commit -b notes-grid-folders -m "Onboarding: window, launch wiring, Show again"`
