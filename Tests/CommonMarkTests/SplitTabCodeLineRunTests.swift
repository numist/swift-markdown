/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Indented code lines in a list item whose indent splits a tab.
///
/// The list item's content starts at column 2, so the second tab of each `\t\tx` line contributes two columns of the
/// four an indented code block strips and leaves two spaces of content (Tabs). Each such line costs time in proportion
/// to its own length, so 200,000 of them, about 800 KB of source, parse well within the time limit.
@Suite("Runs of indented code lines whose indent splits a tab")
struct SplitTabCodeLineRunTests {

    @Test
    func splitTabCodeLines() {
        #expect(TreeDump.dump("- a\n\n\t\tx\n\t\tx\n", options: []) == """
            document
              list bullet '-' loose
                item
                  paragraph
                    text "a"
                  code_block "" "  x\\n  x\\n"

            """)
    }

    @Test(.timeLimit(.minutes(1)))
    func manySplitTabCodeLines() {
        let markdown = "- a\n\n" + String(repeating: "\t\tx\n", count: 200_000)
        let literals = MarkdownDocument.withParsedDocument(markdown) { codeBlocks($0).map(\.literal) }
        #expect(literals == [String(repeating: "  x\n", count: 200_000)])
    }
}
