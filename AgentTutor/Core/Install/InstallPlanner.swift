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

    func resolvedPlan(selectedIDs: Set<String>, apiKey: String) throws -> [InstallItem] {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else {
            throw PlanValidationError.missingAPIKey
        }

        var selected = Set(catalog.filter { $0.isRequired }.map(\.id))
        selected.formUnion(selectedIDs)

        var queue = Array(selected)
        while let next = queue.popLast() {
            guard let item = catalog.first(where: { $0.id == next }) else {
                continue
            }
            for dependency in item.dependencies where !selected.contains(dependency) {
                guard catalog.contains(where: { $0.id == dependency }) else {
                    throw PlanValidationError.unknownDependency(parent: item.id, dependencyID: dependency)
                }
                selected.insert(dependency)
                queue.append(dependency)
            }
        }

        return catalog.filter { selected.contains($0.id) }
    }
}
