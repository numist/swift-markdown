/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A closing code fence may be indented up to three spaces (Fenced code blocks). A leading tab advances to
/// column 4 (Tabs), so a tab-indented fence line is code content, not a closing fence.
@Suite("Fenced code block closing fence indentation")
struct FencedCodeClosingFenceTabIndentTests {

    // The opening fence is unindented, so no indentation is removed from content lines and the tab is kept.
    @Test("tab-led fence line is code content, not a closing fence")
    func tabLedLineIsContent() {
        #expect(TreeDump.dump("```\n\t```", options: []) == """
            document
              code_block "" "\\t```\\n"

            """)
        #expect(codeBlockKinds("```\n\t```") == ["code_block fenced fence='`' length=3 offset=0"])
    }

    @Test("tab-led fence line after content stays content")
    func tabLedLineAfterContent() {
        #expect(TreeDump.dump("```\nx\n\t```", options: []) == """
            document
              code_block "" "x\\n\\t```\\n"

            """)
        #expect(codeBlockKinds("```\nx\n\t```") == ["code_block fenced fence='`' length=3 offset=0"])
    }

    @Test("unindented fence line closes the block")
    func unindentedLineCloses() {
        #expect(TreeDump.dump("```\n```", options: []) == """
            document
              code_block "" ""

            """)
        #expect(codeBlockKinds("```\n```") == ["code_block fenced fence='`' length=3 offset=0"])
    }

    @Test("three-space-indented fence line closes the block")
    func threeSpaceIndentCloses() {
        #expect(TreeDump.dump("```\n   ```", options: []) == """
            document
              code_block "" ""

            """)
        #expect(codeBlockKinds("```\n   ```") == ["code_block fenced fence='`' length=3 offset=0"])
    }

    @Test("four-space-indented fence line is code content")
    func fourSpaceIndentIsContent() {
        #expect(TreeDump.dump("```\n    ```", options: []) == """
            document
              code_block "" "    ```\\n"

            """)
        #expect(codeBlockKinds("```\n    ```") == ["code_block fenced fence='`' length=3 offset=0"])
    }
}

/// The kind of every code block in `markdown`, depth-first, as `TreeDump.describe` gives it, which tells a fenced code
/// block from an indented one.
private func codeBlockKinds(_ markdown: String, options: MarkdownDocument.ParseOptions = []) -> [String] {
    MarkdownDocument.withParsedDocument(markdown, options: options) { doc in
        var kinds: [String] = []
        func visit(_ node: borrowing MarkdownNode) {
            if case .codeBlock = node.kind {
                kinds.append(TreeDump.describe(node.kind))
            }
            node.children.forEach { visit($0) }
        }
        visit(doc.root)
        return kinds
    }
}
