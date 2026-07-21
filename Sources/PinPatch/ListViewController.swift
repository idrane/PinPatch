import ImageIO
import UIKit

@MainActor
final class PPListViewController: UITableViewController {
    var onChanged: (() -> Void)?
    var onClose: (() -> Void)?

    private var screens: [PPScreenRecord] = []
    private var pinsByScreen: [[PPPinSummary]] = []
    private lazy var linkButton = UIBarButtonItem(image: PPTheme.symbol("link"), style: .plain, target: self, action: #selector(toggleLinkMode))
    private lazy var exportButton = UIBarButtonItem(image: PPTheme.symbol("square.and.arrow.up"), style: .plain, target: self, action: #selector(showExportMenu))
    private lazy var linkSelectedButton = UIBarButtonItem(title: "핀 연결", style: .done, target: self, action: #selector(linkSelected))
    private lazy var selectionLabel = UIBarButtonItem(title: "2개 이상 선택", style: .plain, target: nil, action: nil)
    private lazy var deleteAllButton = UIBarButtonItem(image: PPTheme.symbol("trash"), style: .plain, target: self, action: #selector(confirmDeleteAll))

    init() {
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "핀 목록"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        view.backgroundColor = .systemGroupedBackground
        tableView.backgroundColor = .systemGroupedBackground
        tableView.separatorStyle = .none
        tableView.sectionHeaderTopPadding = 12
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.register(PPPinCell.self, forCellReuseIdentifier: PPPinCell.reuseIdentifier)

        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.onClose?() })
        navigationItem.rightBarButtonItems = [exportButton, linkButton]
        updateToolbar()
        navigationController?.isToolbarHidden = false
        reload()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { screens.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        pinsByScreen[section].count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let title = screens[section].fingerprint.rawTitle ?? "제목 없음"
        return "화면 \(section + 1)  ·  \(title)"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        let count = pinsByScreen[section].count
        return "\(count)개의 핀"
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 104 }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: PPPinCell.reuseIdentifier, for: indexPath) as? PPPinCell else {
            return UITableViewCell()
        }
        let pin = pinsByScreen[indexPath.section][indexPath.row]
        cell.configure(pin: pin, displayNumber: "\(indexPath.section + 1)-\(indexPath.row + 1)")
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            updateToolbar()
            PPTheme.selectionFeedback()
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        editPin(at: indexPath)
    }

    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard tableView.isEditing else { return }
        updateToolbar()
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let action = UIContextualAction(style: .destructive, title: "삭제") { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            let id = self.pinsByScreen[indexPath.section][indexPath.row].record.pinID
            Task {
                do {
                    try await PPStorage.shared.deletePin(id)
                    await MainActor.run {
                        PPTheme.successFeedback()
                        self.reload()
                        self.onChanged?()
                        completion(true)
                    }
                } catch {
                    await MainActor.run { self.showToast(symbol: "exclamationmark.triangle.fill", title: "삭제하지 못했어요"); completion(false) }
                }
            }
        }
        action.image = PPTheme.symbol("trash.fill")
        return UISwipeActionsConfiguration(actions: [action])
    }

    private func reload() {
        Task {
            let loadedScreens = (try? await PPStorage.shared.loadScreenRecords()) ?? []
            let loadedPins = (try? await PPStorage.shared.loadPinSummaries()) ?? []
            let activeScreens = loadedScreens.filter { screen in loadedPins.contains(where: { $0.record.screenID == screen.screenID }) }
            await MainActor.run {
                self.screens = activeScreens
                self.pinsByScreen = activeScreens.map { screen in loadedPins.filter { $0.record.screenID == screen.screenID } }
                self.tableView.reloadData()
                self.updateEmptyState(pinCount: loadedPins.count)
                self.updateToolbar()
            }
        }
    }

    private func updateEmptyState(pinCount: Int) {
        guard pinCount == 0 else {
            contentUnavailableConfiguration = nil
            return
        }
        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = PPTheme.symbol("pin.slash", pointSize: 30)
        configuration.imageProperties.tintColor = PPTheme.accent
        configuration.text = "아직 남긴 핀이 없어요"
        configuration.secondaryText = "목록을 닫고 핀 추가 모드에서\n고치고 싶은 곳을 탭해보세요."
        contentUnavailableConfiguration = configuration
    }

