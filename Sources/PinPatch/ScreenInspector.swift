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
        let typeName = controller.map { String(reflecting: type(of: $0)) } ?? "UnknownViewController"
        let swiftUI = typeName.localizedCaseInsensitiveContains("hostingcontroller")
            || typeName.localizedCaseInsensitiveContains("hostingview")
        let rawTitle = controller?.navigationItem.title
            ?? controller?.title
            ?? (swiftUI ? visibleHeaderTitle(in: controller?.view) : nil)
        let rootType = swiftUI ? hostingContentName(from: typeName) : nil
        let semantic = swiftUI ? semanticDigest(in: controller?.view) : nil
        return PPScreenFingerprint(
            framework: swiftUI ? .swiftUI : .uiKit,
            screenKind: typeName,
            swiftUIRootType: rootType,
            swiftUISemanticDigest: semantic,
            rawTitle: rawTitle,
            normalizedTitle: PPTitleNormalizer.normalize(rawTitle),
            isModal: isPresentedModally(controller),
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

    private static func hostingContentName(from typeName: String) -> String {
        guard let start = typeName.firstIndex(of: "<"), let end = typeName.lastIndex(of: ">"), start < end else {
            return typeName
        }
        return String(typeName[typeName.index(after: start)..<end])
    }

    private static func isPresentedModally(_ controller: UIViewController?) -> Bool {
        var current = controller
        while let value = current {
            if value.presentingViewController != nil { return true }
            current = value.parent
        }
        return false
    }

    private static func visibleHeaderTitle(in root: UIView?) -> String? {
        guard let root else { return nil }
        var candidates: [(CGFloat, String)] = []
        func collect(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            if view.accessibilityTraits.contains(.header),
               let label = view.accessibilityLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
               !label.isEmpty {
                candidates.append((view.convert(view.bounds, to: view.window).minY, label))
            }
            view.subviews.forEach(collect)
        }
        collect(root)
        return candidates.min(by: { $0.0 < $1.0 })?.1
    }

    private static func semanticDigest(in root: UIView?) -> String? {
        guard let root else { return nil }
        var entries: [String] = []
        var visited = Set<ObjectIdentifier>()
        let rootBounds = root.convert(root.bounds, to: root.window)
        walk(root, rootBounds: rootBounds, depth: 0, visited: &visited, entries: &entries)
        guard !entries.isEmpty else { return nil }
        return PPStableDigest.hex(entries.joined(separator: "\n"))
    }

    private static func walk(
        _ object: AnyObject,
        rootBounds: CGRect,
        depth: Int,
        visited: inout Set<ObjectIdentifier>,
        entries: inout [String]
    ) {
        guard depth <= 32, entries.count < 512 else { return }
        let identifier = ObjectIdentifier(object)
        guard visited.insert(identifier).inserted else { return }

        if let view = object as? UIView, !view.isHidden, view.alpha > 0.01 {
            let isRepeatedCell = ancestorIsRepeatedCell(view)
            if view.isAccessibilityElement || view.accessibilityIdentifier != nil {
                let frame = view.convert(view.bounds, to: view.window)
                let role = String(reflecting: type(of: view))
                let stableLabel = isRepeatedCell ? nil : stableSemanticLabel(for: view)
                let position = positionBucket(frame, in: rootBounds)
                entries.append("d=\(depth)|r=\(role)|t=\(view.accessibilityTraits.rawValue)|id=\(view.accessibilityIdentifier ?? "")|l=\(stableLabel ?? "")|p=\(position)")
            }
            for child in view.subviews {
                walk(child, rootBounds: rootBounds, depth: depth + 1, visited: &visited, entries: &entries)
            }
            for element in view.accessibilityElements ?? [] {
                guard let child = element as AnyObject?, !(child is UIView) else { continue }
                walk(child, rootBounds: rootBounds, depth: depth + 1, visited: &visited, entries: &entries)
            }
            let accessibilityCount = min(max(0, view.accessibilityElementCount()), 256)
            if accessibilityCount > 0 {
                for index in 0..<accessibilityCount {
                    guard let child = view.accessibilityElement(at: index) as AnyObject?, !(child is UIView) else { continue }
                    walk(child, rootBounds: rootBounds, depth: depth + 1, visited: &visited, entries: &entries)
                }
            }
        } else if let element = object as? UIAccessibilityElement {
            let stableLabel = stableSemanticLabel(element.accessibilityLabel)
            let position = positionBucket(element.accessibilityFrame, in: rootBounds)
            entries.append("d=\(depth)|r=AXElement|t=\(element.accessibilityTraits.rawValue)|id=\(element.accessibilityIdentifier ?? "")|l=\(stableLabel ?? "")|p=\(position)")
        }
    }

    private static func stableSemanticLabel(for view: UIView) -> String? {
        guard !(view is UITextField), !(view is UITextView) else { return nil }
        let traits = view.accessibilityTraits
        let structural = traits.contains(.button) || traits.contains(.header) || traits.contains(.searchField) || view is UIControl
        guard structural else { return nil }
        return stableSemanticLabel(view.accessibilityLabel)
    }

    private static func stableSemanticLabel(_ label: String?) -> String? {
        guard var value = PPTitleNormalizer.normalize(label) else { return nil }
        if value.range(of: #"^\d+$"#, options: .regularExpression) != nil { return nil }
        value = value.replacingOccurrences(
            of: #"(?i)\b\d+\s*(?:개|건|명|items?|results?|notifications?)\b"#,
            with: "{count}",
            options: .regularExpression
        )
        return value
    }

    private static func ancestorIsRepeatedCell(_ view: UIView) -> Bool {
        var current = view.superview
        while let candidate = current {
            if candidate is UITableViewCell || candidate is UICollectionViewCell { return true }
            current = candidate.superview
        }
        return false
    }

    private static func positionBucket(_ frame: CGRect, in bounds: CGRect) -> String {
        guard bounds.width > 0, bounds.height > 0 else { return "0,0,0,0" }
        func bucket(_ value: CGFloat) -> Int { min(10, max(0, Int((value * 10).rounded()))) }
        return [
            bucket(frame.minX / bounds.width), bucket(frame.minY / bounds.height),
            bucket(frame.width / bounds.width), bucket(frame.height / bounds.height)
        ].map(String.init).joined(separator: ",")
    }
}
