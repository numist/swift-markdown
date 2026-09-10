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
/// The rewrite reproduces this within its zero-copy model by materializing ONLY the leftover spaces into
/// the arena as one non-source segment interleaved among the source-backed segments (the multi-segment
/// arena-content extension); the surrounding source stays a borrowed slice, and any following LITERAL
/// tab is preserved by the source segment that begins just past the split tab.
///
/// Flag-ON (`.cmarkBugCompatibility`, the differential-fuzzer surface) reproduces cmark's synthetic
/// spaces. Flag-OFF (the shipped, spec-correct parser) strips the residual entirely - identical to a
/// no-block-quote control. This is a strict extension of Quirk E; flag-OFF behaviour is unchanged.
@Suite("Lazy-continuation split-tab synthetic-space residual in code spans")
struct LazyContinuationSplitTabResidualTests {

    private static let quirkOptions: MarkdownDocument.ParseOptions = [.cmarkBugCompatibility]
    private static let quirkOptionsPos: MarkdownDocument.ParseOptions = [.sourcePosition, .cmarkBugCompatibility]
    private static let specOptions: MarkdownDocument.ParseOptions = [.sourcePosition]

    private func content(_ src: String, _ options: MarkdownDocument.ParseOptions) throws -> [(kind: MarkdownNode.Kind, literal: String?)] {
        try MarkdownDocument.withParsedDocument(src, options: options) { doc in
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

    // MARK: - Flag ON: the code span KEEPS the synthetic leftover-column spaces (matches cmark)

    @Test("flag-ON: depth-2 lazy split-tab yields three synthetic spaces")
    func depth2_flagOn() throws {
        for options in [Self.quirkOptions, Self.quirkOptionsPos] {
            let literal = try #require(firstCodeInline(try content(Self.depth2Spaced, options)),
                                       "fixture must contain a code span (options=\(options.rawValue))")
            #expect(literal == "x   y", "options=\(options.rawValue)")
        }
    }

    @Test("flag-ON: tight `>>` nest yields the same three synthetic spaces")
    func depth2Tight_flagOn() throws {
        for options in [Self.quirkOptions, Self.quirkOptionsPos] {
            let literal = try #require(firstCodeInline(try content(Self.depth2Tight, options)),
                                       "fixture must contain a code span (options=\(options.rawValue))")
            #expect(literal == "x   y", "options=\(options.rawValue)")
        }
    }

