import UIKit

@MainActor
enum PPHostWindowResolver {
    /// System windows such as UITextEffectsWindow appear in the scene after the
    /// first keyboard presentation, stay visible at a very high window level,
    /// and render as an empty (black when opaque) hierarchy. They must never be
    /// treated as the host app window for capture or fingerprinting.
    static func isHostCandidate(_ window: UIWindow) -> Bool {
        guard !(window is PPOverlayWindow) else { return false }
        let className = NSStringFromClass(type(of: window))
        return !className.contains("TextEffectsWindow")
            && !className.contains("RemoteKeyboardWindow")
            && !className.contains("InputWindow")
    }

    static func resolve(remembered: UIWindow?, in windows: [UIWindow]) -> UIWindow? {
        if let remembered,
           !remembered.isHidden,
           remembered.alpha > 0,
           windows.contains(where: { $0 === remembered }),
           isHostCandidate(remembered) {
            return remembered
        }
        let candidates = windows.filter(isHostCandidate)
        let visible = candidates.filter { !$0.isHidden && $0.alpha > 0 }
        return candidates.first(where: { $0.isKeyWindow && !$0.isHidden })
            ?? visible.reversed().first(where: { $0.windowLevel <= .normal })
            ?? visible.last
    }
}
