/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Footnote-shaped brackets nested many levels deep (Footnotes).
///
/// A `]` closes the innermost open `[^`, so an outer bracket's label spans every bracket nested inside it. A label has
/// at most 999 characters (Links), so an outer bracket is no label however deep the nesting, and 32,000 nested
/// brackets, about 96 KB of source, parse well within the time limit.
@Suite("Footnote brackets under deep nesting")
struct DeepFootnoteBracketNestingTests {
    private static let depth = 32_000
    private static let openers = String(repeating: "[^", count: depth)
    private static let closers = String(repeating: "]", count: depth)

    @Test(arguments: [MarkdownDocument.ParseOptions.footnotes, [.footnotes, .inlineOnly]])
    func nestedBracketsWithoutDefinitionAreText(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("[^[^[^x]]]", options: options) == """
            document
              paragraph
                text "[^[^[^x]]]"

            """)
    }

    @Test
    func innermostBracketWithDefinitionIsReference() {
        #expect(TreeDump.dump("[^[^[^x]]]\n\n[^x]: d", options: .footnotes) == """
            document
              paragraph
                text "[^[^"
                footnote_reference "1"
                text "]]"
              footnote_definition "x"
                paragraph
                  text "d"

            """)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [MarkdownDocument.ParseOptions.footnotes, [.footnotes, .inlineOnly]])
    func deeplyNestedBracketsWithoutDefinitionAreText(options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump(Self.openers + "x" + Self.closers, options: options) == """
            document
              paragraph
                text "\(Self.openers)x\(Self.closers)"

            """)
    }

    @Test(.timeLimit(.minutes(1)))
    func deeplyNestedInnermostBracketWithDefinitionIsReference() {
        #expect(TreeDump.dump(Self.openers + "x" + Self.closers + "\n\n[^x]: d", options: .footnotes) == """
            document
              paragraph
                text "\(Self.openers.dropLast(2))"
                footnote_reference "1"
                text "\(Self.closers.dropLast())"
              footnote_definition "x"
                paragraph
                  text "d"

            """)
    }
}
