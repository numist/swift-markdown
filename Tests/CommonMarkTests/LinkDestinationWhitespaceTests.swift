/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A link destination between `<` and `>` keeps its leading, trailing and interior spaces and tabs, in an inline link
/// and in a link reference definition (Links, Link reference definitions). A link title keeps all its whitespace.
@Suite("Whitespace in link destinations")
struct LinkDestinationWhitespaceTests {

    // MARK: - Inline link destinations

    @Test("a single-space angle destination is a space")
    func inlineSingleSpace() {
        #expect(TreeDump.dump("[](< >)", options: []) == """
            document
              paragraph
                link " " ""

            """)
    }

    @Test("a two-space angle destination is two spaces")
    func inlineTwoSpaces() {
        #expect(TreeDump.dump("[](<  >)", options: []) == """
            document
              paragraph
                link "  " ""

            """)
    }

    @Test("a leading space is part of an angle destination")
    func inlineLeadingSpace() {
        #expect(TreeDump.dump("[](< a>)", options: []) == """
            document
              paragraph
                link " a" ""

            """)
    }

    @Test("a trailing space is part of an angle destination")
    func inlineTrailingSpace() {
        #expect(TreeDump.dump("[](<a >)", options: []) == """
            document
              paragraph
                link "a " ""

            """)
    }

    @Test("a leading tab is part of an angle destination")
    func inlineLeadingTab() {
        #expect(TreeDump.dump("[](<\ta>)", options: []) == """
            document
              paragraph
                link "\\ta" ""

            """)
    }

    @Test("a leading space is kept and a backslash escape after it resolves")
    func inlineLeadingSpaceAndEscape() {
        #expect(TreeDump.dump("[](< \\!a>)", options: []) == """
            document
              paragraph
                link " !a" ""

            """)
    }

    // MARK: - Link reference definition destinations

    @Test("a leading space is part of a link reference definition's angle destination")
    func refDefLeadingSpace() {
        #expect(TreeDump.dump("[x]: < a>\n\n[x]", options: []) == """
            document
              paragraph
                link " a" ""
                  text "x"

            """)
    }

    @Test("a single-space link reference definition angle destination is a space")
    func refDefSingleSpace() {
        #expect(TreeDump.dump("[x]: < >\n\n[x]", options: []) == """
            document
              paragraph
                link " " ""
                  text "x"

            """)
    }

    // MARK: - Interior whitespace

    @Test("interior whitespace in an inline destination is kept")
    func inlineInteriorKept() {
        #expect(TreeDump.dump("[](<a b>)", options: []) == """
            document
              paragraph
                link "a b" ""

            """)
    }

    @Test("interior whitespace in a link reference definition destination is kept")
    func refDefInteriorKept() {
        #expect(TreeDump.dump("[x]: <a b>\n\n[x]", options: []) == """
            document
              paragraph
                link "a b" ""
                  text "x"

            """)
    }

    // MARK: - Backslash escapes

    @Test("a backslash escape in an angle destination resolves")
    func angleEscapeRemoval() {
        #expect(TreeDump.dump("[](<a\\>b>)", options: []) == """
            document
              paragraph
                link "a>b" ""

            """)
    }

    @Test("a backslash escape in a bare destination resolves")
    func bareEscapeRemoval() {
        #expect(TreeDump.dump("[](a\\)b)", options: []) == """
            document
              paragraph
                link "a)b" ""

            """)
    }

    // MARK: - Link titles

    @Test("a title with no surrounding space is kept as is")
    func titleNoSpaceUnaffected() {
        #expect(TreeDump.dump("[](<a> \"t\")", options: []) == """
            document
              paragraph
                link "a" "t"

            """)
    }

    @Test("whitespace at the ends of a title is kept")
    func titleSurroundingSpacePreserved() {
        #expect(TreeDump.dump("[](<a> \" t \")", options: []) == """
            document
              paragraph
                link "a" " t "

            """)
    }
}
