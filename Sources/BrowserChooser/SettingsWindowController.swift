import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let store: RoutingRuleStore
    private let profiles: [BrowserProfile]
    private let closed: @MainActor () -> Void
    private let hostField = NSTextField()
    private let profilePicker = NSPopUpButton()
    private let enabledButton = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let errorLabel = NSTextField(labelWithString: "")
    private let rulesStack = NSStackView()
    private var editingHost: String?

    init(store: RoutingRuleStore, profiles: [BrowserProfile], closed: @escaping @MainActor () -> Void) {
        self.store = store
        self.profiles = profiles
        self.closed = closed
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 430), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Routing settings"
        window.center()
        super.init(window: window)
        window.delegate = self

        let content = NSView()
        window.contentView = content
        let heading = NSTextField(labelWithString: "Always open this host in a profile")
        heading.font = .systemFont(ofSize: 16, weight: .semibold)
        let hint = NSTextField(labelWithString: "Paste a link or enter a host. Only the host is saved. Exact matches only.")
        hint.textColor = .secondaryLabelColor
        hostField.placeholderString = "work.example.com"
        profilePicker.addItems(withTitles: profiles.map(\.displayName))
        let saveButton = NSButton(title: "Save rule", target: self, action: #selector(saveRule))
        let cancelButton = NSButton(title: "Cancel edit", target: self, action: #selector(cancelEdit))
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        rulesStack.orientation = .vertical
        rulesStack.alignment = .leading
        rulesStack.spacing = 6
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = rulesStack
        for view in [heading, hint, hostField, profilePicker, enabledButton, saveButton, cancelButton, errorLabel, scroll] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22), heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            hint.leadingAnchor.constraint(equalTo: heading.leadingAnchor), hint.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            hostField.leadingAnchor.constraint(equalTo: heading.leadingAnchor), hostField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22), hostField.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 18),
            profilePicker.leadingAnchor.constraint(equalTo: heading.leadingAnchor), profilePicker.topAnchor.constraint(equalTo: hostField.bottomAnchor, constant: 12), profilePicker.widthAnchor.constraint(equalToConstant: 250),
            enabledButton.leadingAnchor.constraint(equalTo: profilePicker.trailingAnchor, constant: 12), enabledButton.centerYAnchor.constraint(equalTo: profilePicker.centerYAnchor),
            saveButton.leadingAnchor.constraint(equalTo: heading.leadingAnchor), saveButton.topAnchor.constraint(equalTo: profilePicker.bottomAnchor, constant: 14),
            cancelButton.leadingAnchor.constraint(equalTo: saveButton.trailingAnchor, constant: 10), cancelButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: heading.leadingAnchor), errorLabel.topAnchor.constraint(equalTo: saveButton.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: heading.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            scroll.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 12), scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            rulesStack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        enabledButton.state = .on
        reloadList()
    }

    required init?(coder: NSCoder) { nil }
    func windowWillClose(_ notification: Notification) { closed() }
    var selectedProfileID: String? {
        guard profiles.indices.contains(profilePicker.indexOfSelectedItem) else { return nil }
        return profiles[profilePicker.indexOfSelectedItem].id
    }
    var validationMessage: String? { errorLabel.isHidden ? nil : errorLabel.stringValue }

    @objc private func saveRule() {
        do {
            guard let host = RuleRouting.normalizedHost(hostField.stringValue) else { throw RuleError.invalidHost }
            guard profilePicker.indexOfSelectedItem >= 0, profilePicker.indexOfSelectedItem < profiles.count else { throw RuleError.invalidProfile }
            var rules = store.load()
            if let editingHost { rules.removeAll { $0.host == editingHost } }
            if rules.contains(where: { $0.host == host }) { throw RuleError.duplicateHost }
            rules.append(RoutingRule(host: host, profileID: profiles[profilePicker.indexOfSelectedItem].id, enabled: enabledButton.state == .on))
            try store.save(rules.sorted { $0.host < $1.host })
            cancelEdit()
            reloadList()
        } catch {
            errorLabel.stringValue = error.localizedDescription
            errorLabel.isHidden = false
        }
    }

    @objc private func cancelEdit() {
        editingHost = nil
        hostField.stringValue = ""
        enabledButton.state = .on
        errorLabel.isHidden = true
    }

    @objc private func editRule(_ sender: NSButton) {
        beginEditingRule(at: sender.tag)
    }

    func beginEditingRule(at index: Int) {
        let rules = store.load()
        guard rules.indices.contains(index) else { return }
        let rule = rules[index]
        editingHost = rule.host
        hostField.stringValue = rule.host
        if let index = profiles.firstIndex(where: { $0.id == rule.profileID }) { profilePicker.selectItem(at: index) }
        else { profilePicker.select(nil); errorLabel.stringValue = "Saved profile is unavailable. Choose another profile before saving."; errorLabel.isHidden = false }
        enabledButton.state = rule.enabled ? .on : .off
        window?.makeFirstResponder(hostField)
    }

    @objc private func deleteRule(_ sender: NSButton) {
        var rules = store.load()
        guard rules.indices.contains(sender.tag) else { return }
        rules.remove(at: sender.tag)
        do { try store.save(rules); cancelEdit(); reloadList() }
        catch { errorLabel.stringValue = error.localizedDescription; errorLabel.isHidden = false }
    }

    private func reloadList() {
        for view in rulesStack.arrangedSubviews { rulesStack.removeArrangedSubview(view); view.removeFromSuperview() }
        let rules = store.load()
        if rules.isEmpty { rulesStack.addArrangedSubview(NSTextField(labelWithString: "No routing rules yet.")) }
        for (index, rule) in rules.enumerated() {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 10
            let name = profiles.first(where: { $0.id == rule.profileID })?.displayName ?? "Unavailable: \(rule.profileID)"
            let label = NSTextField(labelWithString: "\(rule.enabled ? "" : "Off · ")\(rule.host)  →  \(name)")
            label.lineBreakMode = .byTruncatingMiddle
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let edit = NSButton(title: "Edit", target: self, action: #selector(editRule(_:)))
            edit.tag = index
            let delete = NSButton(title: "Delete", target: self, action: #selector(deleteRule(_:)))
            delete.tag = index
            for item in [label, edit, delete] { row.addArrangedSubview(item) }
            row.translatesAutoresizingMaskIntoConstraints = false
            rulesStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rulesStack.widthAnchor).isActive = true
        }
    }
}
