import UIKit

struct PPMarker {
    let label: String
    let point: CGPoint
}

final class PPOverlayWindow: UIWindow {
    weak var overlayController: PPOverlayViewController?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let controller = overlayController else { return nil }
        let hit = super.hitTest(point, with: event)
        if controller.isPinEditing { return hit }
        guard let hit else { return nil }
        return controller.isInteractiveControl(hit) ? hit : nil
    }

    override var canBecomeKey: Bool { true }
}

@MainActor
final class PPOverlayViewController: UIViewController, UIGestureRecognizerDelegate {
    var onCapture: ((CGPoint) -> Void)?
    var onList: (() -> Void)?
    var onClose: (() -> Void)?
    var activeFlow: PPPinFlowCoordinator?

    var isPinEditing = false {
        didSet {
            captureRecognizer.isEnabled = isPinEditing
            editButton.configuration?.baseBackgroundColor = isPinEditing ? .systemRed : .systemBlue
            editButton.configuration?.title = isPinEditing ? "편집 종료" : "핀 찍기"
        }
    }

    private let bubbleButton = UIButton(type: .system)
    private let menuStack = UIStackView()
    private let editButton = UIButton(type: .system)
    private lazy var captureRecognizer = UITapGestureRecognizer(target: self, action: #selector(captureTap(_:)))
    private var markerViews: [UIView] = []
    private var introLabel: UILabel?
    private weak var previousKeyWindow: UIWindow?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = false
        configureBubble()
        configureMenu()
        captureRecognizer.cancelsTouchesInView = true
        captureRecognizer.delegate = self
        captureRecognizer.isEnabled = false
        view.addGestureRecognizer(captureRecognizer)
    }

    func isInteractiveControl(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current {
            if candidate === bubbleButton || candidate === menuStack || candidate is UIButton && candidate.isDescendant(of: menuStack) {
                return true
            }
            current = candidate.superview
        }
        return false
    }

    func showIntroIfNeeded() {
        let key = "dev.pinpatch.didShowIntro"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let label = UILabel()
        label.text = "PinPatch"
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.isAccessibilityElement = false
        label.frame = CGRect(x: view.bounds.width - 124, y: 76, width: 96, height: 32)
        label.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
        view.addSubview(label)
        introLabel = label
        UIView.animate(withDuration: 0.25, delay: 2, options: []) { label.alpha = 0 } completion: { _ in label.removeFromSuperview() }
    }

    func setMarkers(_ markers: [PPMarker]) {
        markerViews.forEach { $0.removeFromSuperview() }
        markerViews = markers.map { marker in
            let label = UILabel(frame: CGRect(x: marker.point.x - 16, y: marker.point.y - 16, width: 36, height: 32))
            label.text = marker.label
            label.textAlignment = .center
            label.font = .boldSystemFont(ofSize: 11)
            label.textColor = .white
            label.backgroundColor = .systemRed
            label.layer.cornerRadius = 16
            label.clipsToBounds = true
            label.isUserInteractionEnabled = false
            label.isAccessibilityElement = false
            view.insertSubview(label, belowSubview: bubbleButton)
            return label
        }
    }

    func presentInOverlay(_ controller: UIViewController) {
        guard let window = view.window else { return }
        previousKeyWindow = window.windowScene?.windows.first(where: { $0.isKeyWindow && $0 !== window })
        window.makeKey()
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    func dismissOverlayPresentation() {
        dismiss(animated: true) { [weak self] in
            self?.previousKeyWindow?.makeKey()
            self?.previousKeyWindow = nil
        }
    }

    func prepareForRemoval() {
        dismiss(animated: false)
        activeFlow = nil
        previousKeyWindow?.makeKey()
        previousKeyWindow = nil
    }

    func showNonBlockingError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { alert.dismiss(animated: true) }
    }

    private func configureBubble() {
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "pin.fill")
        config.baseBackgroundColor = .systemRed
        config.cornerStyle = .capsule
        bubbleButton.configuration = config
        bubbleButton.accessibilityLabel = "PinPatch 메뉴"
        bubbleButton.frame = CGRect(x: view.bounds.width - 68, y: 24, width: 52, height: 52)
        bubbleButton.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
        bubbleButton.addTarget(self, action: #selector(toggleMenu), for: .touchUpInside)
        view.addSubview(bubbleButton)
    }

    private func configureMenu() {
        menuStack.axis = .vertical
        menuStack.spacing = 8
        menuStack.alignment = .fill
        menuStack.isHidden = true
        menuStack.frame = CGRect(x: view.bounds.width - 156, y: 84, width: 140, height: 132)
        menuStack.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
        editButton.configuration = .filled()
        editButton.configuration?.title = "핀 찍기"
        editButton.addTarget(self, action: #selector(toggleEdit), for: .touchUpInside)
        let list = menuButton(title: "목록", selector: #selector(openList))
        let close = menuButton(title: "끄기", selector: #selector(closeTool))
        [editButton, list, close].forEach(menuStack.addArrangedSubview)
        view.addSubview(menuStack)
    }

    private func menuButton(title: String, selector: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.configuration = .filled()
        button.configuration?.title = title
        button.addTarget(self, action: selector, for: .touchUpInside)
        return button
    }

    @objc private func toggleMenu() { menuStack.isHidden.toggle() }
    @objc private func toggleEdit() { isPinEditing.toggle(); menuStack.isHidden = true }
    @objc private func openList() { menuStack.isHidden = true; onList?() }
    @objc private func closeTool() { onClose?() }

    @objc private func captureTap(_ recognizer: UITapGestureRecognizer) {
        guard isPinEditing, recognizer.state == .ended else { return }
        onCapture?(recognizer.location(in: view))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard isPinEditing, let touched = touch.view else { return false }
        return !isInteractiveControl(touched)
    }
}
