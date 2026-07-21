import UIKit
import XCTest
@testable import PinPatch

@MainActor
final class OverlayTests: XCTestCase {
    func testViewModePassesThroughOutsideControlsAndEditModeCaptures() {
        let controller = PPOverlayViewController()
        let window = PPOverlayWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.overlayController = controller
        window.rootViewController = controller
        window.isHidden = false
        controller.loadViewIfNeeded()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()

        XCTAssertNil(window.hitTest(CGPoint(x: 20, y: 600), with: nil))
        let bubble = controller.view.subviews
            .compactMap { $0 as? UIButton }
            .first(where: { $0.accessibilityLabel == "PinPatch menu" })
        XCTAssertNotNil(bubble)
        if let bubble {
            XCTAssertTrue(window.hitTest(bubble.center, with: nil) === bubble)
        }

        controller.isPinEditing = true
        XCTAssertNotNil(window.hitTest(CGPoint(x: 20, y: 600), with: nil))
    }

    func testPresentedToolScreenReceivesTouchesOutsideFloatingControls() {
        let controller = PPOverlayViewController()
        let window = PPOverlayWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.overlayController = controller
        window.rootViewController = controller
        window.isHidden = false
        controller.loadViewIfNeeded()
        controller.view.frame = window.bounds

        let presented = UIViewController()
        presented.view.backgroundColor = .systemBackground
        let control = UIButton(type: .system)
        control.frame = CGRect(x: 0, y: 540, width: 100, height: 120)
        presented.view.addSubview(control)
        controller.present(presented, animated: false)
        presented.view.frame = window.bounds
        presented.view.layoutIfNeeded()

        XCTAssertTrue(controller.requiresExclusiveInput)
        XCTAssertNotNil(window.hitTest(CGPoint(x: 20, y: 600), with: nil))
    }

    func testEmbeddedScreenshotFlowReceivesTouchesAndRestoresPassThrough() {
        let controller = PPOverlayViewController()
        let window = PPOverlayWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.overlayController = controller
        window.rootViewController = controller
        window.isHidden = false
        controller.loadViewIfNeeded()
        controller.view.frame = window.bounds

        let tool = UIViewController()
        tool.view.backgroundColor = .systemBackground
        let cropHandle = UIButton(type: .system)
        cropHandle.frame = CGRect(x: 0, y: 540, width: 100, height: 120)
        tool.view.addSubview(cropHandle)
        controller.embedToolContent(tool)
        tool.view.layoutIfNeeded()

        XCTAssertTrue(controller.requiresExclusiveInput)
        XCTAssertTrue(window.hitTest(CGPoint(x: 20, y: 600), with: nil) === cropHandle)

        let removed = expectation(description: "embedded tool removed")
        controller.removeEmbeddedToolContent(animated: false) { removed.fulfill() }
        wait(for: [removed], timeout: 1)
        XCTAssertFalse(controller.requiresExclusiveInput)
        XCTAssertNil(window.hitTest(CGPoint(x: 20, y: 600), with: nil))
    }

    func testQuestionMarkTogglesButtonInformationWithoutCompetingDismissal() {
        let controller = PPOverlayViewController()
        let window = PPOverlayWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.overlayController = controller
        window.rootViewController = controller
        window.isHidden = false
        controller.loadViewIfNeeded()
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        guard let help = descendants(of: controller.view)
            .compactMap({ $0 as? UIButton })
            .first(where: { $0.accessibilityLabel == "Button Information" }),
              let helpLabel = descendants(of: controller.view)
            .compactMap({ $0 as? UILabel })
            .first(where: { $0.text == "Button Information" }) else {
            XCTFail("help control is missing")
            return
        }

        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        controller.toggleMenu()
        XCTAssertFalse(help.isHidden)
        controller.toggleActionInfo()
        XCTAssertFalse(helpLabel.isHidden)
        controller.toggleActionInfo()
        XCTAssertEqual(helpLabel.alpha, 0)
    }

    func testEditStatusDropsFromSafeAreaCenterBelowNotch() {
        let controller = PPOverlayViewController()
        let window = PPOverlayWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.overlayController = controller
        window.rootViewController = controller
        window.isHidden = false
        controller.loadViewIfNeeded()
        controller.view.frame = window.bounds
        controller.additionalSafeAreaInsets.top = 59
        controller.view.layoutIfNeeded()

        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        controller.isPinEditing = true
        controller.view.layoutIfNeeded()

        let status = controller.view.subviews.compactMap { $0 as? PPToastView }.first
        XCTAssertNotNil(status)
        XCTAssertFalse(status?.isHidden ?? true)
        XCTAssertEqual(status?.frame.midX ?? 0, controller.view.bounds.midX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(status?.frame.minY ?? 0, controller.view.safeAreaInsets.top)

        _ = window.hitTest(CGPoint(x: 20, y: 600), with: nil)
        let hidden = expectation(description: "status hides on next touch")
        DispatchQueue.main.async {
            XCTAssertEqual(status?.alpha ?? 1, 0)
            hidden.fulfill()
        }
        wait(for: [hidden], timeout: 1)
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }
}
