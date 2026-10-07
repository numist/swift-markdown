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

/// Replays the document regression pairs in `DocumentRegressions/`, one test case per pair.
///
/// Each pair is two files:
///   - `<name>.input`: the Markdown source bytes followed by one final byte, the `ParseOptions` raw value
///     to parse with. Invalid UTF-8 in the source decodes to U+FFFD.
///   - `<name>.expected`: the parsed document's `debugDescription(options: .printSourceLocations)`, as the
///     CommonMark spec and the GFM extensions define its structure and content.
struct DocumentRegressionTests {

    static let corpusDir: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DocumentRegressions")
    }()

    /// Basenames of every `<name>.input` file, sorted.
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

    /// Splits a pair's input into its Markdown source and the `ParseOptions` in its final byte.
    static func splitInput(_ bytes: [UInt8]) -> (markdown: String, options: ParseOptions)? {
        guard let optionBits = bytes.last else { return nil }
        let markdown = String(decoding: bytes.dropLast(), as: UTF8.self)
        return (markdown, ParseOptions(rawValue: UInt(optionBits)))
    }

    /// The parsed document's debug description, with source locations.
    static func surface(_ markdown: String, options: ParseOptions) -> String {
        return Document(parsing: markdown, options: options).debugDescription(options: .printSourceLocations)
    }

    // A parameterized test over an empty collection runs no cases and passes.
    @Test
    func corpusIsNonEmpty() {
        #expect(!Self.corpus.isEmpty, "no document regression pairs found in \(Self.corpusDir.path)")
    }

    @Test(arguments: corpus)
    func documentRegression(_ name: String) throws {
        let bytes = [UInt8](try Data(contentsOf: Self.corpusDir.appendingPathComponent("\(name).input")))
        let expected = try String(
            contentsOf: Self.corpusDir.appendingPathComponent("\(name).expected"), encoding: .utf8)

        let (markdown, options) = try #require(Self.splitInput(bytes), "\(name): empty input")
        let actual = Self.surface(markdown, options: options)

        #expect(actual == expected, """
            parsed document differs from \(name).expected

            input:    \(markdown.debugDescription) options=0x\(String(options.rawValue, radix: 16))

            expected:
            \(expected)

            got:
            \(actual)
            """)
    }
}
