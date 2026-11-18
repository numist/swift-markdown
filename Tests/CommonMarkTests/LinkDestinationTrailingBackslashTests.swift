/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

// A backslash before a line ending in a link destination is a literal backslash (Backslash escapes), and a link
// destination cannot contain a line ending (Links), so the destination ends with that backslash.
@Suite("Link destination trailing backslash")
struct LinkDestinationTrailingBackslashTests {

    @Test("a link reference definition whose destination is one backslash ends at the line ending")
    func refDefBareTrailingBackslash() {
        #expect(TreeDump.dump("[b]:\\\n]\n\n[b]", options: []) == """
            document
              paragraph
                text "]"
              paragraph
                link "\\\\" ""
                  text "b"

            """)
    }

    @Test("a link reference definition destination ending in a backslash after text ends at the line ending")
    func refDefTrailingBackslashAfterText() {
        #expect(TreeDump.dump("[b]:a\\\nx\n\n[b]", options: []) == """
            document
              paragraph
                text "x"
              paragraph
                link "a\\\\" ""
                  text "b"

            """)
    }

    @Test("a link reference definition destination ending in a backslash after a path ends at the line ending")
    func refDefTrailingBackslashSlashPath() {
        #expect(TreeDump.dump("[b]:/u\\\ny\n\n[b]", options: []) == """
            document
              paragraph
                text "y"
              paragraph
                link "/u\\\\" ""
                  text "b"

            """)
    }

    @Test("an inline link destination ending in a backslash, followed by a line that is neither a title nor `)`, forms no link, and the backslash is a hard line break")
    func inlineTrailingBackslash() {
        #expect(TreeDump.dump("[a](/u\\\nx)", options: []) == """
            document
              paragraph
                text "[a](/u"
                linebreak
                text "x)"

            """)
    }

    @Test("a link reference definition whose destination is one backslash at the end of input is a definition")
    func refDefLoneTrailingBackslash() {
        #expect(TreeDump.dump("[b]\n\n[b]:\\", options: []) == """
            document
              paragraph
                link "\\\\" ""
                  text "b"

            """)
    }

    @Test("inline link whose destination line ends in a backslash then a bare close paren")
    func inlineTrailingBackslashThenCloseParen() {
        #expect(TreeDump.dump("[a](/u\\\n)", options: []) == """
            document
              paragraph
                link "/u\\\\" ""
                  text "a"

            """)
    }

    @Test("a link reference definition destination ending in two backslashes ends at the line ending")
    func refDefEvenTrailingBackslashes() {
        #expect(TreeDump.dump("[b]:a\\\\\n]\n\n[b]", options: []) == """
            document
              paragraph
                text "]"
              paragraph
                link "a\\\\" ""
                  text "b"

            """)
    }

    @Test("a link reference definition destination holding a backslash ends at the line ending")
    func refDefBackslashMidDestination() {
        #expect(TreeDump.dump("[b]:a\\b\n]\n\n[b]", options: []) == """
            document
              paragraph
                text "]"
              paragraph
                link "a\\\\b" ""
                  text "b"

            """)
    }

    @Test("a plain link reference definition destination ends at the line ending")
    func refDefPlainDestination() {
        #expect(TreeDump.dump("[b]: x\n]\n\n[b]", options: []) == """
            document
              paragraph
                text "]"
              paragraph
                link "x" ""
                  text "b"

            """)
    }
}

@Suite("Link destination forms")
struct LinkDestinationFormTests {

    @Test("plain single-char destination")
    func plainDestination() {
        #expect(TreeDump.dump("[](a)", options: []) == """
            document
              paragraph
                link "a" ""

            """)
    }

    @Test("balanced parenthesized destination")
    func balancedParenDestination() {
        #expect(TreeDump.dump("[]((a))", options: []) == """
            document
              paragraph
                link "(a)" ""

            """)
    }

    @Test("unbalanced open paren destination stopped by a space is no link")
    func openParenDestinationStoppedBySpace() {
        #expect(TreeDump.dump("[](( )", options: []) == """
            document
              paragraph
                text "[](( )"

            """)
    }

    @Test("empty destination across a line ending")
    func emptyDestinationAcrossLineEnding() {
        #expect(TreeDump.dump("[](\n)", options: []) == """
            document
              paragraph
                link "" ""

            """)
    }
}
