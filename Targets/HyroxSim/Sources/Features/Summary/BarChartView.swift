import UIKit

/// Simple horizontal bar chart view.
/// Each bar fills proportionally to the max value in the data set.
final class BarChartView: UIView {

    struct Bar: Hashable {
        let label: String
        let value: Double
        let display: String
    }

    var bars: [Bar] = [] { didSet { rebuildBars() } }
    var accentColor: UIColor = DesignTokens.Color.stationAccent

    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        stackView.axis = .vertical
        stackView.spacing = DesignTokens.Spacing.xs
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func rebuildBars() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let maxVal = bars.map(\.value).max() ?? 1

        for bar in bars {
            let row = UIStackView()
            row.spacing = DesignTokens.Spacing.s

            let nameLabel = UILabel()
            nameLabel.text = bar.label
            nameLabel.font = .preferredFont(forTextStyle: .caption1)
            nameLabel.textColor = .secondaryLabel
            nameLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true

            let barContainer = UIView()
            barContainer.backgroundColor = UIColor.systemFill
            barContainer.layer.cornerRadius = 4
            barContainer.clipsToBounds = true

            let fill = UIView()
            fill.backgroundColor = accentColor
            fill.layer.cornerRadius = 4
            fill.translatesAutoresizingMaskIntoConstraints = false
            barContainer.addSubview(fill)

            let ratio = maxVal > 0 ? bar.value / maxVal : 0
            NSLayoutConstraint.activate([
                fill.topAnchor.constraint(equalTo: barContainer.topAnchor),
                fill.bottomAnchor.constraint(equalTo: barContainer.bottomAnchor),
                fill.leadingAnchor.constraint(equalTo: barContainer.leadingAnchor),
                fill.widthAnchor.constraint(equalTo: barContainer.widthAnchor, multiplier: max(0.01, ratio))
            ])
            barContainer.heightAnchor.constraint(equalToConstant: 20).isActive = true

            let valueLabel = UILabel()
            valueLabel.text = bar.display
            valueLabel.font = DesignTokens.Font.smallNumber
            valueLabel.textColor = .label
            valueLabel.widthAnchor.constraint(equalToConstant: 60).isActive = true
            valueLabel.textAlignment = .right

            row.addArrangedSubview(nameLabel)
            row.addArrangedSubview(barContainer)
            row.addArrangedSubview(valueLabel)

            stackView.addArrangedSubview(row)
        }
    }
}
