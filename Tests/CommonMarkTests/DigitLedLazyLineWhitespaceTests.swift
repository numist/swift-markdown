/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A list item whose paragraph begins with a digit has no checkbox, because a task list item marker must begin the
/// item's first paragraph (Task list items (extension)); the `[x]` later on the line is paragraph text. Every following
/// line of the paragraph has its leading whitespace stripped (Paragraphs), including inside a code span, link
/// destination or link title that crosses the line ending.
@Suite("Digit-led paragraph with lazy continuation lines")
struct DigitLedLazyLineWhitespaceTests {

    private static let options: MarkdownDocument.ParseOptions = [
        .tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .gfmAutolink,
    ]

    @Test func multiByteLineLazySpaceCodeSpan() {
        #expect(TreeDump.dump("+\n  22é [x] `\n `", options: Self.options) == """
            document
              list bullet '+' tight
                item
                  paragraph
                    text "22é [x] "
                    code " "

            """)
    }

    @Test func tabLedLazyLine() {
        #expect(TreeDump.dump("+\n  2\u{0} [x] `\n\t`", options: Self.options) == """
            document
              list bullet '+' tight
                item
                  paragraph
                    text "2\u{FFFD} [x] "
                    code " "

            """)
    }

    /// The item's first block is a block quote, so the item has no checkbox, and line 2 is a lazy continuation line
    /// of the block quote's paragraph.
    @Test func lazyBlockQuoteLineCodeSpan() {
        #expect(TreeDump.dump("- > a\n  2\u{0} [x] `\n `", options: Self.options) == """
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

    @Test func twoSpaceLazyLineCodeSpan() {
        #expect(TreeDump.dump(" +\n   2\u{0} [x] `\n  `", options: Self.options) == """
            document
              list bullet '+' tight
                item
                  paragraph
                    text "2\u{FFFD} [x] "
                    code " "

            """)
    }

    @Test func lazyLineImageTitle() {
        #expect(TreeDump.dump("+\n  2\u{0} [x] ![a](b \"c\n d\")", options: Self.options) == """
            document
              list bullet '+' tight
                item
                  paragraph
                    text "2\u{FFFD} [x] "
                    image "b" "c\\nd"
                      text "a"

            """)
    }

    @Test func lazyLineLinkDestination() {
        #expect(TreeDump.dump("+\n  2\u{0} [x] [a](\n b)", options: Self.options) == """
            document
              list bullet '+' tight
                item
                  paragraph
                    text "2\u{FFFD} [x] "
                    link "b" ""
                      text "a"

            """)
    }

    @Test func secondLazyLineCodeSpan() {
        #expect(TreeDump.dump("+\n  2\u{0} [x] `\n a\n `", options: Self.options) == """
            document
              list bullet '+' tight
                item
                  paragraph
                    text "2\u{FFFD} [x] "
                    code "a"

            """)
    }

    @Test func matchedContinuation() {
        #expect(TreeDump.dump("+\n  2\u{0} [x] `\n   `", options: Self.options) == """
            document
              list bullet '+' tight
                item
                  paragraph
                    text "2\u{FFFD} [x] "
                    code " "

            """)
    }

    @Test func lazyLineAfterSoftBreak() {
        #expect(TreeDump.dump("+\n  2\u{0} [x] a\n b", options: Self.options) == """
            document
              list bullet '+' tight
                item
                  paragraph
                    text "2\u{FFFD} [x] a"
                    softbreak
                    text "b"

            """)
    }

    @Test func lazyLineAfterBackslashBreak() {
        #expect(TreeDump.dump("+\n  2\u{0} [x] a\\\n b", options: Self.options) == """
            document
              list bullet '+' tight
                item
                  paragraph
                    text "2\u{FFFD} [x] a"
                    linebreak
                    text "b"

            """)
    }

    @Test func tabLazyLineCodeSpan() {
        #expect(TreeDump.dump("100.\n     2\u{0} [x] `\n \t`", options: Self.options) == """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "2\u{FFFD} [x] "
                    code " "

            """)
    }

    @Test func splitTabLazyLineCodeSpan() {
        #expect(TreeDump.dump("+ 100.\n       2\u{0} [x] `\n \t`", options: Self.options) == """
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
