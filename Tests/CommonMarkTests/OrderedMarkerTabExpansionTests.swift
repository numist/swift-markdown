/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Indentation after an ordered list marker is counted in columns with tab stops of 4 (Tabs), as after a
/// bullet list marker. When it reaches five columns, the item starts with an indented code block (List
/// items).
@Suite("Ordered-list marker followed by a tab")
struct OrderedMarkerTabExpansionTests {

    // The tab after `1.` spans two columns; the three spaces bring the indentation to five.
    @Test("period marker: tab then spaces reaching the code threshold is a code block")
    func periodMarkerTabIsCodeBlock() {
        MarkdownDocument.withParsedDocument("1.\t   z") { doc in
            let kinds = dfs(doc).map { $0.kind }
            #expect(kinds == [.document, .orderedList(), .item(checked: nil), .indentedCode])
            #expect(codeBlocks(doc).map(\.literal) == ["z\n"])
        }
    }

    @Test("paren marker: tab then spaces reaching the code threshold is a code block")
    func parenMarkerTabIsCodeBlock() {
        MarkdownDocument.withParsedDocument("1)\t   z") { doc in
            let kinds = dfs(doc).map { $0.kind }
            #expect(kinds == [.document, .orderedList(.paren), .item(checked: nil), .indentedCode])
            #expect(codeBlocks(doc).map(\.literal) == ["z\n"])
        }
    }

    @Test("period marker: five literal spaces is a code block")
    func periodMarkerLiteralSpacesIsCodeBlock() {
        MarkdownDocument.withParsedDocument("1.     z") { doc in
            let kinds = dfs(doc).map { $0.kind }
            #expect(kinds == [.document, .orderedList(), .item(checked: nil), .indentedCode])
            #expect(codeBlocks(doc).map(\.literal) == ["z\n"])
        }
    }

    @Test("period marker: tab-only gap stays a paragraph")
    func periodMarkerTabOnlyIsParagraph() {
        MarkdownDocument.withParsedDocument("1.\tz") { doc in
            let kinds = dfs(doc).map { $0.kind }
            #expect(kinds == [.document, .orderedList(), .item(checked: nil), .paragraph, .text])
        }
    }

    // The tab after `12.` spans one column, so the indentation is three columns.
    @Test("wide marker: tab plus two spaces stays a paragraph")
    func wideMarkerTabStaysParagraph() {
        MarkdownDocument.withParsedDocument("12.\t  z") { doc in
            let kinds = dfs(doc).map { $0.kind }
            #expect(kinds == [.document, .orderedList(start: 12), .item(checked: nil), .paragraph, .text])
        }
    }

    @Test("bullet marker: tab then spaces is a code block")
    func bulletMarkerTabIsCodeBlock() {
        MarkdownDocument.withParsedDocument("-\t   z") { doc in
            let kinds = dfs(doc).map { $0.kind }
            #expect(kinds == [.document, .bulletList(), .item(checked: nil), .indentedCode])
        }
    }

    @Test("ordered marker, tab, then nested bullet marker opens a nested list")
    func orderedMarkerTabThenNestedBullet() {
        MarkdownDocument.withParsedDocument("1.\t- x") { doc in
            let kinds = dfs(doc).map { $0.kind }
            #expect(kinds == [
                .document,
                .orderedList(), .item(checked: nil),
                .bulletList(), .item(checked: nil), .paragraph, .text,
            ])
        }
    }

    // Columns count source bytes, so the tab occupies column 3 alone and `z` is at column 7.
    @Test("positions: tab-expanded ordered item maps content back to source bytes")
    func positionsMapBackToSource() {
        typealias Pos = MarkdownNode.SourcePosition
        MarkdownDocument.withParsedDocument("1.\t   z", options: .sourcePosition) { doc in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            let kinds = ranges.map { $0.kind }
            #expect(kinds == [.document, .orderedList(), .item(checked: nil), .indentedCode])
            let list = ranges.first { if case .list = $0.kind { return true } else { return false } }?.range
            #expect(list?.lowerBound == Pos(line: 1, column: 1))
            #expect(list?.upperBound == Pos(line: 1, column: 8))
            let code = ranges.first { $0.kind == .indentedCode }?.range
            #expect(code?.lowerBound == Pos(line: 1, column: 7))
            #expect(code?.upperBound == Pos(line: 1, column: 8))
        }
    }
}
