import UIKit
import XCTest
@testable import PinPatch

@MainActor
final class ShakeHookTests: XCTestCase {
    func testHookDoesNotLeakPrivateSelectorIntoOrdinaryViews() {
        let view = UIView(frame: .zero)
        view.motionEnded(.motionShake, with: nil)
    }

    func testWindowCanReceiveShakeAfterHookInstallation() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.motionEnded(.motionShake, with: nil)
    }
}
