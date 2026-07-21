import UIKit

struct PPPinFlowOutput {
    let crop: UIImage
    let tag: PPTag?
    let note: String
}

@MainActor
final class PPPinFlowCoordinator {
    private weak var presentingWindow: UIWindow?
    private weak var overlayController: PPOverlayViewController?
    private let image: UIImage
    private let initialFrame: CGRect?
    private let completion: (PPPinFlowOutput?) -> Void
    private var navigationController: UINavigationController?
    private var crop: UIImage?

    init(presentingWindow: UIWindow, image: UIImage, initialFrame: CGRect?, completion: @escaping (PPPinFlowOutput?) -> Void) {
        self.presentingWindow = presentingWindow
        self.image = image
        self.initialFrame = initialFrame
        self.completion = completion
    }

    func start() {
        guard let window = presentingWindow,
              let overlayController = window.rootViewController as? PPOverlayViewController else { return }
        self.overlayController = overlayController
        let cropController = PPCropViewController(image: image, initialFrame: initialFrame)
        cropController.onCancel = { [weak self] in self?.finish(nil) }
        cropController.onCrop = { [weak self] image in self?.showNote(for: image) }
        let navigation = UINavigationController(rootViewController: cropController)
        navigationController = navigation
        overlayController.embedToolContent(navigation)
    }

    private func showNote(for image: UIImage) {
        crop = image
        let note = PPNoteViewController(previewImage: image)
        note.onCancel = { [weak self] in self?.finish(nil) }
        note.onSave = { [weak self] tag, text in
            guard let self, let crop = self.crop else { return }
            self.finish(PPPinFlowOutput(crop: crop, tag: tag, note: text))
        }
        navigationController?.pushViewController(note, animated: true)
    }

    private func finish(_ output: PPPinFlowOutput?) {
        guard let overlayController else {
            navigationController = nil
            completion(output)
            return
        }
        overlayController.removeEmbeddedToolContent(animated: true) { [weak self] in
            guard let self else { return }
            self.navigationController = nil
            self.completion(output)
        }
    }
}

@MainActor
final class PPNoteViewController: UIViewController, UITextViewDelegate {
    var onCancel: (() -> Void)?
    var onSave: ((PPTag?, String) -> Void)?

    private let previewImage: UIImage?
    private let initialText: String
    private let screenTitle: String
    private let saveTitle: String
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let characterCountLabel = UILabel()
    private let saveButton = UIButton(type: .system)
    private var tagButtons: [PPTag: UIButton] = [:]
    private var selectedTag: PPTag? { didSet { updateTagSelection() } }

