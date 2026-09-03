/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// File-scope + `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules (see `dfsRanges`).

/// The checked state of every `.item` node, in document (DFS) order. `.some(false)` = unchecked task
/// item, `.some(true)` = checked, `nil` = an ordinary (non-task) list item.
private func itemCheckStates(_ node: borrowing MarkdownNode, into out: inout [Bool?]) {
    if case .item(let checked) = node.kind {
        out.append(checked)
    }
    node.children.forEach { child in
        itemCheckStates(child, into: &out)
    }
}

/// Every text node's literal, in document (DFS) order.
private func textLiterals(_ node: borrowing MarkdownNode, into out: inout [String?]) {
    if node.kind == .text {
        out.append(node.literal())
    }
    node.children.forEach { child in
        textLiterals(child, into: &out)
    }
}

/// Block structure of a CONTENT-bearing GFM task-list item (`- [ ] x` and its nested variants).
///
/// cmark-gfm recognizes a task checkbox via `scan_tasklist`, which scans the whole physical line from
/// offset 0 as `spacechar* <one list marker> spacechar+ <checkbox> spacechar+ …`. A block-quote `>`
/// prefix OR a second (outer) list marker on the same line before the checkbox breaks that scan, so a
/// checkbox is recognized ONLY when the marker is preceded on its own physical line by nothing but
/// whitespace. This is a PHYSICAL-LINE property, not block-nesting depth: a block-nested item that sits
/// alone on its own indented line IS recognized (the indentation is the `spacechar*` prefix), while an
/// item sharing its line with a `>` or an outer marker is not. The rewrite records that line-anchoring
/// at item-open time (`lineAnchoredTaskItems`) and gates the finalize-time recognition on it, so an
/// item sharing its line with a `>` / outer marker keeps its `[ ]`/`[x]` as literal paragraph text.
///
/// STRUCTURAL match (whether a checkbox is set and whether `[ ]` stays literal): the tasklist
/// recognition fix is unconditional - it is not gated on `.cmarkBugCompatibility` (flag-ON and
/// flag-OFF produce an identical tree for every case here), so these assertions parse with the shipped
/// default options.
@Suite("Content-bearing GFM task-list item block structure")
struct ContentTaskItemStructureTests {

    /// The shipped default: tasklist + positions.
    private static let options: MarkdownDocument.ParseOptions =
        [.tasklist, .sourcePosition]

    private func analyze(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> (checks: [Bool?], texts: [String?]) {
        try MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> (checks: [Bool?], texts: [String?]) in
            var checks: [Bool?] = []
            var texts: [String?] = []
            itemCheckStates(doc.root, into: &checks)
            textLiterals(doc.root, into: &texts)
            return (checks, texts)
        }
    }

    // MARK: - Top-level items ARE recognized (positive controls)

    @Test("top-level content task item is recognized (marker stripped, checkbox set)")
    func topLevelContentTaskRecognized() throws {
        // `- [ ] x`: top-level, so the checkbox is recognized and stripped; the paragraph text is `x`.
        let (checks, texts) = try analyze("- [ ] x", options: Self.options)
        try #require(checks.count == 1, "expected exactly one list item, got \(checks)")
        #expect(checks[0] == .some(false))                 // recognized, UNCHECKED
        #expect(texts.contains("x"))                        // marker stripped
        #expect(!texts.contains { $0?.contains("[ ]") == true })   // no literal `[ ]`
    }

    @Test("indented top-level content task item is recognized")
    func indentedTopLevelContentTaskRecognized() throws {
        // `   - [ ] x` (3-space indent, the max before a list marker becomes code): still a top-level
        // item (leading spaces are `scan_tasklist`'s `spacechar*` prefix), so the checkbox is recognized.
        let (checks, texts) = try analyze("   - [ ] x", options: Self.options)
        try #require(checks.count == 1, "expected exactly one list item, got \(checks)")
        #expect(checks[0] == .some(false))
        #expect(texts.contains("x"))
        #expect(!texts.contains { $0?.contains("[ ]") == true })
    }

    @Test("top-level checked content task item is recognized")
    func topLevelCheckedContentTaskRecognized() throws {
        let (checks, texts) = try analyze("- [x] x", options: Self.options)
        try #require(checks.count == 1, "expected exactly one list item, got \(checks)")
        #expect(checks[0] == .some(true))                  // recognized, CHECKED
        #expect(texts.contains("x"))
    }

