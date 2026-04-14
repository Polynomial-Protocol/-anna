import SwiftUI
import AppKit

// MARK: - Buddy Navigation Mode

enum BuddyNavigationMode {
    case followingCursor
    case navigatingToTarget
    case pointingAtTarget
}

// MARK: - Pointer Overlay Manager

@MainActor
final class PointerOverlayManager: ObservableObject {
    @Published var isVisible = false
    @Published var detectedElementScreenLocation: CGPoint?
    @Published var detectedElementLabel: String?
    @Published var clickRippleAt: CGPoint?

    private var overlayWindows: [OverlayWindow] = []
    var hasShownBefore = false

    /// Converts a PointerCoordinate to AppKit screen coordinates.
    static func screenLocation(for coord: PointerCoordinate) -> CGPoint? {
        guard let screen = NSScreen.main else { return nil }

        let displayWidth = coord.displayWidthPoints
        let displayHeight = coord.displayHeightPoints

        let displayLocalX = coord.x * (displayWidth / coord.screenshotWidth)
        let displayLocalY = coord.y * (displayHeight / coord.screenshotHeight)

        let appKitY = displayHeight - displayLocalY

        let globalX = displayLocalX + screen.frame.origin.x
        let globalY = appKitY + screen.frame.origin.y

        return CGPoint(x: globalX, y: globalY)
    }

    /// Points the buddy cursor at a UI element using Clicky's coordinate mapping.
    func pointAt(_ coord: PointerCoordinate) {
        guard let location = Self.screenLocation(for: coord) else { return }
        detectedElementLabel = coord.label
        detectedElementScreenLocation = location
    }

    func clearDetectedElementLocation() {
        detectedElementScreenLocation = nil
        detectedElementLabel = nil
    }

    func showOverlay(viewModel: AssistantViewModel) {
        hideOverlay()

        let isFirst = !hasShownBefore
        hasShownBefore = true

        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)
            let contentView = BuddyCursorView(
                screenFrame: screen.frame,
                isFirstAppearance: isFirst,
                viewModel: viewModel,
                overlayManager: self
            )
            let hostView = NSHostingView(rootView: contentView)
            hostView.frame = screen.frame
            window.contentView = hostView
            overlayWindows.append(window)
            window.orderFrontRegardless()
        }
        isVisible = true
    }

    func hideOverlay() {
        for window in overlayWindows {
            window.orderOut(nil)
            window.contentView = nil
        }
        overlayWindows.removeAll()
        isVisible = false
    }

    func fadeOutAndHide(duration: TimeInterval = 0.4) {
        let windowsToFade = overlayWindows
        overlayWindows.removeAll()
        isVisible = false

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for w in windowsToFade { w.animator().alphaValue = 0 }
        }, completionHandler: {
            for w in windowsToFade { w.orderOut(nil); w.contentView = nil }
        })
    }

    func hide() {
        fadeOutAndHide()
        clearDetectedElementLocation()
    }
}

// MARK: - Transparent Full-Screen Window

class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hasShadow = false
        hidesOnDeactivate = false
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Small Triangle Shape (Clicky-style)

struct BuddyTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let height = size * sqrt(3.0) / 2.0
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.midY - height / 1.5))
        path.addLine(to: CGPoint(x: rect.midX - size / 2, y: rect.midY + height / 3))
        path.addLine(to: CGPoint(x: rect.midX + size / 2, y: rect.midY + height / 3))
        path.closeSubpath()
        return path
    }
}

// MARK: - Buddy Cursor View (one per screen)

struct BuddyCursorView: View {
    let screenFrame: CGRect
    let isFirstAppearance: Bool
    @ObservedObject var viewModel: AssistantViewModel
    @ObservedObject var overlayManager: PointerOverlayManager

    @State private var cursorPosition: CGPoint
    @State private var isCursorOnThisScreen: Bool
    @State private var cursorOpacity: Double = 0.0
    @State private var timer: Timer?

    // Navigation state
    @State private var buddyMode: BuddyNavigationMode = .followingCursor
    @State private var triangleRotation: Double = -35.0
    @State private var buddyFlightScale: CGFloat = 1.0
    @State private var isReturningToCursor = false
    @State private var cursorAtNavStart: CGPoint = .zero
    @State private var navTimer: Timer?

    // Navigation bubble
    @State private var navBubbleText: String = ""
    @State private var navBubbleOpacity: Double = 0.0
    @State private var navBubbleScale: CGFloat = 1.0
    @State private var navBubbleSize: CGSize = .zero

    // Click ripple animation
    @State private var clickRipplePosition: CGPoint = .zero
    @State private var clickRippleOpacity: Double = 0.0
    @State private var clickRippleScale: CGFloat = 0.3

