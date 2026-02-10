import Foundation

enum GitHubAuthPolicy {
    static let hostname = "github.com"
    static let gitProtocol = "ssh"
    static let statusCommand = "gh auth status >/dev/null 2>&1"
    static let loginCommand = "gh auth login --hostname \(hostname) --web --git-protocol \(gitProtocol)"
}
