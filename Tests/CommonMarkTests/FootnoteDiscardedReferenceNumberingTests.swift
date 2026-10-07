/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// cmark-gfm's `process_footnotes` numbers only the references that survive in the
/// finalized tree, in document order, and appends definitions in that index order.
@Suite("Footnote reference numbering")
struct FootnoteDiscardedReferenceNumberingTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .footnotes]

    /// Flag-off (shipped): `[^ …]` is not a footnote reference, so the inner `[^a]` survives and takes
    /// index 1 ahead of `[^b]`.
    @Test
    func testFlagOffInnerReferenceTakesFirstIndex() {
        #expect(CmarkTreeDump.dump("[^ [^a]] [^b]\n\n[^a]: A\n\n[^b]: B\n", options: Self.options) == """
            document
              paragraph
                text "[^ "
                footnote_reference "1"
                text "] "
                footnote_reference "2"
              footnote_definition "a"
                paragraph
                  text "A"
              footnote_definition "b"
                paragraph
                  text "B"

            """)
    }

    /// Flag-off (shipped): the surviving inner `[^a]` orders definition `a` first and the later `[^a]`
    /// reuses its index.
    @Test
    func testFlagOffInnerReferenceOrdersDefinitions() {
        #expect(CmarkTreeDump.dump("[^ [^a]] [^b] [^a]\n\n[^a]: A\n\n[^b]: B\n", options: Self.options) == """
            document
              paragraph
                text "[^ "
                footnote_reference "1"
                text "] "
                footnote_reference "2"
                text " "
                footnote_reference "1"
              footnote_definition "a"
                paragraph
                  text "A"
              footnote_definition "b"
                paragraph
                  text "B"

            """)
    }

    /// Flag-off numbers references in the same document pre-order.
    @Test
    func testFlagOffReferencesNumberInDocumentPreOrder() {
        #expect(CmarkTreeDump.dump("[^a]: see [^b]\n\n> - q [^c] [^b]\n\n[^b]: x\n\n[^c]: y\n\ntext [^a]\n", options: Self.options) == """
            document
              block_quote
                list bullet '-' tight
                  item
                    paragraph
                      text "q "
                      footnote_reference "2"
                      text " "
                      footnote_reference "1"
              paragraph
                text "text "
                footnote_reference "3"
              footnote_definition "b"
                paragraph
                  text "x"
              footnote_definition "c"
                paragraph
                  text "y"
              footnote_definition "a"
                paragraph
                  text "see "
                  footnote_reference "1"

            """)
    }
}
