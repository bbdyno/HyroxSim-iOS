//
//  RaceArchiveViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import HyroxCore
import PhotosUI
import UIKit

/// 대회 기록 보관함. 실제 대회에서 받은 공식 기록을 모아 둔다.
final class RaceArchiveViewController: UIViewController {

    private let store: RaceResultStore
    private let defaultDivision: HyroxDivision
    /// 기록 하나를 수준 판정 화면으로 넘긴다.
    var onShowLevel: ((CompletedWorkout) -> Void)?

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .large)

    private typealias L = HyroxSimStrings.Localizable.RaceArchive

    init(store: RaceResultStore, defaultDivision: HyroxDivision) {
        self.store = store
        self.defaultDivision = defaultDivision
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.title
        view.backgroundColor = DesignTokens.Color.background
        view.accessibilityIdentifier = "raceArchive.view"
        applyDarkNavBarAppearance()
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(addTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "raceArchive.add"

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = DesignTokens.Color.accent
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -120),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        NotificationCenter.default.addObserver(
            self, selector: #selector(reload), name: RaceResultStore.didChangeNotification, object: store
        )
        reload()
    }

    // MARK: - List

    @objc private func reload() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let results = store.all()
        guard !results.isEmpty else {
            let empty = UILabel()
            empty.font = .systemFont(ofSize: 15)
            empty.textColor = DesignTokens.Color.textSecondary
            empty.numberOfLines = 0
            empty.textAlignment = .center
            empty.text = L.empty
            empty.accessibilityIdentifier = "raceArchive.empty"
            stack.addArrangedSubview(UIView.spacer(80))
            stack.addArrangedSubview(empty)
            return
        }
        // 가장 빠른 기록에 PB 표시 (디비전별).
        var best: [HyroxDivision: Int] = [:]
        for result in results { best[result.division] = min(best[result.division] ?? .max, result.totalSeconds) }

        stack.addArrangedSubview(hairline())
        for result in results {
            stack.addArrangedSubview(makeRow(result, isBest: best[result.division] == result.totalSeconds))
            stack.addArrangedSubview(hairline())
        }
    }

    private func hairline() -> UIView {
        let line = UIView()
        line.backgroundColor = DesignTokens.Color.hairline
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func makeRow(_ result: RaceResult, isBest: Bool) -> UIView {
        let name = UILabel()
        name.font = DesignTokens.Font.wide(15, weight: .heavy)
        name.textColor = DesignTokens.Color.textPrimary
        name.numberOfLines = 2
        name.text = result.eventName.uppercased()

        let meta = UILabel()
        meta.font = .systemFont(ofSize: 12.5, weight: .medium)
        meta.textColor = DesignTokens.Color.textSecondary
        meta.numberOfLines = 0
        let date = result.date.formatted(.dateTime.year().month(.abbreviated).day())
        meta.text = "\(date) · \(result.division.shortName)" + (isBest ? " · PB" : "")

        let time = UILabel()
        time.font = DesignTokens.Font.bigNumber(28)
        time.textColor = isBest ? DesignTokens.Color.accent : DesignTokens.Color.textPrimary
        time.text = DurationFormatter.hms(TimeInterval(result.totalSeconds))
        time.setContentCompressionResistancePriority(.required, for: .horizontal)
        time.setContentHuggingPriority(.required, for: .horizontal)

        let text = UIStackView(arrangedSubviews: [name, meta])
        text.axis = .vertical
        text.spacing = 3
        let row = UIStackView(arrangedSubviews: [text, time])
        row.alignment = .center
        row.spacing = 12
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false

        let control = UIControl()
        control.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: control.topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: control.bottomAnchor, constant: -14),
            row.leadingAnchor.constraint(equalTo: control.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: control.trailingAnchor)
        ])
        control.isAccessibilityElement = true
        control.accessibilityTraits = .button
        control.accessibilityLabel = "\(result.eventName), \(meta.text ?? ""), \(time.text ?? "")"
        control.accessibilityIdentifier = "raceArchive.row"
        control.addAction(UIAction { [weak self] _ in self?.presentEditor(existing: result) }, for: .touchUpInside)
        return control
    }

    // MARK: - Add

    @objc private func addTapped() {
        guard PremiumAccess.gate().canAddRaceResult(existingCount: store.all().count) else {
            PremiumAccess.presentPaywall(.raceArchive)
            return
        }
        let alert = DarkAlertController(title: L.Add.title, message: L.Add.message)
        alert.addAction(.init(title: L.Add.scan, style: .normal, handler: { [weak self] in self?.pickPhoto() }))
        alert.addAction(.init(title: L.Add.manual, style: .normal, handler: { [weak self] in
            self?.presentEditor(existing: nil)
        }))
        alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.cancel, style: .cancel, handler: nil))
        present(alert, animated: true)
    }

    private func pickPhoto() {
        guard PremiumAccess.require(.resultScan) else { return }
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    /// 사진 한 장을 읽어 편집 화면을 채운다. 테스트에서 직접 부른다.
    func handlePicked(_ image: UIImage) {
        spinner.startAnimating()
        Task { [weak self] in
            let parsed = try? await RaceResultScanner.scan(image)
            guard let self else { return }
            self.spinner.stopAnimating()
            guard let parsed, !parsed.isEmpty else {
                let alert = DarkAlertController(title: L.Scan.failedTitle, message: L.Scan.failedMessage)
                alert.addAction(.init(title: L.Add.manual, style: .normal, handler: { [weak self] in
                    self?.presentEditor(existing: nil)
                }))
                alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.cancel, style: .cancel, handler: nil))
                self.present(alert, animated: true)
                return
            }
            self.presentEditor(existing: nil, parsed: parsed)
        }
    }

    private func presentEditor(existing: RaceResult?, parsed: ParsedRaceResult? = nil) {
        let editor = RaceResultEditorViewController(
            existing: existing,
            parsed: parsed,
            defaultDivision: store.all().first?.division ?? defaultDivision,
            onSave: { [weak self] result in self?.persist { try $0.save(result) } },
            onDelete: { [weak self] result in self?.persist { try $0.delete(id: result.id) } },
            onShowLevel: { [weak self] result in
                guard let workout = result.asCompletedWorkout() else { return }
                self?.onShowLevel?(workout)
            }
        )
        let nav = UINavigationController(rootViewController: editor)
        nav.applyDarkTheme()
        present(nav, animated: true)
    }

    private func persist(_ change: (RaceResultStore) throws -> Void) {
        do {
            try change(store)
        } catch {
            let alert = DarkAlertController(title: L.saveFailedTitle, message: error.localizedDescription)
            alert.addAction(.init(title: HyroxSimStrings.Localizable.Button.ok, style: .normal, handler: nil))
            present(alert, animated: true)
        }
    }
}

extension RaceArchiveViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage else { return }
            DispatchQueue.main.async { self?.handlePicked(image) }
        }
    }
}

private extension UIView {
    static func spacer(_ height: CGFloat) -> UIView {
        let view = UIView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }
}
