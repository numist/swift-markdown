/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A footnote-shaped bracket that crosses a line ending, beside a NUL (replaced by U+FFFD) and a checkbox that does not
/// begin its list item's first paragraph. The item is not a task list item (Task list items), and with no matching
/// definition the bracket is literal text.
@Suite("Cross-line footnote-shaped bracket beside replaced characters")
struct FootnoteBracketAcrossReplacedCharactersTests {

    @Test("a bracket continuing onto a line of replaced characters")
    func bracketBeforeReplacedCharacters() {
        #expect(TreeDump.dump("-\n  2\u{0} [x] [^\r\u{0}\u{0}\u{FFFD}]", options: [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .smart, .footnotes, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:7
              list bullet '-' tight @1:1-3:7
                item @1:1-3:7
                  paragraph @2:3-3:7
                    text "2\u{FFFD} [x] [^" @2:3-2:12
                    softbreak @-
                    text "\u{FFFD}\u{FFFD}\u{FFFD}]" @3:1-3:7

            """)
    }

    @Test("a bracket after a NUL, continued on the next line")
    func bracketAfterNULOnFirstLine() {
        #expect(TreeDump.dump("-\n  2\u{0} [x] [^\nabcdefghijkl]", options: [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .smart, .footnotes, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:14
              list bullet '-' tight @1:1-3:14
                item @1:1-3:14
                  paragraph @2:3-3:14
                    text "2\u{FFFD} [x] [^" @2:3-2:12
                    softbreak @-
                    text "abcdefghijkl]" @3:1-3:14

            """)
    }

    @Test("a bracket after a multibyte character, continued on the next line")
    func bracketAfterMultibyteCharacter() {
        #expect(TreeDump.dump("-\n  22\u{E9} [x] [^\nabcdefghijkl]", options: [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .smart, .footnotes, .sourcePosition], sourceRanges: true) == """
            document @1:1-3:14
              list bullet '-' tight @1:1-3:14
                item @1:1-3:14
                  paragraph @2:3-3:14
                    text "22\u{E9} [x] [^" @2:3-2:14
                    softbreak @-
                    text "abcdefghijkl]" @3:1-3:14

            """)
    }

    @Test("a lazy continuation line holding a NUL and a checkbox after an opened bracket")
    func lazyLineAfterBracket() {
        #expect(TreeDump.dump("- > [^abcdefgh\n  2\u{0} [x] b]", options: [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .smart, .footnotes, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:12
              list bullet '-' tight @1:1-2:12
                item @1:1-2:12
                  block_quote @1:3-2:12
                    paragraph @1:5-2:12
                      text "[^abcdefgh" @1:5-1:15
                      softbreak @-
                      text "2\u{FFFD} [x] b]" @2:3-2:12

            """)
    }

    @Test("the same with an escaped caret")
    func lazyLineAfterEscapedCaretBracket() {
        #expect(TreeDump.dump("- > [\\^abcdefgh\n  2\u{0} [x] b]", options: [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .smart, .footnotes, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:12
              list bullet '-' tight @1:1-2:12
                item @1:1-2:12
                  block_quote @1:3-2:12
                    paragraph @1:5-2:12
                      text "[^abcdefgh" @1:5-1:16
                      softbreak @-
                      text "2\u{FFFD} [x] b]" @2:3-2:12

            """)
    }

    @Test("a lazy continuation line after a short opened bracket")
    func lazyLineAfterShortBracket() {
        #expect(TreeDump.dump("- > [^a\n  2\u{0} [x] b]", options: [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .smart, .footnotes, .sourcePosition], sourceRanges: true) == """
            document @1:1-2:12
              list bullet '-' tight @1:1-2:12
                item @1:1-2:12
                  block_quote @1:3-2:12
                    paragraph @1:5-2:12
                      text "[^a" @1:5-1:8
                      softbreak @-
                      text "2\u{FFFD} [x] b]" @2:3-2:12

            """)
    }
}
