/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A line of only spaces or tabs is a blank line (Characters and lines), so it keeps an open footnote definition open.
@Suite("Footnote definition across a line of only spaces or tabs")
struct EmptyFootnoteDefinitionWhitespaceLineTests {
    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition, .footnotes]

    private func tree(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options)
    }

    @Test func emptyLineKeepsDefinitionOpen() {
        #expect(tree("- [^a]:\n\n\t\t\"") == """
            document
              list bullet '-' tight
                item

            """)
    }

    @Test func topLevelSpaceOnlyLines() {
        #expect(tree("[^a]:\n    \n    x\n\n[^a]") == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "a"
                paragraph
                  text "x"

            """)
    }

    @Test func underindentedLineAfterWhitespaceLineClosesDefinition() {
        #expect(tree("- [^a]: x\n \n  y") == """
            document
              list bullet '-' loose
                item
                  paragraph
                    text "y"

            """)
    }

    @Test func crlfEmptyLineKeepsDefinitionOpen() {
        #expect(tree("- [^a]:\r\n\r\n\t\t\"") == """
            document
              list bullet '-' tight
                item

            """)
    }

    @Test func definitionContinuesPastWhitespaceLine() {
        #expect(tree("- [^a]:\n \n      x\n\n[^a]") == """
            document
              list bullet '-' tight
                item
              paragraph
                footnote_reference "1"
              footnote_definition "a"
                paragraph
                  text "x"

            """)
    }

    /// Indented content after a line of only spaces or tabs belongs to the definition, and is dropped with it when the
    /// definition is unreferenced.
    @Test(arguments: ["- [^a]:\n\t\n\t\t\"", "- [^a]:\n \n\t\t\"", "- [^a]:\r\t\n\t\t\"", "- [^\u{0}]:\r\t\n\t\t\"", "- [^a]:\n\t\n      x", "- [^a]:\r\n \r\n\t\t\""])
    func listItemDefinitionHoldsContentAfterWhitespaceLine(_ markdown: String) {
        #expect(tree(markdown) == """
            document
              list bullet '-' tight
                item

            """)
    }

    @Test(arguments: 1...3)
    func topLevelDefinitionHoldsContentAfterSpacesLine(spaces: Int) {
        #expect(tree("[^a]:\n" + String(repeating: " ", count: spaces) + "\n    x\n\n[^a]") == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "a"
                paragraph
                  text "x"

            """)
    }

    @Test func definitionHoldsContentAfterWhitespaceLine() {
        #expect(tree("> [^a]:\n>\t\n>\t\tx") == """
            document
              block_quote

            """)
        #expect(tree("1. [^a]:\n \n       x") == """
            document
              list ordered start=1 delim=period tight
                item

            """)
        #expect(tree("- - [^a]:\n \n        x") == """
            document
              list bullet '-' tight
                item
                  list bullet '-' tight
                    item

            """)
        #expect(tree("- > [^a]:\n  >\n  >     x") == """
            document
              list bullet '-' tight
                item
                  block_quote

            """)
        #expect(tree("- [^a]:\n\t\n\t\tx\n\n[^a]") == """
            document
              list bullet '-' tight
                item
              paragraph
                footnote_reference "1"
              footnote_definition "a"
                paragraph
                  text "x"

            """)
        #expect(tree("- [^a]: x\n \n\t\ty\n\n[^a]") == """
            document
              list bullet '-' tight
                item
              paragraph
                footnote_reference "1"
              footnote_definition "a"
                paragraph
                  text "x"
                paragraph
                  text "y"

            """)
    }
}
