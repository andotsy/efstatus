import Cocoa

class SetupWindow: NSWindow {
    var onSave: ((Credentials) -> Void)?

    private let accessKeyField = NSTextField()
    private let secretKeyField = NSSecureTextField()
    private let serialField    = NSTextField()
    private let statusLabel    = NSTextField(wrappingLabelWithString: "")
    private var saveBtn: NSButton!
    private var verifyTask: Task<Void, Never>?

    private let updatesCheck = NSButton(checkboxWithTitle: "Check for updates automatically", target: nil, action: nil)

    private let notifyChecks: [(NotificationPref, NSButton)] = [
        (.inputLost,     NSButton(checkboxWithTitle: "Input power is lost", target: nil, action: nil)),
        (.inputRestored, NSButton(checkboxWithTitle: "Input power is restored", target: nil, action: nil)),
        (.lowBattery,    NSButton(checkboxWithTitle: "Battery drops to 20% and 10% while discharging", target: nil, action: nil)),
        (.fullCharge,    NSButton(checkboxWithTitle: "Battery is fully charged", target: nil, action: nil)),
    ]

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
            styleMask:   [.titled, .closable],
            backing:     .buffered,
            defer:       false
        )
        title = "EFStatus — Setup"
        isReleasedWhenClosed = false
        center()
        buildUI()
        if let c = CredentialsManager.load() {
            accessKeyField.stringValue = c.accessKey
            secretKeyField.stringValue = c.secretKey
            serialField.stringValue    = c.serial
        }
        updatesCheck.state  = MainActor.assumeIsolated { Updater.shared.automaticallyChecks } ? .on : .off
        updatesCheck.target = self
        updatesCheck.action = #selector(toggleUpdates)
        for (pref, cb) in notifyChecks {
            cb.state  = pref.isOn ? .on : .off
            cb.target = self
            cb.action = #selector(toggleNotify(_:))
        }
        refreshNotifyWarning()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI() {
        let v = NSView(frame: contentView!.bounds)
        v.wantsLayer = true
        contentView = v

        func label(_ text: String) -> NSTextField {
            let f = NSTextField(labelWithString: text)
            f.font = .systemFont(ofSize: 13)
            return f
        }

        let title = NSTextField(labelWithString: "EFStatus")
        title.font = .boldSystemFont(ofSize: 18)

        let sub = NSTextField(labelWithString: "Enter your EcoFlow API credentials to get started.")
        sub.font = .systemFont(ofSize: 12)
        sub.textColor = .secondaryLabelColor

        accessKeyField.placeholderString = "Access Key"
        secretKeyField.placeholderString = "Secret Key"
        serialField.placeholderString    = "Device Serial Number"

        for f in [accessKeyField, secretKeyField] {
            f.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        }
        serialField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        statusLabel.font      = .systemFont(ofSize: 11)
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = ""
        statusLabel.maximumNumberOfLines = 3
        statusLabel.preferredMaxLayoutWidth = 372

        saveBtn = NSButton(title: "Save & Connect", target: self, action: #selector(save))
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"

        let helpBtn = NSButton(title: "Get API credentials →", target: self, action: #selector(openDocs))
        helpBtn.bezelStyle  = .inline
        helpBtn.isBordered  = false
        helpBtn.font        = .systemFont(ofSize: 11)
        helpBtn.contentTintColor = .linkColor

        let notifTitle = NSTextField(labelWithString: "Notify me when…")
        notifTitle.font = .boldSystemFont(ofSize: 13)

        let updatesTitle = NSTextField(labelWithString: "Updates")
        updatesTitle.font = .boldSystemFont(ofSize: 13)
        updatesCheck.font = .systemFont(ofSize: 12)

        for (_, cb) in notifyChecks {
            cb.font = .systemFont(ofSize: 12)
        }

        let stack = NSStackView(views: [
            title, sub,
            label("Access Key"),  accessKeyField,
            label("Secret Key"),  secretKeyField,
            label("Serial Number"), serialField,
            helpBtn, statusLabel, saveBtn,
            notifTitle,
        ] + notifyChecks.map { $0.1 } + [updatesTitle, updatesCheck])
        stack.orientation = .vertical
        stack.alignment   = .leading
        stack.spacing     = 6
        stack.edgeInsets  = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        for f in [accessKeyField, secretKeyField, serialField] {
            f.widthAnchor.constraint(equalToConstant: 372).isActive = true
        }
        stack.setCustomSpacing(2,  after: sub)
        stack.setCustomSpacing(16, after: saveBtn)
        stack.setCustomSpacing(4,  after: notifTitle)
        if let last = notifyChecks.last?.1 { stack.setCustomSpacing(16, after: last) }
        stack.setCustomSpacing(4,  after: updatesTitle)

        v.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: v.topAnchor),
            stack.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        v.layoutSubtreeIfNeeded()
        setContentSize(NSSize(width: 420, height: stack.fittingSize.height))
    }

    @objc private func save() {
        let ak = accessKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        let sk = secretKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        let sn = serialField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !ak.isEmpty, !sk.isEmpty, !sn.isEmpty else {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "All fields are required."
            return
        }

        verifyTask?.cancel()
        saveBtn.isEnabled = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "Checking credentials…"

        let creds = Credentials(accessKey: ak, secretKey: sk, serial: sn)
        let api = EcoFlowAPI(accessKey: ak, secretKey: sk, serial: sn)
        verifyTask = Task { [weak self] in
            do {
                try await api.verifyCredentials()
                try Task.checkCancellation()
                await MainActor.run {
                    guard let self, self.isVisible else { return }
                    CredentialsManager.save(creds)
                    self.statusLabel.stringValue = ""
                    self.saveBtn.isEnabled = true
                    self.onSave?(creds)
                    self.close()
                }
            } catch is CancellationError {
                await MainActor.run { self?.saveBtn.isEnabled = true }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.saveBtn.isEnabled = true
                    self.statusLabel.textColor = .systemRed
                    self.statusLabel.stringValue = Self.verifyErrorMessage(error)
                }
            }
        }
    }

    private static func verifyErrorMessage(_ error: Error) -> String {
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Could not reach EcoFlow. Check your connection."
            default:
                break
            }
        }
        let msg = error.localizedDescription
        return msg.isEmpty ? "Could not verify credentials." : msg
    }

    @objc private func openDocs() {
        NSWorkspace.shared.open(URL(string: "https://developer.ecoflow.com")!)
    }

    @objc private func toggleUpdates() {
        let on = updatesCheck.state == .on
        MainActor.assumeIsolated { Updater.shared.automaticallyChecks = on }
    }

    @objc private func toggleNotify(_ sender: NSButton) {
        guard let pref = notifyChecks.first(where: { $0.1 === sender })?.0 else { return }
        UserDefaults.standard.set(sender.state == .on, forKey: pref.rawValue)
        explainNotifyIfNeeded(sender)
    }

    private func explainNotifyIfNeeded(_ checkbox: NSButton) {
        guard checkbox.state == .on else {
            refreshNotifyWarning()
            return
        }
        Notifier.requestAndExplain { [weak self] message in
            guard let self else { return }
            if let message {
                self.statusLabel.textColor = .systemOrange
                self.statusLabel.stringValue = message
            } else if self.statusLabel.textColor == .systemOrange {
                self.statusLabel.stringValue = ""
            }
        }
    }

    private func refreshNotifyWarning() {
        Notifier.authorizationDeniedMessage { [weak self] message in
            guard let self else { return }
            if let message {
                self.statusLabel.textColor = .systemOrange
                self.statusLabel.stringValue = message
            }
        }
    }
}
