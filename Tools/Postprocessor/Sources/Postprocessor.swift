// Copyright (c) 2026 Apple Inc. Licensed under MIT License.

import Foundation
import SwiftParser
import SwiftSyntax

@main
struct Postprocessor {
    static let usage = """
        Post-processes swift-openapi-generator output.

        Currently, rewrites any @frozen String-backed enums into struct-based
        open enums.

        USAGE: postprocessor <file.swift> [--in-place] [--help]

          --in-place    Rewrite the file in place (default: stdout)
          --help, -h    Show this message
        """

    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())

        if args.isEmpty || args.contains("--help") || args.contains("-h") {
            FileHandle.standardError.write(Data((usage + "\n").utf8))
            exit(args.isEmpty ? 1 : 0)
        }

        let filePath = args.first { !$0.hasPrefix("-") }

        guard let filePath else {
            FileHandle.standardError.write(Data((usage + "\n").utf8))
            exit(1)
        }

        let inPlace = args.contains("--in-place")

        let source = try String(contentsOfFile: filePath, encoding: .utf8)
        let tree = Parser.parse(source: source)

        let rewriter = OpenEnumRewriter(viewMode: .sourceAccurate)
        let result = rewriter.rewrite(tree)

        if inPlace {
            try result.description.write(toFile: filePath, atomically: true, encoding: .utf8)
        } else {
            print(result.description)
        }

        FileHandle.standardError.write(Data("Rewrote \(rewriter.enumsRewritten) enum(s) to open structs\n".utf8))
    }
}
