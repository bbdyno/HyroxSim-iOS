//
//  RaceResultEditorViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import HyroxCore
import UIKit

/// 대회 기록 한 건을 입력·수정한다. 사진에서 읽은 값도 여기서 확인한 뒤에 저장된다.
final class RaceResultEditorViewController: UIViewController, UITextFieldDelegate {

    private let existing: RaceResult?
    private let source: RaceResult.Source
    private let onSave: (RaceResult) -> Void
    private let onDelete: ((RaceResult) -> Void)?
    private let onShowLevel: ((RaceResult) -> Void)?

    private var division: HyroxDivision
    private let nameField = UITextField()
    private let datePicker = UIDatePicker()
    private let divisionButton = UIButton(type: .system)
    private let totalField = UITextField()
    private let runTotalField = UITextField()
    private let roxzoneField = UITextField()
    private var stationFields: [StationKind: UITextField] = [:]
    private let runLaps: [Int]
    private let scroll = UIScrollView()
    private let stack = UIStackView()

    private typealias L = HyroxSimStrings.Localizable.RaceArchive

    /// - Parameters:
    ///   - existing: 수정할 기록. 새로 만들면 nil.
    ///   - parsed: 사진에서 읽은 값. 있으면 그 값으로 채우고 출처를 스캔으로 남긴다.
    init(
        existing: RaceResult?,
        parsed: ParsedRaceResult? = nil,
        defaultDivision: HyroxDivision,
        onSave: @escaping (RaceResult) -> Void,
        onDelete: ((RaceResult) -> Void)? = nil,
        onShowLevel: ((RaceResult) -> Void)? = nil
    ) {
        self.existing = existing
        self.source = existing?.source ?? (parsed == nil ? .manual : .scan)
        self.division = existing?.division ?? defaultDivision
        self.onSave = onSave
        self.onDelete = onDelete
        self.onShowLevel = onShowLevel
        self.runLaps = existing?.runLapSeconds ?? parsed?.runLapSeconds.compactMap { $0 } ?? []
        super.init(nibName: nil, bundle: nil)

        nameField.text = existing?.eventName ?? parsed?.eventName
        datePicker.date = existing?.date ?? Date()
        totalField.text = Self.text(existing?.totalSeconds ?? parsed?.resolvedTotalSeconds)
        runTotalField.text = Self.text(existing?.runTotalSeconds ?? parsed?.runTotalSeconds)
        roxzoneField.text = Self.text(existing?.roxzoneSeconds ?? parsed?.roxzoneSeconds)
        for kind in StationKind.standardOrder {
            let field = UITextField()
            field.text = Self.text(existing?.seconds(for: kind) ?? parsed?.stationSeconds[kind])
            stationFields[kind] = field
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = existing == nil ? L.Editor.titleNew : L.Editor.titleEdit
        view.backgroundColor = DesignTokens.Color.background
        view.accessibilityIdentifier = "raceResultEditor.view"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save, target: self, action: #selector(saveTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "raceResultEditor.save"

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32)
        ])
        buildContent()
    }

    // MARK: - Content

    private func buildContent() {
        if source == .scan, existing == nil {
            let note = UILabel()
            note.font = .systemFont(ofSize: 13, weight: .medium)
            note.textColor = DesignTokens.Color.overGoal
            note.numberOfLines = 0
            note.text = L.Editor.scanNote
            note.accessibilityIdentifier = "raceResultEditor.scanNote"
            stack.addArrangedSubview(note)
            stack.setCustomSpacing(14, after: note)
        }

        nameField.placeholder = L.Editor.namePlaceholder
        nameField.accessibilityIdentifier = "raceResultEditor.name"
        style(nameField, alignment: .right)
        nameField.autocapitalizationType = .words
        nameField.returnKeyType = .done
        addRow(title: L.Editor.name, control: nameField)

        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .compact
        datePicker.maximumDate = Date()
        datePicker.tintColor = DesignTokens.Color.accent
        addRow(title: L.Editor.date, control: datePicker, hugging: true)

        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = DesignTokens.Color.accent
        config.contentInsets = .init(top: 6, leading: 0, bottom: 6, trailing: 0)
        config.image = UIImage(systemName: "chevron.up.chevron.down")
        config.imagePlacement = .trailing
        config.imagePadding = 6
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        divisionButton.configuration = config
        divisionButton.showsMenuAsPrimaryAction = true
        divisionButton.accessibilityIdentifier = "raceResultEditor.division"
        updateDivisionButton()
        addRow(title: L.Editor.division, control: divisionButton, hugging: true)

        addSection(L.Editor.sectionTotals)
        addTimeRow(title: L.Editor.total, field: totalField, id: "total", placeholder: "1:23:45")
        addTimeRow(title: L.Editor.runTotal, field: runTotalField, id: "runTotal", placeholder: "40:00")
        addTimeRow(title: L.Editor.roxzone, field: roxzoneField, id: "roxzone", placeholder: "5:00")

        addSection(L.Editor.sectionStations)
        for kind in StationKind.standardOrder {
            guard let field = stationFields[kind] else { continue }
            addTimeRow(title: kind.displayName, field: field, id: kind.dataKey ?? "", placeholder: "4:00")
        }

        let hint = UILabel()
        hint.font = .systemFont(ofSize: 11.5)
        hint.textColor = DesignTokens.Color.textTertiary
        hint.numberOfLines = 0
        hint.text = L.Editor.hint
        stack.setCustomSpacing(12, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(hint)

        if let existing {
            if existing.asCompletedWorkout() != nil, onShowLevel != nil {
                stack.setCustomSpacing(22, after: hint)
                stack.addArrangedSubview(makeButton(
                    L.Editor.showLevel, color: DesignTokens.Color.accent, id: "raceResultEditor.level",
                    action: #selector(levelTapped)
                ))
            }
            if onDelete != nil {
                stack.setCustomSpacing(10, after: stack.arrangedSubviews.last!)
                stack.addArrangedSubview(makeButton(
                    L.Editor.delete, color: DesignTokens.Color.destructive, id: "raceResultEditor.delete",
                    action: #selector(deleteTapped)
                ))
            }
        }
    }

    private func addSection(_ title: String) {
        let label = UILabel()
        label.font = DesignTokens.Font.wide(11, weight: .heavy)
        label.textColor = DesignTokens.Color.accent
        label.setTracked(title.uppercased(), kern: 1.6)
        stack.setCustomSpacing(24, after: stack.arrangedSubviews.last ?? label)
        stack.addArrangedSubview(label)
        stack.setCustomSpacing(6, after: label)
        stack.addArrangedSubview(hairline())
    }

    private func hairline() -> UIView {
        let line = UIView()
        line.backgroundColor = DesignTokens.Color.hairline
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func addRow(title: String, control: UIView, hugging: Bool = false) {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = DesignTokens.Color.textPrimary
        label.text = title
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        let views: [UIView] = hugging ? [label, UIView(), control] : [label, control]
        let row = UIStackView(arrangedSubviews: views)
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 10, leading: 0, bottom: 10, trailing: 0)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        stack.addArrangedSubview(row)
        stack.addArrangedSubview(hairline())
    }

    private func addTimeRow(title: String, field: UITextField, id: String, placeholder: String) {
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder, attributes: [.foregroundColor: DesignTokens.Color.textTertiary]
        )
        field.keyboardType = .numbersAndPunctuation
        field.accessibilityIdentifier = "raceResultEditor.time.\(id)"
        style(field, alignment: .right)
        field.font = DesignTokens.Font.number(17)
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 110).isActive = true
        addRow(title: title, control: field)
    }

    private func style(_ field: UITextField, alignment: NSTextAlignment) {
        field.textColor = DesignTokens.Color.textPrimary
        field.tintColor = DesignTokens.Color.accent
        field.textAlignment = alignment
        field.font = .systemFont(ofSize: 15)
        field.autocorrectionType = .no
        field.delegate = self
    }

    private func makeButton(_ title: String, color: UIColor, id: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(color, for: .normal)
        button.titleLabel?.font = DesignTokens.Font.wide(13, weight: .heavy)
        button.layer.borderWidth = 1
        button.layer.borderColor = color.cgColor
        button.heightAnchor.constraint(equalToConstant: 48).isActive = true
        button.accessibilityIdentifier = id
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func updateDivisionButton() {
        divisionButton.configuration?.title = division.displayName
        divisionButton.menu = UIMenu(children: HyroxDivision.allCases.map { option in
            UIAction(title: option.displayName, state: option == division ? .on : .off) { [weak self] _ in
                self?.division = option
                self?.updateDivisionButton()
            }
        })
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    // MARK: - Values

    private static func text(_ seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        return seconds >= 3600 ? DurationFormatter.hms(TimeInterval(seconds)) : DurationFormatter.ms(TimeInterval(seconds))
    }

    /// 비어 있으면 `.success(nil)`, 형식이 틀리면 `.failure`.
    private func seconds(in field: UITextField) -> Result<Int?, FormError> {
        let text = (field.text ?? "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return .success(nil) }
        guard let value = RaceResultTextParser.seconds(from: text) else { return .failure(.badTime(text)) }
        return .success(value)
    }

    private enum FormError: Error {
        case badTime(String)
        case missingTotal
        case missingName
    }

    /// 화면의 값으로 기록을 만든다.
    private func makeResult() throws -> RaceResult {
        let name = (nameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FormError.missingName }

        var stations: [String: Int] = [:]
        for kind in StationKind.standardOrder {
            guard let field = stationFields[kind], let key = kind.dataKey else { continue }
            if let value = try seconds(in: field).get() { stations[key] = value }
        }
        let runTotal = try seconds(in: runTotalField).get()
        let roxzone = try seconds(in: roxzoneField).get()
        var total = try seconds(in: totalField).get()
        // 구간 표에는 완주 시간이 없다. 전부 채워져 있으면 더해서 낸다.
        if total == nil, stations.count == StationKind.standardOrder.count, let runTotal, let roxzone {
            total = runTotal + roxzone + stations.values.reduce(0, +)
        }
        guard let total else { throw FormError.missingTotal }

        return RaceResult(
            id: existing?.id ?? UUID(),
            eventName: name,
            date: datePicker.date,
            division: division,
            totalSeconds: total,
            stationSeconds: stations,
            runTotalSeconds: runTotal,
            // 러닝 랩은 편집 칸이 없다. 러닝 합계를 고쳤다면 랩과 어긋날 수 있어 버린다.
            runLapSeconds: runTotal == (existing?.runTotalSeconds ?? runTotal) ? runLaps : [],
            roxzoneSeconds: roxzone,
            source: source,
            note: existing?.note,
            createdAt: existing?.createdAt ?? Date()
        )
    }

    // MARK: - Actions

    @objc private func cancelTapped() { dismiss(animated: true) }

    @objc private func saveTapped() {
        view.endEditing(true)
        do {
            let result = try makeResult()
            dismiss(animated: true) { [onSave] in onSave(result) }
        } catch let error as FormError {
            let message: String
            switch error {
            case .badTime(let text): message = L.Editor.Error.badTime(text)
            case .missingTotal: message = L.Editor.Error.missingTotal
            case .missingName: message = L.Editor.Error.missingName
            }
            let alert = DarkAlertController(title: L.Editor.Error.title, message: message)
            alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.ok, style: .normal, handler: nil))
            present(alert, animated: true)
        } catch {}
    }

    @objc private func levelTapped() {
        guard let existing else { return }
        dismiss(animated: true) { [onShowLevel] in onShowLevel?(existing) }
    }

    @objc private func deleteTapped() {
        guard let existing else { return }
        let alert = DarkAlertController(title: L.Editor.deleteConfirmTitle, message: L.Editor.deleteConfirmMessage)
        alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.cancel, style: .cancel, handler: nil))
        alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.delete, style: .destructive, handler: { [weak self] in
            self?.dismiss(animated: true) { [onDelete = self?.onDelete] in onDelete?(existing) }
        }))
        present(alert, animated: true)
    }
}
