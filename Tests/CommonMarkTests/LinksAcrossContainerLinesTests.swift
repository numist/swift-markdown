/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Link labels (Links) and inline-attribute strings in a block quote or list item paragraph, on lines that carry the
/// container's markers or indentation and on lazy continuation lines. A label or attribute string may span a line
/// ending.
@Suite("Links across the lines of a container's paragraph")
struct LinksAcrossContainerLinesTests {

    @Test("block-quote lazy continuation with empty brackets is literal text")
    func blockQuoteEmptyBrackets() {
        #expect(TreeDump.dump(">a\n[]b", options: []) == """
            document
              block_quote
                paragraph
                  text "a"
                  softbreak
                  text "[]b"

            """)
    }

    @Test("list-item lazy continuation with empty brackets is literal text")
    func listItemEmptyBrackets() {
        #expect(TreeDump.dump("- a\n[]b", options: []) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "a"
                    softbreak
                    text "[]b"

            """)
    }

    @Test("block-quote lazy continuation with full brackets and no definition is literal text")
    func blockQuoteFullBracketsNoDefinition() {
        #expect(TreeDump.dump(">a\n[x]b", options: []) == """
            document
              block_quote
                paragraph
                  text "a"
                  softbreak
                  text "[x]b"

            """)
    }

    @Test("a shortcut reference on a lazy continuation line resolves")
    func shortcutReferenceResolvesOnLazyLine() {
        #expect(TreeDump.dump("[x]: /u\n\n>a\n[x]b", options: []) == """
            document
              block_quote
                paragraph
                  text "a"
                  softbreak
                  link "/u" ""
                    text "x"
                  text "b"

            """)
    }

    /// An inline attribute's `(…)` may span a line ending, which is part of the attribute string.
    @Test("an attribute form across a block quote's line ending holds the line ending")
    func crossLineAttributeBlockQuote() {
        #expect(TreeDump.dump("> ^[a](\n> b)", options: [.attributes]) == """
            document
              block_quote
                paragraph
                  attribute "\\nb"
                    text "a"

            """)
    }

    @Test("an attribute form across a list item's line ending holds the line ending")
    func crossLineAttributeListItem() {
        #expect(TreeDump.dump("- ^[a](\n  b)", options: [.attributes]) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    attribute "\\nb"
                      text "a"

            """)
    }

    /// A link label may span a line ending; matching normalizes `la\nbel` to `la bel` (Links).
    @Test("cross-line full-reference label resolves and consumes the trailing bracket")
    func crossLineFullReferenceResolves() {
        #expect(TreeDump.dump("[la bel]: /u\n\n>[t][la\nbel]", options: []) == """
            document
              block_quote
                paragraph
                  link "/u" ""
                    text "t"

            """)
    }

    @Test("cross-line full-reference label with no definition stays literal")
    func crossLineFullReferenceNoDefinition() {
        #expect(TreeDump.dump(">[t][la\nbel]", options: []) == """
            document
              block_quote
                paragraph
                  text "[t][la"
                  softbreak
                  text "bel]"

            """)
    }
}
