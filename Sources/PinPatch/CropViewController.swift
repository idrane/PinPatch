import UIKit

@MainActor
final class PPCropViewController: UIViewController {
    var onCancel: (() -> Void)?
    var onCrop: ((UIImage) -> Void)?

    private let image: UIImage
    private let initialFrame: CGRect?
    private let imageView = UIImageView()
    private let cropView = PPCropSelectionView()
    private var lastDisplayRect: CGRect = .zero

    init(image: UIImage, initialFrame: CGRect?) {
        self.image = image
        self.initialFrame = initialFrame
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Select Area"
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.onCancel?() })
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Next", style: .done, target: self, action: #selector(confirm))

        let instruction = PPToastView(symbol: "crop", title: "Adjust the area using the four corners")
        instruction.isUserInteractionEnabled = false
        instruction.isAccessibilityElement = false
        instruction.translatesAutoresizingMaskIntoConstraints = false

        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        cropView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        view.addSubview(cropView)
        view.addSubview(instruction)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            cropView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            cropView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            cropView.topAnchor.constraint(equalTo: imageView.topAnchor),
            cropView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            instruction.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            instruction.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            instruction.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            instruction.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let display = imageDisplayRect()
        guard !cropView.hasInitialRect else {
            if display != lastDisplayRect, display.width > 0, display.height > 0 {
                cropView.remap(from: lastDisplayRect, to: display)
                lastDisplayRect = display
            }
            return
        }
        lastDisplayRect = display
        var initial = display.insetBy(dx: display.width * 0.12, dy: display.height * 0.12)
        if let initialFrame, image.size.width > 0, image.size.height > 0 {
            let sx = display.width / image.size.width
            let sy = display.height / image.size.height
            initial = CGRect(
                x: display.minX + initialFrame.minX * sx,
                y: display.minY + initialFrame.minY * sy,
                width: initialFrame.width * sx,
                height: initialFrame.height * sy
            ).insetBy(dx: -12, dy: -12).intersection(display)
        }
        cropView.configure(imageRect: display, cropRect: initial)
    }

    @objc private func confirm() {
        let display = imageDisplayRect()
        let selected = cropView.cropRect.intersection(display)
        guard selected.width > 0, selected.height > 0, let cgImage = image.cgImage else { return }
        let pointToPixelX = CGFloat(cgImage.width) / image.size.width
        let pointToPixelY = CGFloat(cgImage.height) / image.size.height
        let imageRect = CGRect(
            x: (selected.minX - display.minX) / display.width * image.size.width,
            y: (selected.minY - display.minY) / display.height * image.size.height,
            width: selected.width / display.width * image.size.width,
            height: selected.height / display.height * image.size.height
        )
        let pixelRect = CGRect(
            x: imageRect.minX * pointToPixelX,
            y: imageRect.minY * pointToPixelY,
            width: imageRect.width * pointToPixelX,
            height: imageRect.height * pointToPixelY
        ).integral.intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard let cropped = cgImage.cropping(to: pixelRect) else { return }
        PPTheme.impactFeedback(.medium)
        onCrop?(UIImage(cgImage: cropped, scale: image.scale, orientation: .up))
    }

    private func imageDisplayRect() -> CGRect {
        guard image.size.width > 0, image.size.height > 0 else { return imageView.bounds }
        let scale = min(imageView.bounds.width / image.size.width, imageView.bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(
            x: imageView.bounds.midX - size.width / 2,
            y: imageView.bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

private final class PPCropSelectionView: UIView {
    enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

    private(set) var cropRect: CGRect = .zero
    private(set) var hasInitialRect = false
    private var imageRect: CGRect = .zero
    private var handles: [Corner: UIView] = [:]
    private let minimumSize: CGFloat = 44

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        for corner in Corner.allCases {
            let handle = UIView()
            handle.backgroundColor = .clear
            handle.isAccessibilityElement = true
            handle.accessibilityLabel = "Crop area corner"
            handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragHandle(_:))))
            let knob = UIView()
            knob.backgroundColor = .white
            knob.layer.borderColor = PPTheme.accent.cgColor
            knob.layer.borderWidth = 4
            knob.layer.cornerRadius = 9
            knob.isUserInteractionEnabled = false
            knob.translatesAutoresizingMaskIntoConstraints = false
            handle.addSubview(knob)
            NSLayoutConstraint.activate([
                knob.centerXAnchor.constraint(equalTo: handle.centerXAnchor),
                knob.centerYAnchor.constraint(equalTo: handle.centerYAnchor),
                knob.widthAnchor.constraint(equalToConstant: 18),
                knob.heightAnchor.constraint(equalToConstant: 18)
            ])
            addSubview(handle)
            handles[corner] = handle
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(imageRect: CGRect, cropRect: CGRect) {
        self.imageRect = imageRect
        self.cropRect = cropRect.width >= minimumSize && cropRect.height >= minimumSize ? cropRect : imageRect
        hasInitialRect = true
        setNeedsLayout()
        setNeedsDisplay()
    }

    func remap(from oldDisplay: CGRect, to newDisplay: CGRect) {
        guard oldDisplay.width > 0, oldDisplay.height > 0 else {
            configure(imageRect: newDisplay, cropRect: newDisplay)
            return
        }
        let scaled = CGRect(
            x: newDisplay.minX + (cropRect.minX - oldDisplay.minX) / oldDisplay.width * newDisplay.width,
            y: newDisplay.minY + (cropRect.minY - oldDisplay.minY) / oldDisplay.height * newDisplay.height,
            width: cropRect.width / oldDisplay.width * newDisplay.width,
            height: cropRect.height / oldDisplay.height * newDisplay.height
        )
        configure(imageRect: newDisplay, cropRect: scaled.intersection(newDisplay))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size: CGFloat = 44
        func place(_ corner: Corner, _ point: CGPoint) {
            handles[corner]?.frame = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        }
        place(.topLeft, CGPoint(x: cropRect.minX, y: cropRect.minY))
        place(.topRight, CGPoint(x: cropRect.maxX, y: cropRect.minY))
        place(.bottomLeft, CGPoint(x: cropRect.minX, y: cropRect.maxY))
        place(.bottomRight, CGPoint(x: cropRect.maxX, y: cropRect.maxY))
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(UIColor.black.withAlphaComponent(0.55).cgColor)
        context.fill(bounds)
        context.setBlendMode(.clear)
        context.fill(cropRect)
        context.setBlendMode(.normal)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(2.5)
        context.stroke(cropRect)
    }

    @objc private func dragHandle(_ recognizer: UIPanGestureRecognizer) {
        guard let handle = recognizer.view, let corner = handles.first(where: { $0.value === handle })?.key else { return }
        if recognizer.state == .began { PPTheme.impactFeedback(.soft) }
        let location = recognizer.location(in: self)
        let x = min(imageRect.maxX, max(imageRect.minX, location.x))
        let y = min(imageRect.maxY, max(imageRect.minY, location.y))
        var rect = cropRect
        switch corner {
        case .topLeft:
            rect.origin.x = min(x, cropRect.maxX - minimumSize)
            rect.origin.y = min(y, cropRect.maxY - minimumSize)
            rect.size.width = cropRect.maxX - rect.minX
            rect.size.height = cropRect.maxY - rect.minY
        case .topRight:
            let maxX = max(x, cropRect.minX + minimumSize)
            rect.origin.y = min(y, cropRect.maxY - minimumSize)
            rect.size.width = maxX - cropRect.minX
            rect.size.height = cropRect.maxY - rect.minY
        case .bottomLeft:
            rect.origin.x = min(x, cropRect.maxX - minimumSize)
            let maxY = max(y, cropRect.minY + minimumSize)
            rect.size.width = cropRect.maxX - rect.minX
            rect.size.height = maxY - cropRect.minY
        case .bottomRight:
            rect.size.width = max(x, cropRect.minX + minimumSize) - cropRect.minX
            rect.size.height = max(y, cropRect.minY + minimumSize) - cropRect.minY
        }
        cropRect = rect.intersection(imageRect)
        setNeedsLayout()
        setNeedsDisplay()
    }
}
