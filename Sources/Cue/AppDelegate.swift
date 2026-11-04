import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let state = PrompterState()
    private var prompter: PrompterPanelController!
    private var editorWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private let voice = VoiceActivityDetector()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        prompter = PrompterPanelController(state: state)
        setupStatusItem()
        setupHotKeys()

        voice.onLevel = { [weak self] db in self?.state.ingest(level: db) }
        state.$voiceMode
            .removeDuplicates()
            .sink { [weak self] on in self?.setVoice(on) }
            .store(in: &cancellables)

        if state.script == PrompterState.sample { openEditor() } // first launch
    }

    // MARK: Voice
    private func setVoice(_ on: Bool) {
        guard on else {
            voice.stop()
            state.isSpeaking = false
            return
        }
        voice.start { [weak self] ok in
            guard let self, !ok else { return }
            DispatchQueue.main.async {
                self.state.voiceMode = false
                let alert = NSAlert()
                alert.messageText = "Cue needs microphone access for voice mode"
                alert.informativeText = "Turn it on in System Settings → Privacy & Security → Microphone, then try again."
                alert.runModal()
            }
        }
    }

    // MARK: Shortcuts
    private func setupHotKeys() {
        let hk = HotKeyCenter.shared
        let mods = controlKey | optionKey
        hk.register(kVK_Space, modifiers: mods) { [weak self] in self?.state.togglePlay() }
        hk.register(kVK_UpArrow, modifiers: mods) { [weak self] in self?.state.faster() }
        hk.register(kVK_DownArrow, modifiers: mods) { [weak self] in self?.state.slower() }
        hk.register(kVK_LeftArrow, modifiers: mods) { [weak self] in self?.state.rewind() }
        hk.register(kVK_ANSI_R, modifiers: mods) { [weak self] in self?.state.restart() }
        hk.register(kVK_ANSI_M, modifiers: mods) { [weak self] in self?.state.voiceMode.toggle() }
        hk.register(kVK_ANSI_H, modifiers: mods) { [weak self] in self?.prompter.toggleVisible() }
        hk.register(kVK_ANSI_E, modifiers: mods) { [weak self] in self?.openEditor() }
    }

    // MARK: Menu bar icon
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.aligncenter", accessibilityDescription: "Cue")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add(menu, state.isPlaying ? "Pause  ⌃⌥Space" : "Play  ⌃⌥Space", #selector(togglePlay))
        add(menu, "Restart  ⌃⌥R", #selector(restart))
        add(menu, state.voiceMode ? "Turn Voice Mode Off  ⌃⌥M" : "Turn Voice Mode On  ⌃⌥M", #selector(toggleVoice))
        menu.addItem(.separator())
        add(menu, "Edit Script & Settings…  ⌃⌥E", #selector(openEditor))
        add(menu, prompter.panel.isVisible ? "Hide Prompter  ⌃⌥H" : "Show Prompter  ⌃⌥H", #selector(toggleVisible))
        add(menu, "Snap Under Notch", #selector(snap))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Cue", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func togglePlay() { state.togglePlay() }
    @objc private func restart() { state.restart() }
    @objc private func toggleVoice() { state.voiceMode.toggle() }
    @objc private func toggleVisible() { prompter.toggleVisible() }
    @objc private func snap() { prompter.snapToNotch() }

    @objc func openEditor() {
        if editorWindow == nil {
            let editor = EditorView(state: state, onSnap: { [weak self] in self?.prompter.snapToNotch() })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 580),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "Cue — Script & Settings"
            window.contentViewController = NSHostingController(rootView: editor)
            window.isReleasedWhenClosed = false
            window.center()
            editorWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        editorWindow?.makeKeyAndOrderFront(nil)
    }

    // A menu-bar app has no main menu by default, so ⌘C / ⌘V / ⌘Z wouldn't work in the editor without this.
    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Cue", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}
