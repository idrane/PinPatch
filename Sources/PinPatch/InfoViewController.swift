import UIKit

@MainActor
final class PPInfoViewController: UITableViewController {
    var onClose: (() -> Void)?

    private let fingerprint: PPScreenFingerprint
    private let sceneSessionID: String
    private var screenID: UUID?

    init(fingerprint: PPScreenFingerprint, sceneSessionID: String) {
        self.fingerprint = fingerprint
        self.sceneSessionID = sceneSessionID
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

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 3
        case 1: return fingerprint.framework == .swiftUI ? 4 : 2
        default: return 2
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "화면"
        case 1: return "식별 지문"
        default: return "동작 범위"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 2 else { return nil }
        return "이 정보는 기기 안에만 머물며 앱이 화면을 다시 찾을 때 사용됩니다."
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
        case (0, 0): return ("화면 종류", fingerprint.framework == .swiftUI ? "SwiftUI" : "UIKit", "square.stack.3d.up")
        case (0, 1): return ("화면 이름", fingerprint.rawTitle ?? "제목 없음", "textformat")
        case (0, 2): return ("표시 방식", fingerprint.isModal ? "모달" : "일반 화면", "rectangle.on.rectangle")
        case (1, 0): return ("내부 화면", fingerprint.screenKind, "curlybraces")
        case (1, 1): return ("Screen ID", screenID?.uuidString.lowercased() ?? "아직 저장되지 않음", "number")
        case (1, 2): return ("SwiftUI Root", fingerprint.swiftUIRootType ?? "확인되지 않음", "swift")
        case (1, 3): return ("의미 구조", fingerprint.swiftUISemanticDigest.map { String($0.prefix(12)) } ?? "확인되지 않음", "point.3.connected.trianglepath.dotted")
        case (2, 0): return ("현재 창", String(sceneSessionID.prefix(12)), "macwindow")
        default: return ("지문 버전", "v\(fingerprint.fingerprintVersion)", "checkmark.seal")
        }
    }
}
