/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A footnote definition opened after a block quote marker and a tab (Tabs), with and without source positions.
@Suite("Footnote definition on a tab-expanded line")
struct FootnoteDefinitionTabExpandedLineTests {

    private static let positionModes: [MarkdownDocument.ParseOptions] = [[], [.sourcePosition]]

    @Test("the definition keeps its label and resolves a reference", arguments: positionModes)
    func labelResolves(mode: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump(">\t[^ab]: x\n\nc[^ab]\n", options: mode.union(.footnotes)) == """
            document
              block_quote
              paragraph
                text "c"
                footnote_reference "1"
              footnote_definition "ab"
                paragraph
                  text "x"

            """)
    }

    @Test("without footnotes, the definition is a link reference definition", arguments: positionModes)
    func linkDefinitionWithoutFootnotes(mode: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump(">\t[^ab]: x\n\nc[^ab]\n", options: mode) == """
            document
              block_quote
              paragraph
                text "c"
                link "x" ""
                  text "^ab"

            """)
    }

    @Test("an unreferenced empty definition at the end of nested quotes is dropped", arguments: positionModes)
    func emptyDefinitionAtEnd(mode: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump(">\t>\t[^z]:", options: mode.union(.footnotes)) == """
            document
              block_quote
                block_quote

            """)
    }

    @Test("without footnotes, an empty definition at the end of nested quotes is text", arguments: positionModes)
    func emptyDefinitionAtEndWithoutFootnotes(mode: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump(">\t>\t[^z]:", options: mode) == """
            document
              block_quote
                block_quote
                  paragraph
                    text "[^z]:"

            """)
    }
}
