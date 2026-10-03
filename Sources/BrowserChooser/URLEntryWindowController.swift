import AppKit
import Foundation

@MainActor
final class URLEntryWindowController: NSWindowController, NSWindowDelegate {
    private let submit: @MainActor (URL) -> Void
    private let closed: @MainActor (URLEntryWindowController) -> Void
    private let urlField = NSTextField()
    private let errorLabel = NSTextField(labelWithString: "Enter an http or https URL with a host.")

    init(submit: @escaping @MainActor (URL) -> Void,
         closed: @escaping @MainActor (URLEntryWindowController) -> Void) {
        self.submit = submit
        self.closed = closed
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 160),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Open a web link"
        window.center()
        super.init(window: window)
        window.delegate = self

        let content = NSView()
        let heading = NSTextField(labelWithString: "Choose a browser for a web link")
        heading.font = .systemFont(ofSize: 16, weight: .semibold)
        urlField.placeholderString = "https://example.com"
        urlField.target = self
        urlField.action = #selector(openURL)
        let button = NSButton(title: "Open chooser", target: self, action: #selector(openURL))
        button.bezelStyle = .rounded
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        for control in [heading, urlField, errorLabel, button] {
            control.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(control)
        }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            urlField.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            urlField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            urlField.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 14),
            errorLabel.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            errorLabel.topAnchor.constraint(equalTo: urlField.bottomAnchor, constant: 6),
            button.trailingAnchor.constraint(equalTo: urlField.trailingAnchor),
            button.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
        window.contentView = content
        window.initialFirstResponder = urlField
    }

    required init?(coder: NSCoder) { nil }

    @objc private func openURL() {
        guard let url = URLRouter.validatedWebURL(from: ["BrowserChooser", urlField.stringValue]) else {
            errorLabel.isHidden = false
            return
        }
        submit(url)
    }

    func windowWillClose(_ notification: Notification) { closed(self) }
}
