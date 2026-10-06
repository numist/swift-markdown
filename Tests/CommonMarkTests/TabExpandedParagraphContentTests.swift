/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A paragraph line that begins with block-marker characters (`*`, `-`, `+`, `>`, digits, `.`, `)`) followed by a
/// tab. The parser expands that tab into spaces in a copy of the line so container markers can consume part of it,
/// but the paragraph's text keeps the tab as written, whether or not source positions are tracked.
@Suite("Paragraph content on a tab-expanded line")
struct TabExpandedParagraphContentTests {

    private static let positionModes: [MarkdownDocument.ParseOptions] = [[], [.sourcePosition]]

    @Test("emphasis characters before a tab stay literal", arguments: positionModes)
    func emphasisCharactersBeforeTab(mode: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("**\tx", options: mode) == """
            document
              paragraph
                text "**\\tx"

            """)
    }

    @Test("an ordered-marker-like run before a tab stays literal", arguments: positionModes)
    func orderedMarkerRunBeforeTab(mode: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("3)1.\tz", options: mode) == """
            document
              paragraph
                text "3)1.\\tz"

            """)
    }

    @Test("a smart dash before a tab keeps the tab", arguments: positionModes)
    func smartDashBeforeTab(mode: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("--\ta", options: mode.union(.smart)) == """
            document
              paragraph
                text "\u{2013}\\ta"

            """)
    }

    @Test("a trailing tab ends the line with a soft break", arguments: positionModes)
    func trailingTabIsSoftBreak(mode: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("**\t\nb", options: mode) == """
            document
              paragraph
                text "**"
                softbreak
                text "b"

            """)
    }

    @Test("consecutive tab-expanded lines keep their tabs", arguments: positionModes)
    func consecutiveTabExpandedLines(mode: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("**\tx\n**\ty", options: mode) == """
            document
              paragraph
                text "**\\tx"
                softbreak
                text "**\\ty"

            """)
    }

    @Test("inside a block quote whose prefix is followed by a tab", arguments: positionModes)
    func insideTabbedBlockQuote(mode: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump(">\t**\tx", options: mode) == """
            document
              block_quote
                paragraph
                  text "**\\tx"

            """)
    }

    @Test("a tab-expanded line after a setext underline left as text keeps its tab", arguments: positionModes)
    func afterUnderlineLeftAsText(mode: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("[a\n ]:b\n=\n**\tx", options: mode.union(.cmarkBugCompatibility)) == """
            document
              paragraph
                text "="
                softbreak
                text "**\\tx"

            """)
    }

    @Test("a list item continuation line keeps its tabs", arguments: positionModes)
    func listItemContinuation(mode: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("- a\n  **\tb\tc", options: mode) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "a"
                    softbreak
                    text "**\\tb\\tc"

            """)
    }
}
