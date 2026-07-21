import UIKit

struct PPPinFlowOutput {
    let crop: UIImage
    let tag: PPTag?
    let note: String
}

@MainActor
final class PPPinFlowCoordinator {
    private weak var presentingWindow: UIWindow?
    private let image: UIImage
    private let initialFrame: CGRect?
    private let completion: (PPPinFlowOutput?) -> Void
    private weak var previousKeyWindow: UIWindow?
    private var navigationController: UINavigationController?
    private var crop: UIImage?

    init(presentingWindow: UIWindow, image: UIImage, initialFrame: CGRect?, completion: @escaping (PPPinFlowOutput?) -> Void) {
        self.presentingWindow = presentingWindow
        self.image = image
        self.initialFrame = initialFrame
        self.completion = completion
    }

    func start() {
        guard let window = presentingWindow, let presenter = window.rootViewController else { return }
        previousKeyWindow = window.windowScene?.windows.first(where: { $0.isKeyWindow && $0 !== window })
        let cropController = PPCropViewController(image: image, initialFrame: initialFrame)
        cropController.onCancel = { [weak self] in self?.finish(nil) }
        cropController.onCrop = { [weak self] image in self?.showNote(for: image) }
        let navigation = UINavigationController(rootViewController: cropController)
        navigation.modalPresentationStyle = .fullScreen
        navigationController = navigation
        window.makeKey()
        presenter.present(navigation, animated: true)
    }

    private func showNote(for image: UIImage) {
        crop = image
        let note = PPNoteViewController()
        note.onCancel = { [weak self] in self?.finish(nil) }
        note.onSave = { [weak self] tag, text in
            guard let self, let crop = self.crop else { return }
            self.finish(PPPinFlowOutput(crop: crop, tag: tag, note: text))
        }
        navigationController?.pushViewController(note, animated: true)
    }

    private func finish(_ output: PPPinFlowOutput?) {
        navigationController?.dismiss(animated: true) { [weak self] in
            guard let self else { return }
            self.previousKeyWindow?.makeKey()
            self.navigationController = nil
            self.completion(output)
        }
    }
}

@MainActor
final class PPNoteViewController: UIViewController, UITextViewDelegate {
    var onCancel: (() -> Void)?
    var onSave: ((PPTag?, String) -> Void)?

    private let textView = UITextView()
    private let tagButton = UIButton(type: .system)
    private var selectedTag: PPTag?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "수정 메모"
        navigationItem.hidesBackButton = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.onCancel?() })
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "저장", style: .done, target: self, action: #selector(save))
        navigationItem.rightBarButtonItem?.isEnabled = false

        tagButton.configuration = .bordered()
        tagButton.configuration?.title = "태그 선택(선택 사항)"
        tagButton.menu = UIMenu(children: PPTag.allCases.map { tag in
            UIAction(title: tag.localizedTitle) { [weak self] _ in
                self?.selectedTag = tag
                self?.tagButton.configuration?.title = tag.localizedTitle
            }
        })
        tagButton.showsMenuAsPrimaryAction = true
        tagButton.translatesAutoresizingMaskIntoConstraints = false

        textView.font = .preferredFont(forTextStyle: .body)
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.layer.borderWidth = 1
        textView.layer.cornerRadius = 10
        textView.delegate = self
        textView.accessibilityLabel = "바꾸고 싶은 내용"
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tagButton)
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            tagButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            tagButton.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),
            tagButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            textView.topAnchor.constraint(equalTo: tagButton.bottomAnchor, constant: 16),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
        textView.becomeFirstResponder()
    }

    func textViewDidChange(_ textView: UITextView) {
        navigationItem.rightBarButtonItem?.isEnabled = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc private func save() {
        let value = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onSave?(selectedTag, value)
    }
}
