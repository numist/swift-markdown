/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A list marker followed by tabs, on the line after a fenced code block in a list item. Under the
/// rule for an item starting with indented code (List items), indentation after the marker is counted
/// in columns with tab stops of 4: when it reaches five columns, the marker takes one column and the
/// rest begins an indented code block.
@Suite("List-marker padding tab feeding an indented code body")
struct ListMarkerTabPaddingFencedContinuationTests {

    // The marker takes one column of the first tab; the six remaining columns exceed the code indent
    // by two, which the partially consumed second tab contributes as two spaces.
    @Test("double-tab list continuation opens a sibling item with indented code")
    func doubleTabSiblingIndentedCode() {
        MarkdownDocument.withParsedDocument("- ```\n-\t\t-") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == [
                "document",
                "list bullet '-' tight",
                "item",
                "code_block fenced fence='`' length=3 offset=0",
                "item",
                "code_block indented fence=none length=0 offset=0",
            ])
            #expect(codeBlocks(doc).map(\.literal) == ["", "  -\n"])
        }
    }

    @Test("double-tab list continuation with content keeps the split-tab spaces")
    func doubleTabSiblingIndentedCodeContent() {
        MarkdownDocument.withParsedDocument("- ```\n-\t\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == [
                "document",
                "list bullet '-' tight",
                "item",
                "code_block fenced fence='`' length=3 offset=0",
                "item",
                "code_block indented fence=none length=0 offset=0",
            ])
            #expect(codeBlocks(doc).map(\.literal) == ["", "  x\n"])
        }
    }

    // The marker takes one column of the tab; its remaining two columns plus the two spaces are
    // exactly the code indent.
    @Test("tab-then-spaces list continuation opens a sibling item with indented code")
    func tabThenSpacesSiblingIndentedCode() {
        MarkdownDocument.withParsedDocument("*\t~~~\n*\t  -") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == [
                "document",
                "list bullet '*' tight",
                "item",
                "code_block fenced fence='~' length=3 offset=0",
                "item",
                "code_block indented fence=none length=0 offset=0",
            ])
            #expect(codeBlocks(doc).map(\.literal) == ["", "-\n"])
        }
    }

    // A single tab after the marker is three columns, fewer than five, so all of it is padding and `x`
    // begins a paragraph at the item's content column.
    @Test("single-tab list continuation opens a sibling item with a paragraph")
    func singleTabSiblingParagraph() {
        MarkdownDocument.withParsedDocument("- ```\n-\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == [
                "document",
                "list bullet '-' tight",
                "item",
                "code_block fenced fence='`' length=3 offset=0",
                "item",
                "paragraph",
                "text",
            ])
            #expect(codeBlocks(doc).map(\.literal) == [""])
            #expect(dfs(doc).last?.literal == "x")
        }
    }

    // The two-column marker `1.` takes one column of the first tab; the five remaining columns exceed
    // the code indent by one.
    @Test("double-tab ordered-list continuation opens a sibling item with indented code")
    func orderedMarkerDoubleTabSiblingIndentedCode() {
        MarkdownDocument.withParsedDocument("1. ```\n1.\t\tx") { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(kinds.map(TreeDump.describe) == [
                "document",
                "list ordered start=1 delim=period tight",
                "item",
                "code_block fenced fence='`' length=3 offset=0",
                "item",
                "code_block indented fence=none length=0 offset=0",
            ])
            #expect(codeBlocks(doc).map(\.literal) == ["", " x\n"])
        }
    }
}