    private func editPin(at indexPath: IndexPath) {
        let pin = pinsByScreen[indexPath.section][indexPath.row]
        let controller = PPNoteViewController(
            previewImage: UIImage(contentsOfFile: pin.cropURL.path),
            initialTag: pin.record.tag,
            initialText: pin.note,
            title: "메모 수정",
            saveTitle: "변경사항 저장"
        )
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        controller.onCancel = { [weak navigation] in navigation?.dismiss(animated: true) }
        controller.onSave = { [weak self, weak navigation] tag, value in
            Task {
                do {
                    try await PPStorage.shared.updateNote(pinID: pin.record.pinID, note: value, tag: tag)
                    await MainActor.run {
                        navigation?.dismiss(animated: true)
                        self?.reload()
                        self?.onChanged?()
                    }
                } catch {
                    await MainActor.run { self?.showToast(symbol: "exclamationmark.triangle.fill", title: "메모를 저장하지 못했어요") }
                }
            }
        }
        present(navigation, animated: true)
    }

    @objc private func toggleLinkMode() {
        let entering = !tableView.isEditing
        tableView.setEditing(entering, animated: true)
        navigationItem.leftBarButtonItem?.isEnabled = !entering
        exportButton.isEnabled = !entering
        linkButton.image = PPTheme.symbol(entering ? "xmark" : "link")
        linkButton.accessibilityLabel = entering ? "선택 취소" : "핀 연결"
        updateToolbar()
        if entering {
            showToast(symbol: "checkmark.circle", title: "연결할 핀을 선택하세요", detail: "서로 다른 화면의 핀도 선택할 수 있어요")
        }
    }

    private func updateToolbar() {
        let selectedCount = tableView.indexPathsForSelectedRows?.count ?? 0
        if tableView.isEditing {
            selectionLabel.title = selectedCount == 0 ? "2개 이상 선택" : "\(selectedCount)개 선택"
            selectionLabel.isEnabled = false
            linkSelectedButton.isEnabled = selectedCount >= 2
            toolbarItems = [selectionLabel, .flexibleSpace(), linkSelectedButton]
        } else {
            let count = pinsByScreen.reduce(0) { $0 + $1.count }
            let summary = UIBarButtonItem(title: count == 0 ? "저장된 핀 없음" : "총 \(count)개의 핀", style: .plain, target: nil, action: nil)
            summary.isEnabled = false
            deleteAllButton.isEnabled = count > 0
            toolbarItems = [summary, .flexibleSpace(), deleteAllButton]
        }
    }

    @objc private func linkSelected() {
        let selected = tableView.indexPathsForSelectedRows ?? []
        let ids = selected.map { pinsByScreen[$0.section][$0.row].record.pinID }
        guard ids.count >= 2 else { return }
        let controller = PPGroupInstructionViewController(pinCount: ids.count)
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        controller.onCancel = { [weak navigation] in navigation?.dismiss(animated: true) }
        controller.onSave = { [weak self, weak navigation] instruction in
            Task {
                do {
                    _ = try await PPStorage.shared.createGroup(pinIDs: ids, instruction: instruction)
                    await MainActor.run {
                        navigation?.dismiss(animated: true)
                        self?.tableView.setEditing(false, animated: true)
                        self?.navigationItem.leftBarButtonItem?.isEnabled = true
                        self?.exportButton.isEnabled = true
                        self?.linkButton.image = PPTheme.symbol("link")
                        self?.updateToolbar()
                        self?.showToast(symbol: "link.circle.fill", title: "\(ids.count)개 핀을 연결했어요")
                        PPTheme.successFeedback()
                    }
                } catch {
                    await MainActor.run { self?.showToast(symbol: "exclamationmark.triangle.fill", title: "핀을 연결하지 못했어요") }
                }
            }
        }
        present(navigation, animated: true)
    }

