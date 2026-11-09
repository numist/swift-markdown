/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges of thematic breaks. A thematic break runs from its first marker character to just past its last
/// marker character on its own line, so trailing spaces or tabs and any following lines are outside it.
@Suite("Thematic break source ranges")
struct ThematicBreakSourceRangeTests {

    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition]

    @Test
    func singleBreak() {
        #expect(TreeDump.dump("***", options: Self.options, sourceRanges: true) == """
            document @1:1-1:4
              thematic_break @1:1-1:4

            """)
    }

    @Test
    func breakWithInteriorSpaces() {
        #expect(TreeDump.dump("- - -", options: Self.options, sourceRanges: true) == """
            document @1:1-1:6
              thematic_break @1:1-1:6

            """)
    }

    @Test
    func breakWithTrailingSpaces() {
        #expect(TreeDump.dump("***   \nx", options: Self.options, sourceRanges: true) == """
            document @1:1-2:2
              thematic_break @1:1-1:4
              paragraph @2:1-2:2
                text "x" @2:1-2:2

            """)
    }

    @Test
    func breakWithTrailingTab() {
        #expect(TreeDump.dump("***\t\nx", options: Self.options, sourceRanges: true) == """
            document @1:1-2:2
              thematic_break @1:1-1:4
              paragraph @2:1-2:2
                text "x" @2:1-2:2

            """)
    }

    @Test
    func indentedBreak() {
        #expect(TreeDump.dump("  ***", options: Self.options, sourceRanges: true) == """
            document @1:1-1:6
              thematic_break @1:3-1:6

            """)
    }

    @Test
    func breakThenBlankLineAndParagraph() {
        #expect(TreeDump.dump("***\n\nx", options: Self.options, sourceRanges: true) == """
            document @1:1-3:2
              thematic_break @1:1-1:4
              paragraph @3:1-3:2
                text "x" @3:1-3:2

            """)
    }

    @Test
    func breakThenBlankLines() {
        #expect(TreeDump.dump("***\n\n\n", options: Self.options, sourceRanges: true) == """
            document @1:1-3:1
              thematic_break @1:1-1:4

            """)
    }

    @Test
    func breakThenCRLFBlankLineAndParagraph() {
        #expect(TreeDump.dump("***\r\n\r\nx", options: Self.options, sourceRanges: true) == """
            document @1:1-3:2
              thematic_break @1:1-1:4
              paragraph @3:1-3:2
                text "x" @3:1-3:2

            """)
    }

    @Test
    func breakInBlockQuoteThenBlankLine() {
        #expect(TreeDump.dump("> ***\n>\nx", options: Self.options, sourceRanges: true) == """
            document @1:1-3:2
              block_quote @1:1-2:2
                thematic_break @1:3-1:6
              paragraph @3:1-3:2
                text "x" @3:1-3:2

            """)
    }

    @Test
    func breakWithTrailingSpacesInListItem() {
        #expect(TreeDump.dump("- ***  \n- b", options: Self.options, sourceRanges: true) == """
            document @1:1-2:4
              list bullet '-' tight @1:1-2:4
                item @1:1-1:6
                  thematic_break @1:3-1:6
                item @2:1-2:4
                  paragraph @2:3-2:4
                    text "b" @2:3-2:4

            """)
    }

    @Test
    func consecutiveBreaks() {
        #expect(TreeDump.dump("***\n---", options: Self.options, sourceRanges: true) == """
            document @1:1-2:4
              thematic_break @1:1-1:4
              thematic_break @2:1-2:4

            """)
    }
}
