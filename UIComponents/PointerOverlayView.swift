import SwiftUI
import AppKit

// MARK: - Pointer Overlay Manager

@MainActor
final class PointerOverlayManager: ObservableObject {
    @Published var isVisible = false
    @Published var coordinate: PointerCoordinate?
    @Published var bubbleText: String = ""

    private var panel: PointerOverlayPanel?

    func pointAt(_ coord: PointerCoordinate, screenSize: CGSize) {
        coordinate = coord
        bubbleText = coord.label ?? ""

        if panel == nil {
            let newPanel = PointerOverlayPanel()
            let hostView = NSHostingView(
                rootView: PointerOverlayContent(manager: self)
            )
            newPanel.contentView = hostView
            panel = newPanel
        }

        if let screen = NSScreen.main {
            panel?.setFrame(screen.frame, display: true)
        }

        panel?.orderFront(nil)
        isVisible = true
    }

    func hide() {
        withAnimation(.easeOut(duration: 0.3)) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.panel?.orderOut(nil)
            self?.coordinate = nil
            self?.bubbleText = ""
        }
    }
}

// MARK: - Transparent Full-Screen Panel

final class PointerOverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Pointer Content View

struct PointerOverlayContent: View {
    @ObservedObject var manager: PointerOverlayManager

    var body: some View {
        GeometryReader { geo in
            if manager.isVisible, let coord = manager.coordinate {
                let screenX = coord.x
                let screenY = geo.size.height - coord.y

                ZStack {
                    // Anna cursor pointer
                    AnnaCursorView()
                        .position(x: screenX, y: screenY)
                        .transition(.scale.combined(with: .opacity))

                    // Label bubble
                    if !manager.bubbleText.isEmpty {
                        Text(manager.bubbleText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.55, green: 0.4, blue: 0.9).opacity(0.85),
                                                Color(red: 0.45, green: 0.7, blue: 0.95).opacity(0.85)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .shadow(color: Color(red: 0.55, green: 0.4, blue: 0.9).opacity(0.35), radius: 8)
                            )
                            .position(x: screenX + 30, y: screenY + 50)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: screenX)
                .animation(.spring(response: 0.45, dampingFraction: 0.75), value: screenY)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Anna Cursor Design (Purple/Blue striped arrow with dark border)

struct AnnaCursorView: View {
    @State private var glowOpacity: Double = 0.4
    @State private var appeared = false

    // Colors matching the design
    private let purple = Color(red: 0.68, green: 0.55, blue: 0.92)
    private let lightBlue = Color(red: 0.52, green: 0.78, blue: 0.95)
    private let borderColor = Color(red: 0.18, green: 0.18, blue: 0.2)

    var body: some View {
        ZStack {
            // Outer glow
            CursorArrowShape()
                .fill(
                    LinearGradient(
                        colors: [purple.opacity(glowOpacity), lightBlue.opacity(glowOpacity)],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )
                .frame(width: 48, height: 56)
                .blur(radius: 16)

            // Dark border (slightly larger)
            CursorArrowShape()
                .fill(borderColor)
                .frame(width: 42, height: 50)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)

            // Inner fill with diagonal stripes
            CursorArrowShape()
                .fill(
                    LinearGradient(
                        colors: [purple, lightBlue, purple],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )
                .frame(width: 32, height: 40)

            // White diagonal stripe accent
            CursorArrowShape()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.5),
                            .clear,
                        ],
                        startPoint: UnitPoint(x: 0.3, y: 0),
                        endPoint: UnitPoint(x: 0.7, y: 1)
                    )
                )
                .frame(width: 32, height: 40)
        }
        .scaleEffect(appeared ? 1.0 : 0.3)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowOpacity = 0.7
            }
        }
    }
}

// MARK: - Custom Arrow Cursor Shape

struct CursorArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        // Classic macOS cursor arrow shape with a notch
        let w = rect.width
        let h = rect.height

        var path = Path()

        // Tip of arrow (top-left)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Right edge down
        path.addLine(to: CGPoint(x: rect.minX + w * 0.72, y: rect.minY + h * 0.58))

        // Notch inward (where the tail meets the head)
        path.addLine(to: CGPoint(x: rect.minX + w * 0.42, y: rect.minY + h * 0.52))

        // Bottom tail point
        path.addLine(to: CGPoint(x: rect.minX + w * 0.42, y: rect.maxY))

        // Left side of tail
        path.addLine(to: CGPoint(x: rect.minX + w * 0.18, y: rect.minY + h * 0.72))

        // Back to left edge
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.72))

        path.closeSubpath()
        return path
    }
}
