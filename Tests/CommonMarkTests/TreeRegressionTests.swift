/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Foundation
import Testing

/// Whole-tree regression cases, one per pair of files in `TreeRegressions/`:
///   - `<name>.input`    — the markdown followed by one byte that selects the parse options (see `splitInput`).
///   - `<name>.expected` — the `CmarkTreeDump` of the parsed tree, with source ranges.
@Suite("Tree regressions")
struct TreeRegressionTests {

    static let corpusDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("TreeRegressions")

    /// Basenames of every `<name>.input` fixture, sorted.
    static let corpus: [String] = {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: corpusDir, includingPropertiesForKeys: nil
        ) else {
            fatalError("Failed to enumerate TreeRegressions corpus at \(corpusDir.path)")
        }
        return contents.filter { $0.pathExtension == "input" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }()

    /// Splits an input file into its markdown (invalid UTF-8 becomes U+FFFD) and parse options.
    ///
    /// Every case parses with tables, strikethrough, task lists, table spans, inline attributes and source positions.
    /// The final byte adds to those: bit 2 turns smart punctuation off, bit 5 selects `inlineOnly` (or
    /// `preserveWhitespace` when bit 4 is also set), bit 6 enables `gfmAutolink` and bit 7 enables `footnotes`.
    static func splitInput(_ bytes: [UInt8]) -> (markdown: String, options: MarkdownDocument.ParseOptions)? {
        guard let optionBits = bytes.last else { return nil }
        let markdown = String(decoding: bytes.dropLast(), as: UTF8.self)
        var options: MarkdownDocument.ParseOptions = [
            .tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition,
        ]
        if optionBits & 0b0000_0100 == 0 {
            options.insert(.smart)
        }
        if optionBits & 0b0010_0000 != 0 {
            options.insert(optionBits & 0b0001_0000 != 0 ? .preserveWhitespace : .inlineOnly)
        }
        if optionBits & 0b0100_0000 != 0 {
            options.insert(.gfmAutolink)
        }
        if optionBits & 0b1000_0000 != 0 {
            options.insert(.footnotes)
        }
        return (markdown, options)
    }

    /// A `@Test(arguments:)` over an empty collection runs zero cases and reports success, so an empty or missing
    /// fixture directory fails here instead.
    @Test
    func corpusHasEveryPair() {
        #expect(Self.corpus.count == 117, "unexpected pair count in \(Self.corpusDir.path)")
    }

    @Test(arguments: corpus)
    func treeRegression(_ name: String) throws {
        let bytes = [UInt8](try Data(contentsOf: Self.corpusDir.appendingPathComponent("\(name).input")))
        let expected = try String(
            contentsOf: Self.corpusDir.appendingPathComponent("\(name).expected"), encoding: .utf8)

        let (markdown, options) = try #require(Self.splitInput(bytes), "\(name): empty input")
        let actual = CmarkTreeDump.dump(markdown, options: options, sourceRanges: true)

        #expect(actual == expected, """
            tree differs for \(name)

            input:    \(markdown.debugDescription) options=0x\(String(options.rawValue, radix: 16))

            expected:
            \(expected)

            got:
            \(actual)
            """)
    }
}
