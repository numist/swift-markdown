/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// Depth-first: the checked state of the first list item — `.some(nil)` = an ordinary bullet item,
// `.some(.some(x))` = a recognized task item (unchecked/checked), outer `nil` = no item at all.
// File-scope + `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules (see
// code-conventions: use file-scope helpers, don't capture the borrow across the tree walk).
private func firstItemChecked(_ node: borrowing MarkdownNode) -> Bool?? {
    if case .item(let checked) = node.kind {
        return .some(checked)
    }
    var found: Bool?? = nil
    node.children.forEach { child in
        if found == nil {
            found = firstItemChecked(child)
        }
    }
    return found
}

/// GFM task-list checkbox RECOGNITION is anchored to the list item's OPENING line — the physical line
/// that bears the list marker. cmark-gfm sets the checkbox in `open_tasklist_item`
/// (`extensions/tasklist.c`), which runs only as the item opens and only sees that opening line; a
/// `[x]`/`[ ]` token that first appears on a later continuation line is NOT a checkbox, so the item
/// stays an ordinary bullet whose paragraph text keeps the literal `[x]`/`[ ]`.
///
/// The rewrite recognizes the checkbox at paragraph-finalize (`runParagraphMatchers`, #65), which fires
/// for a paragraph beginning with the token regardless of whether that paragraph started on the item's
/// opening line or on a continuation line — so it over-recognizes the continuation-line case. When the
/// item's opening line is blank after the marker (`-` alone, optionally with trailing spaces) and the
/// token appears on the next indented line, the rewrite wrongly reports a checkbox while cmark does not.
///
/// These assertions parse without `.sourcePosition`.
///
/// Regression for the fuzzer divergence minimized from `-\n  [x] \u{FFFD}` (options 0x0).
@Suite("GFM task-list checkbox continuation-line recognition")
struct TaskListContinuationLineRecognitionTests {

    private static let flagOff: MarkdownDocument.ParseOptions = [.tasklist]

    private func firstChecked(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> Bool? {
        let state: Bool?? = MarkdownDocument.withParsedDocument(src, options: options) { doc -> Bool?? in
            firstItemChecked(doc.root)
        }
        // Fixture-sanity: a list item must exist, so an "ordinary item" claim can't pass vacuously
        // against a tree that has no item at all.
        return try #require(state, "no list item parsed")
    }

    // MARK: Shipped parser

    /// The item's first block is the paragraph `[x] foo`, which begins with a task list item marker
    /// (spec "Task list items (extension)"), whatever line it starts on.
    @Test("`-\\n  [x] foo` is a checked task item")
    func continuationRecognizedFlagOff() throws {
        #expect(try firstChecked("-\n  [x] foo", options: Self.flagOff) == true)
    }

    @Test("flag OFF control: `- [x] foo` IS a checked task item")
    func openingLineCheckedFlagOff() throws {
        #expect(try firstChecked("- [x] foo", options: Self.flagOff) == true)
    }

    @Test("flag OFF control: `- [x] a\\n  [x] b` IS a checked task item")
    func openingLineWithContinuationFlagOff() throws {
        #expect(try firstChecked("- [x] a\n  [x] b", options: Self.flagOff) == true)
    }
}
