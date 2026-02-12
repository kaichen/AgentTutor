import Foundation

enum PlanValidationError: LocalizedError, Equatable {
    case missingAPIKey
    case unknownDependency(parent: String, dependencyID: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is required before starting installation."
        case let .unknownDependency(parent, dependencyID):
            return "Configuration error: \(parent) depends on missing item \(dependencyID)."
        }
    }
}

struct InstallPlanner {
    let catalog: [InstallItem]

    func resolvedPlan(
        selectedIDs: Set<String>,
        apiKey: String,
        architecture: MacSystemArchitecture = .current
    ) throws -> [InstallItem] {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            throw PlanValidationError.missingAPIKey
        }

        let supportedCatalog = catalog.filter { $0.supports(architecture) }
        let supportedItemsByID = Dictionary(uniqueKeysWithValues: supportedCatalog.map { ($0.id, $0) })
        let supportedIDs = Set(supportedItemsByID.keys)

        var selected = Set(supportedCatalog.filter { $0.isRequired }.map(\.id))
        selected.formUnion(selectedIDs.intersection(supportedIDs))

        var queue = Array(selected)
        while let next = queue.popLast() {
            guard let item = supportedItemsByID[next] else {
                continue
            }
            for dependency in item.dependencies where !selected.contains(dependency) {
                guard supportedItemsByID[dependency] != nil else {
                    throw PlanValidationError.unknownDependency(parent: item.id, dependencyID: dependency)
                }
                selected.insert(dependency)
                queue.append(dependency)
            }
        }

        return supportedCatalog.filter { selected.contains($0.id) }
    }
}
