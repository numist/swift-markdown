/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The tag names that open an HTML block of type 6.
///
/// CommonMark 0.31 lists `search` and not `source`. cmark-gfm's `blocktagname` (swift-cmark `src/scanners.re`) keeps the
/// earlier list, with `source` and without `search`. With `.cmarkBugCompatibility` the parser uses cmark-gfm's list;
/// without it, the CommonMark 0.31 list.
///
/// A type-6 start needs only the tag name and a following whitespace, `>`, `/>` or line end, and it may interrupt a
/// paragraph. A complete tag such as `<search>` alone on a line is still a type-7 start under either list, which can't
/// interrupt a paragraph.
@Suite("HTML block type-6 tag name list")
struct HTMLBlockType6TagNameListTests {

    private static let cmarkCompatible: MarkdownDocument.ParseOptions = [.sourcePosition, .cmarkBugCompatibility]
    private static let specCompliant: MarkdownDocument.ParseOptions = [.sourcePosition]

    @Test("cmark-compatible: `<source` at the line end opens an HTML block")
    func sourceAtLineEnd() {
        #expect(CmarkTreeDump.dump("<source\n", options: Self.cmarkCompatible, sourceRanges: true) == """
            document @1:1-1:8
              html_block "<source\\n" @1:1-1:8

            """)
    }

    @Test("cmark-compatible: an uppercase `<SOURCE` followed by an attribute opens an HTML block")
    func uppercaseSourceWithAttribute() {
        #expect(CmarkTreeDump.dump("<SOURCE x\n", options: Self.cmarkCompatible, sourceRanges: true) == """
            document @1:1-1:10
              html_block "<SOURCE x\\n" @1:1-1:10

            """)
    }

    @Test("cmark-compatible: a mixed-case closing `</soURce` opens an HTML block")
    func mixedCaseClosingSource() {
        #expect(CmarkTreeDump.dump("</soURce\n", options: Self.cmarkCompatible, sourceRanges: true) == """
            document @1:1-1:9
              html_block "</soURce\\n" @1:1-1:9

            """)
    }

    @Test("cmark-compatible: `<source>` interrupts a paragraph")
    func sourceInterruptsParagraph() {
        #expect(CmarkTreeDump.dump("para\n<source>\n", options: Self.cmarkCompatible, sourceRanges: true) == """
            document @1:1-2:9
              paragraph @1:1-1:5
                text "para" @1:1-1:5
              html_block "<source>\\n" @2:1-2:9

            """)
    }

    @Test("cmark-compatible: `<source/>` interrupts a paragraph")
    func selfClosingSourceInterruptsParagraph() {
        #expect(CmarkTreeDump.dump("para\n<source/>\n", options: Self.cmarkCompatible, sourceRanges: true) == """
            document @1:1-2:10
              paragraph @1:1-1:5
                text "para" @1:1-1:5
              html_block "<source/>\\n" @2:1-2:10

            """)
    }

    @Test("cmark-compatible: `<source` ends a block quote's paragraph instead of continuing it lazily")
    func sourceEndsLazyContinuation() {
        #expect(CmarkTreeDump.dump("> a\n<source\n", options: Self.cmarkCompatible, sourceRanges: true) == """
            document @1:1-2:8
              block_quote @1:1-1:4
                paragraph @1:3-1:4
                  text "a" @1:3-1:4
              html_block "<source\\n" @2:1-2:8

            """)
    }

    @Test("cmark-compatible: a longer name starting with `source` is paragraph text")
    func longerNameIsParagraph() {
        #expect(CmarkTreeDump.dump("<sources\n", options: Self.cmarkCompatible, sourceRanges: true) == """
            document @1:1-1:9
              paragraph @1:1-1:9
                text "<sources" @1:1-1:9

            """)
    }

    @Test("cmark-compatible: `<Source` opens an HTML block inside a block quote")
    func sourceInBlockQuote() {
        #expect(CmarkTreeDump.dump("> <Source\n", options: Self.cmarkCompatible, sourceRanges: true) == """
            document @1:1-1:10
              block_quote @1:1-1:10
                html_block "<Source\\n" @1:3-1:10

            """)
    }

    @Test("cmark-compatible: `<source` opens an HTML block inside a list item")
    func sourceInListItem() {
        #expect(CmarkTreeDump.dump("- <source\nnext\n", options: Self.cmarkCompatible, sourceRanges: true) == """
            document @1:1-2:5
              list bullet '-' tight @1:1-1:10
                item @1:1-1:10
                  html_block "<source\\n" @1:3-1:10
              paragraph @2:1-2:5
                text "next" @2:1-2:5

            """)
    }

    @Test("cmark-compatible: `<search` at the line end is paragraph text")
    func searchAtLineEnd() {
        #expect(CmarkTreeDump.dump("<search\n", options: Self.cmarkCompatible, sourceRanges: true) == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "<search" @1:1-1:8

            """)
    }

    @Test("cmark-compatible: `<search>` doesn't interrupt a paragraph")
    func searchContinuesParagraph() {
        #expect(CmarkTreeDump.dump("para\n<search>\n", options: Self.cmarkCompatible, sourceRanges: true) == """
            document @1:1-2:9
              paragraph @1:1-2:9
                text "para" @1:1-1:5
                softbreak @-
                html_inline "<search>" @2:1-2:9

            """)
    }

    @Test("spec-compliant: `<source` at the line end is paragraph text")
    func specSourceAtLineEnd() {
        #expect(CmarkTreeDump.dump("<source\n", options: Self.specCompliant, sourceRanges: true) == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "<source" @1:1-1:8

            """)
    }

    @Test("spec-compliant: `<search` at the line end opens an HTML block")
    func specSearchAtLineEnd() {
        #expect(CmarkTreeDump.dump("<search\n", options: Self.specCompliant, sourceRanges: true) == """
            document @1:1-1:8
              html_block "<search\\n" @1:1-1:8

            """)
    }

    @Test("spec-compliant: `<search>` interrupts a paragraph")
    func specSearchInterruptsParagraph() {
        #expect(CmarkTreeDump.dump("para\n<search>\n", options: Self.specCompliant, sourceRanges: true) == """
            document @1:1-2:9
              paragraph @1:1-1:5
                text "para" @1:1-1:5
              html_block "<search>\\n" @2:1-2:9

            """)
    }

    @Test("spec-compliant: `<source>` doesn't interrupt a paragraph")
    func specSourceContinuesParagraph() {
        #expect(CmarkTreeDump.dump("para\n<source>\n", options: Self.specCompliant, sourceRanges: true) == """
            document @1:1-2:9
              paragraph @1:1-2:9
                text "para" @1:1-1:5
                softbreak @-
                html_inline "<source>" @2:1-2:9

            """)
    }

    /// `source` is not on CommonMark 0.31's type-6 tag list, so `<SOURCE x` is paragraph text where cmark-gfm opens
    /// an HTML block.
    @Test("spec-compliant: an uppercase `<SOURCE` followed by an attribute is paragraph text")
    func specUppercaseSourceWithAttribute() {
        #expect(CmarkTreeDump.dump("<SOURCE x\n", options: Self.specCompliant, sourceRanges: true) == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "<SOURCE x" @1:1-1:10

            """)
    }

    /// `source` is not on CommonMark 0.31's type-6 tag list, so `</soURce` is paragraph text where cmark-gfm opens an
    /// HTML block.
    @Test("spec-compliant: a mixed-case closing `</soURce` is paragraph text")
    func specMixedCaseClosingSource() {
        #expect(CmarkTreeDump.dump("</soURce\n", options: Self.specCompliant, sourceRanges: true) == """
            document @1:1-1:9
              paragraph @1:1-1:9
                text "</soURce" @1:1-1:9

            """)
    }

    /// `source` is not on CommonMark 0.31's type-6 tag list, so `<source/>` is a type-7 start that can't interrupt a
    /// paragraph and stays inline HTML in it, where cmark-gfm opens an HTML block.
    @Test("spec-compliant: `<source/>` doesn't interrupt a paragraph")
    func specSelfClosingSourceContinuesParagraph() {
        #expect(CmarkTreeDump.dump("para\n<source/>\n", options: Self.specCompliant, sourceRanges: true) == """
            document @1:1-2:10
              paragraph @1:1-2:10
                text "para" @1:1-1:5
                softbreak @-
                html_inline "<source/>" @2:1-2:10

            """)
    }

    /// `source` is not on CommonMark 0.31's type-6 tag list, so `<source` is a lazy continuation line of the block
    /// quote's paragraph, where cmark-gfm ends the block quote with an HTML block.
    @Test("spec-compliant: `<source` continues a block quote's paragraph lazily")
    func specSourceContinuesLazily() {
        #expect(CmarkTreeDump.dump("> a\n<source\n", options: Self.specCompliant, sourceRanges: true) == """
            document @1:1-2:8
              block_quote @1:1-2:8
                paragraph @1:3-2:8
                  text "a" @1:3-1:4
                  softbreak @-
                  text "<source" @2:1-2:8

            """)
    }

    @Test("spec-compliant: a longer name starting with `source` is paragraph text")
    func specLongerNameIsParagraph() {
        #expect(CmarkTreeDump.dump("<sources\n", options: Self.specCompliant, sourceRanges: true) == """
            document @1:1-1:9
              paragraph @1:1-1:9
                text "<sources" @1:1-1:9

            """)
    }

    /// `source` is not on CommonMark 0.31's type-6 tag list, so `<Source` is paragraph text in the block quote where
    /// cmark-gfm opens an HTML block.
    @Test("spec-compliant: `<Source` is paragraph text inside a block quote")
    func specSourceInBlockQuote() {
        #expect(CmarkTreeDump.dump("> <Source\n", options: Self.specCompliant, sourceRanges: true) == """
            document @1:1-1:10
              block_quote @1:1-1:10
                paragraph @1:3-1:10
                  text "<Source" @1:3-1:10

            """)
    }

    /// `source` is not on CommonMark 0.31's type-6 tag list, so `<source` is paragraph text in the list item that
    /// `next` continues lazily, where cmark-gfm opens an HTML block and `next` starts a paragraph after the list.
    @Test("spec-compliant: `<source` is paragraph text inside a list item")
    func specSourceInListItem() {
        #expect(CmarkTreeDump.dump("- <source\nnext\n", options: Self.specCompliant, sourceRanges: true) == """
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
