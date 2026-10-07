/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A list item whose block-quoted paragraph is a link reference definition spanning two lines followed by a setext
/// underline `===`, then a lazy line holding a NUL and a checkbox. cmark resolves the definition when it scans the
/// underline and keeps the underline as paragraph text. On the lazy line its tasklist extension advances three bytes
/// into the NUL's U+FFFD, so the item is checked and the paragraph's last line starts with a replacement character.
/// With `.cmarkBugCompatibility` the rewrite reproduces that tree, with and without source positions.
@Suite("Tasklist retry after a definition-only setext paragraph")
struct TaskListRetryAfterSetextDefinitionTests {

    private static let positionModes: [MarkdownDocument.ParseOptions] = [[], [.sourcePosition]]

    @Test("the lazy line keeps its replacement character after the underline", arguments: positionModes)
    func lazyLineAfterUnderline(mode: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("- > [a]:\n  > u\n  > ===\n  1\u{0} [x] b\n", options: mode.union([.tasklist, .cmarkBugCompatibility])) == """
            document
              list bullet '-' tight
                tasklist checked
                  block_quote
                    paragraph
                      text "==="
                      softbreak
                      text "\u{FFFD} [x] b"

            """)
    }

    /// An item whose first block is a block quote is not a task item (GFM task list items), so the lazy line keeps its
    /// text with only the NUL replaced, where cmark checks the item and drops the line's leading `1`.
    @Test("without cmark bug compatibility, the item stays plain and the lazy line keeps its text", arguments: positionModes)
    func lazyLineAfterUnderlineSpecCorrect(mode: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("- > [a]:\n  > u\n  > ===\n  1\u{0} [x] b\n", options: mode.union(.tasklist)) == """
            document
              list bullet '-' tight
                item
                  block_quote
                    paragraph
                      text "==="
                      softbreak
                      text "1\u{FFFD} [x] b"

            """)
    }
}
