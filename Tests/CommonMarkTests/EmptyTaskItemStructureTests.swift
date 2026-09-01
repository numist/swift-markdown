/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// Depth-first: the checked state and direct-child count of the first list item, or nil if there is
// none. File-scope + `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules (see
// code-conventions: use file-scope helpers, don't capture the borrow across the tree walk).
private func firstListItem(
    _ node: borrowing MarkdownNode
) -> (checked: Bool?, childCount: Int)? {
    if case .item(let checked) = node.kind {
        var count = 0
        node.children.forEach { _ in count += 1 }
        return (checked, count)
    }
    var found: (checked: Bool?, childCount: Int)? = nil
    node.children.forEach { child in
        if found == nil {
            found = firstListItem(child)
        }
    }
    return found
}

/// Block structure of an EMPTY GFM task-list item (`- [ ] ` / `- [x]\t` - a checkbox followed by
/// only trailing whitespace, nothing else on the line).
///
/// cmark-gfm's tasklist extension consumes the checkbox when the list ITEM opens
/// (`open_tasklist_item`), so such an item has no first child: it stays EMPTY, exactly like a plain
/// `- ` empty item. A following UNINDENTED non-blank line therefore closes the item and starts a
/// fresh top-level paragraph rather than lazily continuing the (nonexistent) item paragraph. A line
/// indented to the item's content column still continues it (the item then holds a paragraph and
/// keeps its checkbox). The rewrite recognizes the checkbox at finalize (`runParagraphMatchers`,
/// #65), which cannot see the empty case (there is no paragraph to finalize); it is caught at
/// item-open time instead. This is a STRUCTURAL match (which blocks form), independent of
/// `.cmarkBugCompatibility` - the flag-off assertion is the guardrail.
///
/// Positions are the `dump --ref` (cmark-gfm) oracle for each source.
@Suite("Empty GFM task-list item block structure")
struct EmptyTaskItemStructureTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// The differential-fuzzer configuration: tasklist + positions + cmark bug-compatibility.
    private static let options: MarkdownDocument.ParseOptions =
        [.tasklist, .sourcePosition, .cmarkBugCompatibility]

    /// The shipped default: tasklist + positions, bug-compatibility OFF.
    private static let flagOff: MarkdownDocument.ParseOptions =
        [.tasklist, .sourcePosition]

    private func analyze(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> (nodes: [(kind: MarkdownNode.Kind, range: Range<Pos>?)],
                 firstItem: (checked: Bool?, childCount: Int)?) {
        try MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> (nodes: [(kind: MarkdownNode.Kind, range: Range<Pos>?)],
                    firstItem: (checked: Bool?, childCount: Int)?) in
            var nodes: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &nodes)
            return (nodes, firstListItem(doc.root))
        }
    }

    private func itemRange(
        in nodes: [(kind: MarkdownNode.Kind, range: Range<Pos>?)]
    ) -> Range<Pos>? {
        for entry in nodes {
            if case .item = entry.kind { return entry.range }
        }
        return nil
    }

    private func paragraphs(
        in nodes: [(kind: MarkdownNode.Kind, range: Range<Pos>?)]
    ) -> [Range<Pos>?] {
        nodes.filter { $0.kind == .paragraph }.map { $0.range }
    }

    /// True if ANY item in the tree was recognized as a task item (checkbox set). The negative
    /// controls below use this to prove the checkbox was NOT recognized anywhere.
    private func anyTaskItem(
        in nodes: [(kind: MarkdownNode.Kind, range: Range<Pos>?)]
    ) -> Bool {
        for entry in nodes {
            if case .item(let checked) = entry.kind, checked != nil { return true }
        }
        return false
    }

    @Test("empty task item is childless and does not swallow a following unindented line")
    func emptyTaskItemDoesNotSwallowNextLine() throws {
        // "- [ ] " (checkbox, only trailing space) then "x" (unindented). Oracle `emptytask-min`.
        let (nodes, item) = try analyze("- [ ] \nx", options: Self.options)
        // Fixture-sanity: the item is a RECOGNIZED unchecked task item - not a plain bullet, and not
        // a paragraph whose literal text happens to be "[ ]". Without this the emptiness claim below
        // could pass against a structure that never involved a checkbox at all.
        let firstItem = try #require(item, "no list item parsed")
        try #require(firstItem.checked == .some(false), "expected an UNCHECKED task item")
        // The core claim: the item is EMPTY (no child paragraph), so `x` is not swallowed.
        #expect(firstItem.childCount == 0)
        #expect(itemRange(in: nodes) == Pos(line: 1, column: 1)..<Pos(line: 1, column: 7))
        // `x` is a SEPARATE top-level paragraph on line 2.
        let paras = paragraphs(in: nodes)
        try #require(paras.count == 1)
        #expect(paras[0]?.lowerBound == Pos(line: 2, column: 1))
        #expect(paras[0]?.upperBound == Pos(line: 2, column: 2))
    }

    @Test("empty task item followed by a blank line then text")
    func emptyTaskItemBeforeBlankThenText() throws {
        // "- [ ] " then a blank line then "x". Reference: item empty @1:1-1:7, list end extends to
        // @2:1 (the blank line), `x` a separate paragraph @3:1-3:2.
        let (nodes, item) = try analyze("- [ ] \n\nx", options: Self.options)
        let firstItem = try #require(item)
        try #require(firstItem.checked == .some(false))
        #expect(firstItem.childCount == 0)
        #expect(itemRange(in: nodes) == Pos(line: 1, column: 1)..<Pos(line: 1, column: 7))
        let paras = paragraphs(in: nodes)
        try #require(paras.count == 1)
        #expect(paras[0]?.lowerBound == Pos(line: 3, column: 1))
        #expect(paras[0]?.upperBound == Pos(line: 3, column: 2))
    }

    @Test("empty task item as the last line (EOF)")
    func emptyTaskItemAtEOF() throws {
        // "- [ ] " with nothing after: item empty @1:1-1:7, no paragraph anywhere.
        let (nodes, item) = try analyze("- [ ] ", options: Self.options)
        let firstItem = try #require(item)
        try #require(firstItem.checked == .some(false))
        #expect(firstItem.childCount == 0)
        #expect(itemRange(in: nodes) == Pos(line: 1, column: 1)..<Pos(line: 1, column: 7))
        #expect(paragraphs(in: nodes).isEmpty)
    }

    @Test("empty task item followed by an INDENTED line continues the item")
    func emptyTaskItemContinuesOnIndentedLine() throws {
        // "- [ ] " then "  x" (indented to the item's content column). The reference CONTINUES the
        // item: it gains a paragraph @2:3-2:4 and keeps its checkbox; item spans @1:1-2:4. This is
        // the boundary control proving the fix quarantines the empty case (unindented) from a
        // genuine continuation.
        let (nodes, item) = try analyze("- [ ] \n  x", options: Self.options)
        let firstItem = try #require(item)
        try #require(firstItem.checked == .some(false))
        #expect(firstItem.childCount == 1)   // the continuation paragraph
        #expect(itemRange(in: nodes) == Pos(line: 1, column: 1)..<Pos(line: 2, column: 4))
        let paras = paragraphs(in: nodes)
        try #require(paras.count == 1)
        #expect(paras[0]?.lowerBound == Pos(line: 2, column: 3))
        #expect(paras[0]?.upperBound == Pos(line: 2, column: 4))
    }

    @Test("checked empty task item with a TAB separator")
    func emptyCheckedTaskItemTabSeparator() throws {
        // "- [x]\t" (tab after the checkbox) then "x". Reference: checked item empty @1:1-1:7,
        // `x` a separate paragraph @2:1-2:2.
        let (nodes, item) = try analyze("- [x]\t\nx", options: Self.options)
        let firstItem = try #require(item)
        try #require(firstItem.checked == .some(true), "expected a CHECKED task item")
        #expect(firstItem.childCount == 0)
        #expect(itemRange(in: nodes) == Pos(line: 1, column: 1)..<Pos(line: 1, column: 7))
        let paras = paragraphs(in: nodes)
        try #require(paras.count == 1)
        #expect(paras[0]?.lowerBound == Pos(line: 2, column: 1))
        #expect(paras[0]?.upperBound == Pos(line: 2, column: 2))
    }

    @Test("flag-off: the empty-item STRUCTURE is unchanged (structural fix, not a quirk)")
    func flagOffKeepsEmptyItemStructure() throws {
        // The block structure - childless task item, `x` a separate paragraph - does not depend on
        // `.cmarkBugCompatibility`: it matches cmark-gfm AND the CommonMark reading either way. Only
        // the (already-true) positions would ever differ, and for this shape they don't.
        let (nodes, item) = try analyze("- [ ] \nx", options: Self.flagOff)
        let firstItem = try #require(item)
        try #require(firstItem.checked == .some(false))   // still a task item flag-off
        #expect(firstItem.childCount == 0)
        let paras = paragraphs(in: nodes)
        try #require(paras.count == 1)
        #expect(paras[0]?.lowerBound == Pos(line: 2, column: 1))
        #expect(paras[0]?.upperBound == Pos(line: 2, column: 2))
    }

    @Test("block-quoted empty checkbox is NOT a task item (only top-level lists recognize checkboxes)")
    func blockQuotedEmptyCheckboxIsNotRecognized() throws {
        // cmark's `scan_tasklist` scans the whole line from offset 0 and requires the checkbox be
        // preceded only by spaces + one list marker; the `>` breaks the match, so `> - [ ] ` is an
        // ORDINARY item whose paragraph text is the literal `[ ]`. The open-time detection must
        // replicate that line-start anchoring rather than firing for every list item. Oracle:
        // `emptytask-bq-ctl`.
        let (nodes, item) = try analyze("> - [ ] ", options: Self.options)
        let firstItem = try #require(item, "no list item parsed")
        #expect(firstItem.checked == nil)                 // ordinary item, NOT a task item
        #expect(firstItem.childCount == 1)                // holds the `[ ]` paragraph
        #expect(!anyTaskItem(in: nodes))                  // no checkbox recognized anywhere
        #expect(!paragraphs(in: nodes).isEmpty)           // `[ ]` survives as paragraph content
    }

    @Test("nested empty checkbox is NOT a task item (a second marker breaks scan_tasklist)")
    func nestedEmptyCheckboxIsNotRecognized() throws {
        // `- - [ ] `: the inner list marker is preceded by the OUTER marker, so `scan_tasklist` fails
        // and the inner item is ordinary with literal `[ ]` text. Oracle: `emptytask-nest-ctl`.
        let (nodes, _) = try analyze("- - [ ] ", options: Self.options)
        #expect(!anyTaskItem(in: nodes))                  // no checkbox recognized at any nesting
        #expect(!paragraphs(in: nodes).isEmpty)           // `[ ]` survives as paragraph content
    }
}
