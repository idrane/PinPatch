import UIKit

final class PPOverlayWindow: UIWindow {
    weak var overlayController: PPOverlayViewController?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let controller = overlayController else { return nil }
        let hit = super.hitTest(point, with: event)
        controller.handleAmbientTouch(on: hit)
        if controller.requiresExclusiveInput { return hit }
        guard let hit else { return nil }
        return controller.isInteractiveControl(hit) ? hit : nil
    }

    override var canBecomeKey: Bool { true }
}

@MainActor
final class PPOverlayViewController: UIViewController, UIGestureRecognizerDelegate {
    var onCapture: ((CGPoint) -> Void)?
    var onList: (() -> Void)?
    var onInfo: (() -> Void)?
    var onClose: (() -> Void)?
    var normalizedBubblePosition: CGPoint?
    var onBubblePositionChanged: ((CGPoint) -> Void)?
    var activeFlow: PPPinFlowCoordinator?

    var isPinEditing = false {
        didSet {
            captureRecognizer.isEnabled = isPinEditing
            updateEditState(animated: true)
        }
    }

    private let bubbleButton = UIButton(type: .system)
    private let actionContainer = UIView()
    private let editButton = UIButton(type: .system)
    private let listButton = UIButton(type: .system)
    private let screenInfoButton = UIButton(type: .system)
    private let helpButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let editStatus = PPToastView(symbol: "hand.tap.fill", title: "핀 추가 모드", detail: "고치고 싶은 곳을 탭하세요")
    private lazy var captureRecognizer = UITapGestureRecognizer(target: self, action: #selector(captureTap(_:)))
    private var introView: UIView?
    private var isMenuOpen = false
    private var isShowingActionInfo = false
    private var actionInfoViews: [UIButton: UILabel] = [:]
    private var infoHideWorkItem: DispatchWorkItem?
    private var didApplyInitialBubblePosition = false
    private weak var previousKeyWindow: UIWindow?
    private weak var embeddedToolController: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.accessibilityViewIsModal = false
        configureBubble()
        configureActions()
        captureRecognizer.cancelsTouchesInView = true
        captureRecognizer.delegate = self
        captureRecognizer.isEnabled = false
        view.addGestureRecognizer(captureRecognizer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !didApplyInitialBubblePosition, view.bounds.width > 0, view.bounds.height > 0 {
            didApplyInitialBubblePosition = true
            if let position = normalizedBubblePosition {
                bubbleButton.center = CGPoint(x: position.x * view.bounds.width, y: position.y * view.bounds.height)
            }
        }
        keepBubbleInsideSafeBounds()
        layoutFloatingControls()
    }

    func isInteractiveControl(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current {
            if candidate === bubbleButton || actionButtons.contains(where: { candidate === $0 }) {
                return true
            }
            current = candidate.superview
        }
        return false
    }

    var requiresExclusiveInput: Bool {
        isPinEditing || activeFlow != nil || embeddedToolController != nil || presentedViewController != nil
    }

    func handleAmbientTouch(on hitView: UIView?) {
        if !editStatus.isHidden {
            DispatchQueue.main.async { [weak self] in self?.hideEditStatus(animated: true) }
        }
        guard isShowingActionInfo else { return }
        if let hitView, isHelpControl(hitView) { return }
        DispatchQueue.main.async { [weak self] in self?.setActionInfoVisible(false, animated: true) }
    }

    private func isHelpControl(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let candidate = current {
            if candidate === helpButton { return true }
            current = candidate.superview
        }
        return false
    }

    func showIntroIfNeeded() {
        let key = "dev.pinpatch.didShowIntro"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let toast = PPToastView(symbol: "pin.fill", title: "PinPatch", detail: "탭해서 핀을 남겨보세요")
        toast.isAccessibilityElement = false
        toast.frame = CGRect(x: max(16, view.bounds.width - 242), y: 88, width: 226, height: 62)
        toast.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
        toast.alpha = 0
        toast.transform = CGAffineTransform(translationX: 0, y: -8).scaledBy(x: 0.96, y: 0.96)
        view.insertSubview(toast, belowSubview: bubbleButton)
        introView = toast
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.2) {
            toast.alpha = 1
            toast.transform = .identity
        } completion: { _ in
            UIView.animate(withDuration: 0.25, delay: 2.4, options: [.curveEaseIn]) { toast.alpha = 0 } completion: { _ in toast.removeFromSuperview() }
        }
    }

