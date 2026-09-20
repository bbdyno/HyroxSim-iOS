//
//  EditRunSheetViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit
import HyroxCore

@MainActor
protocol EditRunSheetDelegate: AnyObject {
    func editRunDidSave(distanceMeters: Double, mode: AddStationMode)
    func editRunDidCancel()
}

final class EditRunSheetViewController: UIViewController {

    weak var delegate: EditRunSheetDelegate?
    let mode: AddStationMode
    private var distance: Double

    private let distanceField = UITextField()

    init(mode: AddStationMode) {
        self.mode = mode
        if case .edit(let seg, _) = mode { self.distance = Self.sanitizedDistance(seg.distanceMeters) }
        else { self.distance = 1000 }
        super.init(nibName: nil, bundle: nil)
    }

    /// 저장된 값이 비정상이거나 범위를 벗어나도 안전하게 표시할 수 있도록 다듬는다.
    private static func sanitizedDistance(_ meters: Double?) -> Double {
        guard let meters, meters.isFinite else { return 1000 }
        return LocalizedDecimalFormatter.clamped(meters, to: NumericInputLimits.distanceMeters)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Color.background
        title = mode.isEdit ? "Edit Run" : "Add Run"
        applyDarkNavBarAppearance()
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        setupUI()
    }

    @objc private func cancelTapped() { delegate?.editRunDidCancel() }

    private func setupUI() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])

        let label = UILabel()
        label.text = "DISTANCE (METERS)"
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = DesignTokens.Color.accent
        stack.addArrangedSubview(label)

        distanceField.text = "\(LocalizedDecimalFormatter.safeInt(distance))"
        distanceField.keyboardType = .numberPad
        distanceField.font = DesignTokens.Font.largeNumber
        distanceField.textAlignment = .center
        distanceField.applyDarkStyle()
        distanceField.heightAnchor.constraint(equalToConstant: 64).isActive = true
        distanceField.inputAccessoryView = makeDoneToolbar()
        stack.addArrangedSubview(distanceField)

        let presetStack = UIStackView()
        presetStack.distribution = .fillEqually
        presetStack.spacing = 8
        for m in [500, 1000, 1500, 2000] {
            let btn = UIButton(type: .system)
            btn.setTitle("\(m) m", for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            btn.setTitleColor(.white, for: .normal)
            btn.backgroundColor = DesignTokens.Color.surface
            btn.layer.cornerRadius = 10
            btn.heightAnchor.constraint(equalToConstant: 36).isActive = true
            btn.tag = m
            btn.addTarget(self, action: #selector(presetTapped(_:)), for: .touchUpInside)
            presetStack.addArrangedSubview(btn)
        }
        stack.addArrangedSubview(presetStack)

        let saveBtn = UIButton(type: .system)
        saveBtn.setTitle(mode.isEdit ? "Save" : "Add Run", for: .normal)
        saveBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        saveBtn.setTitleColor(.black, for: .normal)
        saveBtn.backgroundColor = DesignTokens.Color.accent
        saveBtn.layer.cornerRadius = 22
        saveBtn.heightAnchor.constraint(equalToConstant: 44).isActive = true
        saveBtn.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        stack.addArrangedSubview(saveBtn)
    }

    /// `.numberPad` 에는 return 키가 없어 키보드를 내릴 수단이 필요하다.
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

    @objc private func presetTapped(_ sender: UIButton) { distanceField.text = "\(sender.tag)" }

    @objc private func saveTapped() {
        view.endEditing(true)
        let text = distanceField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parsed = text.isEmpty ? distance : LocalizedDecimalFormatter.finiteValue(from: text)
        guard let parsed, NumericInputLimits.distanceMeters.contains(parsed) else {
            let alert = DarkAlertController(
                title: HyroxSimStrings.Localizable.Alert.Error.title,
                message: "Enter a distance between 1 and 100,000 m."
            )
            alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.ok, style: .normal, handler: nil))
            present(alert, animated: true)
            return
        }
        delegate?.editRunDidSave(distanceMeters: parsed, mode: mode)
    }
}
