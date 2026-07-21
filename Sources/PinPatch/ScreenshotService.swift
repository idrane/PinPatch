import UIKit

@MainActor
enum PPScreenshotService {
    static func capture(window: UIWindow) -> UIImage? {
        guard window.bounds.width > 0, window.bounds.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat(for: window.traitCollection)
        format.scale = window.screen.scale
        format.opaque = true
        var completed = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            completed = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        return completed ? image : nil
    }
}
