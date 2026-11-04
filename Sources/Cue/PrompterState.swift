import AppKit
import Combine
import QuartzCore
import SwiftUI

/// Single source of truth for the script, settings and scroll position.
final class PrompterState: ObservableObject {
    private let d = UserDefaults.standard

    // MARK: Persisted settings
    @Published var script: String { didSet { d.set(script, forKey: "script") } }
    @Published var speed: Double { didSet { d.set(speed, forKey: "speed") } }               // points per second
    @Published var fontSize: Double { didSet { d.set(fontSize, forKey: "fontSize") } }
    @Published var fontDesign: String { didSet { d.set(fontDesign, forKey: "fontDesign") } } // rounded | monospaced | serif | default
    @Published var panelWidth: Double { didSet { d.set(panelWidth, forKey: "panelWidth") } }
    @Published var panelHeight: Double { didSet { d.set(panelHeight, forKey: "panelHeight") } }
    @Published var voiceMode: Bool { didSet { d.set(voiceMode, forKey: "voiceMode") } }
    @Published var voiceThreshold: Double { didSet { d.set(voiceThreshold, forKey: "voiceThreshold") } } // dBFS

    // MARK: Live state
    @Published var isPlaying = false
    @Published var offset: CGFloat = 0
    @Published var contentHeight: CGFloat = 0
    @Published var viewportHeight: CGFloat = 0
    @Published var topInset: CGFloat = 0      // part of the panel hidden behind the notch / menu bar
    @Published var micLevel: Float = -160
    @Published var isSpeaking = false

    private var lastVoice: CFTimeInterval = 0
    private var lastTick: CFTimeInterval = CACurrentMediaTime()
    private var timer: Timer?

    static let sample = """
    Welcome to Cue.

    This teleprompter sits right under your camera, so you can read your script while keeping natural eye contact.

    Open the editor with Control-Option-E and paste your own script. Press Control-Option-Space to start and pause.

    Turn on voice mode with Control-Option-M and Cue will pause whenever you stop talking.
    """

    init() {
        script = d.string(forKey: "script") ?? PrompterState.sample
        speed = d.object(forKey: "speed") as? Double ?? 45
        fontSize = d.object(forKey: "fontSize") as? Double ?? 22
        fontDesign = d.string(forKey: "fontDesign") ?? "rounded"
        panelWidth = d.object(forKey: "panelWidth") as? Double ?? 520
        panelHeight = d.object(forKey: "panelHeight") as? Double ?? 170
        voiceMode = d.object(forKey: "voiceMode") as? Bool ?? false
        voiceThreshold = d.object(forKey: "voiceThreshold") as? Double ?? -42
        startTicker()
    }

    // MARK: Scroll engine (60 fps)
    private func startTicker() {
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now

        if voiceMode {
            let speaking = now - lastVoice < 0.6 // short hold so pauses between words don't stutter
            if speaking != isSpeaking { isSpeaking = speaking }
        }

        guard isPlaying else { return }
        if voiceMode && !isSpeaking { return }

        let end = maxOffset
        let next = min(offset + CGFloat(speed * dt), end)
        offset = next
        if next >= end { isPlaying = false }
    }

    var maxOffset: CGFloat { max(0, contentHeight - CGFloat(fontSize) * 1.5) }
    var progress: Double { maxOffset > 0 ? Double(offset / maxOffset) : 0 }

    // MARK: Voice
    func ingest(level: Float) {
        micLevel = level
        if Double(level) > voiceThreshold { lastVoice = CACurrentMediaTime() }
    }

    // MARK: Actions
    func togglePlay() {
        if !isPlaying && offset >= maxOffset && maxOffset > 0 { offset = 0 }
        isPlaying.toggle()
    }
    func restart() { offset = 0 }
    func rewind() { nudge(by: -CGFloat(fontSize) * 4) }
    func nudge(by delta: CGFloat) { offset = min(max(offset + delta, 0), maxOffset) }
    func faster() { speed = min(speed + 5, 300) }
    func slower() { speed = max(speed - 5, 5) }

    var font: Font {
        let design: Font.Design
        switch fontDesign {
        case "monospaced": design = .monospaced
        case "serif": design = .serif
        case "default": design = .default
        default: design = .rounded
        }
        return .system(size: CGFloat(fontSize), weight: .semibold, design: design)
    }

    var wordCount: Int { script.split(whereSeparator: { $0.isWhitespace }).count }
}
