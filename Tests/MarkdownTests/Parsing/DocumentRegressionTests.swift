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

/// Regression coverage for divergences found by the swift-markdown-difftest differential fuzzer.
///
/// Each case is a pair of files in `DocumentRegressions/`:
///   - `<name>.input`    — the raw fuzzer artifact bytes (`[markdown …][final byte = options]`).
///   - `<name>.expected` — the shipped parser's surface WITH source positions
///                         (`debugDescription(options: .printSourceLocations)`). Its structure + literal
///                         content match the cmark-gfm reference, except where cmark-gfm departs from the
///                         CommonMark/GFM spec; there it holds the spec-correct output. The positions are
///                         the rewrite's own byte projection (gated separately by the `*PositionEncoding`
///                         suites). This is the oracle; the parser must reproduce it.
///
/// `@Test(arguments:)` runs one case per pair, so a failure names the exact fixture. The input split
/// mirrors `DiffSupport.splitInput` (the fuzzer and `dump` build from it); MarkdownTests can't import
/// that package, so the equivalent is inlined here.
struct DocumentRegressionTests {

    static let corpusDir: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DocumentRegressions")
    }()

    /// Basenames of every `<name>.input` fixture, sorted. Built once from the filesystem so adding a
    /// pair to `DocumentRegressions/` automatically adds a test case with no code change.
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

    /// Split a raw artifact: the last byte is the `ParseOptions` raw value, the rest is the UTF-8 document
    /// (invalid sequences → U+FFFD).
    static func splitInput(_ bytes: [UInt8]) -> (markdown: String, options: ParseOptions)? {
        guard let optionBits = bytes.last else { return nil }
        let markdown = String(decoding: bytes.dropLast(), as: UTF8.self)
        return (markdown, ParseOptions(rawValue: UInt(optionBits)))
    }

    /// The shipped parser's surface for `markdown`, with source positions.
    static func surface(_ markdown: String, options: ParseOptions) -> String {
        return Document(parsing: markdown, options: options).debugDescription(options: .printSourceLocations)
    }

    /// A `@Test(arguments:)` over an empty collection silently runs zero cases and reports success, so
    /// the fixture set is guarded explicitly here: a broken path or empty directory fails loudly.
    @Test
    func corpusIsNonEmpty() {
        #expect(!Self.corpus.isEmpty, "no fuzz regression pairs found in \(Self.corpusDir.path)")
    }

    @Test(arguments: corpus)
    func documentRegression(_ name: String) throws {
        let bytes = [UInt8](try Data(contentsOf: Self.corpusDir.appendingPathComponent("\(name).input")))
        let expected = try String(
            contentsOf: Self.corpusDir.appendingPathComponent("\(name).expected"), encoding: .utf8)

        let (markdown, options) = try #require(Self.splitInput(bytes), "\(name): empty artifact")
        let actual = Self.surface(markdown, options: options)

        #expect(actual == expected, """
            surface diverges from reference for \(name)

            input:    \(markdown.debugDescription) options=0x\(String(options.rawValue, radix: 16))

            expected:
            \(expected)

            got:
            \(actual)
            """)
    }
}
