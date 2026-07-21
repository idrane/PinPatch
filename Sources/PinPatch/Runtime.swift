import Foundation
import PinPatchBootstrap
import UIKit

@objc(PPBootstrapRuntime)
public final class PPBootstrapRuntime: NSObject {
    @objc public static func start() {
        Task { @MainActor in
            PinPatchRuntime.shared.startIfNeeded()
        }
    }
}

@MainActor
final class PinPatchRuntime {
    static let shared = PinPatchRuntime()

    private var started = false
    private var sessions: [String: PPSceneSession] = [:]
    private var observers: [NSObjectProtocol] = []

    func startIfNeeded() {
        guard !started else { return }
        started = true
        let installed = PPShakeHook.install { window, _ in
            Task { @MainActor in
                PinPatchRuntime.shared.handleShake(in: window)
            }
        }
        guard installed else { return }

        observers.append(NotificationCenter.default.addObserver(
            forName: UIScene.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let scene = notification.object as? UIWindowScene else { return }
            Task { @MainActor in self?.removeSession(for: scene.session.persistentIdentifier) }
        })
        Task { try? await PPStorage.shared.prepare() }
    }

    private func handleShake(in window: UIWindow) {
        guard !(PPFirstResponder.current() is UITextInput),
              let scene = window.windowScene else { return }
        let key = scene.session.persistentIdentifier
        let session = sessions[key] ?? PPSceneSession(scene: scene)
        sessions[key] = session
        session.toggle(shakeWindow: window)
    }

    private func removeSession(for key: String) {
        sessions[key]?.disable()
        sessions.removeValue(forKey: key)
    }
}

@MainActor
final class PPSceneSession {
    private weak var scene: UIWindowScene?
    private var overlay: PPOverlayWindow?
    private weak var hostWindow: UIWindow?
    private var lastToggleUptime: TimeInterval = -.infinity
    private var normalizedBubblePosition: CGPoint?

    init(scene: UIWindowScene) {
        self.scene = scene
    }

    func toggle(shakeWindow: UIWindow? = nil) {
        if let shakeWindow, PPHostWindowResolver.isHostCandidate(shakeWindow) {
            hostWindow = shakeWindow
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastToggleUptime >= 0.5 else { return }
        if overlay == nil {
            guard enable() else { return }
        } else {
            disable()
        }
        lastToggleUptime = now
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    func disable() {
        let hostWindow = appWindow()
        overlay?.overlayController?.prepareForRemoval()
        overlay?.isHidden = true
        overlay?.rootViewController = nil
        overlay = nil
        hostWindow?.makeKey()
    }

    @discardableResult
    private func enable() -> Bool {
        guard let scene else { return false }
        let controller = PPOverlayViewController()
        controller.normalizedBubblePosition = normalizedBubblePosition
        let window = PPOverlayWindow(windowScene: scene)
        window.overlayController = controller
        window.rootViewController = controller
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.isOpaque = false
        controller.onClose = { [weak self] in self?.disable() }
        controller.onCapture = { [weak self] point in self?.beginCapture(at: point) }
        controller.onList = { [weak self] in self?.showList() }
        controller.onInfo = { [weak self] in self?.showInfo() }
        controller.onBubblePositionChanged = { [weak self] position in self?.normalizedBubblePosition = position }
        overlay = window
        window.isHidden = false
        controller.showIntroIfNeeded()
        return true
    }

    private func appWindow() -> UIWindow? {
        guard let scene else { return nil }
        return PPHostWindowResolver.resolve(remembered: hostWindow, in: scene.windows)
    }

    private func beginCapture(at point: CGPoint) {
        guard let scene, let appWindow = appWindow(), let overlay, let controller = overlay.overlayController,
              let screenshot = PPScreenshotService.capture(window: appWindow) else { return }
        controller.isPinEditing = false
        let fingerprint = PPScreenInspector.fingerprint(in: appWindow)
        let (element, targetFrame) = PPScreenInspector.elementHint(at: point, in: appWindow)
        let normalized = PPNormalizedPoint(
            x: appWindow.bounds.width > 0 ? point.x / appWindow.bounds.width : 0,
            y: appWindow.bounds.height > 0 ? point.y / appWindow.bounds.height : 0
        )
        let flow = PPPinFlowCoordinator(presentingWindow: overlay, image: screenshot, initialFrame: targetFrame) { [weak controller] output in
            controller?.activeFlow = nil
            guard let output else { return }
            Task {
                do {
                    let screen = try await PPStorage.shared.resolveScreen(fingerprint)
                    let pinID = UUID()
                    let revisionID = UUID()
                    let record = PPPinRecord(
                        schemaVersion: 1,
                        pinID: pinID,
                        screenID: screen.screenID,
                        revisionID: revisionID,
                        createdAt: Date(),
                        sceneSessionID: scene.session.persistentIdentifier,
                        normalizedPoint: normalized,
                        targetFrame: targetFrame.map(PPRect.init),
                        tag: output.tag,
                        fingerprint: fingerprint,
                        element: element,
                        interfaceStyle: appWindow.traitCollection.userInterfaceStyle == .dark ? "dark" : "light",
                        orientation: scene.interfaceOrientation.rawValue,
                        displayScale: appWindow.screen.scale
                    )
                    guard let screenData = screenshot.pngData(), let cropData = output.crop.pngData() else { return }
                    try await PPStorage.shared.savePin(screen: screen, record: record, note: output.note, screenshot: screenData, crop: cropData)
                } catch {
                    await MainActor.run { controller?.showNonBlockingError("저장하지 못했습니다") }
                }
            }
        }
        controller.activeFlow = flow
        flow.start()
    }

    private func showList() {
        guard let overlay, let controller = overlay.overlayController else { return }
        let list = PPListViewController()
        list.onClose = { [weak controller] in controller?.dismissOverlayPresentation() }
        controller.presentInOverlay(UINavigationController(rootViewController: list))
    }

    private func showInfo() {
        guard let scene, let appWindow = appWindow(), let overlay, let controller = overlay.overlayController else { return }
        let info = PPInfoViewController(
            fingerprint: PPScreenInspector.fingerprint(in: appWindow),
            sceneSessionID: scene.session.persistentIdentifier
        )
        info.onClose = { [weak controller] in controller?.dismissOverlayPresentation() }
        controller.presentInOverlay(UINavigationController(rootViewController: info))
    }

}

private enum PPFirstResponder {
    private weak static var captured: UIResponder?

    @MainActor static func current() -> UIResponder? {
        captured = nil
        UIApplication.shared.sendAction(#selector(UIResponder.pp_captureFirstResponder), to: nil, from: nil, for: nil)
        return captured
    }

    @MainActor static func capture(_ responder: UIResponder) {
        captured = responder
    }
}

extension UIResponder {
    @objc fileprivate func pp_captureFirstResponder() {
        PPFirstResponder.capture(self)
    }
}
