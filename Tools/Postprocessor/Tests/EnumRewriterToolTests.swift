// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import Testing
import Foundation
import SwiftParser
import SwiftSyntax

/// Tests that the postprocessor tool produces correct output.
///
/// These test the rewriting logic end-to-end by invoking the built binary.
@Suite("Postprocessor Tool Tests")
struct PostprocessorToolTests {

    /// Path to the built binary (assumes `swift build` has been run).
    private var toolPath: String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // Postprocessor/
        #if arch(arm64) && os(macOS)
        let triple = "arm64-apple-macosx"
        #elseif arch(x86_64) && os(Linux)
        let triple = "x86_64-unknown-linux-gnu"
        #elseif arch(arm64) && os(Linux)
        let triple = "aarch64-unknown-linux-gnu"
        #else
        let triple = "debug"
        #endif
        return packageRoot.appendingPathComponent(".build/\(triple)/debug/postprocessor").path
    }

    private func run(input: String) throws -> (stdout: String, stderr: String) {
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("enum-rewriter-test-\(UUID().uuidString).swift")
        try input.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = [tmpFile.path]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (stdout, stderr)
    }

    // MARK: - Basic rewriting

    @Test("Rewrites a simple String enum to a struct")
    func rewritesSimpleEnum() throws {
        let input = """
            @frozen public enum Status: String, Codable, Hashable, Sendable, CaseIterable {
                case active = "ACTIVE"
                case paused = "PAUSED"
            }
            """
        let (output, stderr) = try run(input: input)

        #expect(stderr.contains("Rewrote 1 enum"))
        #expect(output.contains("struct Status"))
        #expect(output.contains("RawRepresentable"))
        #expect(output.contains("static let active = Status(rawValue: \"ACTIVE\")"))
        #expect(output.contains("static let paused = Status(rawValue: \"PAUSED\")"))
        #expect(output.contains("init(from decoder: any Decoder)"))
        #expect(output.contains("func encode(to encoder: any Encoder)"))
        #expect(output.contains("static var allCases"))
        #expect(!output.contains("enum Status"))
    }

    // MARK: - CodingKeys are not rewritten

    @Test("Leaves CodingKeys enums untouched")
    func preservesCodingKeys() throws {
        let input = """
            public enum CodingKeys: String, CodingKey {
                case name
                case status
            }
            """
        let (output, stderr) = try run(input: input)

        #expect(stderr.contains("Rewrote 0 enum"))
        #expect(output.contains("enum CodingKeys"))
        #expect(!output.contains("struct CodingKeys"))
    }

    // MARK: - Nested enums

    @Test("Rewrites nested enums inside structs")
    func rewritesNestedEnums() throws {
        let input = """
            public struct Components {
                public enum Schemas {
                    @frozen public enum EventType: String, Codable, Hashable, Sendable, CaseIterable {
                        case create = "CREATE"
                        case delete = "DELETE"
                    }
                }
            }
            """
        let (output, stderr) = try run(input: input)

        #expect(stderr.contains("Rewrote 1 enum"))
        #expect(output.contains("struct EventType"))
        #expect(output.contains("static let create = EventType(rawValue: \"CREATE\")"))
        // Parent structures preserved
        #expect(output.contains("struct Components"))
        #expect(output.contains("enum Schemas"))
    }

    // MARK: - Non-Codable enums are not rewritten

    @Test("Leaves non-Codable String enums untouched")
    func preservesNonCodableEnums() throws {
        let input = """
            public enum Direction: String {
                case left
                case right
            }
            """
        let (output, stderr) = try run(input: input)

        #expect(stderr.contains("Rewrote 0 enum"))
        #expect(output.contains("enum Direction"))
        #expect(!output.contains("struct Direction"))
    }

    // MARK: - Cases without explicit raw values

    @Test("Handles cases without explicit raw values (uses case name)")
    func handlesImplicitRawValues() throws {
        let input = """
            @frozen public enum Color: String, Codable, Hashable, Sendable, CaseIterable {
                case red
                case green
                case blue
            }
            """
        let (output, stderr) = try run(input: input)

        #expect(stderr.contains("Rewrote 1 enum"))
        #expect(output.contains("static let red = Color(rawValue: \"red\")"))
        #expect(output.contains("static let green = Color(rawValue: \"green\")"))
        #expect(output.contains("static let blue = Color(rawValue: \"blue\")"))
    }

    // MARK: - Generated output compiles (parse check)

    @Test("Generated struct parses as valid Swift")
    func outputParsesCleanly() throws {
        let input = """
            @frozen public enum Status: String, Codable, Hashable, Sendable, CaseIterable {
                case active = "ACTIVE"
                case paused = "PAUSED"
                case deleted = "DELETED"
            }
            """
        let (output, _) = try run(input: input)

        let parsed = Parser.parse(source: output)
        // If it parsed without crashing and has statements, it's valid Swift
        #expect(!parsed.statements.isEmpty, "Output should parse as valid Swift")
    }

    // MARK: - Multiple enums in one file

    @Test("Rewrites multiple enums in a single file")
    func rewritesMultipleEnums() throws {
        let input = """
            @frozen public enum Status: String, Codable, Hashable, Sendable, CaseIterable {
                case active = "ACTIVE"
            }
            public enum CodingKeys: String, CodingKey {
                case id
            }
            @frozen public enum Priority: String, Codable, Hashable, Sendable, CaseIterable {
                case high = "HIGH"
                case low = "LOW"
            }
            """
        let (output, stderr) = try run(input: input)

        #expect(stderr.contains("Rewrote 2 enum"))
        #expect(output.contains("struct Status"))
        #expect(output.contains("struct Priority"))
        #expect(output.contains("enum CodingKeys"))
    }
}
