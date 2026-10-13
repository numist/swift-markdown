/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Storage growth for a paragraph whose single text run starts with content rewritten after its neighbours were
/// parsed, followed by many separate text pieces.
///
/// A resolved smart quote pair takes its final glyphs only once the paragraph's inlines are parsed. It precedes text
/// pieces that merge into one run - unmatched brackets, image openers, emphasis delimiters, apostrophes, link openers,
/// unresolved footnote references. Merging that run must store content in proportion to the input.
@Suite("Text runs merged after rewritten content store linear content")
struct RelocatedTextRunSegmentGrowthTests {

    /// A source of `prefix` followed by `count` copies of `unit`.
    struct RepeatedSource: Sendable, CustomTestStringConvertible {
        let prefix: String
        let unit: String
        let options: MarkdownDocument.ParseOptions
        /// The paragraph's text for three copies of `unit`.
        let text: String

        func source(count: Int) -> String {
            prefix + String(repeating: unit, count: count)
        }

        var testDescription: String {
            "\(prefix)\(unit)…"
        }
    }

    static let sources: [RepeatedSource] = [
        RepeatedSource(prefix: "\"\"", unit: "[a]", options: [.smart], text: "\u{201C}\u{201D}[a][a][a]"),
        RepeatedSource(prefix: "'x'", unit: "![a]", options: [.smart], text: "\u{2018}x\u{2019}![a]![a]![a]"),
        RepeatedSource(prefix: "''", unit: " _a", options: [.smart], text: "\u{2018}\u{2019} _a _a _a"),
        RepeatedSource(prefix: "''", unit: "a'", options: [.smart], text: "\u{2018}\u{2018}a\u{2019}a\u{2019}a\u{2019}"),
        RepeatedSource(prefix: "''", unit: "[a](", options: [.smart], text: "\u{2018}\u{2019}[a]([a]([a]("),
        RepeatedSource(prefix: "'x' ", unit: "x[^a]", options: [.smart, .footnotes], text: "\u{2018}x\u{2019} x[^a]x[^a]x[^a]"),
        RepeatedSource(prefix: "", unit: "x[^a]", options: [.footnotes], text: "x[^a]x[^a]x[^a]"),
        RepeatedSource(prefix: "", unit: "x![^a]", options: [.footnotes], text: "x![^a]x![^a]x![^a]"),
        RepeatedSource(prefix: "", unit: "x[\\^a]", options: [.footnotes], text: "x[^a]x[^a]x[^a]"),
    ]

    @Test("the text is one run", arguments: sources)
    func text(_ repeated: RepeatedSource) {
        #expect(TreeDump.dump(repeated.source(count: 3), options: repeated.options) == """
            document
              paragraph
                text "\(repeated.text)"

            """)
    }

    @Test("segment count grows linearly with the repetitions", arguments: sources)
    func linearSegments(_ repeated: RepeatedSource) {
        let source = repeated.source(count: 2000)
        let segments = MarkdownDocument.withParsedDocument(source, options: repeated.options) { $0._segmentCount }
        // A linear parse stores at most about two segments per byte for these inputs; the bound leaves headroom.
        #expect(segments <= 4 * source.utf8.count, "\(segments) segments for \(source.utf8.count) bytes")
    }
}
