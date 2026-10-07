/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The tag names of HTML block start condition 6 (HTML blocks) follow the CommonMark 0.31 list, which has `search` and
/// not `source`.
///
/// Start condition 6 needs only the tag name followed by whitespace, `>`, `/>` or the end of the line, and it may
/// interrupt a paragraph. A complete tag whose name isn't on the list, such as `<source>`, meets only start condition 7,
/// which can't interrupt a paragraph.
@Suite("HTML block type-6 tag name list")
struct HTMLBlockType6TagNameListTests {

    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition]

    @Test("`<source` at the line end is paragraph text")
    func sourceAtLineEnd() {
        #expect(TreeDump.dump("<source\n", options: Self.options, sourceRanges: true) == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "<source" @1:1-1:8

            """)
    }

    @Test("`<search` at the line end opens an HTML block")
    func searchAtLineEnd() {
        #expect(TreeDump.dump("<search\n", options: Self.options, sourceRanges: true) == """
            document @1:1-1:8
              html_block "<search\\n" @1:1-1:8

            """)
    }

    @Test("`<search>` interrupts a paragraph")
    func searchInterruptsParagraph() {
        #expect(TreeDump.dump("para\n<search>\n", options: Self.options, sourceRanges: true) == """
            document @1:1-2:9
              paragraph @1:1-1:5
                text "para" @1:1-1:5
              html_block "<search>\\n" @2:1-2:9

            """)
    }

    @Test("`<source>` doesn't interrupt a paragraph")
    func sourceContinuesParagraph() {
        #expect(TreeDump.dump("para\n<source>\n", options: Self.options, sourceRanges: true) == """
            document @1:1-2:9
              paragraph @1:1-2:9
                text "para" @1:1-1:5
                softbreak @-
                html_inline "<source>" @2:1-2:9

            """)
    }

    @Test("an uppercase `<SOURCE` followed by an attribute is paragraph text")
    func uppercaseSourceWithAttribute() {
        #expect(TreeDump.dump("<SOURCE x\n", options: Self.options, sourceRanges: true) == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "<SOURCE x" @1:1-1:10

            """)
    }

    @Test("a mixed-case closing `</soURce` is paragraph text")
    func mixedCaseClosingSource() {
        #expect(TreeDump.dump("</soURce\n", options: Self.options, sourceRanges: true) == """
            document @1:1-1:9
              paragraph @1:1-1:9
                text "</soURce" @1:1-1:9

            """)
    }

    @Test("`<source/>` doesn't interrupt a paragraph")
    func selfClosingSourceContinuesParagraph() {
        #expect(TreeDump.dump("para\n<source/>\n", options: Self.options, sourceRanges: true) == """
            document @1:1-2:10
              paragraph @1:1-2:10
                text "para" @1:1-1:5
                softbreak @-
                html_inline "<source/>" @2:1-2:10

            """)
    }

    @Test("`<source` continues a block quote's paragraph lazily")
    func sourceContinuesLazily() {
        #expect(TreeDump.dump("> a\n<source\n", options: Self.options, sourceRanges: true) == """
            document @1:1-2:8
              block_quote @1:1-2:8
                paragraph @1:3-2:8
                  text "a" @1:3-1:4
                  softbreak @-
                  text "<source" @2:1-2:8

            """)
    }

    @Test("a longer name starting with `source` is paragraph text")
    func longerNameIsParagraph() {
        #expect(TreeDump.dump("<sources\n", options: Self.options, sourceRanges: true) == """
            document @1:1-1:9
              paragraph @1:1-1:9
                text "<sources" @1:1-1:9

            """)
    }

    @Test("`<Source` is paragraph text inside a block quote")
    func sourceInBlockQuote() {
        #expect(TreeDump.dump("> <Source\n", options: Self.options, sourceRanges: true) == """
            document @1:1-1:10
              block_quote @1:1-1:10
                paragraph @1:3-1:10
                  text "<Source" @1:3-1:10

            """)
    }

    /// `<source` is paragraph text, so `next` is a lazy continuation line of the list item's paragraph.
    @Test("`<source` is paragraph text inside a list item")
    func sourceInListItem() {
        #expect(TreeDump.dump("- <source\nnext\n", options: Self.options, sourceRanges: true) == """
            document @1:1-2:5
              list bullet '-' tight @1:1-2:5
                item @1:1-2:5
                  paragraph @1:3-2:5
                    text "<source" @1:3-1:10
                    softbreak @-
                    text "next" @2:1-2:5

            """)
    }
}
