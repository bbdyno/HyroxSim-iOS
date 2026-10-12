//
//  PaywallViewController.swift
//  HyroxSim
//
//  Created by bbdyno on 10/12/26.
//

import HyroxCore
import StoreKit
import UIKit

/// 구독 안내 화면. 잠긴 기능을 눌렀을 때와 설정에서 연다.
///
/// 가격은 직접 쓰지 않고 스토어가 준 `displayPrice` 만 보여 준다 — 국가·환율에 따라 다르다.
final class PaywallViewController: UIViewController {

    enum Links {
        static let terms = URL(string: "https://bbdyno.github.io/HyroxSim-iOS/terms.html")!
        static let privacy = URL(string: "https://bbdyno.github.io/HyroxSim-iOS/privacy.html")!
    }

    private let store: SubscriptionStore
    private let trigger: PremiumFeature?
    private var selectedProductID = SubscriptionStore.yearlyProductID
    private var isBusy = false

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let planStack = UIStackView()
    private var planRows: [String: PlanRow] = [:]
    private let purchaseButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    private typealias L = HyroxSimStrings.Localizable.Paywall

    /// - Parameter trigger: 사용자가 누른 잠긴 기능. 있으면 맨 위에 그 기능을 먼저 말한다.
    init(store: SubscriptionStore, trigger: PremiumFeature? = nil) {
        self.store = store
        self.trigger = trigger
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignTokens.Color.background
        view.accessibilityIdentifier = "paywall.view"
        setupLayout()
        buildContent()
        renderPlans()
        NotificationCenter.default.addObserver(
            self, selector: #selector(entitlementChanged),
            name: SubscriptionStore.didChangeNotification, object: store
        )
        Task { [weak self] in
            await self?.store.loadProducts()
            self?.renderPlans()
        }
    }

    // MARK: - Layout

