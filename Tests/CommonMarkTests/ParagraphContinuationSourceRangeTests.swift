/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A paragraph continuation line's text starts at the line's first non-whitespace byte, wherever that falls relative to
/// the paragraph's first line, since the line's initial whitespace is not part of the paragraph's content (Paragraphs).
@Suite("Paragraph continuation line source ranges")
struct ParagraphContinuationSourceRangeTests {

    private static let options: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    @Test("top-level continuation line text starts after its leading whitespace")
    func topLevelContinuation() {
        #expect(TreeDump.dump("foo\n   bar", options: Self.options, sourceRanges: true) == """
            document @1:1-2:7
              paragraph @1:1-2:7
                text "foo" @1:1-1:4
                softbreak @-
                text "bar" @2:4-2:7

            """)
    }

    /// The block quote marker takes `>` and one space, and the remaining three spaces are the paragraph line's
    /// initial whitespace, so `bar` starts at column 6.
    @Test("block quote continuation line text starts after its leading whitespace")
    func blockquoteContinuation() {
        #expect(TreeDump.dump("> foo\n>    bar", options: Self.options, sourceRanges: true) == """
            document @1:1-2:9
              block_quote @1:1-2:9
                paragraph @1:3-2:9
                  text "foo" @1:3-1:6
                  softbreak @-
                  text "bar" @2:6-2:9

            """)
    }

    @Test("lazy continuation line in a block quote starts at column 1")
    func lazyBlockquoteContinuation() {
        #expect(TreeDump.dump("> bar\nbaz", options: Self.options, sourceRanges: true) == """
            document @1:1-2:4
              block_quote @1:1-2:4
                paragraph @1:3-2:4
                  text "bar" @1:3-1:6
                  softbreak @-
                  text "baz" @2:1-2:4

            """)
    }

    @Test("consecutive lazy continuation lines each start at column 1")
    func lazyMultilineContinuation() {
        #expect(TreeDump.dump("> bar\nbaz\nqux", options: Self.options, sourceRanges: true) == """
            document @1:1-3:4
              block_quote @1:1-3:4
                paragraph @1:3-3:4
                  text "bar" @1:3-1:6
                  softbreak @-
                  text "baz" @2:1-2:4
                  softbreak @-
                  text "qux" @3:1-3:4

            """)
    }

    @Test("indented lazy continuation line in a block quote starts after its leading whitespace")
    func lazyBlockquoteContinuationWithLeadingWhitespace() {
        #expect(TreeDump.dump("> foo\n  baz", options: Self.options, sourceRanges: true) == """
            document @1:1-2:6
              block_quote @1:1-2:6
                paragraph @1:3-2:6
                  text "foo" @1:3-1:6
                  softbreak @-
                  text "baz" @2:3-2:6

            """)
    }

    /// One space is less than the item's content indent of two, so ` bar` is a lazy continuation line (List items).
    @Test("lazy continuation line in a list item starts after its leading whitespace")
    func lazyListContinuation() {
        #expect(TreeDump.dump("- foo\n bar", options: Self.options, sourceRanges: true) == """
            document @1:1-2:5
              list bullet '-' tight @1:1-2:5
                item @1:1-2:5
                  paragraph @1:3-2:5
                    text "foo" @1:3-1:6
                    softbreak @-
                    text "bar" @2:2-2:5

            """)
    }

    /// Line 2 matches the outer block quote marker only, so `baz` is a lazy continuation line of the inner block
    /// quote's paragraph.
    @Test("lazy continuation line in a nested block quote starts after its leading whitespace")
    func lazyNestedBlockquoteContinuation() {
        #expect(TreeDump.dump("> > foo\n>  baz", options: Self.options, sourceRanges: true) == """
            document @1:1-2:7
              block_quote @1:1-2:7
                block_quote @1:3-2:7
                  paragraph @1:5-2:7
                    text "foo" @1:5-1:8
                    softbreak @-
                    text "baz" @2:4-2:7

            """)
    }
}
