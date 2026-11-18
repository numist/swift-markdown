/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

// The item's content starts two columns into the first tab, so the code block's four-column indent ends two
// columns into the second tab and leaves two spaces of content (Tabs).
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

    @Test
    func manySplitTabCodeLines() {
        let markdown = "- a\n\n" + String(repeating: "\t\tx\n", count: 100)
        let literals = MarkdownDocument.withParsedDocument(markdown) { codeBlocks($0).map(\.literal) }
        #expect(literals == [String(repeating: "  x\n", count: 100)])
    }
}
