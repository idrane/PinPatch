import UIKit

enum PPTheme {
    static let accent = UIColor.systemIndigo
    static let pin = UIColor.systemRed
    static let cardCornerRadius: CGFloat = 18

    static func symbol(_ name: String, pointSize: CGFloat = 16, weight: UIImage.SymbolWeight = .semibold) -> UIImage? {
        UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight))
    }

    static func applyFloatingShadow(to layer: CALayer) {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 7)
    }

    static func selectionFeedback() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func impactFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func successFeedback() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

extension PPTag {
    var systemImageName: String {
        switch self {
        case .bug: return "ladybug.fill"
        case .color: return "paintpalette.fill"
        case .size: return "arrow.up.left.and.arrow.down.right"
        case .spacing: return "arrow.left.and.right"
        case .text: return "textformat"
        case .behavior: return "hand.tap.fill"
        case .other: return "ellipsis"
        }
    }

    var tintColor: UIColor {
        switch self {
        case .bug: return .systemRed
        case .color: return .systemPurple
        case .size: return .systemBlue
        case .spacing: return .systemTeal
        case .text: return .systemOrange
        case .behavior: return .systemIndigo
        case .other: return .systemGray
        }
    }
}

final class PPToastView: UIVisualEffectView {
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    init(symbol: String, title: String, detail: String? = nil) {
        super.init(effect: UIBlurEffect(style: .systemMaterial))
        clipsToBounds = false
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.masksToBounds = true

        imageView.image = PPTheme.symbol(symbol, pointSize: 17)
        imageView.tintColor = PPTheme.accent
        imageView.setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .subheadline).bolded
        titleLabel.textColor = .label

        detailLabel.text = detail
        detailLabel.font = .preferredFont(forTextStyle: .caption1)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 2
        detailLabel.isHidden = detail == nil

        let labels = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        labels.axis = .vertical
        labels.spacing = 1
        let row = UIStackView(arrangedSubviews: [imageView, labels])
        row.alignment = .center
        row.spacing = 11
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -11),
            imageView.widthAnchor.constraint(equalToConstant: 24)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

private extension UIFont {
    var bolded: UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
