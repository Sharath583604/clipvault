import UIKit
import SwiftUI
import ClipKit

/// Hosts the SwiftUI keyboard. It never opens the containing app (App Review 4.4.1), always
/// offers a next-keyboard key, and works in a reduced form when Full Access is off.
/// iOS replaces this keyboard with the system keyboard in secure and phone-pad fields.
final class KeyboardViewController: UIInputViewController {
    private let model: KeyboardModel
    private var host: UIHostingController<KeyboardRootView>?

    init() {
        model = KeyboardModel(hasFullAccess: false)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        model = KeyboardModel(hasFullAccess: false)
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        model.actions = KeyboardModel.Actions(
            insert: { [weak self] in self?.textDocumentProxy.insertText($0) },
            deleteBackward: { [weak self] in self?.textDocumentProxy.deleteBackward() },
            returnKey: { [weak self] in self?.textDocumentProxy.insertText("\n") })

        let host = UIHostingController(rootView: KeyboardRootView(model: model, inputController: self))
        self.host = host
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        let height = view.heightAnchor.constraint(equalToConstant: 260)
        height.priority = .defaultHigh
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height,
        ])
        host.didMove(toParent: self)
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
        model.startWatching()
        Task { await model.captureClipboardIfNeeded() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        model.stopWatching()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        model.update(hasFullAccess: hasFullAccess, isSecure: textDocumentProxy.isSecureTextEntry ?? false)
        Task { await model.captureClipboardIfNeeded() }
    }

    private func refresh() {
        model.update(hasFullAccess: hasFullAccess, isSecure: textDocumentProxy.isSecureTextEntry ?? false)
        Task { await model.reload() }
    }
}