    private let buddyColor = Color(red: 0.45, green: 0.55, blue: 0.95)
    private let pointerPhrases = ["right here!", "this one!", "over here!", "click this!", "here it is!", "found it!"]

    init(screenFrame: CGRect, isFirstAppearance: Bool, viewModel: AssistantViewModel, overlayManager: PointerOverlayManager) {
        self.screenFrame = screenFrame
        self.isFirstAppearance = isFirstAppearance
        self.viewModel = viewModel
        self.overlayManager = overlayManager

        let mouse = NSEvent.mouseLocation
        let localX = mouse.x - screenFrame.origin.x
        let localY = screenFrame.height - (mouse.y - screenFrame.origin.y)
        _cursorPosition = State(initialValue: CGPoint(x: localX + 35, y: localY + 25))
        _isCursorOnThisScreen = State(initialValue: screenFrame.contains(mouse))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.001)

            // Navigation bubble (when pointing at element)
            if buddyMode == .pointingAtTarget && !navBubbleText.isEmpty {
                Text(navBubbleText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(buddyColor)
                            .shadow(color: buddyColor.opacity(0.5 + (1.0 - navBubbleScale)), radius: 6 + (1.0 - navBubbleScale) * 16)
                    )
                    .fixedSize()
                    .scaleEffect(navBubbleScale)
                    .opacity(navBubbleOpacity)
                    .position(
                        x: min(max(cursorPosition.x, navBubbleSize.width / 2 + 8),
                               screenFrame.width - navBubbleSize.width / 2 - 8),
                        y: cursorPosition.y + 22 + navBubbleSize.height / 2
                    )
                    .animation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0), value: cursorPosition)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: navBubbleScale)
                    .overlay(
                        GeometryReader { geo in
                            Color.clear.preference(key: BubbleSizeKey.self, value: geo.size)
                        }
                    )
                    .onPreferenceChange(BubbleSizeKey.self) { navBubbleSize = $0 }
            }

            // Click ripple animation
            Circle()
                .stroke(buddyColor, lineWidth: 2)
                .frame(width: 40, height: 40)
                .scaleEffect(clickRippleScale)
                .opacity(clickRippleOpacity)
                .position(clickRipplePosition)

            // Triangle cursor (idle + responding)
            BuddyTriangle()
                .fill(buddyColor)
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(triangleRotation))
                .shadow(color: buddyColor, radius: 8 + (buddyFlightScale - 1.0) * 20)
                .scaleEffect(buddyFlightScale)
                .opacity(shouldShowTriangle ? cursorOpacity : 0)
                .position(cursorPosition)
                .animation(
                    buddyMode == .followingCursor
                        ? .spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0)
                        : nil,
                    value: cursorPosition
                )
                .animation(.easeIn(duration: 0.25), value: viewModel.status)
                .animation(
                    buddyMode == .navigatingToTarget ? nil : .easeInOut(duration: 0.3),
                    value: triangleRotation
                )

            // Waveform (listening — non-rewrite modes)
            BuddyWaveformView()
                .opacity(buddyVisible && viewModel.status == .listening && viewModel.activeMode != .rewriteDictation ? cursorOpacity : 0)
                .position(cursorPosition)
                .animation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0), value: cursorPosition)
                .animation(.easeIn(duration: 0.15), value: viewModel.status)

            // Microphone (rewrite dictation listening)
            BuddyMicrophoneView()
                .opacity(buddyVisible && viewModel.status == .listening && viewModel.activeMode == .rewriteDictation ? cursorOpacity : 0)
                .position(x: cursorPosition.x, y: cursorPosition.y)
                .animation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0), value: cursorPosition)
                .animation(.easeIn(duration: 0.15), value: viewModel.status)

            // Spinner (thinking/acting)
            BuddySpinnerView()
                .opacity(buddyVisible && (viewModel.status == .thinking || viewModel.status == .acting) ? cursorOpacity : 0)
                .position(cursorPosition)
                .animation(.spring(response: 0.2, dampingFraction: 0.6, blendDuration: 0), value: cursorPosition)
                .animation(.easeIn(duration: 0.15), value: viewModel.status)
        }
        .frame(width: screenFrame.width, height: screenFrame.height)
        .ignoresSafeArea()
        .onAppear {
            startTracking()
            withAnimation(.easeIn(duration: 0.8)) { cursorOpacity = 1.0 }
        }
        .onDisappear {
            timer?.invalidate()
            navTimer?.invalidate()
        }
        .onChange(of: overlayManager.detectedElementScreenLocation) { _, newLoc in
            guard let loc = newLoc else { return }
            guard screenFrame.contains(loc) else { return }
            startNavigatingToElement(screenLocation: loc)
        }
        .onChange(of: overlayManager.clickRippleAt) { _, newLoc in
            guard let loc = newLoc else { return }
            guard screenFrame.contains(loc) else { return }
            let local = toSwiftUI(loc)
            showClickRipple(at: local)
            overlayManager.clickRippleAt = nil
        }
    }

    private func showClickRipple(at point: CGPoint) {
        clickRipplePosition = point
        clickRippleScale = 0.3
        clickRippleOpacity = 0.8
        withAnimation(.easeOut(duration: 0.5)) {
            clickRippleScale = 1.5
            clickRippleOpacity = 0.0
        }
    }

    private var buddyVisible: Bool {
        switch buddyMode {
        case .followingCursor:
            if overlayManager.detectedElementScreenLocation != nil { return false }
            return isCursorOnThisScreen
        case .navigatingToTarget, .pointingAtTarget:
            return true
        }
    }

    private var shouldShowTriangle: Bool {
        buddyVisible && (viewModel.status == .idle || viewModel.status == .speaking)
    }

    // MARK: - 60fps Cursor Tracking

    private func startTracking() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { _ in
            let mouse = NSEvent.mouseLocation
            self.isCursorOnThisScreen = self.screenFrame.contains(mouse)

            if self.buddyMode == .navigatingToTarget && self.isReturningToCursor {
                let current = self.toSwiftUI(mouse)
                let dist = hypot(current.x - cursorAtNavStart.x, current.y - cursorAtNavStart.y)
                if dist > 100 { cancelNavigation() }
                return
            }

            if self.buddyMode != .followingCursor { return }

            let local = self.toSwiftUI(mouse)
            self.cursorPosition = CGPoint(x: local.x + 35, y: local.y + 25)
        }
    }

    private func toSwiftUI(_ screenPoint: CGPoint) -> CGPoint {
        let x = screenPoint.x - screenFrame.origin.x
        let y = (screenFrame.origin.y + screenFrame.height) - screenPoint.y
        return CGPoint(x: x, y: y)
    }

    // MARK: - Bezier Arc Flight

    private func startNavigatingToElement(screenLocation: CGPoint) {
        let target = toSwiftUI(screenLocation)
        let offsetTarget = CGPoint(x: target.x + 8, y: target.y + 12)
        let clamped = CGPoint(
            x: max(20, min(offsetTarget.x, screenFrame.width - 20)),
            y: max(20, min(offsetTarget.y, screenFrame.height - 20))
        )

        let mouse = NSEvent.mouseLocation
        cursorAtNavStart = toSwiftUI(mouse)
        buddyMode = .navigatingToTarget
        isReturningToCursor = false

        flyBezier(to: clamped) {
            guard self.buddyMode == .navigatingToTarget else { return }
            self.startPointing()
        }
    }

    private func flyBezier(to destination: CGPoint, onComplete: @escaping () -> Void) {
        navTimer?.invalidate()

        let start = cursorPosition
        let end = destination
        let dist = hypot(end.x - start.x, end.y - start.y)
        let duration = min(max(dist / 800.0, 0.6), 1.4)
        let frameInterval = 1.0 / 60.0
        let totalFrames = Int(duration / frameInterval)
        var frame = 0

        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let arcHeight = min(dist * 0.2, 80)
        let control = CGPoint(x: mid.x, y: mid.y - arcHeight)

        navTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { _ in
            frame += 1
            if frame > totalFrames {
                self.navTimer?.invalidate()
                self.navTimer = nil
                self.cursorPosition = end
                self.buddyFlightScale = 1.0
                onComplete()
                return
            }

            let linear = Double(frame) / Double(totalFrames)
            let t = linear * linear * (3.0 - 2.0 * linear) // smoothstep

            let omt = 1.0 - t
            let bx = omt * omt * start.x + 2 * omt * t * control.x + t * t * end.x
            let by = omt * omt * start.y + 2 * omt * t * control.y + t * t * end.y
            self.cursorPosition = CGPoint(x: bx, y: by)

            // Tangent rotation
            let tx = 2 * omt * (control.x - start.x) + 2 * t * (end.x - control.x)
            let ty = 2 * omt * (control.y - start.y) + 2 * t * (end.y - control.y)
            self.triangleRotation = atan2(ty, tx) * (180.0 / .pi) + 90.0

            // Scale pulse
            self.buddyFlightScale = 1.0 + sin(linear * .pi) * 0.3
        }
    }

    // MARK: - Pointing

    private func startPointing() {
        buddyMode = .pointingAtTarget
        triangleRotation = -35.0
        navBubbleText = ""
        navBubbleOpacity = 1.0
        navBubbleScale = 0.5
        navBubbleSize = .zero

        let phrase = overlayManager.detectedElementLabel ?? pointerPhrases.randomElement() ?? "right here!"

        streamBubble(phrase: phrase, index: 0) {
            // Stay anchored at the target. Fade the label after a moment, but the cursor
            // remains here until (a) a new pointAt moves it to the next element, or
            // (b) the task fully completes and the overlay hides.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                guard self.buddyMode == .pointingAtTarget else { return }
                withAnimation(.easeOut(duration: 0.4)) {
                    self.navBubbleOpacity = 0.0
                }
            }
        }
    }

    private func streamBubble(phrase: String, index: Int, onComplete: @escaping () -> Void) {
        guard buddyMode == .pointingAtTarget, index < phrase.count else {
            onComplete()
            return
        }
        let charIdx = phrase.index(phrase.startIndex, offsetBy: index)
        navBubbleText.append(phrase[charIdx])
        if index == 0 { navBubbleScale = 1.0 }

        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0.03...0.06)) {
            self.streamBubble(phrase: phrase, index: index + 1, onComplete: onComplete)
        }
    }

    private func flyBackToCursor() {
        let mouse = NSEvent.mouseLocation
        let swiftUI = toSwiftUI(mouse)
        let target = CGPoint(x: swiftUI.x + 35, y: swiftUI.y + 25)
        cursorAtNavStart = swiftUI
        buddyMode = .navigatingToTarget
        isReturningToCursor = true

        flyBezier(to: target) { self.finishNavigation() }
    }

    private func cancelNavigation() {
        navTimer?.invalidate()
        navTimer = nil
        navBubbleText = ""
        navBubbleOpacity = 0.0
        navBubbleScale = 1.0
        buddyFlightScale = 1.0
        finishNavigation()
    }

    private func finishNavigation() {
        navTimer?.invalidate()
        navTimer = nil
        buddyMode = .followingCursor
        isReturningToCursor = false
        triangleRotation = -35.0
        buddyFlightScale = 1.0
        navBubbleText = ""
        navBubbleOpacity = 0.0
        navBubbleScale = 1.0
        overlayManager.clearDetectedElementLocation()
    }
}

