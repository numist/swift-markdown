/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A whitespace-only line is a blank line (Characters and lines), so it keeps an open footnote definition open.
@Suite("Footnote definition across a whitespace-only line")
struct EmptyFootnoteDefinitionWhitespaceLineTests {
    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition, .footnotes]

    private func surface(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options)
    }

    @Test func emptyLineKeepsDefinitionOpen() {
        #expect(surface("- [^a]:\n\n\t\t\"") == """
            document
              list bullet '-' tight
                item

            """)
    }

    @Test func topLevelSpaceOnlyLines() {
        #expect(surface("[^a]:\n    \n    x\n\n[^a]") == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "a"
                paragraph
                  text "x"

            """)
    }

    @Test func underindentedLineAfterWhitespaceLineClosesDefinition() {
        #expect(surface("- [^a]: x\n \n  y") == """
            document
              list bullet '-' loose
                item
                  paragraph
                    text "y"

            """)
    }

    @Test func crlfEmptyLineKeepsDefinitionOpen() {
        #expect(surface("- [^a]:\r\n\r\n\t\t\"") == """
            document
              list bullet '-' tight
                item

            """)
    }

    @Test func definitionContinuesPastWhitespaceLine() {
        #expect(surface("- [^a]:\n \n      x\n\n[^a]") == """
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

    /// Indented content after a whitespace-only line belongs to the definition, and is dropped with it when the
    /// definition is unreferenced.
    @Test(arguments: ["- [^a]:\n\t\n\t\t\"", "- [^a]:\n \n\t\t\"", "- [^a]:\r\t\n\t\t\"", "- [^\u{0}]:\r\t\n\t\t\"", "- [^a]:\n\t\n      x", "- [^a]:\r\n \r\n\t\t\""])
    func listItemDefinitionHoldsContentAfterWhitespaceLine(_ markdown: String) {
        #expect(surface(markdown) == """
            document
              list bullet '-' tight
                item

            """)
    }

    @Test(arguments: 1...3)
    func topLevelDefinitionHoldsContentAfterSpacesLine(spaces: Int) {
        #expect(surface("[^a]:\n" + String(repeating: " ", count: spaces) + "\n    x\n\n[^a]") == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "a"
                paragraph
                  text "x"

            """)
    }

    /// Indented content after a whitespace-only line belongs to the definition, and is dropped with it when the
    /// definition is unreferenced.
    @Test func definitionHoldsContentAfterWhitespaceLine() {
        #expect(surface("> [^a]:\n>\t\n>\t\tx") == """
            document
              block_quote

            """)
        #expect(surface("1. [^a]:\n \n       x") == """
            document
              list ordered start=1 delim=period tight
                item

            """)
        #expect(surface("- - [^a]:\n \n        x") == """
            document
              list bullet '-' tight
                item
                  list bullet '-' tight
                    item

            """)
        #expect(surface("- > [^a]:\n  >\n  >     x") == """
            document
              list bullet '-' tight
                item
                  block_quote

            """)
        #expect(surface("- [^a]:\n\t\n\t\tx\n\n[^a]") == """
            document
              list bullet '-' tight
                item
              paragraph
                footnote_reference "1"
              footnote_definition "a"
                paragraph
                  text "x"

            """)
        #expect(surface("- [^a]: x\n \n\t\ty\n\n[^a]") == """
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
