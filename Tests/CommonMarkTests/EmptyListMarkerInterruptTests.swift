/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A list item that begins with a blank line cannot interrupt a paragraph (List items), so a list marker with
/// nothing after it, on a line that would otherwise be paragraph continuation text, stays paragraph text. Where the
/// paragraph's container does not continue onto that line, the marker opens a list.
@Suite("Empty list marker paragraph interruption")
struct EmptyListMarkerInterruptTests {

    @Test("empty marker in a continued list item stays paragraph text (no nested list)", arguments: [
        ("- a\n  +", """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "a"
                    softbreak
                    text "+"

            """),
        ("- a\n  *", """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "a"
                    softbreak
                    text "*"

            """),
        ("- a\n  1.", """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "a"
                    softbreak
                    text "1."

            """),
    ])
    func emptyMarkerInNestedItemStaysText(markdown: String, tree: String) {
        #expect(TreeDump.dump(markdown, options: []) == tree)
    }

    @Test("empty marker on a line without `>` opens a top-level list after the block quote")
    func emptyMarkerAfterUnmatchedBlockQuoteOpensTopLevelList() {
        #expect(TreeDump.dump("> a\n+", options: []) == """
            document
              block_quote
                paragraph
                  text "a"
              list bullet '+' tight
                item

            """)
    }

    @Test("empty marker after a top-level paragraph stays text", arguments: [
        ("a\n+", """
            document
              paragraph
                text "a"
                softbreak
                text "+"

            """),
        ("a\n* ", """
            document
              paragraph
                text "a"
                softbreak
                text "*"

            """),
    ])
    func emptyMarkerAfterTopLevelParagraphStaysText(markdown: String, tree: String) {
        #expect(TreeDump.dump(markdown, options: []) == tree)
    }
}
