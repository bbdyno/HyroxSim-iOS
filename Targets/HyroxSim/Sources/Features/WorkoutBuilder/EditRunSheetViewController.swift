//
//  EditRunSheetViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit
import HyroxKit

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
        if case .edit(let seg, _) = mode {
            self.distance = seg.distanceMeters ?? 1000
        } else {
            self.distance = 1000
        }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = mode.isEdit ? "Edit Run" : "Add Run"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)
        )
        setupUI()
    }

    @objc private func cancelTapped() {
        delegate?.editRunDidCancel()
    }

    private func setupUI() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = DesignTokens.Spacing.m
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DesignTokens.Spacing.l),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignTokens.Spacing.m),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignTokens.Spacing.m)
        ])

        let label = UILabel()
        label.text = "Distance (meters)"
        label.font = .preferredFont(forTextStyle: .headline)
        stack.addArrangedSubview(label)

        distanceField.borderStyle = .roundedRect
        distanceField.keyboardType = .numberPad
        distanceField.text = "\(Int(distance))"
        distanceField.font = DesignTokens.Font.mediumNumber
        distanceField.textAlignment = .center
        stack.addArrangedSubview(distanceField)

        // Quick presets
        let presetStack = UIStackView()
        presetStack.distribution = .fillEqually
        presetStack.spacing = DesignTokens.Spacing.s
        for m in [500, 1000, 1500, 2000] {
            let btn = UIButton(type: .system)
            btn.setTitle("\(m) m", for: .normal)
            btn.tag = m
            btn.addTarget(self, action: #selector(presetTapped(_:)), for: .touchUpInside)
            presetStack.addArrangedSubview(btn)
        }
        stack.addArrangedSubview(presetStack)

        let saveBtn = UIButton(type: .system)
        saveBtn.setTitle(mode.isEdit ? "Save" : "Add Run", for: .normal)
        saveBtn.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        saveBtn.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        stack.addArrangedSubview(saveBtn)
    }

    @objc private func presetTapped(_ sender: UIButton) {
        distanceField.text = "\(sender.tag)"
    }

    @objc private func saveTapped() {
        let meters = Double(distanceField.text ?? "") ?? 1000
        delegate?.editRunDidSave(distanceMeters: max(1, meters), mode: mode)
    }
}
