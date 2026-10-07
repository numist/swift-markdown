/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A list item whose first block is a block quote is not a task list item (Task list items (extension)).
/// Here the block quote's paragraph begins with a link reference definition, so the `===` line has no
/// heading content and is paragraph text (Setext headings), followed by a lazy continuation line.
@Suite("List item whose first block is a block quote")
struct TaskListBlockQuoteFirstBlockTests {

    private static let positionModes: [MarkdownDocument.ParseOptions] = [[], [.sourcePosition]]

    /// The lazy line keeps its text, with the NUL replaced by U+FFFD (Insecure characters).
    @Test("the item has no checkbox and the lazy line keeps its text", arguments: positionModes)
    func lazyLineAfterUnderline(mode: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("- > [a]:\n  > u\n  > ===\n  1\u{0} [x] b\n", options: mode.union(.tasklist)) == """
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
