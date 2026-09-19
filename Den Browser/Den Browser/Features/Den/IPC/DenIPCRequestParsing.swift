import Foundation

nonisolated enum DenIPCRequestParsingError: Error, Equatable, LocalizedError, Sendable {
    case usage(String)
    case unknownGetTarget(String)
    case unknownElementState(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message):
            message
        case .unknownGetTarget(let target):
            "Unknown get target: \(target)"
        case .unknownElementState(let state):
            "Unknown element state: \(state)"
        }
    }
}

nonisolated enum DenSheetGetInput: Equatable, Sendable {
    case text(target: String)
    case value(target: String)
    case attribute(target: String, name: String)
    case count(selector: String)
    case box(target: String)

    init(args: [String]) throws {
        guard let kind = args.first?.lowercased() else {
            throw DenIPCRequestParsingError.usage("Usage: den sheet get <text|value|attr|count> ...")
        }

        switch kind {
        case "text":
            guard args.count == 2, let target = args.last, !target.isEmpty else {
                throw DenIPCRequestParsingError.usage("Usage: den sheet get text <@ref|selector>")
            }
            self = .text(target: target)

        case "value":
            guard args.count == 2, let target = args.last, !target.isEmpty else {
                throw DenIPCRequestParsingError.usage("Usage: den sheet get value <@ref|selector>")
            }
            self = .value(target: target)

        case "attr":
            guard args.count == 3 else {
                throw DenIPCRequestParsingError.usage(
                    "Usage: den sheet get attr <@ref|selector> <attribute>"
                )
            }
            let target = args[1]
            let attribute = args[2]
            guard !target.isEmpty, !attribute.isEmpty else {
                throw DenIPCRequestParsingError.usage(
                    "Usage: den sheet get attr <@ref|selector> <attribute>"
                )
            }
            self = .attribute(target: target, name: attribute)

        case "count":
            guard args.count == 2, let selector = args.last, !selector.isEmpty else {
                throw DenIPCRequestParsingError.usage("Usage: den sheet get count <selector>")
            }
            self = .count(selector: selector)

        case "box":
            guard args.count == 2, let target = args.last, !target.isEmpty else {
                throw DenIPCRequestParsingError.usage("Usage: den sheet get box <@ref|selector>")
            }
            self = .box(target: target)

        default:
            throw DenIPCRequestParsingError.unknownGetTarget(kind)
        }
    }
}

nonisolated enum DenSheetStateInput: Equatable, Sendable {
    case visible(target: String)
    case enabled(target: String)
    case checked(target: String)

    init(args: [String]) throws {
        guard args.count == 2 else {
            throw DenIPCRequestParsingError.usage(
                "Usage: den sheet is <visible|enabled|checked> <@ref|selector>"
            )
        }
        let state = args[0].lowercased()
        let target = args[1]
        guard !target.isEmpty else {
            throw DenIPCRequestParsingError.usage(
                "Usage: den sheet is <visible|enabled|checked> <@ref|selector>"
            )
        }

        switch state {
        case "visible":
            self = .visible(target: target)
        case "enabled":
            self = .enabled(target: target)
        case "checked":
            self = .checked(target: target)
        default:
            throw DenIPCRequestParsingError.unknownElementState(state)
        }
    }
}
