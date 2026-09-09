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

// True if ANY item in the tree was recognized as a task item (checkbox set). Negative cases use this
// to prove the checkbox was NOT recognized anywhere in the tree.
private func anyTaskItem(_ node: borrowing MarkdownNode) -> Bool {
    if case .item(let checked) = node.kind, checked != nil {
        return true
    }
    var found = false
    node.children.forEach { child in
        if !found {
            found = anyTaskItem(child)
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
/// This is a RECOGNITION-anchoring match, so — like the block-quote / nested-marker anchoring controls
/// in `EmptyTaskItemStructureTests` — the fix is UNCONDITIONAL: flag-ON and flag-OFF produce the same
/// tree. (Contrast `TaskListCheckboxStrstrQuirkTests`, where only the checked-STATE scan is a
/// `.cmarkBugCompatibility` quirk.) These assertions parse without `.sourcePosition`.
///
/// Regression for the fuzzer divergence minimized from `-\n  [x] \u{FFFD}` (options 0x0).
@Suite("GFM task-list checkbox continuation-line recognition")
struct TaskListContinuationLineRecognitionTests {

    private static let flagOn: MarkdownDocument.ParseOptions = [.tasklist, .cmarkBugCompatibility]
    private static let flagOff: MarkdownDocument.ParseOptions = [.tasklist]

    private func firstChecked(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> Bool? {
        let state: Bool?? = try MarkdownDocument.withParsedDocument(src, options: options) { doc -> Bool?? in
            firstItemChecked(doc.root)
        }
        // Fixture-sanity: a list item must exist, so an "ordinary item" claim can't pass vacuously
        // against a tree that has no item at all.
        return try #require(state, "no list item parsed")
    }

    private func hasTaskItem(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> Bool {
        try MarkdownDocument.withParsedDocument(src, options: options) { doc -> Bool in
            anyTaskItem(doc.root)
        }
    }

    // MARK: Divergence — token on a continuation line is NOT a checkbox

    @Test("flag ON: `-\\n  [x] foo` is an ORDINARY item (checkbox token on continuation line)")
    func continuationCheckedNotRecognized() throws {
        #expect(try firstChecked("-\n  [x] foo", options: Self.flagOn) == nil)
        #expect(try !hasTaskItem("-\n  [x] foo", options: Self.flagOn))
    }

    @Test("flag ON: `-\\n  [ ] foo` is an ORDINARY item (unchecked variant)")
    func continuationUncheckedNotRecognized() throws {
        #expect(try firstChecked("-\n  [ ] foo", options: Self.flagOn) == nil)
        #expect(try !hasTaskItem("-\n  [ ] foo", options: Self.flagOn))
    }

    @Test("flag ON: `- \\n  [x] foo` is an ORDINARY item (marker + trailing space, then continuation)")
    func continuationAfterTrailingSpaceNotRecognized() throws {
        #expect(try firstChecked("- \n  [x] foo", options: Self.flagOn) == nil)
        #expect(try !hasTaskItem("- \n  [x] foo", options: Self.flagOn))
    }

    // MARK: Agreeing controls — token on the opening line IS a checkbox (guard against over-correction)

    @Test("flag ON control: `- [x] foo` IS a checked task item (token on opening line)")
    func openingLineChecked() throws {
        #expect(try firstChecked("- [x] foo", options: Self.flagOn) == true)
    }

    @Test("flag ON control: `- [x] a\\n  [x] b` IS a checked task item (opening-line token)")
    func openingLineWithContinuation() throws {
        #expect(try firstChecked("- [x] a\n  [x] b", options: Self.flagOn) == true)
    }

    // MARK: Unconditional — the deliverable (flag OFF) anchors recognition the same way

    @Test("flag OFF: `-\\n  [x] foo` is an ORDINARY item (anchoring is unconditional, not a quirk)")
    func continuationNotRecognizedFlagOff() throws {
        #expect(try firstChecked("-\n  [x] foo", options: Self.flagOff) == nil)
        #expect(try !hasTaskItem("-\n  [x] foo", options: Self.flagOff))
    }

    @Test("flag OFF control: `- [x] foo` IS a checked task item")
    func openingLineCheckedFlagOff() throws {
        #expect(try firstChecked("- [x] foo", options: Self.flagOff) == true)
    }
}
