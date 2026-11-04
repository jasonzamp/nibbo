import AppKit
import Combine
import QuartzCore
import SwiftUI

/// A script saved in the editor's history. Stored locally in UserDefaults only.
struct ScriptEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    var updated: Date

    var title: String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? "Untitled"
        return String(line.prefix(60))
    }
}

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
    /// In voice mode the prompter stays armed (isPlaying) and only moves while you talk.
    @Published var voiceMode: Bool {
        didSet {
            d.set(voiceMode, forKey: "voiceMode")
            if voiceMode && !oldValue { isPlaying = true }
        }
    }
    @Published var voiceThreshold: Double { didSet { d.set(voiceThreshold, forKey: "voiceThreshold") } } // dBFS
    @Published var history: [ScriptEntry] { didSet { d.set(try? JSONEncoder().encode(history), forKey: "history") } } // newest first
    @Published var currentEntryID: UUID? { didSet { d.set(currentEntryID?.uuidString, forKey: "currentEntryID") } }

    // MARK: Live state
    @Published var isPlaying = false
    @Published var offset: CGFloat = 0
    @Published var contentHeight: CGFloat = 0
    @Published var viewportHeight: CGFloat = 0
    @Published var topInset: CGFloat = 0      // part of the panel hidden behind the notch / menu bar
    @Published var micLevel: Float = -160
    @Published var isSpeaking = false
    @Published var lineOffsets: [Int: CGFloat] = [:] // script line index → y position in the prompter

    private var lastVoice: CFTimeInterval = 0
    private var lastTick: CFTimeInterval = CACurrentMediaTime()
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    static let sample = """
    Welcome to Cue.

    This teleprompter sits right under your camera, so you can read your script while keeping natural eye contact.

    Open the editor with Control-Option-E and paste your own script. Press Control-Option-Space to start and pause.

    Turn on voice mode with Control-Option-M and Cue will pause whenever you stop talking.
    """

    init() {
        script = d.string(forKey: "script") ?? PrompterState.sample
        speed = d.object(forKey: "speed") as? Double ?? 10
        fontSize = d.object(forKey: "fontSize") as? Double ?? 22
        fontDesign = d.string(forKey: "fontDesign") ?? "rounded"
        panelWidth = d.object(forKey: "panelWidth") as? Double ?? 520
        panelHeight = d.object(forKey: "panelHeight") as? Double ?? 220
        voiceMode = d.object(forKey: "voiceMode") as? Bool ?? false
        voiceThreshold = d.object(forKey: "voiceThreshold") as? Double ?? -50
        history = d.data(forKey: "history").flatMap { try? JSONDecoder().decode([ScriptEntry].self, from: $0) } ?? []
        currentEntryID = d.string(forKey: "currentEntryID").flatMap(UUID.init(uuidString:))
        isPlaying = voiceMode // talking starts the scroll straight away
        startTicker()
        saveToHistory() // so the script you already had shows up in history

        // Autosave the script into history once typing settles.
        $script
            .dropFirst()
            .debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveToHistory() }
            .store(in: &cancellables)
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
        guard end > 0 else { return } // script not measured yet
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

    /// Puts the start of the given script line on the reading line.
    func jump(toLine line: Int) {
        guard let y = lineOffsets[line] else { return } // blank line
        offset = min(max(y, 0), maxOffset)
    }

    /// The paragraph (script line index) currently on the reading line.
    var currentLine: Int? {
        let target = offset + CGFloat(fontSize) * 0.5
        return lineOffsets.filter { $0.value <= target }.max { $0.value < $1.value }?.key
    }

    func faster() { speed = min(speed + 5, 300) }
    func slower() { speed = max(speed - 5, 5) }

    // MARK: History
    /// Saves the current script into history, updating its entry if it came from there.
    func saveToHistory() {
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, script != Self.sample else { return }
        var entry: ScriptEntry
        if let id = currentEntryID, let i = history.firstIndex(where: { $0.id == id }) {
            entry = history.remove(at: i)
            if entry.text == script { history.insert(entry, at: i); return } // nothing changed, keep its place
            entry.text = script
            entry.updated = Date()
        } else if let i = history.firstIndex(where: { $0.text == script }) {
            entry = history.remove(at: i)
            entry.updated = Date()
        } else {
            entry = ScriptEntry(id: UUID(), text: script, updated: Date())
        }
        history.insert(entry, at: 0)
        currentEntryID = entry.id
    }

    func load(_ entry: ScriptEntry) {
        saveToHistory()
        currentEntryID = entry.id
        script = entry.text
        isPlaying = voiceMode
        offset = 0
    }

    func newScript() {
        saveToHistory()
        currentEntryID = nil
        script = ""
        isPlaying = voiceMode
        offset = 0
    }

    func delete(_ entry: ScriptEntry) {
        history.removeAll { $0.id == entry.id }
        if currentEntryID == entry.id { currentEntryID = nil }
    }

    func clearHistory() {
        history.removeAll()
        currentEntryID = nil
    }

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
