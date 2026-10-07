/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A list item whose paragraph begins with a digit and a NUL or multi-byte character before `[x]`, continued by lazy
/// lines: the item has no checkbox, and each continuation line's leading whitespace is stripped (spec "Paragraphs";
/// GFM "Task list items").
@Suite("Digit-led paragraph with lazy continuation lines")
struct DigitLedLazyLineWhitespaceTests {

    private static let options: MarkdownDocument.ParseOptions = [
        .tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .gfmAutolink,
    ]

    /// Flag-off (spec-correct): a paragraph beginning `22` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the lazy line's leading whitespace is stripped like any
    /// paragraph line's (CommonMark paragraphs), leaving a one-space code span, where cmark's later-line
    /// checkbox retry checks the item and keeps the lazy line's leading whitespace.
    @Test func multiByteLineLazySpaceCodeSpanFlagOff() {
        #expect(CmarkTreeDump.dump("+\n  22é [x] `\n `", options: Self.options) == """
            document
              list bullet '+' tight
                item
                  paragraph
                    text "22é [x] "
                    code " "

            """)
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the lazy line's leading whitespace is stripped like any
    /// paragraph line's (CommonMark paragraphs), leaving a one-space code span, where cmark's later-line
    /// checkbox retry checks the item and keeps the lazy line's leading whitespace.
    @Test func tabLedLazyLineFlagOff() {
        #expect(CmarkTreeDump.dump("+\n  2\u{0} [x] `\n\t`", options: Self.options) == """
            document
              list bullet '+' tight
                item
                  paragraph
                    text "2\u{FFFD} [x] "
                    code " "

            """)
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote), and the lazy
    /// line keeps its `2` prefix while the next line loses its leading whitespace (CommonMark paragraphs),
    /// where cmark's later-line checkbox retry checks the item and drops the advanced bytes.
    @Test func lazyBlockQuoteLineCodeSpanFlagOff() {
        #expect(CmarkTreeDump.dump("- > a\n  2\u{0} [x] `\n `", options: Self.options) == """
            document
              list bullet '-' tight
                item
                  block_quote
                    paragraph
                      text "a"
                      softbreak
                      text "2\u{FFFD} [x] "
                      code " "

            """)
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the lazy line's leading whitespace is stripped like any
    /// paragraph line's (CommonMark paragraphs), leaving a one-space code span, where cmark's later-line
    /// checkbox retry checks the item and keeps the lazy line's leading whitespace.
    @Test func twoSpaceLazyLineCodeSpanFlagOff() {
        #expect(CmarkTreeDump.dump(" +\n   2\u{0} [x] `\n  `", options: Self.options) == """
            document
              list bullet '+' tight
                item
                  paragraph
                    text "2\u{FFFD} [x] "
                    code " "

            """)
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the lazy line's leading whitespace is stripped like any
    /// paragraph line's (CommonMark paragraphs) inside the image title, where cmark's later-line checkbox
    /// retry checks the item and keeps the lazy line's leading whitespace.
    @Test func lazyLineImageTitleFlagOff() {
        #expect(CmarkTreeDump.dump("+\n  2\u{0} [x] ![a](b \"c\n d\")", options: Self.options) == """
            document
              list bullet '+' tight
                item
                  paragraph
                    text "2\u{FFFD} [x] "
                    image "b" "c\\nd"
                      text "a"

            """)
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the link destination follows the line ending, where cmark's
    /// later-line checkbox retry checks the item and keeps the lazy line's leading whitespace.
    @Test func lazyLineLinkDestinationFlagOff() {
        #expect(CmarkTreeDump.dump("+\n  2\u{0} [x] [a](\n b)", options: Self.options) == """
            document
              list bullet '+' tight
                item
                  paragraph
                    text "2\u{FFFD} [x] "
                    link "b" ""
                      text "a"

            """)
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the lazy lines' leading whitespace is stripped like any
    /// paragraph line's (CommonMark paragraphs), leaving the code span `a`, where cmark's later-line
    /// checkbox retry checks the item and keeps the lazy line's leading whitespace.
    @Test func secondLazyLineCodeSpanFlagOff() {
        #expect(CmarkTreeDump.dump("+\n  2\u{0} [x] `\n a\n `", options: Self.options) == """
            document
              list bullet '+' tight
                item
                  paragraph
                    text "2\u{FFFD} [x] "
                    code "a"

            """)
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the continuation line's extra indent is stripped like any
    /// paragraph line's (CommonMark paragraphs), leaving a one-space code span, where cmark's later-line
    /// checkbox retry checks the item and keeps the lazy line's leading whitespace.
    @Test func matchedContinuationFlagOff() {
        #expect(CmarkTreeDump.dump("+\n  2\u{0} [x] `\n   `", options: Self.options) == """
            document
              list bullet '+' tight
                item
                  paragraph
                    text "2\u{FFFD} [x] "
                    code " "

            """)
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the lazy line's leading whitespace is stripped like any
    /// paragraph line's (CommonMark paragraphs), where cmark's later-line checkbox retry checks the item
    /// and keeps the lazy line's leading whitespace.
    @Test func lazyLineAfterSoftBreakFlagOff() {
        #expect(CmarkTreeDump.dump("+\n  2\u{0} [x] a\n b", options: Self.options) == """
            document
              list bullet '+' tight
                item
                  paragraph
                    text "2\u{FFFD} [x] a"
                    softbreak
                    text "b"

            """)
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the lazy line's leading whitespace is stripped like any
    /// paragraph line's (CommonMark paragraphs) after the hard line break, where cmark's later-line
    /// checkbox retry checks the item and keeps the lazy line's leading whitespace.
    @Test func lazyLineAfterBackslashBreakFlagOff() {
        #expect(CmarkTreeDump.dump("+\n  2\u{0} [x] a\\\n b", options: Self.options) == """
            document
              list bullet '+' tight
                item
                  paragraph
                    text "2\u{FFFD} [x] a"
                    linebreak
                    text "b"

            """)
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the lazy line's leading whitespace is stripped like any
    /// paragraph line's (CommonMark paragraphs), leaving a one-space code span, where cmark's later-line
    /// checkbox retry checks the item and keeps the lazy line's leading whitespace.
    @Test func tabLazyLineCodeSpanFlagOff() {
        #expect(CmarkTreeDump.dump("100.\n     2\u{0} [x] `\n \t`", options: Self.options) == """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "2\u{FFFD} [x] "
                    code " "

            """)
    }

    /// Flag-off (spec-correct): a paragraph beginning `2` has no task list item marker (GFM task list
    /// items), so the item has no checkbox, and the lazy line's leading whitespace is stripped like any
    /// paragraph line's (CommonMark paragraphs), leaving a one-space code span, where cmark's later-line
    /// checkbox retry checks the item and keeps the lazy line's leading whitespace.
    @Test func splitTabLazyLineCodeSpanFlagOff() {
        #expect(CmarkTreeDump.dump("+ 100.\n       2\u{0} [x] `\n \t`", options: Self.options) == """
            document
              list bullet '+' tight
                item
                  list ordered start=100 delim=period tight
                    item
                      paragraph
                        text "2\u{FFFD} [x] "
                        code " "

            """)
    }
}
