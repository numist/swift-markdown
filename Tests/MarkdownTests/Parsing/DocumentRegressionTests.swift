/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation
import Markdown
import Testing

struct DocumentRegressionTests {

    static let corpusDir: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DocumentRegressions")
    }()

    static let corpus: [String] = {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: corpusDir, includingPropertiesForKeys: nil
        ) else {
            fatalError("Failed to enumerate DocumentRegressions corpus at \(corpusDir.path)")
        }
        return contents.filter { $0.pathExtension == "input" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }()

    static func splitInput(_ bytes: [UInt8]) -> (markdown: String, options: ParseOptions)? {
        guard let optionBits = bytes.last else { return nil }
        let markdown = String(decoding: bytes.dropLast(), as: UTF8.self)
        return (markdown, ParseOptions(rawValue: UInt(optionBits)))
    }

    static func tree(_ markdown: String, options: ParseOptions) -> String {
        return Document(parsing: markdown, options: options).debugDescription(options: .printSourceLocations)
    }

    static let deepTreePairs: Set<String> = ["deepnest-empty-doc"]

    // A `@Test(arguments:)` over an empty collection runs zero cases and reports success, so this pins the number of
    // pairs.
    @Test
    func corpusHasEveryPair() {
        #expect(Self.corpus.count == 677, "unexpected pair count in \(Self.corpusDir.path)")
        #expect(Self.deepTreePairs.isSubset(of: Self.corpus))
    }

    @Test(arguments: corpus.filter { !deepTreePairs.contains($0) })
    func documentRegression(_ name: String) throws {
        let bytes = [UInt8](try Data(contentsOf: Self.corpusDir.appendingPathComponent("\(name).input")))
        let expected = try String(
            contentsOf: Self.corpusDir.appendingPathComponent("\(name).expected"), encoding: .utf8)

        let (markdown, options) = try #require(Self.splitInput(bytes), "\(name): empty input")
        let actual = Self.tree(markdown, options: options)

        #expect(actual == expected, """
            parsed document differs from \(name).expected

            input:    \(markdown.debugDescription) options=0x\(String(options.rawValue, radix: 16))

            expected:
            \(expected)

            got:
            \(actual)
            """)
    }

    @Test(.disabled("The recursive tree dumper overflows the stack on deep trees."), arguments: deepTreePairs.sorted())
    func deepTreeDocumentRegression(_ name: String) throws {
        try documentRegression(name)
    }
}
