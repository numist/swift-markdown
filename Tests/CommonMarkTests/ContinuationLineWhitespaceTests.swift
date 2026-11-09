/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Every line of a paragraph after its first has its leading whitespace stripped (Paragraphs), including inside a
/// code span, link destination or link title that crosses the line ending. Each paragraph here begins in a list item,
/// holds a NUL, which is replaced by U+FFFD (Insecure characters), or a multibyte character, and holds a `[x]` that
/// does not begin the paragraph and so is text (Task list items (extension)).
@Suite("Leading whitespace of a paragraph's continuation lines")
struct ContinuationLineWhitespaceTests {

    private static let options: MarkdownDocument.ParseOptions = [.tasklist, .sourcePosition]

    /// The U+FFFD that replaces the NUL spans the NUL's one source byte.
    @Test func lineHoldingNULBeforeCheckbox() {
        #expect(TreeDump.dump("+\n  2\u{0} [x] *u*", options: Self.options, sourceRanges: true) == """
            document @1:1-2:13
              list bullet '+' tight @1:1-2:13
                item @1:1-2:13
                  paragraph @2:3-2:13
                    text "2\u{FFFD} [x] " @2:3-2:10
                    emph @2:10-2:13
                      text "u" @2:11-2:12

            """)
    }

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
