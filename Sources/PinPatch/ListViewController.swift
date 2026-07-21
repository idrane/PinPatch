import UIKit

@MainActor
final class PPListViewController: UITableViewController {
    var onChanged: (() -> Void)?
    var onClose: (() -> Void)?

    private var screens: [PPScreenRecord] = []
    private var pinsByScreen: [[PPPinSummary]] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "PinPatch 목록"
        tableView.allowsMultipleSelectionDuringEditing = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.onClose?() })
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "링크", style: .plain, target: self, action: #selector(toggleLinkMode)),
            UIBarButtonItem(title: "내보내기", style: .plain, target: self, action: #selector(showExportMenu))
        ]
        toolbarItems = [
            UIBarButtonItem(title: "선택 핀 링크", style: .done, target: self, action: #selector(linkSelected)),
            .flexibleSpace(),
            UIBarButtonItem(title: "전체 삭제", style: .plain, target: self, action: #selector(confirmDeleteAll))
        ]
        navigationController?.isToolbarHidden = false
        reload()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { screens.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { pinsByScreen[section].count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let title = screens[section].fingerprint.rawTitle ?? screens[section].fingerprint.screenKind
        return "화면 \(section + 1) · \(title)"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "Pin"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        let pin = pinsByScreen[indexPath.section][indexPath.row]
        cell.textLabel?.text = "\(indexPath.section + 1)-\(indexPath.row + 1)  \(pin.record.tag?.localizedTitle ?? "메모")"
        cell.detailTextLabel?.text = pin.note
        cell.detailTextLabel?.numberOfLines = 2
        cell.accessoryType = pin.result == nil ? .none : .checkmark
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !tableView.isEditing else { return }
        tableView.deselectRow(at: indexPath, animated: true)
        editPin(at: indexPath)
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        UISwipeActionsConfiguration(actions: [UIContextualAction(style: .destructive, title: "삭제") { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            let id = self.pinsByScreen[indexPath.section][indexPath.row].record.pinID
            Task {
                let success = (try? await PPStorage.shared.deletePin(id)) != nil
                await MainActor.run { self.reload(); self.onChanged?(); completion(success) }
            }
        }])
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
            }
        }
    }

    private func editPin(at indexPath: IndexPath) {
        let pin = pinsByScreen[indexPath.section][indexPath.row]
        let alert = UIAlertController(title: "메모 수정", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = pin.note }
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "저장", style: .default) { [weak self, weak alert] _ in
            guard let value = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
            Task {
                try? await PPStorage.shared.updateNote(pinID: pin.record.pinID, note: value, tag: pin.record.tag)
                await MainActor.run { self?.reload(); self?.onChanged?() }
            }
        })
        present(alert, animated: true)
    }

    @objc private func toggleLinkMode() {
        tableView.setEditing(!tableView.isEditing, animated: true)
    }

    @objc private func linkSelected() {
        let selected = tableView.indexPathsForSelectedRows ?? []
        let ids = selected.map { pinsByScreen[$0.section][$0.row].record.pinID }
        guard ids.count >= 2 else { return }
        let alert = UIAlertController(title: "공통 지시", message: "선택한 핀에 함께 적용할 내용을 입력하세요.", preferredStyle: .alert)
        alert.addTextField()
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "링크", style: .default) { [weak self, weak alert] _ in
            guard let instruction = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !instruction.isEmpty else { return }
            Task { _ = try? await PPStorage.shared.createGroup(pinIDs: ids, instruction: instruction) }
            self?.tableView.setEditing(false, animated: true)
        })
        present(alert, animated: true)
    }

    @objc private func showExportMenu() {
        let sheet = UIAlertController(title: "내보내기", message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Markdown 복사", style: .default) { _ in
            Task { if let value = try? await PPExportService.shared.markdown() { await MainActor.run { UIPasteboard.general.string = value } } }
        })
        sheet.addAction(UIAlertAction(title: "Markdown 파일 공유", style: .default) { [weak self] _ in self?.share(kind: .markdown) })
        sheet.addAction(UIAlertAction(title: "ZIP 공유", style: .default) { [weak self] _ in self?.share(kind: .zip) })
        sheet.addAction(UIAlertAction(title: "취소", style: .cancel))
        if let popover = sheet.popoverPresentationController { popover.barButtonItem = navigationItem.rightBarButtonItems?.last }
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
            guard let artifact else { return }
            await MainActor.run {
                let activity = UIActivityViewController(activityItems: [artifact.url], applicationActivities: nil)
                activity.completionWithItemsHandler = { _, _, _, _ in Task { await PPExportService.shared.cleanup(artifact) } }
                if let popover = activity.popoverPresentationController { popover.sourceView = self.view; popover.sourceRect = self.view.bounds }
                self.present(activity, animated: true)
            }
        }
    }

    @objc private func confirmDeleteAll() {
        let alert = UIAlertController(title: "모두 삭제할까요?", message: "핀, 메모, 링크와 결과가 모두 삭제됩니다.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "삭제", style: .destructive) { [weak self] _ in
            Task {
                try? await PPStorage.shared.deleteAll()
                await MainActor.run { self?.reload(); self?.onChanged?() }
            }
        })
        present(alert, animated: true)
    }
}
