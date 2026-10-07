/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Inline-only parsing merges adjacent text nodes, so a delimiter or bracket that opens nothing, an entity reference and
/// a backslash escape join the text around them.
@Suite("Inline-only text consolidation")
struct InlineOnlyTextConsolidationTests {

    private static let inlineOnly: MarkdownDocument.ParseOptions = [
        .tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .inlineOnly,
    ]

    private static let preserveWhitespace: MarkdownDocument.ParseOptions = [
        .tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .preserveWhitespace,
    ]

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func failedEmphasisRunMerges(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("*a", options: options) == """
            document
              paragraph
                text "*a"

            """)
        #expect(CmarkTreeDump.dump("a*b", options: options) == """
            document
              paragraph
                text "a*b"

            """)
        #expect(CmarkTreeDump.dump("a_b_", options: options) == """
            document
              paragraph
                text "a_b_"

            """)
        #expect(CmarkTreeDump.dump("**a", options: options) == """
            document
              paragraph
                text "**a"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func failedBracketMerges(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("a ]b", options: options) == """
            document
              paragraph
                text "a ]b"

            """)
        #expect(CmarkTreeDump.dump("![x", options: options) == """
            document
              paragraph
                text "![x"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func entityMergesWithAdjacentText(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("&copy;x", options: options) == """
            document
              paragraph
                text "©x"

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func backslashEscapeMergesWithAdjacentText(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("\\_x", options: options) == """
            document
              paragraph
                text "_x"

            """)
        #expect(CmarkTreeDump.dump("a\\qb", options: options) == """
            document
              paragraph
                text "a\\\\qb"

            """)
    }

    @Test func preservedNewlineMergesWithAdjacentText() {
        #expect(CmarkTreeDump.dump("_\nb", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "_\\nb"

            """)
        #expect(CmarkTreeDump.dump("a\n&amp;\nb", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "a\\n&\\nb"

            """)
        #expect(CmarkTreeDump.dump("a\n[b", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "a\\n[b"

            """)
    }
}
