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
        if case .edit(let seg, _) = mode { self.distance = seg.distanceMeters ?? 1000 }
        else { self.distance = 1000 }
        super.init(nibName: nil, bundle: nil)
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

        distanceField.text = "\(Int(distance))"
        distanceField.keyboardType = .numberPad
        distanceField.font = DesignTokens.Font.largeNumber
        distanceField.textAlignment = .center
        distanceField.applyDarkStyle()
        distanceField.heightAnchor.constraint(equalToConstant: 64).isActive = true
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

    @objc private func presetTapped(_ sender: UIButton) { distanceField.text = "\(sender.tag)" }

    @objc private func saveTapped() {
        let meters = Double(distanceField.text ?? "") ?? 1000
        delegate?.editRunDidSave(distanceMeters: max(1, meters), mode: mode)
    }
}
