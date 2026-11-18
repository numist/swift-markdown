/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Source ranges of email autolinks starting with an escape")
struct EscapedEmailAutolinkSourceRangeTests {

    private func tree(_ source: String, options: MarkdownDocument.ParseOptions = [.sourcePosition, .gfmAutolink]) -> String {
        TreeDump.dump(source, options: options, sourceRanges: true)
    }

    @Test("an address opening the paragraph")
    func openingParagraph() {
        #expect(tree("\\_a@b.co") == """
            document @1:1-1:9
              paragraph @1:1-1:9
                link "mailto:_a@b.co" "" @1:1-1:9
                  text "_a@b.co" @1:1-1:9

            """)
    }

    @Test("an address whose escaped first character is a hyphen")
    func escapedHyphen() {
        #expect(tree("\\-a@b.co") == """
            document @1:1-1:9
              paragraph @1:1-1:9
                link "mailto:-a@b.co" "" @1:1-1:9
                  text "-a@b.co" @1:1-1:9

            """)
    }

    @Test("an address after text")
    func afterText() {
        #expect(tree("x \\_a@b.co") == """
            document @1:1-1:11
              paragraph @1:1-1:11
                text "x " @1:1-1:3
                link "mailto:_a@b.co" "" @1:3-1:11
                  text "_a@b.co" @1:3-1:11

            """)
    }

    @Test("an address opening a continuation line")
    func openingContinuationLine() {
        #expect(tree("x\n\\_a@b.co y") == """
            document @1:1-2:11
              paragraph @1:1-2:11
                text "x" @1:1-1:2
                softbreak @-
                link "mailto:_a@b.co" "" @2:1-2:9
                  text "_a@b.co" @2:1-2:9
                text " y" @2:9-2:11

            """)
    }

    @Test("an address after an escaped backslash")
    func afterEscapedBackslash() {
        #expect(tree("\\\\_a@b.co") == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "\\\\" @1:1-1:3
                link "mailto:_a@b.co" "" @1:3-1:10
                  text "_a@b.co" @1:3-1:10

            """)
    }

    @Test("an address after an escaped backslash and an escape")
    func afterEscapedBackslashAndEscape() {
        #expect(tree("\\\\\\_a@b.co") == """
            document @1:1-1:11
              paragraph @1:1-1:11
                text "\\\\" @1:1-1:3
                link "mailto:_a@b.co" "" @1:3-1:11
                  text "_a@b.co" @1:3-1:11

            """)
    }

    @Test("an address after a CRLF line ending")
    func afterCRLF() {
        #expect(tree("x\r\n\\_a@b.co") == """
            document @1:1-2:9
              paragraph @1:1-2:9
                text "x" @1:1-1:2
                softbreak @-
                link "mailto:_a@b.co" "" @2:1-2:9
                  text "_a@b.co" @2:1-2:9

            """)
    }

    @Test("an address in a table cell")
    func inTableCell() {
        #expect(tree("|\\_a@b.co|\n|-|", options: [.sourcePosition, .gfmAutolink, .tables]) == """
            document @1:1-2:4
              table @1:1-2:4
                table_header @1:1-1:11
                  table_cell align=none colspan=1 rowspan=1 @1:2-1:10
                    link "mailto:_a@b.co" "" @1:2-1:10
                      text "_a@b.co" @1:2-1:10

            """)
    }

    @Test("an address after a backslash that escapes nothing")
    func afterLiteralBackslash() {
        #expect(tree("\\a@b.co") == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "\\\\" @1:1-1:2
                link "mailto:a@b.co" "" @1:2-1:8
                  text "a@b.co" @1:2-1:8

            """)
    }

    @Test("an address after text and a backslash that escapes nothing")
    func afterTextAndLiteralBackslash() {
        #expect(tree("x\\a@b.co") == """
            document @1:1-1:9
              paragraph @1:1-1:9
                text "x\\\\" @1:1-1:3
                link "mailto:a@b.co" "" @1:3-1:9
                  text "a@b.co" @1:3-1:9

            """)
    }

    @Test("an address starting with a digit after a backslash that escapes nothing")
    func digitAfterLiteralBackslash() {
        #expect(tree("\\1a@b.co") == """
            document @1:1-1:9
              paragraph @1:1-1:9
                text "\\\\" @1:1-1:2
                link "mailto:1a@b.co" "" @1:2-1:9
                  text "1a@b.co" @1:2-1:9

            """)
    }

    @Test("an address after an escaped backslash and a backslash that escapes nothing")
    func afterEscapedBackslashAndLiteralBackslash() {
        #expect(tree("\\\\\\a@b.co") == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "\\\\\\\\" @1:1-1:4
                link "mailto:a@b.co" "" @1:4-1:10
                  text "a@b.co" @1:4-1:10

            """)
    }
}
