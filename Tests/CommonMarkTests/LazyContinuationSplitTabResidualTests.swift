/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// DFS-collect each node's kind and owned literal content (nil for structural nodes). File-scope +
// `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules.
private func dfsContent(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, literal: String?)]
) {
    out.append((node.kind, node.literal()))
    node.children.forEach { child in
        dfsContent(child, into: &out)
    }
}

/// The SPLIT-TAB sibling of `LazyContinuationTabResidualTests`: a NESTED block quote whose OUTER
/// matched prefix only PARTIALLY consumes a following tab, so the lazy continuation's residual is a run
/// of SYNTHETIC spaces (the tab's leftover columns) with NO source byte to slice - not a literal tab.
///
/// On `> > \u{60}x` then `>\ty\u{60}`, cmark matches only the OUTER block quote on line 2: its `>` plus
/// one optional column consumes ONE column of the tab, leaving `partially_consumed_tab` set. The inner
/// `>` fails, so the paragraph continues lazily and cmark's `add_line` (blocks.c:236) drops the split
/// tab byte and emits its LEFTOVER columns as spaces (`TAB_STOP - column % TAB_STOP`), then copies the
/// rest of the line verbatim. A code span spanning the soft break captures those spaces: the raw content
/// `x` + `\n` + `  ` + `y` normalizes (newline -> space) to `x   y`. The leftover count is column-math:
/// two spaces at nest-depth 2 (tab starts at column 2 after the consumed prefix -> 4 - 2), one at
/// depth 3 (column 3 -> 4 - 3).
///
/// Flag-OFF (the shipped, spec-correct parser) strips the residual entirely - identical to a
/// no-block-quote control.
@Suite("Lazy-continuation split-tab synthetic-space residual in code spans")
struct LazyContinuationSplitTabResidualTests {

    private static let specOptions: MarkdownDocument.ParseOptions = [.sourcePosition]

    private func content(_ src: String, _ options: MarkdownDocument.ParseOptions) -> [(kind: MarkdownNode.Kind, literal: String?)] {
        MarkdownDocument.withParsedDocument(src, options: options) { doc in
            var out: [(kind: MarkdownNode.Kind, literal: String?)] = []
            dfsContent(doc.root, into: &out)
            return out
        }
    }

    private func firstCodeInline(_ nodes: [(kind: MarkdownNode.Kind, literal: String?)]) -> String? {
        nodes.first { if case .codeInline = $0.kind { return true } else { return false } }?.literal
    }

    // Source shapes. `\u{60}` = backtick, `\t` = tab. Line 2 of each block-quote shape is a LAZY
    // continuation whose OUTER matched prefix splits a tab.
    private static let depth2Spaced = "> > \u{60}x\n>\ty\u{60}"     // outer `> >`, line 2 `>` TAB
    private static let depth2Tight = ">> \u{60}x\n>\ty\u{60}"       // tight `>>`, same result
    private static let depth2LongOpen = "> > \u{60}xx\n>\ty\u{60}"  // longer opener content
    private static let depth2SecondTab = "> > \u{60}x\n>\t\ty\u{60}"// two tabs: first splits, second literal
    private static let depth3 = "> > > \u{60}x\n>>\ty\u{60}"        // depth 3, line 2 `>>` TAB

    // Controls (unchanged by the split-tab extension).
    private static let noTab = "> > \u{60}x\n>y\u{60}"             // no tab -> just the newline join
    private static let markerSpaceTab = "> > \u{60}x\n> \ty\u{60}" // `> ` consumes to the tab stop cleanly

    // MARK: - Flag OFF (shipped): the residual is stripped - spec-correct, UNCHANGED

    @Test("flag-OFF: every split-tab shape strips to the bare newline join")
    func flagOff_stripsResidual() {
        #expect(firstCodeInline(content(Self.depth2Spaced, Self.specOptions)) == "x y")
        #expect(firstCodeInline(content(Self.depth2Tight, Self.specOptions)) == "x y")
        #expect(firstCodeInline(content(Self.depth2LongOpen, Self.specOptions)) == "xx y")
        #expect(firstCodeInline(content(Self.depth2SecondTab, Self.specOptions)) == "x y")
        #expect(firstCodeInline(content(Self.depth3, Self.specOptions)) == "x y")
    }

    // MARK: - Controls: unchanged under both flags by the split-tab extension

    @Test("control: no tab yields just the newline-join space under both flags")
    func noTab_control() throws {
        let literal = try #require(firstCodeInline(content(Self.noTab, Self.specOptions)),
                                   "fixture must contain a code span")
        #expect(literal == "x y")
    }

    @Test("control: marker+space consuming the partial keeps a clean literal tab (flag-ON), strips flag-OFF")
    func markerSpaceTab_control() throws {
        // `> ` consumes exactly to the tab stop, so no tab is split: flag-OFF strips it.
        #expect(firstCodeInline(content(Self.markerSpaceTab, Self.specOptions)) == "x y")
    }

    // MARK: - Text flow across the synthetic segment (must not crash; must match cmark)

    private func texts(_ nodes: [(kind: MarkdownNode.Kind, literal: String?)]) -> [String?] {
        nodes.filter { $0.kind == .text }.map { $0.literal }
    }

    @Test("text flow: a soft-break split-tab continuation strips the synthetic residual (both flags)")
    func textFlowSoftBreak_stripsResidual() {
        // `> > x` / `>\ty` - no code span, no backslash. The inline whitespace-skip after a soft break
        // consumes the synthetic residual, so it never reaches a text node (spec-correct in text flow).
        let nodes = content("> > x\n>\ty", Self.specOptions)
        #expect(texts(nodes) == ["x", "y"])
    }

    @Test("text flow: flag-OFF strips the backslash-break residual to the first non-space")
    func textFlowBackslashHardBreak_flagOff_strips() {
        // Flag-OFF the block parser begins the continuation at its first non-space, so the residual never
        // enters the content: `x`, hard break, `y`.
        let nodes = content("> > x\\\n>\ty", Self.specOptions)
        #expect(texts(nodes) == ["x", "y"])
        #expect(nodes.contains { $0.kind == .lineBreak })
    }
}
