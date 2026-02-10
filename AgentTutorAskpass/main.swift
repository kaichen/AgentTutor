import AppKit
import Foundation

private func promptText(from arguments: [String]) -> String {
    let message = arguments.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    if message.isEmpty {
        return "Please enter your administrator password to continue."
    }
    return message
}

private func showPasswordPrompt(message: String) -> String? {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.activate(ignoringOtherApps: true)

    let secureField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
    secureField.placeholderString = "Password"
    secureField.lineBreakMode = .byTruncatingTail

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Administrator Authentication Required"
    alert.informativeText = message
    alert.accessoryView = secureField
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")

    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else {
        return nil
    }

    let password = secureField.stringValue
    guard !password.isEmpty else {
        return nil
    }
    return password
}

let message = promptText(from: CommandLine.arguments)
if let password = showPasswordPrompt(message: message) {
    if let data = "\(password)\n".data(using: .utf8) {
        FileHandle.standardOutput.write(data)
        fflush(stdout)
        exit(EXIT_SUCCESS)
    }
}

exit(EXIT_FAILURE)