    @Test("top-level content task item with a TAB separator is recognized")
    func topLevelTabSeparatorContentTaskRecognized() throws {
        // `- [ ]\tx`: still a top-level checkbox (the marker's separator may be a space OR a tab). Only
        // the STRUCTURAL recognition is asserted here; the tab column-width is a separate deferred class.
        let (checks, _) = try analyze("- [ ]\tx", options: Self.options)
        try #require(checks.count == 1, "expected exactly one list item, got \(checks)")
        #expect(checks[0] == .some(false))
    }

    // MARK: - Nested / block-quoted items are NOT recognized (negative controls)

    @Test("block-quoted content task item is NOT recognized (literal `[ ]`)")
    func blockQuotedContentTaskNotRecognized() throws {
        // `> - [ ] x`: the `>` breaks `scan_tasklist`, so the item is ordinary and its paragraph keeps
        // the literal `[ ] x`. Oracle: `nesttask-bq`.
        let (checks, texts) = try analyze("> - [ ] x", options: Self.options)
        try #require(checks.count == 1, "expected exactly one list item, got \(checks)")
        #expect(checks[0] == nil)                          // ordinary item, NOT a task item
        #expect(texts.contains("[ ] x"))                    // marker survives as literal text
    }

    @Test("outer-list-nested content task item is NOT recognized (a second marker breaks scan_tasklist)")
    func nestedContentTaskNotRecognized() throws {
        // `- - [ ] x`: the inner marker is preceded by the OUTER marker. Oracle: `nesttask-list`.
        let (checks, texts) = try analyze("- - [ ] x", options: Self.options)
        try #require(checks.count == 2, "expected outer + inner items, got \(checks)")
        #expect(!checks.contains { $0 != nil })            // no checkbox at any nesting level
        #expect(texts.contains("[ ] x"))
    }

    @Test("three-deep nested content task item is NOT recognized")
    func threeDeepNestedContentTaskNotRecognized() throws {
        // `- - - [ ] x`: the innermost marker is preceded by two outer markers. Only the innermost item
        // holds the `[ ] x` paragraph; the outer items hold nested lists (never a checkbox paragraph).
        let (checks, texts) = try analyze("- - - [ ] x", options: Self.options)
        try #require(checks.count == 3, "expected three nested items, got \(checks)")
        #expect(!checks.contains { $0 != nil })
        #expect(texts.contains("[ ] x"))
    }

    @Test("content task item inside a block quote inside a list is NOT recognized")
    func taskInBlockQuoteInListNotRecognized() throws {
        // `- > - [ ] x`: list item > block quote > list item. The innermost marker is preceded by
        // `- > `, a non-space prefix, so `scan_tasklist` fails.
        let (checks, texts) = try analyze("- > - [ ] x", options: Self.options)
        try #require(checks.count == 2, "expected outer + inner items, got \(checks)")
        #expect(!checks.contains { $0 != nil })
        #expect(texts.contains("[ ] x"))
    }

    @Test("content task item nested in an ORDERED item is NOT recognized")
    func orderedNestedContentTaskNotRecognized() throws {
        // `1. - [ ] x`: the inner bullet marker is preceded by the ordered `1. ` marker.
        let (checks, texts) = try analyze("1. - [ ] x", options: Self.options)
        try #require(checks.count == 2, "expected outer ordered + inner bullet items, got \(checks)")
        #expect(!checks.contains { $0 != nil })
        #expect(texts.contains("[ ] x"))
    }

    // MARK: - Block-nested BUT alone on its own line IS recognized (physical-line, not block-depth)

    @Test("block-nested content task item alone on its own indented line IS recognized")
    func blockNestedButLineAnchoredIsRecognized() throws {
        // `- a` then `  - [ ] b`: `b` is block-nested (a sub-list of item `a`), but its marker is alone
        // on its physical line preceded only by spaces, so `scan_tasklist` matches from offset 0 and the
        // checkbox IS recognized. This pins the PHYSICAL-LINE semantics: recognition does not depend on
        // block-nesting depth. `a` is an ordinary item (nil); `b` is an unchecked task item.
        let (checks, texts) = try analyze("- a\n  - [ ] b", options: Self.options)
        try #require(checks.count == 2, "expected outer `a` + nested `b` items, got \(checks)")
        #expect(checks == [nil, false])                    // `a` ordinary, `b` recognized unchecked task
        #expect(texts.contains("b"))                        // `b`'s marker stripped
        #expect(!texts.contains { $0?.contains("[ ]") == true })   // no literal `[ ]` anywhere
    }
}
