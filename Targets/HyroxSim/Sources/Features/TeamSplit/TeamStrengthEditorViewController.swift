//
//  TeamStrengthEditorViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import HyroxCore
import UIKit

/// 스테이션마다 "누가 더 강한가" 를 고르는 화면. 고른 값으로 분담을 추천받는다.
final class TeamStrengthEditorViewController: UIViewController {

    /// 공식 스테이션 순서대로, 더 강한 팀원의 순번. 비슷하면 nil.
    private var strongerSlot: [Int?]
    private let memberNames: [String]
    private let onApply: ([Int?]) -> Void
    private var controls: [UISegmentedControl] = []

    init(memberNames: [String], strongerSlot: [Int?], onApply: @escaping ([Int?]) -> Void) {
        self.memberNames = memberNames
        let count = StationKind.standardOrder.count
        self.strongerSlot = (0..<count).map { strongerSlot.indices.contains($0) ? strongerSlot[$0] : nil }
        self.onApply = onApply
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = TeamSplitStrings.strategyTitle
        view.backgroundColor = DesignTokens.Color.background
        view.accessibilityIdentifier = "teamStrength.view"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)
        )

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let applyButton = UIButton(type: .system)
        applyButton.backgroundColor = DesignTokens.Color.accent
        applyButton.setTitleColor(.black, for: .normal)
        applyButton.setTitle(TeamSplitStrings.strategyApply, for: .normal)
        applyButton.titleLabel?.font = DesignTokens.Font.wide(15, weight: .heavy)
        applyButton.accessibilityIdentifier = "teamStrength.apply"
        applyButton.addTarget(self, action: #selector(applyTapped), for: .touchUpInside)
        applyButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scroll)
        view.addSubview(applyButton)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: applyButton.topAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -12),
            applyButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            applyButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            applyButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            applyButton.heightAnchor.constraint(equalToConstant: 54)
        ])

        let intro = UILabel()
        intro.font = .systemFont(ofSize: 13)
        intro.textColor = DesignTokens.Color.textSecondary
        intro.numberOfLines = 0
        intro.text = TeamSplitStrings.strategyIntro(isRelay: memberNames.count > 2)
        stack.addArrangedSubview(intro)
        stack.setCustomSpacing(14, after: intro)
        stack.addArrangedSubview(hairline())

        for (index, station) in StationKind.standardOrder.enumerated() {
            stack.addArrangedSubview(makeRow(index: index, station: station))
            stack.addArrangedSubview(hairline())
        }
    }

    private func hairline() -> UIView {
        let line = UIView()
        line.backgroundColor = DesignTokens.Color.hairline
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    /// 칸 0 은 "비슷함", 칸 n 은 n−1 번 팀원.
    private func makeRow(index: Int, station: StationKind) -> UIView {
        let name = UILabel()
        name.font = DesignTokens.Font.wide(13, weight: .bold)
        name.textColor = DesignTokens.Color.textPrimary
        name.text = station.courseLabel

        let control = UISegmentedControl(items: [TeamSplitStrings.strategyEven] + memberNames)
        control.selectedSegmentIndex = strongerSlot[index].map { $0 + 1 } ?? 0
        control.selectedSegmentTintColor = DesignTokens.Color.accent
        control.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        control.setTitleTextAttributes([.foregroundColor: DesignTokens.Color.textSecondary], for: .normal)
        control.apportionsSegmentWidthsByContent = false
        control.tag = index
        control.accessibilityIdentifier = "teamStrength.station.\(index)"
        control.addTarget(self, action: #selector(selectionChanged(_:)), for: .valueChanged)
        controls.append(control)

        let row = UIStackView(arrangedSubviews: [name, control])
        row.axis = .vertical
        row.spacing = 8
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 12, leading: 0, bottom: 12, trailing: 0)
        return row
    }

    @objc private func selectionChanged(_ sender: UISegmentedControl) {
        strongerSlot[sender.tag] = sender.selectedSegmentIndex == 0 ? nil : sender.selectedSegmentIndex - 1
    }

    @objc private func cancelTapped() { dismiss(animated: true) }

    @objc private func applyTapped() {
        let result = strongerSlot
        dismiss(animated: true) { [onApply] in onApply(result) }
    }
}
