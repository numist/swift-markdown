/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Footnote references are numbered in document order among those that remain in the final tree, and
/// definitions are appended in that index order.
@Suite("Footnote reference numbering")
struct FootnoteDiscardedReferenceNumberingTests {
    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition, .footnotes]

    /// `[^ [^a]]` is not a footnote reference, since its label holds unescaped brackets (Links), so the
    /// inner `[^a]` takes index 1 ahead of `[^b]`.
    @Test
    func innerReferenceTakesFirstIndex() {
        #expect(TreeDump.dump("[^ [^a]] [^b]\n\n[^a]: A\n\n[^b]: B\n", options: Self.options) == """
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

    /// The inner `[^a]` orders definition `a` first, and the later `[^a]` reuses its index.
    @Test
    func innerReferenceOrdersDefinitions() {
        #expect(TreeDump.dump("[^ [^a]] [^b] [^a]\n\n[^a]: A\n\n[^b]: B\n", options: Self.options) == """
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

    /// A reference inside a footnote definition is numbered at the definition's place in the source.
    @Test
    func referencesNumberInDocumentPreOrder() {
        #expect(TreeDump.dump("[^a]: see [^b]\n\n> - q [^c] [^b]\n\n[^b]: x\n\n[^c]: y\n\ntext [^a]\n", options: Self.options) == """
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

    /// A reference inside a definition that no reference resolves to is numbered, so the definition it resolves to
    /// is kept, while the reference is dropped with the definition holding it.
    @Test
    func referenceInDroppedDefinitionKeepsItsDefinition() {
        #expect(TreeDump.dump("x [^c]\n\n[^a]: [^b]\n\n[^b]: B\n\n[^c]: C\n", options: Self.options) == """
            document
              paragraph
                text "x "
                footnote_reference "1"
              footnote_definition "c"
                paragraph
                  text "C"
              footnote_definition "b"
                paragraph
                  text "B"

            """)
    }
}
