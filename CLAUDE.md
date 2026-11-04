# Cue — notes for Claude Code

Native macOS menu-bar teleprompter (Swift Package, SwiftUI + AppKit, macOS 13+). No Xcode project — built with SwiftPM.

## Build / run
- Build check: `swift build`
- App bundle: `./build.sh` then `open Cue.app` (bundle is needed for the microphone permission prompt). Builds a universal binary (arm64 + x86_64 via two `--triple` builds + `lipo`; multi-arch `swift build` needs full Xcode, which isn't installed)
- Release zip: `./build.sh --zip` → `dist/Cue.zip`; the README download button points at `releases/latest/download/Cue.zip`, so attach it to each release under exactly that name
- Icon: `swift scripts/make-icon.swift` regenerates `Resources/AppIcon.icns` (+ `AppIcon.png` used in the README)
- Ad-hoc signing changes on every build, so macOS re-asks for microphone permission after each rebuild
- After changing code, quit the running app first: `pkill -x Cue`

## Architecture
- `main.swift` → `AppDelegate` (status item, main Edit menu, hotkeys, voice wiring)
- `PrompterState` — ObservableObject, single source of truth; scroll engine is a 60 fps Timer
- `PrompterPanel` / `PrompterPanelController` — borderless non-activating NSPanel above menu bar, `sharingType = .none`
- `PrompterView` — SwiftUI text layer (offset-based scrolling, fade mask)
- `VoiceActivityDetector` — AVAudioEngine RMS level → `state.ingest(level:)`
- `HotKeys` — Carbon RegisterEventHotKey (⌃⌥ + key)

## Rules
- The prompter panel must never become key/main or activate the app (it must not steal focus from meeting apps).
- No audio is recorded or sent anywhere; keep voice detection local.
- Keep it dependency-free (no third-party packages) unless there's a strong reason.
- Swift language mode 5 (tools 5.9); fix warnings when cheap, don't migrate to Swift 6 strict concurrency without asking.

## Core requirement: only the presenter sees the script
The prompter must be invisible in screen sharing, screen recordings AND screenshots ("audience sees my slides, I see my notes").
Currently done via `sharingType = .none` on the panel. Verify on this Mac with:
- `screencapture -x /tmp/cue-test.png` while the prompter is visible, then open the PNG — the prompter must not be in it
- ⌘⇧5 recording, and a whole-screen share in Zoom/Teams/Meet
If any path still captures it, research the current macOS behaviour and propose a fix (don't silently drop the requirement). Also confirm it shows over full-screen Keynote/PowerPoint.

## Status
v0.1 was written without being compiled — first job is `swift build` and fixing any compile errors, then running it on a notched MacBook to tune positioning.
