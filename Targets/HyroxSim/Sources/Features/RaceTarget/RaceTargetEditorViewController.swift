//
//  RaceTargetEditorViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 9/18/26.
//

import UIKit
import HyroxCore

@MainActor
protocol RaceTargetEditorViewControllerDelegate: AnyObject {
    func raceTargetEditorDidCancel()
    func raceTargetEditorDidSave(_ target: RaceTarget)
    func raceTargetEditorDidRequestDelete(_ target: RaceTarget)
}

/// 내 대회 등록·편집 화면. 시스템 폼 대신 앱의 블랙+골드 스타일로 직접 그린다.
final class RaceTargetEditorViewController: UIViewController {

    weak var delegate: RaceTargetEditorViewControllerDelegate?

    private var form: RaceTargetForm

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let nameField = UITextField()
    private let cityField = UITextField()
    private let datePicker = UIDatePicker()
    private let pastDateHintLabel = UILabel()
    private let divisionChipStack = UIStackView()
    private let goalSwitch = UISwitch()
    private let goalValueLabel = UILabel()
    private let goalPicker = UIPickerView()
    private let noteView = UITextView()
    private let notePlaceholderLabel = UILabel()
    private let footerContainer = UIView()
    private let saveButton = UIButton(type: .system)
    private lazy var doneToolbar: UIToolbar = makeDoneToolbar()

    private var selectedHours = 1
    private var selectedMinutes = 30
    private var selectedSeconds = 0
    private static let maxGoalHours = 5

    /// 디비전 칩 순서. 첫 칸은 "미정"(nil).
    private let divisionOptions: [HyroxDivision?] = [nil] + HyroxDivision.allCases

    init(target: RaceTarget?, defaultDivision: HyroxDivision?) {
        self.form = RaceTargetForm(existing: target, defaultDivision: defaultDivision)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Color.background
        title = form.isEditingExisting
            ? HyroxSimStrings.Localizable.RaceTarget.Title.edit
            : HyroxSimStrings.Localizable.RaceTarget.Title.new
        applyDarkNavBarAppearance()
        navigationItem.largeTitleDisplayMode = .never
        setupNavBarItems()
        setupFooter()
        setupScrollView()
        buildContent()
        applyFormToControls()
    }

    // MARK: - Nav bar

