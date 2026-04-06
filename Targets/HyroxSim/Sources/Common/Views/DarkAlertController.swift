//
//  DarkAlertController.swift
//  HyroxSim
//
//  Created by bbdyno on 4/7/26.
//

import UIKit

/// Custom dark-themed alert matching the app's black + yellow aesthetic.
/// Replaces system UIAlertController for visual consistency.
final class DarkAlertController: UIViewController {

    struct Action {
        let title: String
        let style: Style
        let handler: (() -> Void)?

        enum Style { case normal, destructive, cancel }
    }

    private let alertTitle: String?
    private let alertMessage: String?
    private var actions: [Action] = []
    private var textFieldConfig: ((UITextField) -> Void)?
    private(set) var textField: UITextField?

    private let containerView = UIView()

    init(title: String?, message: String?) {
        self.alertTitle = title
        self.alertMessage = message
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func addAction(_ action: Action) { actions.append(action) }

    func addTextField(_ configure: @escaping (UITextField) -> Void) {
        textFieldConfig = configure
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        setupContainer()
    }

    private func setupContainer() {
        containerView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        containerView.layer.cornerRadius = 16
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 300)
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20)
        ])

        // Title
        if let t = alertTitle {
            let label = UILabel()
            label.text = t
            label.font = .systemFont(ofSize: 17, weight: .bold)
            label.textColor = .white
            label.textAlignment = .center
            label.numberOfLines = 0
            stack.addArrangedSubview(label)
        }

        // Message
        if let m = alertMessage {
            let label = UILabel()
            label.text = m
            label.font = .systemFont(ofSize: 14, weight: .regular)
            label.textColor = UIColor.white.withAlphaComponent(0.6)
            label.textAlignment = .center
            label.numberOfLines = 0
            stack.addArrangedSubview(label)
        }

        // Text field
        if let config = textFieldConfig {
            let tf = UITextField()
            tf.backgroundColor = UIColor(white: 0.2, alpha: 1)
            tf.textColor = .white
            tf.borderStyle = .none
            tf.layer.cornerRadius = 10
            let padding = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
            tf.leftView = padding
            tf.leftViewMode = .always
            tf.heightAnchor.constraint(equalToConstant: 40).isActive = true
            config(tf)
            stack.addArrangedSubview(tf)
            self.textField = tf
        }

        // Buttons
        let btnStack = UIStackView()
        btnStack.axis = actions.count <= 2 ? .horizontal : .vertical
        btnStack.spacing = 10
        btnStack.distribution = .fillEqually

        for action in actions {
            let btn = UIButton(type: .system)
            btn.setTitle(action.title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 16, weight: action.style == .cancel ? .regular : .bold)
            btn.layer.cornerRadius = 12
            btn.heightAnchor.constraint(equalToConstant: 44).isActive = true

            switch action.style {
            case .destructive:
                btn.setTitleColor(.white, for: .normal)
                btn.backgroundColor = UIColor.systemRed.withAlphaComponent(0.8)
            case .cancel:
                btn.setTitleColor(.white, for: .normal)
                btn.backgroundColor = UIColor(white: 0.2, alpha: 1)
            case .normal:
                btn.setTitleColor(.black, for: .normal)
                btn.backgroundColor = DesignTokens.Color.accent
            }

            let handler = action.handler
            btn.addAction(UIAction { [weak self] _ in
                self?.dismiss(animated: true) { handler?() }
            }, for: .touchUpInside)
            btnStack.addArrangedSubview(btn)
        }
        stack.addArrangedSubview(btnStack)

        // Tap outside to dismiss (if cancel exists)
        if actions.contains(where: { $0.style == .cancel }) {
            let tapBg = UITapGestureRecognizer(target: self, action: #selector(bgTapped))
            view.addGestureRecognizer(tapBg)
        }
    }

    @objc private func bgTapped() {
        let cancelAction = actions.first(where: { $0.style == .cancel })
        dismiss(animated: true) { cancelAction?.handler?() }
    }
}
