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
        title = "Current Screen Info"
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
        "Screen Identification"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Only the normalized screen name is used to find this screen again."
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
        case (0, 0): return ("Screen Name", fingerprint.rawTitle ?? "Untitled", "textformat")
        case (0, 1): return ("Screen ID", screenID?.uuidString.lowercased() ?? "Not saved yet", "number")
        default: return ("Fingerprint Version", "v\(fingerprint.fingerprintVersion)", "checkmark.seal")
        }
    }
}
