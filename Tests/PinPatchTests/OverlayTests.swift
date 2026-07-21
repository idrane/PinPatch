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
        XCTAssertTrue(window.hitTest(CGPoint(x: 348, y: 50), with: nil) is UIButton)

        controller.isPinEditing = true
        XCTAssertNotNil(window.hitTest(CGPoint(x: 20, y: 600), with: nil))
    }

    func testMarkersAreNoninteractiveAndNotAccessibilityElements() {
        let controller = PPOverlayViewController()
        controller.loadViewIfNeeded()
        controller.setMarkers([PPMarker(label: "1-1", point: CGPoint(x: 100, y: 100))])
        let marker = controller.view.subviews
            .compactMap { $0 as? UILabel }
            .first(where: { $0.text == "1-1" })
        XCTAssertNotNil(marker)
        XCTAssertEqual(marker?.isUserInteractionEnabled, false)
        XCTAssertEqual(marker?.isAccessibilityElement, false)
    }
}