    private func setupNavBarItems() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        guard form.isEditingExisting else { return }
        let deleteItem = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(deleteTapped)
        )
        deleteItem.tintColor = DesignTokens.Color.destructive
        navigationItem.rightBarButtonItem = deleteItem
    }

    @objc private func cancelTapped() {
        delegate?.raceTargetEditorDidCancel()
    }

    @objc private func deleteTapped() {
        guard let existing = form.existing else { return }
        let alert = DarkAlertController(
            title: HyroxSimStrings.Localizable.RaceTarget.Alert.Delete.title,
            message: HyroxSimStrings.Localizable.RaceTarget.Alert.Delete.message(existing.eventName)
        )
        alert.addAction(.init(
            title: HyroxSimStrings.Localizable.Button.cancel,
            style: .cancel,
            handler: nil
        ))
        alert.addAction(.init(
            title: HyroxSimStrings.Localizable.Button.delete,
            style: .destructive,
            handler: { [weak self] in
                self?.delegate?.raceTargetEditorDidRequestDelete(existing)
            }
        ))
        present(alert, animated: true)
    }

    // MARK: - Layout

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footerContainer.topAnchor)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    private func setupFooter() {
        footerContainer.translatesAutoresizingMaskIntoConstraints = false
        footerContainer.backgroundColor = DesignTokens.Color.background
        view.addSubview(footerContainer)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        footerContainer.addSubview(separator)

        saveButton.setTitle(HyroxSimStrings.Localizable.Button.save, for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        saveButton.setTitleColor(.black, for: .normal)
        saveButton.backgroundColor = DesignTokens.Color.accent
        saveButton.layer.cornerRadius = 24
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        footerContainer.addSubview(saveButton)

        NSLayoutConstraint.activate([
            footerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footerContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            separator.topAnchor.constraint(equalTo: footerContainer.topAnchor),
            separator.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            saveButton.topAnchor.constraint(equalTo: footerContainer.topAnchor, constant: 12),
            saveButton.leadingAnchor.constraint(equalTo: footerContainer.leadingAnchor, constant: 20),
            saveButton.trailingAnchor.constraint(equalTo: footerContainer.trailingAnchor, constant: -20),
            saveButton.heightAnchor.constraint(equalToConstant: 48),
            // 키보드가 올라오면 저장 버튼도 같이 올라온다.
            saveButton.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -12)
        ])

        let restingBottom = saveButton.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -12
        )
        restingBottom.priority = .defaultHigh
        restingBottom.isActive = true
    }

    // MARK: - Content

    private func buildContent() {
        contentStack.addArrangedSubview(makeFieldHeader(HyroxSimStrings.Localizable.RaceTarget.Field.eventName))
        nameField.placeholder = HyroxSimStrings.Localizable.RaceTarget.Field.EventName.placeholder
        contentStack.addArrangedSubview(makeTextFieldRow(nameField))

        contentStack.addArrangedSubview(makeFieldHeader(HyroxSimStrings.Localizable.RaceTarget.Field.city))
        cityField.placeholder = HyroxSimStrings.Localizable.RaceTarget.Field.City.placeholder
        contentStack.addArrangedSubview(makeTextFieldRow(cityField))

        contentStack.addArrangedSubview(makeFieldHeader(HyroxSimStrings.Localizable.RaceTarget.Field.date))
        contentStack.addArrangedSubview(makeDateRow())

        pastDateHintLabel.text = HyroxSimStrings.Localizable.RaceTarget.Hint.pastDate
        pastDateHintLabel.font = .systemFont(ofSize: 12, weight: .medium)
        pastDateHintLabel.textColor = DesignTokens.Color.roxZoneAccent
        pastDateHintLabel.numberOfLines = 0
        contentStack.addArrangedSubview(pastDateHintLabel)

        contentStack.addArrangedSubview(makeFieldHeader(HyroxSimStrings.Localizable.RaceTarget.Field.division))
        contentStack.addArrangedSubview(makeDivisionChips())

        contentStack.addArrangedSubview(makeFieldHeader(HyroxSimStrings.Localizable.RaceTarget.Field.goal))
        contentStack.addArrangedSubview(makeGoalRow())
        goalPicker.dataSource = self
        goalPicker.delegate = self
        goalPicker.translatesAutoresizingMaskIntoConstraints = false
        goalPicker.heightAnchor.constraint(equalToConstant: 130).isActive = true
        contentStack.addArrangedSubview(goalPicker)

        contentStack.addArrangedSubview(makeFieldHeader(HyroxSimStrings.Localizable.RaceTarget.Field.note))
        contentStack.addArrangedSubview(makeNoteRow())
    }

    private func makeFieldHeader(_ text: String) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = DesignTokens.Font.label
        label.textColor = DesignTokens.Color.accent

        let container = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])
        return container
    }

    private func makeTextFieldRow(_ field: UITextField) -> UIView {
        field.applyDarkStyle()
        field.font = .systemFont(ofSize: 17, weight: .medium)
        field.autocorrectionType = .no
        field.returnKeyType = .done
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: 48).isActive = true
        return field
    }

    private func makeDateRow() -> UIView {
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .inline
        datePicker.tintColor = DesignTokens.Color.accent
        // 앱은 다크를 강제하지만, 시스템 피커는 명시적으로 지정해야 흰 배경이 안 새어 나온다.
        datePicker.overrideUserInterfaceStyle = .dark
        datePicker.addTarget(self, action: #selector(dateChanged), for: .valueChanged)
        datePicker.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.backgroundColor = DesignTokens.Color.surface
        container.layer.cornerRadius = DesignTokens.Radius.card
        container.addSubview(datePicker)
        NSLayoutConstraint.activate([
            datePicker.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            datePicker.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            datePicker.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            datePicker.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6)
        ])
        return container
    }

    private func makeDivisionChips() -> UIView {
        divisionChipStack.axis = .horizontal
        divisionChipStack.spacing = 8
        divisionChipStack.translatesAutoresizingMaskIntoConstraints = false

        for (index, division) in divisionOptions.enumerated() {
            let chip = UIButton(type: .system)
            var config = UIButton.Configuration.filled()
            config.title = division?.shortName ?? HyroxSimStrings.Localizable.RaceTarget.Field.Division.undecided
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
            chip.configuration = config
            chip.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            chip.tag = index
            chip.addTarget(self, action: #selector(divisionChipTapped(_:)), for: .touchUpInside)
            divisionChipStack.addArrangedSubview(chip)
        }

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(divisionChipStack)
        NSLayoutConstraint.activate([
            divisionChipStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            divisionChipStack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            divisionChipStack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            divisionChipStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            divisionChipStack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 38)
        ])
        return scroll
    }

    private func makeGoalRow() -> UIView {
        goalValueLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        goalValueLabel.textColor = .white

        goalSwitch.onTintColor = DesignTokens.Color.accent
        goalSwitch.addTarget(self, action: #selector(goalSwitchChanged), for: .valueChanged)

        let stack = UIStackView(arrangedSubviews: [goalValueLabel, UIView(), goalSwitch])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView()
        container.backgroundColor = DesignTokens.Color.surface
        container.layer.cornerRadius = DesignTokens.Radius.card
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func makeNoteRow() -> UIView {
        noteView.backgroundColor = DesignTokens.Color.surface
        noteView.textColor = .white
        noteView.font = .systemFont(ofSize: 15, weight: .regular)
        noteView.layer.cornerRadius = DesignTokens.Radius.card
        noteView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        noteView.isScrollEnabled = false
        noteView.delegate = self
        noteView.inputAccessoryView = doneToolbar
        noteView.translatesAutoresizingMaskIntoConstraints = false
        noteView.heightAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true

        notePlaceholderLabel.text = HyroxSimStrings.Localizable.RaceTarget.Field.Note.placeholder
        notePlaceholderLabel.font = .systemFont(ofSize: 15, weight: .regular)
        notePlaceholderLabel.textColor = DesignTokens.Color.textTertiary
        notePlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false
        noteView.addSubview(notePlaceholderLabel)
        NSLayoutConstraint.activate([
            notePlaceholderLabel.topAnchor.constraint(equalTo: noteView.topAnchor, constant: 12),
            notePlaceholderLabel.leadingAnchor.constraint(equalTo: noteView.leadingAnchor, constant: 16)
        ])
        return noteView
    }

    private func makeDoneToolbar() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.barStyle = .black
        toolbar.tintColor = DesignTokens.Color.accent
        toolbar.items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in
                self?.view.endEditing(true)
            })
        ]
        toolbar.sizeToFit()
        return toolbar
    }

    // MARK: - State ↔ Controls

    private func applyFormToControls() {
        nameField.text = form.eventName
        cityField.text = form.city
        datePicker.date = form.date
        noteView.text = form.note
        notePlaceholderLabel.isHidden = !form.note.isEmpty

        if let goal = form.goalDurationSeconds, goal > 0 {
            goalSwitch.isOn = true
            let total = max(0, Int(goal))
            selectedHours = min(Self.maxGoalHours, total / 3600)
            selectedMinutes = (total % 3600) / 60
            selectedSeconds = total % 60
        } else {
            goalSwitch.isOn = false
        }
        goalPicker.selectRow(selectedHours, inComponent: 0, animated: false)
        goalPicker.selectRow(selectedMinutes, inComponent: 2, animated: false)
        goalPicker.selectRow(selectedSeconds, inComponent: 4, animated: false)

        updateGoalDisplay()
        updateDivisionChips()
        updatePastDateHint()
    }

    private func updateGoalDisplay() {
        goalPicker.isHidden = !goalSwitch.isOn
        goalValueLabel.text = goalSwitch.isOn
            ? DurationFormatter.hms(TimeInterval(currentGoalSeconds))
            : HyroxSimStrings.Localizable.RaceTarget.Field.Goal.unset
        goalValueLabel.textColor = goalSwitch.isOn ? .white : DesignTokens.Color.textTertiary
    }

    private var currentGoalSeconds: Int {
        selectedHours * 3600 + selectedMinutes * 60 + selectedSeconds
    }

    private func updateDivisionChips() {
        for (index, chip) in divisionChipStack.arrangedSubviews.enumerated() {
            guard let button = chip as? UIButton, var config = button.configuration else { continue }
            let isSelected = divisionOptions[index] == form.division
            config.baseBackgroundColor = isSelected
                ? DesignTokens.Color.accent
                : DesignTokens.Color.surface
            config.baseForegroundColor = isSelected ? .black : DesignTokens.Color.textSecondary
            button.configuration = config
        }
    }

    private func updatePastDateHint() {
        pastDateHintLabel.isHidden = !form.isPastDate()
    }

    // MARK: - Actions

    @objc private func dateChanged() {
        form.date = datePicker.date
        updatePastDateHint()
    }

    @objc private func divisionChipTapped(_ sender: UIButton) {
        guard sender.tag < divisionOptions.count else { return }
        form.division = divisionOptions[sender.tag]
        updateDivisionChips()
    }

    @objc private func goalSwitchChanged() {
        updateGoalDisplay()
    }

    @objc private func saveTapped() {
        view.endEditing(true)
        syncControlsToForm()
        do {
            let target = try form.makeTarget()
            delegate?.raceTargetEditorDidSave(target)
        } catch {
            presentValidationError(error)
        }
    }

    private func syncControlsToForm() {
        form.eventName = nameField.text ?? ""
        form.city = cityField.text ?? ""
        form.date = datePicker.date
        form.note = noteView.text ?? ""
        form.goalDurationSeconds = goalSwitch.isOn && currentGoalSeconds > 0
            ? TimeInterval(currentGoalSeconds)
            : nil
    }

    private func presentValidationError(_ error: Error) {
        let alert = DarkAlertController(
            title: HyroxSimStrings.Localizable.Alert.Error.title,
            message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        )
        alert.addAction(.init(
            title: HyroxSimStrings.Localizable.Button.ok,
            style: .normal,
            handler: { [weak self] in self?.nameField.becomeFirstResponder() }
        ))
        present(alert, animated: true)
    }
}