    @objc private func showExportMenu() {
        let sheet = UIAlertController(title: "내보내기", message: "AI 에이전트나 팀에 전달할 형식을 선택하세요.", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Markdown 복사", style: .default) { [weak self] _ in
            Task {
                guard let value = try? await PPExportService.shared.markdown() else {
                    await MainActor.run { self?.showToast(symbol: "exclamationmark.triangle.fill", title: "복사하지 못했어요") }
                    return
                }
                await MainActor.run {
                    UIPasteboard.general.string = value
                    self?.showToast(symbol: "doc.on.doc.fill", title: "Markdown을 복사했어요")
                    PPTheme.successFeedback()
                }
            }
        })
        sheet.addAction(UIAlertAction(title: "Markdown 파일 공유", style: .default) { [weak self] _ in self?.share(kind: .markdown) })
        sheet.addAction(UIAlertAction(title: "스크린샷 포함 ZIP 공유", style: .default) { [weak self] _ in self?.share(kind: .zip) })
        sheet.addAction(UIAlertAction(title: "취소", style: .cancel))
        if let popover = sheet.popoverPresentationController { popover.barButtonItem = exportButton }
        present(sheet, animated: true)
    }

    private enum ShareKind { case markdown, zip }

    private func share(kind: ShareKind) {
        Task {
            let artifact: PPExportArtifact?
            switch kind {
            case .markdown: artifact = try? await PPExportService.shared.markdownFile()
            case .zip: artifact = try? await PPExportService.shared.zip()
            }
            guard let artifact else {
                await MainActor.run { self.showToast(symbol: "exclamationmark.triangle.fill", title: "파일을 만들지 못했어요") }
                return
            }
            await MainActor.run {
                let activity = UIActivityViewController(activityItems: [artifact.url], applicationActivities: nil)
                activity.completionWithItemsHandler = { _, _, _, _ in Task { await PPExportService.shared.cleanup(artifact) } }
                if let popover = activity.popoverPresentationController {
                    popover.sourceView = self.view
                    popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.maxY - 20, width: 1, height: 1)
                }
                self.present(activity, animated: true)
            }
        }
    }

    @objc private func confirmDeleteAll() {
        let alert = UIAlertController(title: "모든 핀을 삭제할까요?", message: "핀, 메모, 링크와 처리 결과가 모두 삭제되며 되돌릴 수 없습니다.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "모두 삭제", style: .destructive) { [weak self] _ in
            Task {
                do {
                    try await PPStorage.shared.deleteAll()
                    await MainActor.run {
                        self?.reload()
                        self?.onChanged?()
                        self?.showToast(symbol: "trash.fill", title: "모든 핀을 삭제했어요")
                    }
                } catch {
                    await MainActor.run { self?.showToast(symbol: "exclamationmark.triangle.fill", title: "삭제하지 못했어요") }
                }
            }
        })
        present(alert, animated: true)
    }

    private func showToast(symbol: String, title: String, detail: String? = nil) {
        let toast = PPToastView(symbol: symbol, title: title, detail: detail)
        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.alpha = 0
        toast.transform = CGAffineTransform(translationX: 0, y: -8)
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            toast.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
        UIView.animate(withDuration: 0.25) {
            toast.alpha = 1
            toast.transform = .identity
        } completion: { _ in
            UIView.animate(withDuration: 0.22, delay: 1.8, options: []) { toast.alpha = 0 } completion: { _ in toast.removeFromSuperview() }
        }
    }
}

@MainActor
private final class PPPinCell: UITableViewCell {
    static let reuseIdentifier = "PinPatch.PinCell"

    private let thumbnailView = UIImageView()
    private let numberLabel = UILabel()
    private let tagLabel = UILabel()
    private let noteLabel = UILabel()
    private let statusView = UIImageView()
    private var representedPinID: UUID?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        selectionStyle = .default

        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.backgroundColor = .tertiarySystemFill
        thumbnailView.layer.cornerRadius = 12
        thumbnailView.layer.cornerCurve = .continuous
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false

        numberLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        numberLabel.textColor = .secondaryLabel
        tagLabel.font = .preferredFont(forTextStyle: .caption1).withWeight(.semibold)
        noteLabel.font = .preferredFont(forTextStyle: .subheadline)
        noteLabel.textColor = .label
        noteLabel.numberOfLines = 2
        statusView.contentMode = .scaleAspectFit
        statusView.translatesAutoresizingMaskIntoConstraints = false

