import UIKit
import HyroxKit

enum AddStationMode {
    case create
    case edit(existing: WorkoutSegment, index: Int)
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
        var title: String {
            switch self {
            case .distance: return "Distance"
            case .reps: return "Reps"
            case .duration: return "Duration"
            case .none: return "None"
            }
        }
    }

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var kindButtons: [UIButton] = []
    private let targetSegmented = UISegmentedControl()
    private let targetField = UITextField()
    private let weightSwitch = UISwitch()
    private let weightField = UITextField()
    private let weightNoteField = UITextField()
    private let saveButton = UIButton(type: .system)

    init(mode: AddStationMode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
        if case .edit(let seg, _) = mode {
            selectedKind = seg.stationKind ?? .skiErg
            if let target = seg.stationTarget {
                switch target {
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
        view.backgroundColor = .systemBackground
        title = mode.isEdit ? "Edit Station" : "Add Station"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)
        )
        setupUI()
        populateFromState()
    }

    @objc private func cancelTapped() {
        delegate?.cancelAddStation()
    }

    // MARK: - Setup

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
        stackView.spacing = DesignTokens.Spacing.m
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: DesignTokens.Spacing.m),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.Spacing.m),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.Spacing.m),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -DesignTokens.Spacing.m)
        ])

        // Station Kind
        stackView.addArrangedSubview(makeLabel("Station Type"))
        let kindStack = UIStackView()
        kindStack.axis = .vertical
        kindStack.spacing = DesignTokens.Spacing.xs
        for kind in stationKinds {
            let btn = UIButton(type: .system)
            btn.setTitle(kind.displayName, for: .normal)
            btn.contentHorizontalAlignment = .leading
            btn.tag = stationKinds.firstIndex(of: kind) ?? 0
            btn.addTarget(self, action: #selector(kindSelected(_:)), for: .touchUpInside)
            kindButtons.append(btn)
            kindStack.addArrangedSubview(btn)
        }
        stackView.addArrangedSubview(kindStack)

        // Target
        stackView.addArrangedSubview(makeLabel("Target"))
        for (i, t) in TargetType.allCases.enumerated() {
            targetSegmented.insertSegment(withTitle: t.title, at: i, animated: false)
        }
        targetSegmented.selectedSegmentIndex = targetType.rawValue
        targetSegmented.addTarget(self, action: #selector(targetTypeChanged), for: .valueChanged)
        stackView.addArrangedSubview(targetSegmented)

        targetField.borderStyle = .roundedRect
        targetField.keyboardType = .decimalPad
        targetField.placeholder = "Value"
        stackView.addArrangedSubview(targetField)

        // Weight
        stackView.addArrangedSubview(makeLabel("Weight"))
        let weightRow = UIStackView(arrangedSubviews: [UILabel(), weightSwitch])
        (weightRow.arrangedSubviews[0] as? UILabel)?.text = "Add Weight"
        weightRow.spacing = DesignTokens.Spacing.s
        weightSwitch.addTarget(self, action: #selector(weightToggled), for: .valueChanged)
        stackView.addArrangedSubview(weightRow)

        weightField.borderStyle = .roundedRect
        weightField.keyboardType = .decimalPad
        weightField.placeholder = "kg"
        weightField.isHidden = true
        stackView.addArrangedSubview(weightField)

        weightNoteField.borderStyle = .roundedRect
        weightNoteField.placeholder = "Note (e.g., per hand)"
        weightNoteField.isHidden = true
        stackView.addArrangedSubview(weightNoteField)

        // Save
        saveButton.setTitle(mode.isEdit ? "Save Changes" : "Add to Workout", for: .normal)
        saveButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        stackView.addArrangedSubview(saveButton)
    }

    private func makeLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .preferredFont(forTextStyle: .headline)
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
            btn.configuration = nil
            if kind == selectedKind {
                btn.setTitleColor(.systemBackground, for: .normal)
                btn.backgroundColor = .label
                btn.layer.cornerRadius = 8
            } else {
                btn.setTitleColor(.label, for: .normal)
                btn.backgroundColor = .clear
            }
        }
    }

    // MARK: - Actions

    @objc private func kindSelected(_ sender: UIButton) {
        selectedKind = stationKinds[sender.tag]
        let defaultTarget = selectedKind.defaultTarget
        switch defaultTarget {
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

        var wKg: Double?
        var wNote: String?
        if weightSwitch.isOn {
            wKg = Double(weightField.text ?? "")
            wNote = weightNoteField.text?.isEmpty == true ? nil : weightNoteField.text
        }

        let segment = WorkoutSegment.station(selectedKind, target: target, weightKg: wKg, weightNote: wNote)
        delegate?.addStation(segment, mode: mode)
    }
}

extension AddStationMode {
    var isEdit: Bool {
        if case .edit = self { return true }
        return false
    }
}
