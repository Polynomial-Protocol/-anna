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

        // Position the panel to cover the full screen
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
                // Flip Y coordinate (screen coords are bottom-up in AppKit)
                let screenY = geo.size.height - coord.y

                ZStack {
                    // Blue triangle pointer
                    PointerTriangleView()
                        .position(x: screenX, y: screenY)
                        .transition(.scale.combined(with: .opacity))

                    // Label bubble
                    if !manager.bubbleText.isEmpty {
                        Text(manager.bubbleText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.85))
                                    .shadow(color: .blue.opacity(0.4), radius: 8)
                            )
                            .position(x: screenX, y: screenY - 40)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: screenX)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: screenY)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Blue Triangle Shape

struct PointerTriangleView: View {
    @State private var rotation: Double = 0
    @State private var glowOpacity: Double = 0.6

    var body: some View {
        ZStack {
            // Glow effect
            Triangle()
                .fill(Color.blue.opacity(glowOpacity))
                .frame(width: 36, height: 36)
                .blur(radius: 12)

            // Main triangle
            Triangle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 28, height: 28)
                .overlay(
                    Triangle()
                        .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                )
                .shadow(color: .blue.opacity(0.5), radius: 6)
        }
        .rotationEffect(.degrees(rotation))
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                glowOpacity = 1.0
            }
            withAnimation(.linear(duration: 0.5)) {
                rotation = 180 // Point downward
            }
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