    @Test("flag-ON: leftover-column count is independent of the opener content")
    func depth2LongOpen_flagOn() throws {
        for options in [Self.quirkOptions, Self.quirkOptionsPos] {
            let literal = try #require(firstCodeInline(try content(Self.depth2LongOpen, options)),
                                       "fixture must contain a code span (options=\(options.rawValue))")
            #expect(literal == "xx   y", "options=\(options.rawValue)")
        }
    }

    @Test("flag-ON: only the split tab becomes spaces; a following literal tab stays literal")
    func depth2SecondTab_flagOn() throws {
        for options in [Self.quirkOptions, Self.quirkOptionsPos] {
            let literal = try #require(firstCodeInline(try content(Self.depth2SecondTab, options)),
                                       "fixture must contain a code span (options=\(options.rawValue))")
            #expect(literal == "x   \ty", "options=\(options.rawValue)")
        }
    }

    @Test("flag-ON: depth-3 leftover column count is two synthetic spaces")
    func depth3_flagOn() throws {
        for options in [Self.quirkOptions, Self.quirkOptionsPos] {
            let literal = try #require(firstCodeInline(try content(Self.depth3, options)),
                                       "fixture must contain a code span (options=\(options.rawValue))")
            #expect(literal == "x  y", "options=\(options.rawValue)")
        }
    }

    // MARK: - Flag OFF (shipped): the residual is stripped - spec-correct, UNCHANGED

    @Test("flag-OFF: every split-tab shape strips to the bare newline join")
    func flagOff_stripsResidual() throws {
        #expect(try firstCodeInline(try content(Self.depth2Spaced, Self.specOptions)) == "x y")
        #expect(try firstCodeInline(try content(Self.depth2Tight, Self.specOptions)) == "x y")
        #expect(try firstCodeInline(try content(Self.depth2LongOpen, Self.specOptions)) == "xx y")
        #expect(try firstCodeInline(try content(Self.depth2SecondTab, Self.specOptions)) == "x y")
        #expect(try firstCodeInline(try content(Self.depth3, Self.specOptions)) == "x y")
    }

    // MARK: - Controls: unchanged under both flags by the split-tab extension

    @Test("control: no tab yields just the newline-join space under both flags")
    func noTab_control() throws {
        for options in [Self.quirkOptions, Self.quirkOptionsPos, Self.specOptions] {
            let literal = try #require(firstCodeInline(try content(Self.noTab, options)),
                                       "fixture must contain a code span (options=\(options.rawValue))")
            #expect(literal == "x y", "options=\(options.rawValue)")
        }
    }

    @Test("control: marker+space consuming the partial keeps a clean literal tab (flag-ON), strips flag-OFF")
    func markerSpaceTab_control() throws {
        // `> ` consumes exactly to the tab stop, so no tab is split: flag-ON carries the LITERAL tab
        // (the existing zero-copy #137 carry), flag-OFF strips it. Guards that the split-tab branch does
        // not perturb the clean-boundary carry.
        for options in [Self.quirkOptions, Self.quirkOptionsPos] {
            let literal = try #require(firstCodeInline(try content(Self.markerSpaceTab, options)),
                                       "fixture must contain a code span (options=\(options.rawValue))")
            #expect(literal == "x \ty", "options=\(options.rawValue)")
        }
        #expect(try firstCodeInline(try content(Self.markerSpaceTab, Self.specOptions)) == "x y")
    }

    // MARK: - Text flow across the synthetic segment (must not crash; must match cmark)

    private func texts(_ nodes: [(kind: MarkdownNode.Kind, literal: String?)]) -> [String?] {
        nodes.filter { $0.kind == .text }.map { $0.literal }
    }

    @Test("text flow: a soft-break split-tab continuation strips the synthetic residual (both flags)")
    func textFlowSoftBreak_stripsResidual() throws {
        // `> > x` / `>\ty` - no code span, no backslash. The inline whitespace-skip after a soft break
        // consumes the synthetic residual, so it never reaches a text node (spec-correct in text flow).
        for options in [Self.quirkOptions, Self.quirkOptionsPos, Self.specOptions] {
            let nodes = try content("> > x\n>\ty", options)
            #expect(texts(nodes) == ["x", "y"], "options=\(options.rawValue)")
        }
    }

    @Test("text flow: a backslash hard break keeps the synthetic residual as literal text (flag-ON)")
    func textFlowBackslashHardBreak_keepsResidual() throws {
        // `> > x\` / `>\ty` - a backslash hard break, after which cmark's `handle_backslash` does NOT skip
        // the next line's leading whitespace, so the synthetic split-tab residual survives as literal text
        // (`x`, hard break, `  y`). This is the text-flow sibling of the code-span cases and the regression
        // guard for a text run STRADDLING the synthetic arena segment into the following source segment.
        for options in [Self.quirkOptions, Self.quirkOptionsPos] {
            let nodes = try content("> > x\\\n>\ty", options)
            #expect(texts(nodes) == ["x", "  y"], "options=\(options.rawValue)")
            #expect(nodes.contains { $0.kind == .lineBreak }, "fixture must contain a hard line break (options=\(options.rawValue))")
        }
    }

    @Test("text flow: flag-OFF strips the backslash-break residual to the first non-space")
    func textFlowBackslashHardBreak_flagOff_strips() throws {
        // Flag-OFF the block parser begins the continuation at its first non-space, so the residual never
        // enters the content: `x`, hard break, `y`.
        let nodes = try content("> > x\\\n>\ty", Self.specOptions)
        #expect(texts(nodes) == ["x", "y"])
        #expect(nodes.contains { $0.kind == .lineBreak })
    }
}
