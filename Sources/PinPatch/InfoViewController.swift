import UIKit

@MainActor
final class PPInfoViewController: UITableViewController {
    var onClose: (() -> Void)?

    private let fingerprint: PPScreenFingerprint
    private var screenID: UUID?

    init(fingerprint: PPScreenFingerprint) {
        self.fingerprint = fingerprint
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "현재 화면 정보"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.onClose?() })
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Info")
        Task {
            let record = try? await PPStorage.shared.findScreen(fingerprint)
            await MainActor.run {
                self.screenID = record?.screenID
                self.tableView.reloadData()
            }
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        3
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "화면 식별"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "정규화된 화면 이름만 같은 화면을 다시 찾는 데 사용됩니다."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.detailTextLabel?.numberOfLines = 2
        cell.detailTextLabel?.adjustsFontSizeToFitWidth = true
        let item = row(at: indexPath)
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.value
        cell.imageView?.image = PPTheme.symbol(item.symbol, pointSize: 15)
        cell.imageView?.tintColor = PPTheme.accent
        cell.accessibilityLabel = "\(item.title), \(item.value)"
        return cell
    }

    private func row(at indexPath: IndexPath) -> (title: String, value: String, symbol: String) {
        switch (indexPath.section, indexPath.row) {
        case (0, 0): return ("화면 이름", fingerprint.rawTitle ?? "제목 없음", "textformat")
        case (0, 1): return ("Screen ID", screenID?.uuidString.lowercased() ?? "아직 저장되지 않음", "number")
        default: return ("지문 버전", "v\(fingerprint.fingerprintVersion)", "checkmark.seal")
        }
    }
}
