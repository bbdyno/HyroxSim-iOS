//
//  AddStationSheetViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit
import HyroxCore

enum AddStationMode {
    case create
    case edit(existing: WorkoutSegment, index: Int)
    var isEdit: Bool { if case .edit = self { return true }; return false }
}

@MainActor
protocol AddStationSheetDelegate: AnyObject {
    func addStation(_ segment: WorkoutSegment, mode: AddStationMode)
    func cancelAddStation()
}

final class AddStationSheetViewController: UIViewController {

    weak var delegate: AddStationSheetDelegate?
    let mode: AddStationMode

    private let stationKinds: [StationKind] = [
        .skiErg, .sledPush, .sledPull, .burpeeBroadJumps,
        .rowing, .farmersCarry, .sandbagLunges, .wallBalls
    ]

    private var selectedKind: StationKind = .skiErg
    private var targetValue: Double = 1000
    private var targetType: TargetType = .distance
    private var weightKg: Double?
    private var weightNote: String?

    private enum TargetType: Int, CaseIterable {
        case distance, reps, duration, none
        var title: String { switch self { case .distance: "Distance"; case .reps: "Reps"; case .duration: "Duration"; case .none: "None" } }
    }

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var kindButtons: [UIButton] = []
    private let targetSegmented = UISegmentedControl()
    private let targetField = UITextField()
    private let weightSwitch = UISwitch()
    private let weightField = UITextField()
    private let weightNoteField = UITextField()