    private func setupLayout() {
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = DesignTokens.Color.textSecondary
        closeButton.accessibilityLabel = L.close
        closeButton.accessibilityIdentifier = "paywall.close"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        let footer = makeFooter()
        footer.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        view.addSubview(footer)
        view.addSubview(closeButton)

        let margin: CGFloat = 24
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 56),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),

            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func buildContent() {
        let caption = UILabel()
        caption.font = DesignTokens.Font.wide(11, weight: .heavy)
        caption.textColor = DesignTokens.Color.accent
        caption.setTracked(L.caption.uppercased(), kern: 2)
        contentStack.addArrangedSubview(caption)
        contentStack.setCustomSpacing(10, after: caption)

        let headline = UILabel()
        headline.font = DesignTokens.Font.wide(30, weight: .black)
        headline.textColor = DesignTokens.Color.textPrimary
        headline.numberOfLines = 0
        headline.text = L.headline
        headline.adjustsFontSizeToFitWidth = true
        headline.minimumScaleFactor = 0.7
        contentStack.addArrangedSubview(headline)
        contentStack.setCustomSpacing(10, after: headline)

        if let trigger {
            let context = UILabel()
            context.font = .systemFont(ofSize: 14, weight: .medium)
            context.textColor = DesignTokens.Color.overGoal
            context.numberOfLines = 0
            context.text = L.triggerFormat(PaywallCopy.title(for: trigger))
            context.accessibilityIdentifier = "paywall.trigger"
            contentStack.addArrangedSubview(context)
            contentStack.setCustomSpacing(18, after: context)
        } else {
            contentStack.setCustomSpacing(18, after: headline)
        }

        contentStack.addArrangedSubview(makeHairline())
        // 눌러서 들어온 기능을 목록 맨 위로.
        var features = PaywallCopy.highlighted
        if let trigger, let index = features.firstIndex(of: trigger) {
            features.insert(features.remove(at: index), at: 0)
        }
        for feature in features {
            contentStack.addArrangedSubview(makeFeatureRow(feature))
            contentStack.addArrangedSubview(makeHairline())
        }

        let freeNote = UILabel()
        freeNote.font = .systemFont(ofSize: 12)
        freeNote.textColor = DesignTokens.Color.textSecondary
        freeNote.numberOfLines = 0
        freeNote.text = L.freeNote
        contentStack.setCustomSpacing(14, after: contentStack.arrangedSubviews.last!)
        contentStack.addArrangedSubview(freeNote)
    }

    private func makeFooter() -> UIView {
        let container = UIView()
        container.backgroundColor = DesignTokens.Color.background

        let topLine = makeHairline()

        planStack.axis = .vertical
        planStack.spacing = 8

        purchaseButton.backgroundColor = DesignTokens.Color.accent
        purchaseButton.setTitleColor(.black, for: .normal)
        purchaseButton.titleLabel?.font = DesignTokens.Font.wide(16, weight: .heavy)
        purchaseButton.titleLabel?.adjustsFontSizeToFitWidth = true
        purchaseButton.titleLabel?.minimumScaleFactor = 0.7
        purchaseButton.accessibilityIdentifier = "paywall.purchase"
        purchaseButton.addTarget(self, action: #selector(purchaseTapped), for: .touchUpInside)
        purchaseButton.heightAnchor.constraint(equalToConstant: 54).isActive = true

        spinner.color = .black
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        purchaseButton.addSubview(spinner)

        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = DesignTokens.Color.overGoal
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.isHidden = true
        statusLabel.accessibilityIdentifier = "paywall.status"

        let disclosure = UILabel()
        disclosure.font = .systemFont(ofSize: 10.5)
        disclosure.textColor = DesignTokens.Color.textTertiary
        disclosure.numberOfLines = 0
        disclosure.textAlignment = .center
        disclosure.text = L.disclosure

        let links = UIStackView(arrangedSubviews: [
            makeLinkButton(L.restore, action: #selector(restoreTapped), id: "paywall.restore"),
            makeLinkButton(L.terms, action: #selector(termsTapped), id: "paywall.terms"),
            makeLinkButton(L.privacy, action: #selector(privacyTapped), id: "paywall.privacy")
        ])
        links.axis = .horizontal
        links.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [planStack, purchaseButton, statusLabel, disclosure, links])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(12, after: planStack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(topLine)
        container.addSubview(stack)
        topLine.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topLine.topAnchor.constraint(equalTo: container.topAnchor),
            topLine.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            spinner.centerYAnchor.constraint(equalTo: purchaseButton.centerYAnchor),
            spinner.trailingAnchor.constraint(equalTo: purchaseButton.trailingAnchor, constant: -18)
        ])
        return container
    }

    private func makeHairline() -> UIView {
        let line = UIView()
        line.backgroundColor = DesignTokens.Color.hairline
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func makeFeatureRow(_ feature: PremiumFeature) -> UIView {
        let title = UILabel()
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = DesignTokens.Color.textPrimary
        title.numberOfLines = 0
        title.text = PaywallCopy.title(for: feature)

        let detail = UILabel()
        detail.font = .systemFont(ofSize: 12.5)
        detail.textColor = DesignTokens.Color.textSecondary
        detail.numberOfLines = 0
        detail.text = PaywallCopy.detail(for: feature)

        let marker = UIView()
        marker.backgroundColor = feature == trigger ? DesignTokens.Color.overGoal : DesignTokens.Color.accent
        marker.translatesAutoresizingMaskIntoConstraints = false

        let text = UIStackView(arrangedSubviews: [title, detail])
        text.axis = .vertical
        text.spacing = 3
        text.translatesAutoresizingMaskIntoConstraints = false

        let row = UIView()
        row.addSubview(marker)
        row.addSubview(text)
        NSLayoutConstraint.activate([
            marker.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            marker.topAnchor.constraint(equalTo: text.topAnchor, constant: 2),
            marker.bottomAnchor.constraint(equalTo: text.bottomAnchor, constant: -2),
            marker.widthAnchor.constraint(equalToConstant: 3),
            text.leadingAnchor.constraint(equalTo: marker.trailingAnchor, constant: 12),
            text.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            text.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            text.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12)
        ])
        return row
    }

    private func makeLinkButton(_ title: String, action: Selector, id: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(DesignTokens.Color.textSecondary, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .medium)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.7
        button.accessibilityIdentifier = id
        button.addTarget(self, action: action, for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        return button
    }

    // MARK: - Plans

    private func renderPlans() {
        planStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        planRows.removeAll()

        #if DEBUG
        // 스토어 없이 요금제 행의 배치를 확인하기 위한 표본. 구매는 되지 않는다.
        if store.products.isEmpty, ProcessInfo.processInfo.arguments.contains("-PaywallSamplePlans") {
            add(PlanRow(title: L.planYearly, price: "₩29,000", note: L.perMonthSavingFormat("₩2,417", 51)),
                id: SubscriptionStore.yearlyProductID)
            add(PlanRow(title: L.planMonthly, price: "₩4,900", note: nil), id: SubscriptionStore.monthlyProductID)
            updateSelection()
            return
        }
        #endif

        guard !store.products.isEmpty else {
            let label = UILabel()
            label.font = .systemFont(ofSize: 13)
            label.textColor = DesignTokens.Color.textSecondary
            label.numberOfLines = 0
            label.textAlignment = .center
            label.text = L.productsUnavailable
            label.accessibilityIdentifier = "paywall.unavailable"
            planStack.addArrangedSubview(label)
            purchaseButton.setTitle(L.retry, for: .normal)
            return
        }

        if let yearly = store.yearlyProduct {
            let row = PlanRow(
                title: L.planYearly,
                price: yearly.displayPrice,
                note: yearlyNote(yearly: yearly, monthly: store.monthlyProduct)
            )
            add(row, id: yearly.id)
        }
        if let monthly = store.monthlyProduct {
            add(PlanRow(title: L.planMonthly, price: monthly.displayPrice, note: nil), id: monthly.id)
        }
        if planRows[selectedProductID] == nil, let first = store.products.first {
            selectedProductID = first.id
        }
        updateSelection()
    }

    private func add(_ row: PlanRow, id: String) {
        row.accessibilityIdentifier = "paywall.plan.\(id.split(separator: ".").last ?? "")"
        row.addAction(UIAction { [weak self] _ in
            self?.selectedProductID = id
            self?.updateSelection()
        }, for: .touchUpInside)
        planRows[id] = row
        planStack.addArrangedSubview(row)
    }

    /// "월 2,417원꼴 · 51% 절약" — 스토어 가격에서 계산한다.
    private func yearlyNote(yearly: Product, monthly: Product?) -> String? {
        let perMonth = yearly.price / 12
        let perMonthText = perMonth.formatted(yearly.priceFormatStyle)
        guard let monthly, monthly.price > 0 else { return L.perMonthFormat(perMonthText) }
        let saving = 1 - (perMonth / monthly.price)
        let percent = Int((NSDecimalNumber(decimal: saving).doubleValue * 100).rounded())
        guard percent > 0 else { return L.perMonthFormat(perMonthText) }
        return L.perMonthSavingFormat(perMonthText, percent)
    }

    private func updateSelection() {
        for (id, row) in planRows { row.isChosen = id == selectedProductID }
        purchaseButton.setTitle(L.subscribe, for: .normal)
    }

    // MARK: - Actions

    @objc private func closeTapped() { dismiss(animated: true) }

    @objc private func entitlementChanged() {
        if store.tier.isUnlocked { dismiss(animated: true) }
    }

    @objc private func purchaseTapped() {
        guard !isBusy else { return }
        guard let product = store.products.first(where: { $0.id == selectedProductID }) else {
            // 상품을 못 불러온 상태. 다시 시도한다.
            setBusy(true)
            Task { [weak self] in
                await self?.store.loadProducts()
                self?.setBusy(false)
                self?.renderPlans()
            }
            return
        }
        setBusy(true)
        showStatus(nil)
        Task { [weak self] in
            guard let self else { return }
            do {
                let unlocked = try await self.store.purchase(product)
                self.setBusy(false)
                if unlocked { self.dismiss(animated: true) }
            } catch {
                self.setBusy(false)
                self.showStatus(L.purchaseFailed)
            }
        }
    }

    @objc private func restoreTapped() {
        guard !isBusy else { return }
        setBusy(true)
        showStatus(nil)
        Task { [weak self] in
            guard let self else { return }
            await self.store.restore()
            self.setBusy(false)
            if self.store.tier.isUnlocked {
                self.dismiss(animated: true)
            } else {
                self.showStatus(L.restoreNothing)
            }
        }
    }

    @objc private func termsTapped() { UIApplication.shared.open(Links.terms) }
    @objc private func privacyTapped() { UIApplication.shared.open(Links.privacy) }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        purchaseButton.isEnabled = !busy
        purchaseButton.alpha = busy ? 0.6 : 1
        busy ? spinner.startAnimating() : spinner.stopAnimating()
    }

    private func showStatus(_ text: String?) {
        statusLabel.text = text
        statusLabel.isHidden = text == nil
    }
}

// MARK: - Plan row

private final class PlanRow: UIControl {

    private let titleLabel = UILabel()
    private let noteLabel = UILabel()
    private let priceLabel = UILabel()
    private let marker = UIView()

    var isChosen = false { didSet { applyState() } }

    init(title: String, price: String, note: String?) {
        super.init(frame: .zero)
        layer.borderWidth = 1

        titleLabel.font = DesignTokens.Font.wide(14, weight: .heavy)
        titleLabel.text = title
        noteLabel.font = .systemFont(ofSize: 12, weight: .medium)
        noteLabel.text = note
        noteLabel.isHidden = note == nil
        noteLabel.adjustsFontSizeToFitWidth = true
        noteLabel.minimumScaleFactor = 0.75
        priceLabel.font = DesignTokens.Font.number(18)
        priceLabel.text = price
        priceLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        priceLabel.setContentHuggingPriority(.required, for: .horizontal)

        let text = UIStackView(arrangedSubviews: [titleLabel, noteLabel])
        text.axis = .vertical
        text.spacing = 2
        let row = UIStackView(arrangedSubviews: [text, priceLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        marker.translatesAutoresizingMaskIntoConstraints = false
        marker.isUserInteractionEnabled = false
        addSubview(marker)
        addSubview(row)
        NSLayoutConstraint.activate([
            marker.leadingAnchor.constraint(equalTo: leadingAnchor),
            marker.topAnchor.constraint(equalTo: topAnchor),
            marker.bottomAnchor.constraint(equalTo: bottomAnchor),
            marker.widthAnchor.constraint(equalToConstant: 4),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
        ])
        isAccessibilityElement = true
        accessibilityLabel = [title, price, note].compactMap { $0 }.joined(separator: ", ")
        applyState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func applyState() {
        layer.borderColor = (isChosen ? DesignTokens.Color.accent : DesignTokens.Color.hairline).cgColor
        marker.backgroundColor = isChosen ? DesignTokens.Color.accent : .clear
        backgroundColor = isChosen ? DesignTokens.Color.surface : .clear
        titleLabel.textColor = isChosen ? DesignTokens.Color.textPrimary : DesignTokens.Color.textSecondary
        priceLabel.textColor = isChosen ? DesignTokens.Color.accent : DesignTokens.Color.textSecondary
        noteLabel.textColor = isChosen ? DesignTokens.Color.accent : DesignTokens.Color.textTertiary
        accessibilityTraits = isChosen ? [.button, .selected] : .button
    }
}
