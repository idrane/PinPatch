import SwiftUI
import UIKit
import XCTest
@testable import PinPatch

@MainActor
final class ScreenInspectorTests: XCTestCase {
    func testUIKitUsesVisibleLeafControllerAndPreservesRoomTitle() {
        let detail = FixtureDetailViewController()
        detail.title = "301호"
        let window = makeWindow(root: UINavigationController(rootViewController: detail))
        let fingerprint = PPScreenInspector.fingerprint(in: window)
        XCTAssertEqual(fingerprint.framework, .uiKit)
        XCTAssertTrue(fingerprint.screenKind.contains("FixtureDetailViewController"))
        XCTAssertEqual(fingerprint.normalizedTitle, "301호")

        detail.title = "302호"
        let second = PPScreenInspector.fingerprint(in: window)
        XCTAssertNotEqual(fingerprint.canonical, second.canonical)
    }

    func testSwiftUIAnyViewUsesSemanticStructureBeyondHostingType() {
        let first = UIHostingController(rootView: AnyView(
            AccessibilityFixtureView(identifier: "save-button", label: "저장")
        ))
        let second = UIHostingController(rootView: AnyView(
            AccessibilityFixtureView(identifier: "delete-button", label: "삭제")
        ))
        let firstWindow = makeWindow(root: first)
        let secondWindow = makeWindow(root: second)
        let firstFingerprint = PPScreenInspector.fingerprint(in: firstWindow)
        let secondFingerprint = PPScreenInspector.fingerprint(in: secondWindow)
        XCTAssertEqual(firstFingerprint.framework, .swiftUI)
        XCTAssertEqual(firstFingerprint.swiftUIRootType, secondFingerprint.swiftUIRootType)
        XCTAssertNotNil(firstFingerprint.swiftUISemanticDigest)
        XCTAssertNotEqual(firstFingerprint.swiftUISemanticDigest, secondFingerprint.swiftUISemanticDigest)

        let button = firstDescendant(of: first.view, type: UIButton.self)
        XCTAssertNotNil(button)
        if let button {
            let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: firstWindow)
            let (hint, _) = PPScreenInspector.elementHint(at: point, in: firstWindow)
            XCTAssertEqual(hint.accessibilityIdentifier, "save-button")
        }
    }

    func testSwiftUISemanticDigestIgnoresExplicitCounters() {
        let first = UIHostingController(rootView: AnyView(
            AccessibilityFixtureView(identifier: "notifications", label: "알림 3개")
        ))
        let second = UIHostingController(rootView: AnyView(
            AccessibilityFixtureView(identifier: "notifications", label: "알림 4개")
        ))
        let firstFingerprint = PPScreenInspector.fingerprint(in: makeWindow(root: first))
        let secondFingerprint = PPScreenInspector.fingerprint(in: makeWindow(root: second))
        XCTAssertEqual(firstFingerprint.swiftUISemanticDigest, secondFingerprint.swiftUISemanticDigest)
    }

    private func makeWindow(root: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.loadViewIfNeeded()
        root.view.frame = window.bounds
        root.view.setNeedsLayout()
        root.view.layoutIfNeeded()
        return window
    }

    private func firstDescendant<T: UIView>(of root: UIView, type: T.Type) -> T? {
        if let match = root as? T { return match }
        for child in root.subviews {
            if let match = firstDescendant(of: child, type: type) { return match }
        }
        return nil
    }

}

private final class FixtureDetailViewController: UIViewController {}

private struct AccessibilityFixtureView: UIViewRepresentable {
    let identifier: String
    let label: String

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(label, for: .normal)
        button.isAccessibilityElement = true
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = label
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}
}
