@testable import PinPatch
import UIKit
import XCTest

private final class FakeTextEffectsWindow: UIWindow {}

@MainActor
final class HostWindowResolverTests: XCTestCase {
    private func makeHostWindow() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        return window
    }

    func testTextEffectsAndOverlayWindowsAreNotHostCandidates() {
        let keyboardHelper = FakeTextEffectsWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let overlay = PPOverlayWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        XCTAssertFalse(PPHostWindowResolver.isHostCandidate(keyboardHelper))
        XCTAssertFalse(PPHostWindowResolver.isHostCandidate(overlay))
        XCTAssertTrue(PPHostWindowResolver.isHostCandidate(makeHostWindow()))
    }

    func testResolvePrefersRememberedHostWindow() {
        let host = makeHostWindow()
        let other = makeHostWindow()
        let resolved = PPHostWindowResolver.resolve(remembered: host, in: [other, host])
        XCTAssertTrue(resolved === host)
    }

    func testResolveSkipsTextEffectsWindowWithoutKeyWindow() {
        let host = makeHostWindow()
        let keyboardHelper = FakeTextEffectsWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        keyboardHelper.isHidden = false
        keyboardHelper.windowLevel = UIWindow.Level(rawValue: 10_000_000)
        let overlay = PPOverlayWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        overlay.isHidden = false
        overlay.windowLevel = .alert + 1
        let resolved = PPHostWindowResolver.resolve(remembered: nil, in: [host, keyboardHelper, overlay])
        XCTAssertTrue(resolved === host)
    }

    func testResolveIgnoresHiddenRememberedWindow() {
        let host = makeHostWindow()
        let remembered = makeHostWindow()
        remembered.isHidden = true
        let resolved = PPHostWindowResolver.resolve(remembered: remembered, in: [host, remembered])
        XCTAssertTrue(resolved === host)
    }
}
