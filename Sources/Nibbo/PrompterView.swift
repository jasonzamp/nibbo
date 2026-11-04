import SwiftUI

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Where each non-empty line of the script starts, keyed by its line index.
private struct LineOffsetsKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Black panel with square top corners when docked under the notch,
/// so it reads as an extension of the camera housing.
struct PanelShape: Shape {
    var top: CGFloat
    var bottom: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + top), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: r.maxX - bottom, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + bottom, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - bottom), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + top))
        p.addQuadCurve(to: CGPoint(x: r.minX + top, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct PrompterView: View {
    @ObservedObject var state: PrompterState
    var onDrag: (_ ended: Bool) -> Void
    var onOpenSettings: () -> Void
    @State private var hovering = false

    /// Where the line you're currently reading sits, as a fraction of the visible height.
    /// Kept small so most of the panel shows upcoming text; the area above is a short fade strip.
    private let readingLine: CGFloat = 0.05

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: state.topInset) // hidden behind the notch
            GeometryReader { geo in
                textLayer(in: geo.size)
                    .onAppear { state.viewportHeight = geo.size.height }
                    .onChange(of: geo.size) { state.viewportHeight = $0.height }
            }
            .overlay(alignment: .topLeading) { statusDot.padding(10) }
        }
        .background(PanelShape(top: state.topInset > 0 ? 0 : 14, bottom: 18).fill(Color.black))
        .overlay(alignment: .topTrailing) { // in the very corner, beside the notch rather than below it
            if hovering {
                closeButton.padding(5).transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) { progressBar }
        .overlay(alignment: .bottom) {
            if hovering {
                controls.padding(.bottom, 10).transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { _ in onDrag(false) }
                .onEnded { _ in onDrag(true) }
        )
        .onTapGesture { state.togglePlay() }
    }

    private var displayText: String {
        state.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Press ⌃⌥E to open the editor and paste your script."
            : state.script
    }

    /// One Text per line so the editor can jump to, and highlight, a specific paragraph.
    private func textLayer(in size: CGSize) -> some View {
        let spacing = CGFloat(state.fontSize) * 0.3
        let lines = displayText.components(separatedBy: "\n")
        return VStack(spacing: spacing) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
                Text(isBlank ? " " : line)
                    .font(state.font)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(spacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: LineOffsetsKey.self,
                                               value: isBlank ? [:] : [i: g.frame(in: .named("script")).minY])
                    })
            }
        }
        .frame(width: max(size.width - 40, 60))
        .fixedSize(horizontal: false, vertical: true)
        .coordinateSpace(name: "script")
        .background(GeometryReader { g in
            Color.clear.preference(key: ContentHeightKey.self, value: g.size.height)
        })
        .offset(y: size.height * readingLine - state.offset)
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
        .mask(fade)
        .onPreferenceChange(ContentHeightKey.self) { state.contentHeight = $0 }
        .onPreferenceChange(LineOffsetsKey.self) { offsets in
            if state.lineOffsets != offsets { state.lineOffsets = offsets }
        }
    }

    /// Lines you've already read dim out; upcoming lines fade in at the bottom.
    private var fade: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(0.0), location: 0.0),
            .init(color: .black.opacity(0.35), location: readingLine * 0.6),
            .init(color: .black, location: readingLine),
            .init(color: .black, location: 0.8),
            .init(color: .black.opacity(0.0), location: 1.0),
        ], startPoint: .top, endPoint: .bottom)
    }

    private var statusDot: some View {
        let colour: Color
        if !state.isPlaying {
            colour = .gray
        } else if state.voiceMode && !state.isSpeaking {
            colour = .yellow // playing, waiting for you to speak
        } else {
            colour = .green
        }
        return Circle().fill(colour).frame(width: 6, height: 6)
    }

    private var progressBar: some View {
        GeometryReader { g in
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(width: g.size.width * CGFloat(state.progress), height: 2)
        }
        .frame(height: 2)
        .padding(.horizontal, 18)
        .padding(.bottom, 3)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            iconButton("gobackward.5") { state.rewind() }
            iconButton(state.isPlaying ? "pause.fill" : "play.fill") { state.togglePlay() }
            iconButton("tortoise.fill") { state.slower() }
            Text("\(Int(state.speed))")
                .font(.caption.monospacedDigit())
                .foregroundColor(.white.opacity(0.7))
            iconButton("hare.fill") { state.faster() }
            iconButton(state.voiceMode ? "mic.fill" : "mic.slash.fill") { state.voiceMode.toggle() }
            iconButton("gearshape.fill") { onOpenSettings() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.14)))
    }

    private var closeButton: some View {
        Button { NSApp.terminate(nil) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .help("Quit Nibbo")
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
    }
}
