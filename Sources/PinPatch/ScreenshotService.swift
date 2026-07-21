import UIKit

@MainActor
enum PPScreenshotService {
    static func capture(window: UIWindow) -> UIImage? {
        guard window.bounds.width > 0, window.bounds.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat(for: window.traitCollection)
        format.scale = window.screen.scale
        format.opaque = window.isOpaque
        return UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { context in
            let completed = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            if !completed {
                window.layer.render(in: context.cgContext)
            }
        }
    }
}