// MARK: - Waveform (listening)

private struct BuddyWaveformView: View {
    private let barProfile: [CGFloat] = [0.4, 0.7, 1.0, 0.7, 0.4]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 36.0)) { ctx in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color(red: 0.45, green: 0.55, blue: 0.95))
                        .frame(width: 2, height: barHeight(i, ctx.date))
                }
            }
            .shadow(color: Color(red: 0.45, green: 0.55, blue: 0.95).opacity(0.6), radius: 6)
        }
    }

    private func barHeight(_ index: Int, _ date: Date) -> CGFloat {
        let phase = CGFloat(date.timeIntervalSinceReferenceDate * 3.6) + CGFloat(index) * 0.35
        let pulse = (sin(phase) + 1) / 2 * 3.0
        return 3 + barProfile[index] * 6 + pulse
    }
}

// MARK: - Microphone (rewrite dictation listening)

private struct BuddyMicrophoneView: View {
    @State private var pulse: CGFloat = 1.0
    @State private var ringScale: CGFloat = 1.0
    @State private var ringOpacity: Double = 0.6

    private let accent = Color(red: 0.45, green: 0.55, blue: 0.95)

    var body: some View {
        ZStack {
            // Expanding ring (ripple effect)
            Circle()
                .stroke(accent.opacity(ringOpacity), lineWidth: 1.5)
                .frame(width: 22, height: 22)
                .scaleEffect(ringScale)

            // Solid filled circle backing the mic icon
            Circle()
                .fill(accent)
                .frame(width: 22, height: 22)
                .shadow(color: accent.opacity(0.7), radius: 8 + (pulse - 1.0) * 10)

            // Microphone SF Symbol
            Image(systemName: "mic.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
        }
        .scaleEffect(pulse)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulse = 1.12
            }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                ringScale = 1.8
                ringOpacity = 0.0
            }
        }
    }
}

// MARK: - Spinner (thinking/processing)

private struct BuddySpinnerView: View {
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0.15, to: 0.85)
            .stroke(
                AngularGradient(
                    colors: [Color(red: 0.45, green: 0.55, blue: 0.95).opacity(0), Color(red: 0.45, green: 0.55, blue: 0.95)],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .shadow(color: Color(red: 0.45, green: 0.55, blue: 0.95).opacity(0.6), radius: 6)
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    spinning = true
                }
            }
    }
}

// MARK: - Preference Key

private struct BubbleSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
