/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Every U+0000 is replaced with U+FFFD (Insecure characters), on any line of a block and next to any kind of line
/// ending.
@Suite("NUL replacement across lines")
struct NULReplacementAcrossLinesTests {

    private func tree(_ source: String, options: MarkdownDocument.ParseOptions = []) -> String {
        TreeDump.dump(source, options: options.union(.sourcePosition), sourceRanges: true)
    }

    @Test("a NUL before each kind of line ending")
    func nulBeforeLineEndings() {
        #expect(tree("a\u{0}\nb\u{0}\rc\u{0}\r\nd\u{0}") == """
            document @1:1-4:3
              paragraph @1:1-4:3
                text "a\u{FFFD}" @1:1-1:3
                softbreak @-
                text "b\u{FFFD}" @2:1-2:3
                softbreak @-
                text "c\u{FFFD}" @3:1-3:3
                softbreak @-
                text "d\u{FFFD}" @4:1-4:3

            """)
    }

    @Test("a paragraph after one holding a NUL")
    func paragraphAfterNUL() {
        #expect(tree("a\u{0}\n\nb\n") == """
            document @1:1-4:1
              paragraph @1:1-1:3
                text "a\u{FFFD}" @1:1-1:3
              paragraph @3:1-3:2
                text "b" @3:1-3:2

            """)
    }

    @Test("a paragraph whose first line holds a NUL and whose last doesn't")
    func nulOnFirstParagraphLine() {
        #expect(tree("a\u{0}\nb") == """
            document @1:1-2:2
              paragraph @1:1-2:2
                text "a\u{FFFD}" @1:1-1:3
                softbreak @-
                text "b" @2:1-2:2

            """)
    }

    @Test("a block quote paragraph whose last line holds a NUL")
    func nulOnLastBlockQuoteLine() {
        #expect(tree("> a\n> b\u{0}") == """
            document @1:1-2:5
              block_quote @1:1-2:5
                paragraph @1:3-2:5
                  text "a" @1:3-1:4
                  softbreak @-
                  text "b\u{FFFD}" @2:3-2:5

            """)
    }

    @Test("fenced code lines with CRLF endings, one holding a NUL")
    func fencedCodeWithCRLF() {
        #expect(tree("```\r\na\u{0}b\r\nc\r\n```\r\n") == """
            document @1:1-5:1
              code_block "" "a\u{FFFD}b\\nc\\n" @1:1-4:4

            """)
    }

    @Test("a fenced code line holding a NUL in a block quote")
    func fencedCodeInBlockQuote() {
        #expect(tree("> ```\n> a\u{0}\n> ```") == """
            document @1:1-3:6
              block_quote @1:1-3:6
                code_block "" "a\u{FFFD}\\n" @1:3-3:6

            """)
    }

    @Test("an indented code line holding a NUL at the end of input")
    func indentedCodeAtEndOfInput() {
        #expect(tree("    x\u{0}") == """
            document @1:1-1:7
              code_block "" "x\u{FFFD}\\n" @1:5-1:7

            """)
    }

    @Test("an HTML block whose opening line holds a NUL")
    func htmlBlockOpeningLine() {
        #expect(tree("<div>\u{0}\n</div>") == """
            document @1:1-2:7
              html_block "<div>\u{FFFD}\\n</div>\\n" @1:1-2:7

            """)
    }

    @Test("a byte order mark before a NUL")
    func byteOrderMarkBeforeNUL() {
        #expect(tree("\u{FEFF}\u{0}") == """
            document @1:1-1:5
              paragraph @1:4-1:5
                text "\u{FFFD}" @1:4-1:5

            """)
    }

    @Test("an inline-only parse whose later line holds a NUL")
    func inlineOnlyLaterLine() {
        #expect(tree("a\nb\u{0}", options: [.inlineOnly]) == """
            document @1:1-2:3
              paragraph @1:1-2:3
                text "a\\nb\u{FFFD}" @1:1-2:3

            """)
    }
}
