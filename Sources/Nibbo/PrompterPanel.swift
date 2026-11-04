import AppKit
import Combine
import SwiftUI

/// Borderless floating panel that hugs the notch, never steals focus,
/// and asks macOS to keep it out of screen sharing and recordings.
final class PrompterPanel: NSPanel {
    var onScroll: ((CGFloat) -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel, .resizable],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1) // above the menu bar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        sharingType = .none // excluded from screen capture (verify with your meeting app, see README)
        minSize = NSSize(width: 240, height: 90)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Let the panel sit over the menu bar / notch instead of being pushed below it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func scrollWheel(with event: NSEvent) {
        let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        onScroll?(-event.scrollingDeltaY * multiplier)
    }
}

/// Lets buttons respond on the first click even though the panel never becomes active.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class PrompterPanelController: NSObject, NSWindowDelegate {
    let panel: PrompterPanel
    private let state: PrompterState
    var onOpenSettings: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()
    private var applyingFrame = false
    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint = .zero

    init(state: PrompterState) {
        self.state = state
        panel = PrompterPanel(contentRect: NSRect(x: 0, y: 0, width: state.panelWidth, height: state.panelHeight))
        super.init()

        let root = PrompterView(state: state,
                                onDrag: { [weak self] ended in self?.handleDrag(ended: ended) },
                                onOpenSettings: { [weak self] in self?.onOpenSettings?() })
        panel.contentView = FirstMouseHostingView(rootView: root)
        panel.delegate = self
        panel.onScroll = { [weak state] delta in state?.nudge(by: delta) }

        // Size changes from the settings sliders: keep the top edge pinned.
        Publishers.CombineLatest(state.$panelWidth, state.$panelHeight)
            .dropFirst()
            .sink { [weak self] w, h in
                guard let self, !self.applyingFrame else { return }
                let f = self.panel.frame
                if abs(f.width - w) < 0.5 && abs(f.height - h) < 0.5 { return }
                self.setFrame(NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h))
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.updateInset()
        }

        snapToNotch()
    }

    /// Centre the panel at the top of the notched screen (or the main screen if none).
    func snapToNotch() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let w = CGFloat(state.panelWidth), h = CGFloat(state.panelHeight)
        setFrame(NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h))
        panel.orderFrontRegardless()
    }

    func toggleVisible() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    private func setFrame(_ frame: NSRect) {
        applyingFrame = true
        panel.setFrame(frame, display: true)
        applyingFrame = false
        updateInset()
    }

    /// How much of the panel overlaps the notch / menu-bar strip, so text starts below it.
    private func updateInset() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let strip = max(screen.safeAreaInsets.top, screen.frame.maxY - screen.visibleFrame.maxY)
        let stripBottom = screen.frame.maxY - strip
        let overlap = min(max(panel.frame.maxY - stripBottom, 0), strip)
        if abs(state.topInset - overlap) > 0.5 { state.topInset = overlap }
    }

    private func handleDrag(ended: Bool) {
        let mouse = NSEvent.mouseLocation
        if dragStartMouse == nil {
            dragStartMouse = mouse
            dragStartOrigin = panel.frame.origin
        }
        guard let start = dragStartMouse else { return }
        var origin = NSPoint(x: dragStartOrigin.x + mouse.x - start.x,
                             y: dragStartOrigin.y + mouse.y - start.y)

        if ended {
            dragStartMouse = nil
            // Magnetic snap back to the top edge / notch.
            if let screen = panel.screen ?? NSScreen.main {
                let h = panel.frame.height, w = panel.frame.width
                if abs(screen.frame.maxY - (origin.y + h)) < 40 {
                    origin.y = screen.frame.maxY - h
                    let centreX = screen.frame.midX - w / 2
                    if abs(origin.x - centreX) < 80 { origin.x = centreX }
                }
            }
        }
        panel.setFrameOrigin(origin)
        updateInset()
    }

    // MARK: NSWindowDelegate
    func windowDidResize(_ notification: Notification) {
        updateInset()
        guard !applyingFrame else { return }
        state.panelWidth = Double(panel.frame.width)
        state.panelHeight = Double(panel.frame.height)
    }

    func windowDidMove(_ notification: Notification) { updateInset() }
}
