/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges of the text that `.smart` rewrites: an ellipsis, en and em dashes, and curly quotes each span the
/// source bytes they replace, so the text they merge into keeps those bytes' columns. Columns are 1-based UTF-8 byte
/// offsets and each end is half-open.
@Suite("Source ranges of smart punctuation")
struct SmartPunctuationSourceRangeTests {

    private func tree(_ source: String) -> String {
        CmarkTreeDump.dump(source, options: [.smart, .sourcePosition], sourceRanges: true)
    }

    @Test("an ellipsis that starts a text spans its three dots")
    func leadingEllipsis() {
        #expect(tree("...a") == """
            document @1:1-1:5
              paragraph @1:1-1:5
                text "…a" @1:1-1:5

            """)
    }

    @Test("an ellipsis that ends a text spans its three dots")
    func trailingEllipsis() {
        #expect(tree("a...") == """
            document @1:1-1:5
              paragraph @1:1-1:5
                text "a…" @1:1-1:5

            """)
    }

    @Test("an ellipsis alone in emphasis spans its three dots")
    func ellipsisInEmphasis() {
        #expect(tree("*...*") == """
            document @1:1-1:6
              paragraph @1:1-1:6
                emph @1:1-1:6
                  text "…" @1:2-1:5

            """)
    }

    @Test("an en dash spans its two hyphens")
    func enDash() {
        #expect(tree("a--b") == """
            document @1:1-1:5
              paragraph @1:1-1:5
                text "a–b" @1:1-1:5

            """)
    }

    @Test("an em dash spans its three hyphens")
    func emDash() {
        #expect(tree("a---b") == """
            document @1:1-1:6
              paragraph @1:1-1:6
                text "a—b" @1:1-1:6

            """)
    }

    @Test("curly double quotes span their straight quotes")
    func doubleQuotes() {
        #expect(tree("\"q\"") == """
            document @1:1-1:4
              paragraph @1:1-1:4
                text "“q”" @1:1-1:4

            """)
    }

    @Test("curly single quotes span their straight quotes")
    func singleQuotes() {
        #expect(tree("'q'") == """
            document @1:1-1:4
              paragraph @1:1-1:4
                text "‘q’" @1:1-1:4

            """)
    }

    @Test("an ellipsis that starts a list item's text spans its three dots")
    func leadingEllipsisInListItem() {
        #expect(tree("- ...a") == """
            document @1:1-1:7
              list bullet '-' tight @1:1-1:7
                item @1:1-1:7
                  paragraph @1:3-1:7
                    text "…a" @1:3-1:7

            """)
    }

    @Test("an ellipsis that ends a list item's text spans its three dots")
    func trailingEllipsisInListItem() {
        #expect(tree("- a...") == """
            document @1:1-1:7
              list bullet '-' tight @1:1-1:7
                item @1:1-1:7
                  paragraph @1:3-1:7
                    text "a…" @1:3-1:7

            """)
    }

    @Test("an ellipsis alone in emphasis in a list item spans its three dots")
    func ellipsisInEmphasisInListItem() {
        #expect(tree("- *...*") == """
            document @1:1-1:8
              list bullet '-' tight @1:1-1:8
                item @1:1-1:8
                  paragraph @1:3-1:8
                    emph @1:3-1:8
                      text "…" @1:4-1:7

            """)
    }

    @Test("an en dash in a list item spans its two hyphens")
    func enDashInListItem() {
        #expect(tree("- a--b") == """
            document @1:1-1:7
              list bullet '-' tight @1:1-1:7
                item @1:1-1:7
                  paragraph @1:3-1:7
                    text "a–b" @1:3-1:7

            """)
    }

    @Test("an em dash in a list item spans its three hyphens")
    func emDashInListItem() {
        #expect(tree("- a---b") == """
            document @1:1-1:8
              list bullet '-' tight @1:1-1:8
                item @1:1-1:8
                  paragraph @1:3-1:8
                    text "a—b" @1:3-1:8

            """)
    }

    @Test("curly double quotes in a list item span their straight quotes")
    func doubleQuotesInListItem() {
        #expect(tree("- \"q\"") == """
            document @1:1-1:6
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  paragraph @1:3-1:6
                    text "“q”" @1:3-1:6

            """)
    }

    @Test("curly single quotes in a list item span their straight quotes")
    func singleQuotesInListItem() {
        #expect(tree("- 'q'") == """
            document @1:1-1:6
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  paragraph @1:3-1:6
                    text "‘q’" @1:3-1:6

            """)
    }

    /// The second line is a block-quote continuation, so the paragraph's lines are not contiguous in the source.
    @Test("an ellipsis on a block quote's continuation line spans its three dots")
    func ellipsisOnContinuationLine() {
        #expect(tree("> a\n> ...b") == """
            document @1:1-2:7
              block_quote @1:1-2:7
                paragraph @1:3-2:7
                  text "a" @1:3-1:4
                  softbreak @-
                  text "…b" @2:3-2:7

            """)
    }

    /// A NUL makes the paragraph's content an arena copy, read back to the source through its run map.
    @Test("an ellipsis in content holding a NUL spans its three dots")
    func ellipsisInArenaContent() {
        #expect(tree("\u{0} *...*") == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "\u{FFFD} " @1:1-1:3
                emph @1:3-1:8
                  text "…" @1:4-1:7

            """)
    }
}