// MARK: - UITextFieldDelegate

extension RaceTargetEditorViewController: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === nameField {
            cityField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        return true
    }
}

// MARK: - UITextViewDelegate

extension RaceTargetEditorViewController: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        notePlaceholderLabel.isHidden = !(textView.text ?? "").isEmpty
    }
}

// MARK: - UIPickerView (목표 시간 h/m/s)

extension RaceTargetEditorViewController: UIPickerViewDataSource, UIPickerViewDelegate {

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 6 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        switch component {
        case 0: return Self.maxGoalHours + 1
        case 2, 4: return 60
        default: return 1
        }
    }

    func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
        switch component {
        case 0, 2, 4: return 44
        default: return 24
        }
    }

    func pickerView(
        _ pickerView: UIPickerView,
        viewForRow row: Int,
        forComponent component: Int,
        reusing view: UIView?
    ) -> UIView {
        let label = (view as? UILabel) ?? UILabel()
        switch component {
        case 0, 2, 4:
            label.textAlignment = .right
            label.font = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
            label.textColor = .white
            label.text = String(format: "%02d", row)
        default:
            label.textAlignment = .left
            label.font = .systemFont(ofSize: 16, weight: .medium)
            label.textColor = DesignTokens.Color.textSecondary
            label.text = component == 1 ? "h" : (component == 3 ? "m" : "s")
        }
        return label
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        switch component {
        case 0: selectedHours = row
        case 2: selectedMinutes = row
        case 4: selectedSeconds = row
        default: break
        }
        updateGoalDisplay()
    }
}
