/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A tab right after an ordered-list marker (`1.`/`1)`) must be expanded into spaces for the
/// content-indent decision, exactly as it already is after a bullet marker (`-`/`+`/`*`). When the
/// expanded whitespace reaches the >=5-column threshold, the item content is an indented code block,
/// not a paragraph. cmark expands the whitespace after every list marker; the rewrite previously
/// stopped prefix-tab expansion at the ordered marker, leaving the tab literal and miscomputing the
/// content column.
@Suite("Ordered-list marker followed by a tab")
struct OrderedMarkerTabExpansionTests {

    // FIX: `1.` occupies columns 0-1, so the tab at column 2 expands to 2 columns and the three
    // trailing spaces bring the gap to 5 columns - crossing the code-block threshold. Content is `z`.
    @Test("period marker: tab then spaces reaching the code threshold is a code block")
    func periodMarkerTabIsCodeBlock() throws {
        try MarkdownDocument.withParsedDocument("1.\t   z") { doc in
            let kinds = dfs(doc).map { $0.kind }
            #expect(kinds == [.document, .orderedList(), .item(checked: nil), .indentedCode])
            #expect(codeBlocks(doc).map(\.literal) == ["z\n"])
        }
    }

    @Test("paren marker: tab then spaces reaching the code threshold is a code block")
    func parenMarkerTabIsCodeBlock() throws {
        try MarkdownDocument.withParsedDocument("1)\t   z") { doc in
            let kinds = dfs(doc).map { $0.kind }
            #expect(kinds == [.document, .orderedList(.paren), .item(checked: nil), .indentedCode])
            #expect(codeBlocks(doc).map(\.literal) == ["z\n"])
        }
    }

    // GUARD: the literal-spaces spelling of the same content already parses as a code block; the fix
    // must leave it untouched (the tab case materializes to exactly this line).
    @Test("period marker: five literal spaces is a code block (unchanged)")
    func periodMarkerLiteralSpacesIsCodeBlock() throws {
        try MarkdownDocument.withParsedDocument("1.     z") { doc in
            let kinds = dfs(doc).map { $0.kind }
            #expect(kinds == [.document, .orderedList(), .item(checked: nil), .indentedCode])
            #expect(codeBlocks(doc).map(\.literal) == ["z\n"])
        }
    }

    // GUARD: a tab-only gap after `1.` expands to just 2 columns - below the >=5-column threshold - so
    // the content stays a paragraph.
    @Test("period marker: tab-only gap stays a paragraph")
    func periodMarkerTabOnlyIsParagraph() throws {
        try MarkdownDocument.withParsedDocument("1.\tz") { doc in
            let kinds = dfs(doc).map { $0.kind }
            #expect(kinds == [.document, .orderedList(), .item(checked: nil), .paragraph, .text])
        }
    }

    // GUARD: a wider marker (`12.`, columns 0-2) expands its tab to a single column, so `12.` + tab +
    // two spaces totals 3 columns - still below the threshold - and stays a paragraph.
    @Test("wide marker: tab plus two spaces stays a paragraph")
    func wideMarkerTabStaysParagraph() throws {
        try MarkdownDocument.withParsedDocument("12.\t  z") { doc in
            let kinds = dfs(doc).map { $0.kind }
            #expect(kinds == [.document, .orderedList(start: 12), .item(checked: nil), .paragraph, .text])
        }
    }

    // GUARD: a bullet marker already expands the following tab; this pins that behavior so the fix is
    // demonstrably aligning the ordered path with the bullet path.
    @Test("bullet marker: tab then spaces is a code block (unchanged)")
    func bulletMarkerTabIsCodeBlock() throws {
        try MarkdownDocument.withParsedDocument("-\t   z") { doc in
            let kinds = dfs(doc).map { $0.kind }
            #expect(kinds == [.document, .bulletList(), .item(checked: nil), .indentedCode])
        }
    }

    // EDGE: with the tab expanded, the two-column gap after `1.` is a valid list-item content indent,
    // so a bullet marker in the content opens a nested bullet list rather than being defeated by the
    // literal tab.
    @Test("edge: ordered marker, tab, then nested bullet marker opens a nested list")
    func orderedMarkerTabThenNestedBullet() throws {
        try MarkdownDocument.withParsedDocument("1.\t- x") { doc in
            let kinds = dfs(doc).map { $0.kind }
            #expect(kinds == [
                .document,
                .orderedList(), .item(checked: nil),
                .bulletList(), .item(checked: nil), .paragraph, .text,
            ])
        }
    }

    // POSITIONS: exercise the prefix-tab position re-walk (`originalPrefixSourceOffset` /
    // `materializedSourceStart`) with `.sourcePosition` on, which the structural tests above leave
    // untouched. Columns are raw byte offsets into the original source (the zero-copy model, as in
    // `SourcePositionTests.emptyItemTabContinuation`): in `1.\t   z` the bytes are `1`@1, `.`@2,
    // `\t`@3, spaces@4-6, `z`@7. The load-bearing property is that the tab-expanded code content maps
    // back to `z`'s TRUE source byte (column 7), not to a materialized-buffer column - proving the
    // re-walk stayed in lockstep with the fixed `expandPrefixTabs` expansion.
    @Test("positions: tab-expanded ordered item maps content back to true source bytes")
    func positionsMapBackToSource() throws {
        typealias Pos = MarkdownNode.SourcePosition
        try MarkdownDocument.withParsedDocument("1.\t   z", options: .sourcePosition) { doc in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            let kinds = ranges.map { $0.kind }
            #expect(kinds == [.document, .orderedList(), .item(checked: nil), .indentedCode])
            // List / item start at the `1` marker (column 1) and end just past `z` (column 8).
            let list = ranges.first { if case .list = $0.kind { return true } else { return false } }?.range
            #expect(list?.lowerBound == Pos(line: 1, column: 1))
            #expect(list?.upperBound == Pos(line: 1, column: 8))
            // The indented-code content is the single byte `z`: column 7 (its true source byte) to
            // column 8. A stale materialized-buffer offset would land elsewhere.
            let code = ranges.first { $0.kind.isCodeBlock }?.range
            #expect(code?.lowerBound == Pos(line: 1, column: 7))
            #expect(code?.upperBound == Pos(line: 1, column: 8))
        }
    }
}