    init(mode: AddStationMode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
        if case .edit(let seg, _) = mode {
            selectedKind = seg.stationKind ?? .skiErg
            if let t = seg.stationTarget {
                switch t {
                case .distance(let m): targetType = .distance; targetValue = m
                case .reps(let c): targetType = .reps; targetValue = Double(c)
                case .duration(let s): targetType = .duration; targetValue = s
                case .none: targetType = .none
                }
            }
            weightKg = seg.weightKg
            weightNote = seg.weightNote
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Color.background
        title = mode.isEdit ? "Edit Station" : "Add Station"
        applyDarkNavBarAppearance()
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        setupUI()
        populateFromState()
    }

    @objc private func cancelTapped() { delegate?.cancelAddStation() }

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16)
        ])

        // Station Kind
        stackView.addArrangedSubview(makeSectionLabel("STATION TYPE"))
        let kindStack = UIStackView()
        kindStack.axis = .vertical
        kindStack.spacing = 4
        for kind in stationKinds {
            let btn = UIButton(type: .system)
            btn.setTitle("  \(kind.displayName)", for: .normal)
            btn.contentHorizontalAlignment = .leading
            btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            btn.layer.cornerRadius = 8
            btn.heightAnchor.constraint(equalToConstant: 36).isActive = true
            btn.tag = stationKinds.firstIndex(of: kind) ?? 0
            btn.addTarget(self, action: #selector(kindSelected(_:)), for: .touchUpInside)
            kindButtons.append(btn)
            kindStack.addArrangedSubview(btn)
        }
        stackView.addArrangedSubview(kindStack)

        // Target
        stackView.addArrangedSubview(makeSectionLabel("TARGET"))
        for (i, t) in TargetType.allCases.enumerated() { targetSegmented.insertSegment(withTitle: t.title, at: i, animated: false) }
        targetSegmented.selectedSegmentIndex = targetType.rawValue
        targetSegmented.addTarget(self, action: #selector(targetTypeChanged), for: .valueChanged)
        stackView.addArrangedSubview(targetSegmented)

        targetField.placeholder = "Value"
        targetField.keyboardType = .decimalPad
        targetField.font = DesignTokens.Font.mediumNumber
        targetField.textAlignment = .center
        targetField.applyDarkStyle()
        targetField.heightAnchor.constraint(equalToConstant: 44).isActive = true
        stackView.addArrangedSubview(targetField)

        // Weight
        stackView.addArrangedSubview(makeSectionLabel("WEIGHT"))
        let weightRow = UIStackView()
        let wLabel = UILabel()
        wLabel.text = "Add Weight"
        wLabel.font = .systemFont(ofSize: 14, weight: .medium)
        wLabel.textColor = .white
        weightRow.addArrangedSubview(wLabel)
        weightRow.addArrangedSubview(weightSwitch)
        weightSwitch.onTintColor = DesignTokens.Color.accent
        weightSwitch.addTarget(self, action: #selector(weightToggled), for: .valueChanged)
        stackView.addArrangedSubview(weightRow)

        weightField.placeholder = "kg"
        weightField.keyboardType = .decimalPad
        weightField.applyDarkStyle()
        weightField.heightAnchor.constraint(equalToConstant: 40).isActive = true
        weightField.isHidden = true
        stackView.addArrangedSubview(weightField)

        weightNoteField.placeholder = "Note (e.g., per hand)"
        weightNoteField.applyDarkStyle()
        weightNoteField.heightAnchor.constraint(equalToConstant: 40).isActive = true
        weightNoteField.isHidden = true
        stackView.addArrangedSubview(weightNoteField)

        // Save
        let saveBtn = UIButton(type: .system)
        saveBtn.setTitle(mode.isEdit ? "Save Changes" : "Add to Workout", for: .normal)
        saveBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        saveBtn.setTitleColor(.black, for: .normal)
        saveBtn.backgroundColor = DesignTokens.Color.accent
        saveBtn.layer.cornerRadius = 22
        saveBtn.heightAnchor.constraint(equalToConstant: 44).isActive = true
        saveBtn.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        stackView.addArrangedSubview(saveBtn)
    }

    private func makeSectionLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 12, weight: .bold)
        l.textColor = DesignTokens.Color.accent
        return l
    }

    private func populateFromState() {
        targetField.text = "\(Int(targetValue))"
        if let w = weightKg {
            weightSwitch.isOn = true
            weightField.isHidden = false
            weightField.text = "\(Int(w))"
            weightNoteField.isHidden = false
            weightNoteField.text = weightNote
        }
        updateKindSelection()
    }

    private func updateKindSelection() {
        for btn in kindButtons {
            let kind = stationKinds[btn.tag]
            if kind == selectedKind {
                btn.setTitleColor(.black, for: .normal)
                btn.backgroundColor = DesignTokens.Color.accent
            } else {
                btn.setTitleColor(.white, for: .normal)
                btn.backgroundColor = DesignTokens.Color.surface
            }
        }
    }

    @objc private func kindSelected(_ sender: UIButton) {
        selectedKind = stationKinds[sender.tag]
        let d = selectedKind.defaultTarget
        switch d {
        case .distance(let m): targetType = .distance; targetValue = m
        case .reps(let c): targetType = .reps; targetValue = Double(c)
        case .duration(let s): targetType = .duration; targetValue = s
        case .none: targetType = .none; targetValue = 0
        }
        targetSegmented.selectedSegmentIndex = targetType.rawValue
        targetField.text = targetType == .none ? "" : "\(Int(targetValue))"
        updateKindSelection()
    }

    @objc private func targetTypeChanged() {
        targetType = TargetType(rawValue: targetSegmented.selectedSegmentIndex) ?? .none
        targetField.isHidden = targetType == .none
    }

    @objc private func weightToggled() {
        weightField.isHidden = !weightSwitch.isOn
        weightNoteField.isHidden = !weightSwitch.isOn
    }

    @objc private func saveTapped() {
        let val = Double(targetField.text ?? "") ?? targetValue
        let target: StationTarget
        switch targetType {
        case .distance: target = .distance(meters: val)
        case .reps: target = .reps(count: Int(val))
        case .duration: target = .duration(seconds: val)
        case .none: target = .none
        }
        var wKg: Double?; var wNote: String?
        if weightSwitch.isOn {
            wKg = Double(weightField.text ?? "")
            wNote = weightNoteField.text?.isEmpty == true ? nil : weightNoteField.text
        }
        delegate?.addStation(.station(selectedKind, target: target, weightKg: wKg, weightNote: wNote), mode: mode)
    }
}