    init(
        previewImage: UIImage? = nil,
        initialTag: PPTag? = nil,
        initialText: String = "",
        title: String = "Create Request",
        saveTitle: String = "Save Pin"
    ) {
        self.previewImage = previewImage
        self.initialText = initialText
        self.screenTitle = title
        self.saveTitle = saveTitle
        self.selectedTag = initialTag
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        title = screenTitle
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.onCancel?() })
        navigationController?.navigationBar.prefersLargeTitles = false

        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 22
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        let header = makeHeader()
        contentStack.addArrangedSubview(header)
        if let previewImage {
            contentStack.addArrangedSubview(makePreview(image: previewImage))
        }
        contentStack.addArrangedSubview(makeTagSection())
        contentStack.addArrangedSubview(makeEditor())

        configureSaveButton()
        view.addSubview(saveButton)
        NSLayoutConstraint.activate([
            saveButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            saveButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            saveButton.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
            saveButton.heightAnchor.constraint(equalToConstant: 54),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -10),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        textView.text = initialText
        textView.delegate = self
        updateTextState()
        updateTagSelection()
        if initialText.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.textView.becomeFirstResponder() }
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        updateTextState()
    }

    @objc private func save() {
        let value = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        PPTheme.successFeedback()
        onSave?(selectedTag, value)
    }

    private func makeHeader() -> UIView {
        let eyebrow = UILabel()
        eyebrow.text = previewImage == nil ? "Edit Note" : "New Change Request"
        eyebrow.font = .preferredFont(forTextStyle: .caption1)
        eyebrow.textColor = PPTheme.accent

        let title = UILabel()
        title.text = "What would you like to change?"
        title.font = .preferredFont(forTextStyle: .title2).withWeight(.bold)
        title.textColor = .label
        title.numberOfLines = 0

        let detail = UILabel()
        detail.text = "Describe the desired result clearly so AI can understand it right away."
        detail.font = .preferredFont(forTextStyle: .subheadline)
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [eyebrow, title, detail])
        stack.axis = .vertical
        stack.spacing = 5
        return stack
    }

    private func makePreview(image: UIImage) -> UIView {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = PPTheme.cardCornerRadius
        imageView.layer.cornerCurve = .continuous
        imageView.layer.borderWidth = 1 / UIScreen.main.scale
        imageView.layer.borderColor = UIColor.separator.cgColor
        imageView.accessibilityLabel = "Selected screen area"
        imageView.heightAnchor.constraint(equalToConstant: 150).isActive = true
        return imageView
    }

    private func makeTagSection() -> UIView {
        let title = UILabel()
        title.text = "Request Type  ·  Optional"
        title.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        title.textColor = .label

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(row)
        for tag in PPTag.allCases {
            let button = UIButton(type: .system)
            button.tag = PPTag.allCases.firstIndex(of: tag) ?? 0
            button.addTarget(self, action: #selector(selectTag(_:)), for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: 40).isActive = true
            row.addArrangedSubview(button)
            tagButtons[tag] = button
        }
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 42)
        ])
        let section = UIStackView(arrangedSubviews: [title, scroll])
        section.axis = .vertical
        section.spacing = 10
        return section
    }

    private func makeEditor() -> UIView {
        let card = UIView()
        card.backgroundColor = .tertiarySystemBackground
        card.layer.cornerRadius = PPTheme.cardCornerRadius
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1 / UIScreen.main.scale
        card.layer.borderColor = UIColor.separator.cgColor

        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 34, right: 12)
        textView.accessibilityLabel = "Requested changes"
        textView.translatesAutoresizingMaskIntoConstraints = false

        placeholderLabel.text = "Example: Make this button a little larger and match the blue color of the card above."
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        characterCountLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        characterCountLabel.textColor = .tertiaryLabel
        characterCountLabel.textAlignment = .right
        characterCountLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(textView)
        card.addSubview(placeholderLabel)
        card.addSubview(characterCountLabel)
        NSLayoutConstraint.activate([
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 210),
            textView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            textView.topAnchor.constraint(equalTo: card.topAnchor),
            textView.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 17),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -17),
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 16),
            characterCountLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            characterCountLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12)
        ])
        return card
    }

    private func configureSaveButton() {
        var config = UIButton.Configuration.filled()
        config.title = saveTitle
        config.image = PPTheme.symbol("checkmark", pointSize: 16, weight: .bold)
        config.imagePlacement = .trailing
        config.imagePadding = 9
        config.baseBackgroundColor = PPTheme.accent
        config.cornerStyle = .large
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var value = attributes
            value.font = .preferredFont(forTextStyle: .headline)
            return value
        }
        saveButton.configuration = config
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)
        PPTheme.applyFloatingShadow(to: saveButton.layer)
    }

    @objc private func selectTag(_ sender: UIButton) {
        let tags = PPTag.allCases
        guard tags.indices.contains(sender.tag) else { return }
        let tag = tags[sender.tag]
        selectedTag = selectedTag == tag ? nil : tag
        PPTheme.selectionFeedback()
    }

    private func updateTagSelection() {
        for (tag, button) in tagButtons {
            let selected = tag == selectedTag
            var config = selected ? UIButton.Configuration.filled() : UIButton.Configuration.tinted()
            config.title = tag.localizedTitle
            config.image = PPTheme.symbol(tag.systemImageName, pointSize: 14)
            config.imagePadding = 6
            config.baseBackgroundColor = selected ? tag.tintColor : tag.tintColor.withAlphaComponent(0.13)
            config.baseForegroundColor = selected ? .white : tag.tintColor
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 13, bottom: 8, trailing: 13)
            button.configuration = config
            button.accessibilityValue = selected ? "Selected" : nil
        }
    }

    private func updateTextState() {
        let trimmed = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        placeholderLabel.isHidden = !textView.text.isEmpty
        characterCountLabel.text = "\(textView.text.count) characters"
        saveButton.isEnabled = !trimmed.isEmpty
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: pointSize, weight: weight)
    }
}