        let metadata = UIStackView(arrangedSubviews: [numberLabel, tagLabel])
        metadata.axis = .horizontal
        metadata.spacing = 8
        metadata.alignment = .firstBaseline
        let labels = UIStackView(arrangedSubviews: [metadata, noteLabel])
        labels.axis = .vertical
        labels.spacing = 7
        labels.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(thumbnailView)
        contentView.addSubview(labels)
        contentView.addSubview(statusView)
        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            thumbnailView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 76),
            thumbnailView.heightAnchor.constraint(equalToConstant: 76),
            labels.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 13),
            labels.trailingAnchor.constraint(equalTo: statusView.leadingAnchor, constant: -10),
            labels.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            statusView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            statusView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            statusView.widthAnchor.constraint(equalToConstant: 22),
            statusView.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedPinID = nil
        thumbnailView.image = PPTheme.symbol("photo", pointSize: 22)
        thumbnailView.tintColor = .tertiaryLabel
    }

    func configure(pin: PPPinSummary, displayNumber: String) {
        representedPinID = pin.record.pinID
        numberLabel.text = displayNumber
        let tag = pin.record.tag
        tagLabel.text = tag?.localizedTitle ?? "메모"
        tagLabel.textColor = tag?.tintColor ?? PPTheme.accent
        noteLabel.text = pin.note
        thumbnailView.image = PPTheme.symbol("photo", pointSize: 22)
        thumbnailView.tintColor = .tertiaryLabel

        if pin.result == nil {
            statusView.image = PPTheme.symbol("chevron.right", pointSize: 14)
            statusView.tintColor = .tertiaryLabel
            accessibilityValue = "미처리"
        } else {
            statusView.image = PPTheme.symbol("checkmark.circle.fill", pointSize: 19)
            statusView.tintColor = .systemGreen
            accessibilityValue = "처리 완료"
        }
        accessibilityLabel = "핀 \(displayNumber), \(tag?.localizedTitle ?? "메모"), \(pin.note)"

        let id = pin.record.pinID
        let url = pin.cropURL
        Task { [weak self] in
            let image = await PPThumbnailLoader.shared.image(at: url)
            guard let self, self.representedPinID == id, let image else { return }
            self.thumbnailView.image = image
        }
    }
}

private actor PPThumbnailLoader {
    static let shared = PPThumbnailLoader()
    private let cache = NSCache<NSURL, UIImage>()

    func image(at url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let image = await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as UIImage? }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 240,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: cgImage)
        }.value
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}

@MainActor
private final class PPGroupInstructionViewController: UIViewController, UITextViewDelegate {
    var onCancel: (() -> Void)?
    var onSave: ((String) -> Void)?

    private let pinCount: Int
    private let textView = UITextView()
    private let placeholder = UILabel()
    private let saveButton = UIButton(type: .system)

    init(pinCount: Int) {
        self.pinCount = pinCount
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        title = "공통 지시"
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.onCancel?() })

        let icon = UIImageView(image: PPTheme.symbol("link.circle.fill", pointSize: 34))
        icon.tintColor = PPTheme.accent
        let titleLabel = UILabel()
        titleLabel.text = "\(pinCount)개 핀을 한 요청으로 연결"
        titleLabel.font = .preferredFont(forTextStyle: .title3).withWeight(.bold)
        titleLabel.numberOfLines = 0
        let detail = UILabel()
        detail.text = "모든 핀에 함께 적용할 내용을 적어주세요."
        detail.font = .preferredFont(forTextStyle: .subheadline)
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 0

        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = PPTheme.cardCornerRadius
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholder.text = "예: 선택한 버튼들을 모두 같은 색과 높이로 맞춰줘"
        placeholder.font = .preferredFont(forTextStyle: .body)
        placeholder.textColor = .placeholderText
        placeholder.numberOfLines = 0
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(textView)
        card.addSubview(placeholder)

        var config = UIButton.Configuration.filled()
        config.title = "핀 연결하기"
        config.image = PPTheme.symbol("link", pointSize: 15, weight: .bold)
        config.imagePadding = 8
        config.baseBackgroundColor = PPTheme.accent
        config.cornerStyle = .large
        saveButton.configuration = config
        saveButton.isEnabled = false
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [icon, titleLabel, detail, card, saveButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(20, after: detail)
        stack.setCustomSpacing(18, after: card)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            card.heightAnchor.constraint(equalToConstant: 130),
            textView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            textView.topAnchor.constraint(equalTo: card.topAnchor, constant: 4),
            textView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -4),
            placeholder.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 5),
            placeholder.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -5),
            placeholder.topAnchor.constraint(equalTo: textView.topAnchor, constant: 8),
            saveButton.heightAnchor.constraint(equalToConstant: 52)
        ])
        DispatchQueue.main.async { [weak self] in self?.textView.becomeFirstResponder() }
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholder.isHidden = !textView.text.isEmpty
        saveButton.isEnabled = !textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @objc private func save() {
        let value = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        onSave?(value)
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: pointSize, weight: weight)
    }
}
