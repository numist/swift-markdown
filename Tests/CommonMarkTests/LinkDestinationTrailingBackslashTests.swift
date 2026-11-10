/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A backslash before a line ending in a link destination is a literal backslash (Backslash escapes), and a link
/// destination cannot contain a line ending (Links), so the destination ends with that backslash. An even run of
/// trailing backslashes is a run of escaped backslashes.
@Suite("Link destination trailing backslash")
struct LinkDestinationTrailingBackslashTests {

    // MARK: - An odd run of trailing backslashes

    @Test("a link reference definition whose destination is one backslash ends at the line ending")
    func refDefBareTrailingBackslash() {
        // The destination is `\`, and the `]` line is a paragraph.
        #expect(TreeDump.dump("[b]:\\\n]", options: []) == """
            document
              paragraph
                text "]"

            """)
    }

    @Test("a link reference definition destination ending in a backslash after text ends at the line ending")
    func refDefTrailingBackslashAfterText() {
        #expect(TreeDump.dump("[b]:a\\\nx", options: []) == """
            document
              paragraph
                text "x"

            """)
    }

    @Test("a link reference definition destination ending in a backslash after a path ends at the line ending")
    func refDefTrailingBackslashSlashPath() {
        #expect(TreeDump.dump("[b]:/u\\\ny", options: []) == """
            document
              paragraph
                text "y"

            """)
    }

    @Test("an inline link destination ending in a backslash forms no link, and the backslash is a hard line break")
    func inlineTrailingBackslash() {
        // After the destination `/u\` and the whitespace that follows it, `x)` is neither a link title nor `)` (Links),
        // so no link forms and the backslash before the line ending is a hard line break (Hard line breaks).
        #expect(TreeDump.dump("[a](/u\\\nx)", options: []) == """
            document
              paragraph
                text "[a](/u"
                linebreak
                text "x)"

            """)
    }

    // MARK: - Other destinations

    @Test("a link reference definition destination ending in two backslashes ends at the line ending")
    func refDefEvenTrailingBackslashes() {
        #expect(TreeDump.dump("[b]:a\\\\\n]", options: []) == """
            document
              paragraph
                text "]"

            """)
    }

    @Test("a link reference definition destination holding a backslash ends at the line ending")
    func refDefBackslashMidDestination() {
        #expect(TreeDump.dump("[b]:a\\b\n]", options: []) == """
            document
              paragraph
                text "]"

            """)
    }

    @Test("a plain link reference definition destination ends at the line ending")
    func refDefPlainDestination() {
        #expect(TreeDump.dump("[b]: x\n]", options: []) == """
            document
              paragraph
                text "]"

            """)
    }

    @Test("a link reference definition whose destination is one backslash at the end of input is a definition")
    func refDefLoneTrailingBackslash() {
        #expect(TreeDump.dump("[b]:\\", options: []) == """
            document

            """)
    }

    @Test("inline link whose destination line ends in a backslash then a bare close paren")
    func inlineTrailingBackslashThenCloseParen() {
        // Whitespace, here a line ending, may separate the destination `/u\` from the `)` (Links).
        #expect(TreeDump.dump("[a](/u\\\n)", options: []) == """
            document
              paragraph
                link "/u\\\\" ""
                  text "a"

            """)
    }
}

/// A bare link destination (Links) is a run of non-whitespace characters whose parentheses are escaped or balanced, and
/// an inline link's destination may be empty.
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

    /// A bare destination includes parentheses only when they are escaped or balanced (Links).
    @Test("unbalanced open paren destination stopped by a space is no link")
    func openParenDestinationStoppedBySpace() {
        #expect(TreeDump.dump("[](( )", options: []) == """
            document
              paragraph
                text "[](( )"

            """)
    }

    /// Whitespace, including a line ending, may follow the `(`, and the destination may be empty.
    @Test("empty destination across a line ending")
    func emptyDestinationAcrossLineEnding() {
        #expect(TreeDump.dump("[](\n)", options: []) == """
            document
              paragraph
                link "" ""

            """)
    }
}
