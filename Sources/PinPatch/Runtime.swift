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
        session.toggle()
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
    private var lastToggleUptime: TimeInterval = -.infinity

    init(scene: UIWindowScene) {
        self.scene = scene
    }

    func toggle() {
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
        let window = PPOverlayWindow(windowScene: scene)
        window.overlayController = controller
        window.rootViewController = controller
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        controller.onClose = { [weak self] in self?.disable() }
        controller.onCapture = { [weak self] point in self?.beginCapture(at: point) }
        controller.onList = { [weak self] in self?.showList() }
        overlay = window
        window.isHidden = false
        controller.showIntroIfNeeded()
        refreshMarkers()
        return true
    }

    private func appWindow() -> UIWindow? {
        guard let scene else { return nil }
        return scene.windows.first(where: { $0.isKeyWindow && !($0 is PPOverlayWindow) })
            ?? scene.windows.reversed().first(where: { !$0.isHidden && $0.alpha > 0 && !($0 is PPOverlayWindow) })
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
        let flow = PPPinFlowCoordinator(presentingWindow: overlay, image: screenshot, initialFrame: targetFrame) { [weak self] output in
            controller.activeFlow = nil
            guard let self, let output else { return }
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
                    await MainActor.run { self.refreshMarkers() }
                } catch {
                    await MainActor.run { controller.showNonBlockingError("저장하지 못했습니다") }
                }
            }
        }
        controller.activeFlow = flow
        flow.start()
    }

    private func showList() {
        guard let overlay, let controller = overlay.overlayController else { return }
        let list = PPListViewController()
        list.onChanged = { [weak self] in self?.refreshMarkers() }
        list.onClose = { [weak controller] in controller?.dismissOverlayPresentation() }
        controller.presentInOverlay(UINavigationController(rootViewController: list))
    }

    private func refreshMarkers() {
        guard let appWindow = appWindow(), let controller = overlay?.overlayController else { return }
        let fingerprint = PPScreenInspector.fingerprint(in: appWindow)
        Task {
            guard let screen = try? await PPStorage.shared.findScreen(fingerprint),
                  let pins = try? await PPStorage.shared.loadPinSummaries(),
                  let screens = try? await PPStorage.shared.loadScreenRecords() else { return }
            let activeScreens = screens.filter { candidate in
                pins.contains(where: { $0.record.screenID == candidate.screenID })
            }
            let screenNumber = (activeScreens.firstIndex(where: { $0.screenID == screen.screenID }) ?? 0) + 1
            let matching = pins.filter { $0.record.screenID == screen.screenID }
            let markers = matching.enumerated().map { index, pin in
                PPMarker(
                    label: "\(screenNumber)-\(index + 1)",
                    point: CGPoint(
                        x: pin.record.normalizedPoint.x * appWindow.bounds.width,
                        y: pin.record.normalizedPoint.y * appWindow.bounds.height
                    )
                )
            }
            await MainActor.run { controller.setMarkers(markers) }
        }
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
