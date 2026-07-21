import Foundation
import UIKit

@MainActor
enum PPScreenInspector {
    static func visibleController(in window: UIWindow) -> UIViewController? {
        guard let root = window.rootViewController else { return nil }
        return visibleLeaf(from: root)
    }

    static func fingerprint(in window: UIWindow) -> PPScreenFingerprint {
        let controller = visibleController(in: window)
        let rawTitle = controller?.navigationItem.title
            ?? controller?.title
        return PPScreenFingerprint(
            rawTitle: rawTitle,
            normalizedTitle: PPTitleNormalizer.normalize(rawTitle),
            fingerprintVersion: PPScreenFingerprint.version
        )
    }

    static func elementHint(at point: CGPoint, in window: UIWindow) -> (PPElementHint, CGRect?) {
        let view = window.hitTest(point, with: nil)
        let controller = visibleController(in: window)
        let chain = controllerChain(from: controller)
        let accessibility = closestAccessibilityElement(at: point, in: controller?.view, window: window)
        let frame = accessibility?.frame
            ?? view.flatMap { $0.superview?.convert($0.frame, to: window) ?? $0.convert($0.bounds, to: window) }

        var actions: [String] = []
        if let control = view as? UIControl {
            for target in control.allTargets {
                actions.append(contentsOf: control.actions(forTarget: target, forControlEvent: .allEvents) ?? [])
            }
        }
        let secureValue = (view as? UITextField)?.isSecureTextEntry == true || (view as? UITextView)?.isSecureTextEntry == true
        let className = view.map { String(reflecting: type(of: $0)) }
        let module = className?.split(separator: ".").first.map(String.init)
        return (
            PPElementHint(
                viewClass: className,
                moduleName: module,
                controllerChain: chain,
                accessibilityIdentifier: accessibility?.identifier ?? view?.accessibilityIdentifier,
                accessibilityLabel: accessibility?.label ?? view?.accessibilityLabel,
                accessibilityValue: secureValue ? nil : (accessibility?.value ?? view?.accessibilityValue),
                accessibilityTraits: accessibility?.traits ?? view?.accessibilityTraits.rawValue ?? 0,
                controlActions: Array(Set(actions)).sorted()
            ),
            frame
        )
    }

    private struct AccessibilityCandidate {
        let identifier: String?
        let label: String?
        let value: String?
        let traits: UInt64
        let frame: CGRect
    }

    private static func closestAccessibilityElement(
        at point: CGPoint,
        in root: UIView?,
        window: UIWindow
    ) -> AccessibilityCandidate? {
        guard let root else { return nil }
        var candidates: [AccessibilityCandidate] = []
        var visited = Set<ObjectIdentifier>()

        func add(_ candidate: AccessibilityCandidate) {
            guard candidate.frame.width > 0, candidate.frame.height > 0, candidate.frame.contains(point) else { return }
            candidates.append(candidate)
        }

        func walk(_ object: AnyObject, depth: Int) {
            guard depth <= 32, visited.count < 512, visited.insert(ObjectIdentifier(object)).inserted else { return }
            if let view = object as? UIView, !view.isHidden, view.alpha > 0.01 {
                if view.isAccessibilityElement || view.accessibilityIdentifier != nil {
                    add(AccessibilityCandidate(
                        identifier: view.accessibilityIdentifier,
                        label: view.accessibilityLabel,
                        value: view.accessibilityValue,
                        traits: view.accessibilityTraits.rawValue,
                        frame: view.convert(view.bounds, to: window)
                    ))
                }
                view.subviews.forEach { walk($0, depth: depth + 1) }
                for element in view.accessibilityElements ?? [] {
                    guard let child = element as AnyObject?, !(child is UIView) else { continue }
                    walk(child, depth: depth + 1)
                }
                let count = min(max(0, view.accessibilityElementCount()), 256)
                if count > 0 {
                    for index in 0..<count {
                        guard let child = view.accessibilityElement(at: index) as AnyObject?, !(child is UIView) else { continue }
                        walk(child, depth: depth + 1)
                    }
                }
            } else if let element = object as? UIAccessibilityElement {
                add(AccessibilityCandidate(
                    identifier: element.accessibilityIdentifier,
                    label: element.accessibilityLabel,
                    value: nil,
                    traits: element.accessibilityTraits.rawValue,
                    frame: window.convert(element.accessibilityFrame, from: window.screen.coordinateSpace)
                ))
            }
        }

        walk(root, depth: 0)
        return candidates.min { lhs, rhs in
            lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
        }
    }

    private static func visibleLeaf(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController, !presented.isBeingDismissed {
            return visibleLeaf(from: presented)
        }
        if let navigation = controller as? UINavigationController, let visible = navigation.visibleViewController {
            return visibleLeaf(from: visible)
        }
        if let tab = controller as? UITabBarController, let selected = tab.selectedViewController {
            return visibleLeaf(from: selected)
        }
        if let split = controller as? UISplitViewController, let last = split.viewControllers.last {
            return visibleLeaf(from: last)
        }
        for child in controller.children.reversed() where child.viewIfLoaded?.window != nil {
            return visibleLeaf(from: child)
        }
        return controller
    }

    private static func controllerChain(from controller: UIViewController?) -> [String] {
        var result: [String] = []
        var current = controller
        while let value = current {
            result.append(String(reflecting: type(of: value)))
            current = value.parent ?? value.presentingViewController
            if result.count >= 32 { break }
        }
        return result
    }

}
