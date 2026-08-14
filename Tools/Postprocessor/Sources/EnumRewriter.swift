// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import SwiftParser
import SwiftSyntax

/// Rewrites String-backed Codable enums into struct-based open enums that
/// decode unknown raw values without throwing.
///
/// Match criteria: has `String` raw type, conforms to `Codable`, and does not
/// conform to `CodingKey`. Non-matching enums are traversed so nested enums
/// within namespace types are still rewritten.
final class OpenEnumRewriter: SyntaxRewriter {
    private(set) var enumsRewritten = 0

    override func visit(_ node: EnumDeclSyntax) -> DeclSyntax {
        // Check if this enum qualifies else visit to find nested enums.
        guard let inheritance = node.inheritanceClause,
            isStringRawValueEnum(inheritance),
            conformsToCodable(inheritance),
            !conformsToCodingKey(inheritance)
        else {
            return super.visit(node)
        }

        let cases = extractCases(from: node)
        guard !cases.isEmpty else {
            return super.visit(node)
        }

        enumsRewritten += 1

        let structSource = generateStruct(
            name: node.name.text,
            cases: cases,
            access: accessLevel(of: node),
            leadingTrivia: node.leadingTrivia
        )

        let parsed = Parser.parse(source: structSource)
        if let stmt = parsed.statements.first,
            let decl = stmt.item.as(StructDeclSyntax.self)
        {
            // Preserve the original node's leading trivia (newlines, comments, indentation)
            let withTrivia = decl.with(\.leadingTrivia, node.leadingTrivia)
            return DeclSyntax(withTrivia)
        }
        // A failed rewrite means this enum would ship as a closed type that throws
        // on unknown values — the exact problem we exist to prevent. Fail loudly.
        fatalError("Failed to rewrite enum '\(node.name.text)' to struct")
    }

    // MARK: - Detection

    /// True if the inheritance clause includes `String` as a raw type.
    private func isStringRawValueEnum(_ clause: InheritanceClauseSyntax) -> Bool {
        clause.inheritedTypes.contains {
            $0.type.as(IdentifierTypeSyntax.self)?.name.text == "String"
        }
    }

    /// True if the inheritance clause includes `Codable` or `Decodable`.
    private func conformsToCodable(_ clause: InheritanceClauseSyntax) -> Bool {
        clause.inheritedTypes.contains {
            guard let name = $0.type.as(IdentifierTypeSyntax.self)?.name.text else {
                return false
            }
            return name == "Codable" || name == "Decodable"
        }
    }

    /// True if the inheritance clause includes `CodingKey`.
    private func conformsToCodingKey(_ clause: InheritanceClauseSyntax) -> Bool {
        clause.inheritedTypes.contains {
            $0.type.as(IdentifierTypeSyntax.self)?.name.text == "CodingKey"
        }
    }

    /// Extracts the access level modifier, defaulting to `internal` if none is present.
    private func accessLevel(of node: EnumDeclSyntax) -> String {
        for modifier in node.modifiers {
            switch modifier.name.text {
            case "public", "package", "internal", "fileprivate", "private":
                return modifier.name.text
            default:
                continue
            }
        }
        return "internal"
    }

    // MARK: - Case Extraction

    /// A single enum case with its Swift identifier and string raw value.
    private struct EnumCase {
        let name: String
        let rawValue: String
    }

    /// Pulls case names and raw values out of the enum declaration.
    ///
    /// Falls back to the case name itself when no explicit raw value is assigned.
    private func extractCases(from node: EnumDeclSyntax) -> [EnumCase] {
        var result: [EnumCase] = []
        for member in node.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in caseDecl.elements {
                let name = element.name.text
                let raw: String
                if let initClause = element.rawValue,
                    let literal = initClause.value.as(StringLiteralExprSyntax.self)
                {
                    raw = literal.segments.trimmedDescription
                } else {
                    raw = name
                }
                result.append(EnumCase(name: name, rawValue: raw))
            }
        }
        return result
    }

    // MARK: - Code Generation

    /// Produces the struct source text that replaces the original enum.
    ///
    /// Conforms to Codable, Hashable, Sendable, RawRepresentable, and CaseIterable.
    private func generateStruct(
        name: String,
        cases: [EnumCase],
        access: String,
        leadingTrivia: Trivia
    ) -> String {
        let a = access == "internal" ? "" : "\(access) "

        // Detect indentation from leading trivia (last spaces/tabs before the decl)
        let indent = extractIndentation(from: leadingTrivia)
        let inner = indent + "    "

        let statics =
            cases.map {
                // Escape quotes/backslashes in raw values to produce valid Swift string literals.
                let escaped = $0.rawValue.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                return "\(inner)\(a)static let \($0.name) = \(name)(rawValue: \"\(escaped)\")"
            }
            .joined(separator: "\n")

        let allCases = cases.map { ".\($0.name)" }.joined(separator: ", ")

        return """
            \(indent)\(a)struct \(name): Codable, Hashable, Sendable, RawRepresentable, CaseIterable {
            \(inner)\(a)let rawValue: String
            \(inner)\(a)init(rawValue: String) { self.rawValue = rawValue }
            \(statics)
            \(inner)\(a)init(from decoder: any Decoder) throws {
            \(inner)    self.rawValue = try decoder.singleValueContainer().decode(String.self)
            \(inner)}
            \(inner)\(a)func encode(to encoder: any Encoder) throws {
            \(inner)    var container = encoder.singleValueContainer()
            \(inner)    try container.encode(rawValue)
            \(inner)}
            \(inner)\(a)static var allCases: [\(name)] { [\(allCases)] }
            \(indent)}
            """
    }

    /// Extracts the indentation (spaces/tabs) from trivia so generated code
    /// aligns with the nesting level of the original enum.
    private func extractIndentation(from trivia: Trivia) -> String {
        for piece in trivia.reversed() {
            switch piece {
            case .spaces(let count):
                return String(repeating: " ", count: count)
            case .tabs(let count):
                return String(repeating: "\t", count: count)
            case .newlines, .carriageReturns, .carriageReturnLineFeeds:
                return ""
            default:
                continue
            }
        }
        return ""
    }
}