    func presentInOverlay(_ controller: UIViewController) {
        guard let window = view.window else { return }
        previousKeyWindow = window.windowScene?.windows.first(where: { $0.isKeyWindow && $0 !== window })
        window.makeKey()
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    func embedToolContent(_ controller: UIViewController) {
        guard let window = view.window, embeddedToolController == nil else { return }
        previousKeyWindow = window.windowScene?.windows.first(where: { $0.isKeyWindow && $0 !== window })
        window.makeKey()
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.alpha = 0
        controller.view.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
        embeddedToolController = controller
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            controller.view.alpha = 1
            controller.view.transform = .identity
        }
    }

    func removeEmbeddedToolContent(animated: Bool, completion: @escaping () -> Void) {
        guard let controller = embeddedToolController else {
            completion()
            return
        }
        controller.willMove(toParent: nil)
        let finish = { [weak self, weak controller] in
            controller?.view.removeFromSuperview()
            controller?.removeFromParent()
            self?.embeddedToolController = nil
            self?.previousKeyWindow?.makeKey()
            self?.previousKeyWindow = nil
            completion()
        }
        guard animated else {
            finish()
            return
        }
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            controller.view.alpha = 0
            controller.view.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
        } completion: { _ in finish() }
    }

    func dismissOverlayPresentation() {
        dismiss(animated: true) { [weak self] in
            self?.previousKeyWindow?.makeKey()
            self?.previousKeyWindow = nil
        }
    }

    func prepareForRemoval() {
        infoHideWorkItem?.cancel()
        dismiss(animated: false)
        if let embeddedToolController {
            embeddedToolController.willMove(toParent: nil)
            embeddedToolController.view.removeFromSuperview()
            embeddedToolController.removeFromParent()
            self.embeddedToolController = nil
        }
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
        config.image = PPTheme.symbol("pin.fill", pointSize: 19, weight: .bold)
        config.baseBackgroundColor = PPTheme.accent
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        bubbleButton.configuration = config
        bubbleButton.accessibilityLabel = "PinPatch 메뉴"
        bubbleButton.accessibilityHint = "핀 추가와 목록 메뉴를 엽니다"
        bubbleButton.frame = CGRect(x: view.bounds.width - 72, y: 20, width: 56, height: 56)
        bubbleButton.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
        bubbleButton.layer.cornerRadius = 28
        bubbleButton.layer.cornerCurve = .continuous
        PPTheme.applyFloatingShadow(to: bubbleButton.layer)
        bubbleButton.addTarget(self, action: #selector(toggleMenu), for: .touchUpInside)
        let drag = UIPanGestureRecognizer(target: self, action: #selector(dragBubble(_:)))
        drag.cancelsTouchesInView = true
        bubbleButton.addGestureRecognizer(drag)
        view.addSubview(bubbleButton)
    }

    private var actionButtons: [UIButton] {
        [editButton, listButton, screenInfoButton, helpButton, closeButton]
    }

    private func configureActions() {
        actionContainer.frame = view.bounds
        actionContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        actionContainer.backgroundColor = .clear
        view.insertSubview(actionContainer, belowSubview: bubbleButton)

        configureActionButton(editButton, symbol: "pin.fill", title: "핀 추가", tint: PPTheme.pin, selector: #selector(toggleEdit))
        configureActionButton(listButton, symbol: "list.bullet.rectangle.fill", title: "핀 목록", tint: PPTheme.accent, selector: #selector(openList))
        configureActionButton(screenInfoButton, symbol: "rectangle.and.text.magnifyingglass", title: "현재 화면 정보", tint: .systemTeal, selector: #selector(openInfo))
        configureActionButton(helpButton, symbol: "questionmark", title: "버튼 설명", tint: .systemOrange, selector: #selector(toggleActionInfo))
        configureActionButton(closeButton, symbol: "power", title: "PinPatch 끄기", tint: .secondaryLabel, selector: #selector(closeTool))

        for button in actionButtons {
            button.isHidden = true
            button.alpha = 0
            actionContainer.addSubview(button)

            let label = UILabel()
            label.text = button.accessibilityLabel
            label.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
            label.textColor = .systemBackground
            label.backgroundColor = UIColor.label.withAlphaComponent(0.9)
            label.textAlignment = .center
            label.layer.cornerRadius = 12
            label.layer.cornerCurve = .continuous
            label.clipsToBounds = true
            label.isUserInteractionEnabled = false
            label.isAccessibilityElement = false
            label.alpha = 0
            label.isHidden = true
            actionContainer.addSubview(label)
            actionInfoViews[button] = label
        }

        editStatus.isHidden = true
        editStatus.alpha = 0
        editStatus.isUserInteractionEnabled = false
        editStatus.isAccessibilityElement = false
        editStatus.frame = CGRect(x: 16, y: 22, width: 218, height: 58)
        editStatus.autoresizingMask = [.flexibleRightMargin, .flexibleBottomMargin]
        view.insertSubview(editStatus, belowSubview: actionContainer)
    }

    private func configureActionButton(_ button: UIButton, symbol: String, title: String, tint: UIColor, selector: Selector) {
        var config = UIButton.Configuration.filled()
        config.image = PPTheme.symbol(symbol, pointSize: 17, weight: .semibold)
        config.baseBackgroundColor = .secondarySystemBackground
        config.baseForegroundColor = tint
        config.cornerStyle = .capsule
        button.configuration = config
        button.frame.size = CGSize(width: 48, height: 48)
        button.layer.cornerRadius = 24
        button.layer.cornerCurve = .continuous
        button.accessibilityLabel = title
        button.addTarget(self, action: selector, for: .touchUpInside)
        PPTheme.applyFloatingShadow(to: button.layer)
    }

    private func setMenuOpen(_ open: Bool, animated: Bool) {
        isMenuOpen = open
        bubbleButton.accessibilityValue = open ? "열림" : "닫힘"
        if !open { setActionInfoVisible(false, animated: animated) }
        if open {
            layoutFloatingControls()
            for button in actionButtons {
                button.isHidden = false
                button.center = bubbleButton.center
                button.transform = CGAffineTransform(scaleX: 0.45, y: 0.45)
            }
        }

        let targets = actionButtonCenters()
        for (index, button) in actionButtons.enumerated() {
            let changes = {
                button.center = open ? targets[index] : self.bubbleButton.center
                button.alpha = open ? 1 : 0
                button.transform = open ? .identity : CGAffineTransform(scaleX: 0.45, y: 0.45)
            }
            let completion: (Bool) -> Void = { _ in if !open { button.isHidden = true } }
            if animated {
                UIView.animate(
                    withDuration: 0.38,
                    delay: open ? Double(index) * 0.035 : 0,
                    usingSpringWithDamping: 0.72,
                    initialSpringVelocity: 0.2,
                    options: [.beginFromCurrentState, .allowUserInteraction],
                    animations: changes,
                    completion: completion
                )
            } else {
                changes()
                completion(true)
            }
        }

        UIView.animate(withDuration: 0.26, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.bubbleButton.transform = open ? CGAffineTransform(rotationAngle: .pi / 4) : .identity
        }
    }

    private func updateEditState(animated: Bool) {
        var config = editButton.configuration
        config?.image = PPTheme.symbol(isPinEditing ? "checkmark.circle.fill" : "pin.fill", pointSize: 17)
        editButton.configuration = config
        editButton.accessibilityLabel = isPinEditing ? "핀 추가 끝내기" : "핀 추가"
        actionInfoViews[editButton]?.text = editButton.accessibilityLabel
        bubbleButton.configuration?.baseBackgroundColor = isPinEditing ? PPTheme.pin : PPTheme.accent
        bubbleButton.configuration?.image = PPTheme.symbol(isPinEditing ? "hand.tap.fill" : "pin.fill", pointSize: 19, weight: .bold)
        guard isPinEditing else {
            hideEditStatus(animated: animated)
            return
        }

        layoutEditStatus()
        editStatus.isHidden = false
        editStatus.alpha = 0
        editStatus.transform = CGAffineTransform(translationX: 0, y: -18).scaledBy(x: 0.98, y: 0.98)
        let changes = {
            self.editStatus.alpha = 1
            self.editStatus.transform = .identity
        }
        if animated {
            UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0.25, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
        } else {
            changes()
        }

    }

    private func hideEditStatus(animated: Bool) {
        let changes = {
            self.editStatus.alpha = 0
            self.editStatus.transform = CGAffineTransform(translationX: 0, y: -10).scaledBy(x: 0.98, y: 0.98)
        }
        let completion: (Bool) -> Void = { _ in self.editStatus.isHidden = true }
        guard animated, !editStatus.isHidden else {
            changes()
            completion(true)
            return
        }
        UIView.animate(withDuration: 0.22, delay: 0, options: [.beginFromCurrentState, .curveEaseIn], animations: changes, completion: completion)
    }

    @objc func toggleMenu() {
        PPTheme.impactFeedback(.soft)
        setMenuOpen(!isMenuOpen, animated: true)
    }

    @objc private func toggleEdit() {
        PPTheme.selectionFeedback()
        isPinEditing.toggle()
        setMenuOpen(false, animated: true)
    }

    @objc private func openList() {
        PPTheme.selectionFeedback()
        setMenuOpen(false, animated: true)
        onList?()
    }

    @objc private func openInfo() {
        PPTheme.selectionFeedback()
        setMenuOpen(false, animated: true)
        onInfo?()
    }

    @objc func toggleActionInfo() {
        PPTheme.selectionFeedback()
        setActionInfoVisible(!isShowingActionInfo, animated: true)
    }

    @objc private func closeTool() {
        PPTheme.impactFeedback(.soft)
        onClose?()
    }

    @objc private func dragBubble(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            setMenuOpen(false, animated: true)
            PPTheme.impactFeedback(.soft)
        case .changed:
            let translation = recognizer.translation(in: view)
            bubbleButton.center = CGPoint(x: bubbleButton.center.x + translation.x, y: bubbleButton.center.y + translation.y)
            recognizer.setTranslation(.zero, in: view)
            keepBubbleInsideSafeBounds()
            layoutFloatingControls()
        case .ended, .cancelled:
            snapBubbleToNearestEdge()
        default:
            break
        }
    }

    private func keepBubbleInsideSafeBounds() {
        let safe = view.safeAreaInsets
        let half = bubbleButton.bounds.width / 2
        let minimumX = max(half + 8, safe.left + half + 8)
        let maximumX = min(view.bounds.width - half - 8, view.bounds.width - safe.right - half - 8)
        let minimumY = max(half + 8, safe.top + half + 8)
        let maximumY = min(view.bounds.height - half - 8, view.bounds.height - safe.bottom - half - 8)
        guard minimumX <= maximumX, minimumY <= maximumY else { return }
        bubbleButton.center = CGPoint(
            x: min(maximumX, max(minimumX, bubbleButton.center.x)),
            y: min(maximumY, max(minimumY, bubbleButton.center.y))
        )
    }

    private func snapBubbleToNearestEdge() {
        let safe = view.safeAreaInsets
        let half = bubbleButton.bounds.width / 2
        let left = safe.left + half + 8
        let right = view.bounds.width - safe.right - half - 8
        let targetX = bubbleButton.center.x < view.bounds.midX ? left : right
        UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.72, initialSpringVelocity: 0.35, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.bubbleButton.center.x = targetX
            self.layoutFloatingControls()
        } completion: { _ in
            guard self.view.bounds.width > 0, self.view.bounds.height > 0 else { return }
            let normalized = CGPoint(
                x: self.bubbleButton.center.x / self.view.bounds.width,
                y: self.bubbleButton.center.y / self.view.bounds.height
            )
            self.normalizedBubblePosition = normalized
            self.onBubblePositionChanged?(normalized)
        }
    }

    private func layoutFloatingControls() {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        if !editStatus.isHidden { layoutEditStatus() }
        guard isMenuOpen else { return }
        let centers = actionButtonCenters()
        for (index, button) in actionButtons.enumerated() where !button.isHidden {
            button.center = centers[index]
        }
        layoutActionInfoViews()

    }

    private func layoutEditStatus() {
        let safe = view.safeAreaInsets
        let minimumX = safe.left + 16
        let availableWidth = max(0, view.bounds.width - safe.left - safe.right - 32)
        let width = min(320, availableWidth)
        editStatus.frame = CGRect(
            x: minimumX + max(0, (availableWidth - width) / 2),
            y: safe.top + 10,
            width: width,
            height: 62
        )
    }

    private func actionButtonCenters() -> [CGPoint] {
        let spacing: CGFloat = 58
        let safe = view.safeAreaInsets
        let requiredHeight = spacing * CGFloat(actionButtons.count)
        let availableBelow = view.bounds.height - safe.bottom - bubbleButton.frame.maxY
        let direction: CGFloat = availableBelow >= requiredHeight + 8 ? 1 : -1
        return actionButtons.indices.map { index in
            CGPoint(x: bubbleButton.center.x, y: bubbleButton.center.y + direction * spacing * CGFloat(index + 1))
        }
    }

    private func layoutActionInfoViews() {
        let labelsOnRight = bubbleButton.center.x < view.bounds.midX
        for button in actionButtons {
            guard let label = actionInfoViews[button] else { continue }
            let fitting = label.sizeThatFits(CGSize(width: 210, height: 36))
            let width = min(210, max(86, fitting.width + 24))
            let x = labelsOnRight ? button.frame.maxX + 9 : button.frame.minX - width - 9
            label.frame = CGRect(x: x, y: button.center.y - 18, width: width, height: 36)
        }
    }

    private func setActionInfoVisible(_ visible: Bool, animated: Bool) {
        guard visible != isShowingActionInfo else { return }
        isShowingActionInfo = visible
        infoHideWorkItem?.cancel()
        helpButton.configuration?.image = PPTheme.symbol(visible ? "xmark" : "questionmark", pointSize: 17, weight: .semibold)
        if visible {
            layoutActionInfoViews()
            for label in actionInfoViews.values {
                label.isHidden = false
                label.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            }
        }
        let changes = {
            for label in self.actionInfoViews.values {
                label.alpha = visible ? 1 : 0
                label.transform = .identity
            }
        }
        let completion: (Bool) -> Void = { _ in
            if !visible { self.actionInfoViews.values.forEach { $0.isHidden = true } }
        }
        if animated {
            UIView.animate(withDuration: 0.24, delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: changes, completion: completion)
        } else {
            changes()
            completion(true)
        }
        guard visible else { return }
        let workItem = DispatchWorkItem { [weak self] in self?.setActionInfoVisible(false, animated: true) }
        infoHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: workItem)
    }

    @objc private func captureTap(_ recognizer: UITapGestureRecognizer) {
        guard isPinEditing, recognizer.state == .ended else { return }
        onCapture?(recognizer.location(in: view))
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard isPinEditing, let touched = touch.view else { return false }
        return !isInteractiveControl(touched)
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: pointSize, weight: weight)
    }
}
