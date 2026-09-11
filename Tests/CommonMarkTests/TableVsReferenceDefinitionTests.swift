/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// GFM table detection takes precedence over link-reference-definition extraction, matching cmark.
///
/// cmark opens a table while processing the delimiter row (`extensions/table.c`
/// `try_opening_table_block`), which converts the still-open paragraph to a table BEFORE it is ever
/// finalized. Reference-link definitions are resolved only at PARAGRAPH finalize
/// (`src/blocks.c` `resolve_reference_link_definitions`, reached from `finalize`), so a paragraph that
/// became a table is never probed for ref-defs. The rewrite detects tables at finalize too, so the
/// two matchers meet in `runParagraphMatchers`; the table must be tried first.
///
/// The motivating divergence: `[\n|-\n]:/` looks like a multi-line ref-def (`[<newline>|-<newline>]`
/// closes the label, then `: /` is the destination), but its second physical line `|-` is a delimiter
/// row, so cmark forms a table and never extracts the ref-def. Ref-def-first ordering consumed the
/// whole paragraph as an (output-free) definition and produced an EMPTY document.
@Suite("GFM table vs link reference definition precedence")
struct TableVsReferenceDefinitionTests {

    private struct Block {
        enum Kind { case none, paragraph, heading, table, other }
        var kind: Kind = .none
        var alignments: [MarkdownNode.TableAlignment] = []
        var headerCells: [String] = []
        var bodyRows: [[String]] = []
        /// The concatenated literal text of the block's direct-child inlines (paragraph / heading; empty for a table / other).
        var text: String = ""
    }

    /// Extract a `.table` node's header-cell texts, per-column alignments, and body-row cell texts.
    private func tableBlock(from node: borrowing MarkdownNode) -> Block {
        var block = Block()
        block.kind = .table
        node.children.forEach { row in
            guard case .tableRow(let isHeader) = row.kind else { return }
            var cellTexts: [String] = []
            var aligns: [MarkdownNode.TableAlignment] = []
            row.children.forEach { cell in
                guard case .tableCell(let alignment, _, _) = cell.kind else { return }
                aligns.append(alignment)
                var text = ""
                cell.children.forEach { inline in
                    if let lit = inline.literal() { text += lit }
                }
                cellTexts.append(text)
            }
            if isHeader {
                block.headerCells = cellTexts
                block.alignments = aligns
            } else {
                block.bodyRows.append(cellTexts)
            }
        }
        return block
    }

    /// The document's top-level blocks, each classified as paragraph / heading / table (with shape).
    private func blocks(
        _ source: String,
        options: MarkdownDocument.ParseOptions = [.tables]
    ) throws -> [Block] {
        try MarkdownDocument.withParsedDocument(source, options: options) { doc -> [Block] in
            var out: [Block] = []
            doc.root.children.forEach { child in
                var block = Block()
                switch child.kind {
                case .paragraph:
                    block.kind = .paragraph
                    child.children.forEach { inline in
                        if let lit = inline.literal() { block.text += lit }
                    }
                case .heading:
                    block.kind = .heading
                    child.children.forEach { inline in
                        if let lit = inline.literal() { block.text += lit }
                    }
                case .table:
                    block = self.tableBlock(from: child)
                default:
                    block.kind = .other
                }
                out.append(block)
            }
            return out
        }
    }

    /// The first resolved reference-link URL anywhere in `source`, or `nil`.
    private func firstLinkURL(
        _ source: String,
        options: MarkdownDocument.ParseOptions = [.tables]
    ) throws -> String? {
        try MarkdownDocument.withParsedDocument(source, options: options) { doc -> String? in
            var found: String? = nil
            func walk(_ n: borrowing MarkdownNode) {
                if found == nil, case .link = n.kind { found = n.url() }
                n.children.forEach { walk($0) }
            }
            walk(doc.root)
            return found
        }
    }

    @Test("a delimiter-row second line forms a table even when the paragraph reads as a ref-def")
    func delimiterRowBeatsReferenceDefinition() throws {
        // `[\n|-\n]:/`: label `[<nl>|-<nl>]`, then `: /` — a valid (output-free) ref-def shape. But line 2
        // `|-` is a delimiter row, so cmark forms a table; the ref-def is never extracted.
        let doc = try blocks("[\n|-\n]:/")
        let table = try #require(doc.first, "expected a block, got an empty document")
        try #require(table.kind == .table, "expected a table, got \(table.kind)")
        #expect(table.alignments == [.none])
        #expect(table.headerCells == ["["])
        #expect(table.bodyRows == [["]:/"]])
        #expect(doc.count == 1)
    }

    @Test("the non-ref-def-shaped control still forms the same table")
    func delimiterRowControlWithoutColon() throws {
        // `[\n|-\n]a`: last line `]a` never looks like a ref-def destination (no `:` after `]`), so this
        // matched cmark even under ref-def-first ordering. Pin it so the reorder does not regress it.
        let doc = try blocks("[\n|-\n]a")
        let table = try #require(doc.first, "expected a block, got an empty document")
        try #require(table.kind == .table, "expected a table, got \(table.kind)")
        #expect(table.alignments == [.none])
        #expect(table.headerCells == ["["])
        #expect(table.bodyRows == [["]a"]])
        #expect(doc.count == 1)
    }

    @Test("a complete first-line ref-def becomes the header cell when a delimiter row follows")
    func firstLineReferenceDefinitionAbsorbedAsHeader() throws {
        // `[foo]: /bar\n|-\n|x`: line 1 is a complete ref-def by itself, but line 2 `|-` is a delimiter
        // row, so cmark makes `[foo]: /bar` the table's header cell and registers NO definition. The old
        // ref-def-first ordering registered `foo` -> /bar and made `|-\n|x` a paragraph — the strongest
        // discriminator that the table now wins.
        let doc = try blocks("[foo]: /bar\n|-\n|x")
        let table = try #require(doc.first, "expected a block, got an empty document")
        try #require(table.kind == .table, "expected a table, got \(table.kind)")
        #expect(table.headerCells == ["[foo]: /bar"])
        #expect(table.bodyRows == [["x"]])
        #expect(doc.count == 1)
        // The definition must NOT have been registered: a trailing `[foo]` reference stays literal.
        #expect(try firstLinkURL("[foo]: /bar\n|-\n|x\n\n[foo]") == nil, "the ref-def must not be registered")
    }

    @Test("a genuine multi-line ref-def without a delimiter row is still a ref-def")
    func genuineMultiLineReferenceDefinitionNotRegressed() throws {
        // `[a\nb]: /u` spans two lines but its second line `b]: /u` is NOT a delimiter row, so no table
        // forms and the definition must still be extracted: the def paragraph is dropped and `[a b]`
        // resolves to a link. Guards the reorder against breaking real multi-line ref-defs.
        let doc = try blocks("[a\nb]: /u\n\n[a b]")
        // Exactly one surviving block (the `[a b]` reference paragraph); the ref-def paragraph is dropped.
        try #require(doc.count == 1, "expected the ref-def to be consumed, leaving one block; got \(doc.count)")
        #expect(doc[0].kind == .paragraph, "expected a paragraph, got \(doc[0].kind)")
        let url = try #require(try firstLinkURL("[a\nb]: /u\n\n[a b]"), "expected `[a b]` to resolve to a link")
        #expect(url == "/u")
    }

    // MARK: - Bare (pipe-less) delimiter row after a complete ref-def (regression: refines #134)
    //
    // #134 made table detection run before ref-def extraction unconditionally. That was too coarse: a BARE
    // `-`/`=` delimiter row can never open a table in cmark. cmark's `open_new_blocks` tries the
    // setext-heading-underline branch (`scan_setext_heading_line`, which matches a pipe-less run of `-` or
    // `=`) BEFORE the GFM table extension (`try_opening_table_block`, the last-resort block opener). The
    // setext branch resolves reference-link definitions on the open paragraph; when the whole paragraph is a
    // complete ref-def, no header content remains, so no heading forms and the bare `-` becomes a fresh
    // paragraph line — the table extension is never reached. A PIPE-containing delimiter row (`|-`) does NOT
    // match the setext scanner, so the table extension runs and a table opens over the would-be ref-def.
    // These run under `.cmarkBugCompatibility` (the fuzzer's fixed option) because only there does cmark keep
    // the emptied paragraph open and absorb the `-` (spec-correct default drops it and re-dispatches `-`).

    @Test("a bare `-` delimiter row after a complete single-line ref-def is a ref-def + paragraph, not a table")
    func bareDelimiterAfterCompleteReferenceDefinition() throws {
        // `[o]:o\n-`: line 1 is a COMPLETE ref-def; line 2 `-` is a bare (pipe-less) delimiter row. cmark
        // resolves the ref-def at the setext branch (no header left → no heading) and the `-` becomes a
        // paragraph. #134's table-first ordering wrongly formed a table with header `[o]:o`.
        let doc = try blocks("[o]:o\n-", options: [.tables, .cmarkBugCompatibility])
        try #require(doc.count == 1, "expected the ref-def to be extracted, leaving one paragraph; got \(doc.count)")
        try #require(doc[0].kind == .paragraph, "expected a paragraph, got \(doc[0].kind)")
        #expect(doc[0].text == "-")
    }

    @Test("a bare `-` delimiter row after a ref-def with a space before the destination is a ref-def + paragraph")
    func bareDelimiterAfterCompleteReferenceDefinitionWithSpace() throws {
        // `[o]: o\n-`: same shape with a space after the label colon — still a complete ref-def + bare `-`.
        let doc = try blocks("[o]: o\n-", options: [.tables, .cmarkBugCompatibility])
        try #require(doc.count == 1, "expected the ref-def to be extracted, leaving one paragraph; got \(doc.count)")
        try #require(doc[0].kind == .paragraph, "expected a paragraph, got \(doc[0].kind)")
        #expect(doc[0].text == "-")
    }

    @Test("a PIPE delimiter row after a complete ref-def still forms a table (must not re-regress #134)")
    func pipeDelimiterAfterCompleteReferenceDefinitionStaysTable() throws {
        // `[o]:o\n|-`: line 2 `|-` has a pipe, so it does NOT match the setext scanner; cmark's table
        // extension opens a table using the raw paragraph string `[o]:o` as the header cell (the ref-def is
        // never resolved). Both implementations already agreed here; pin it so the fix keeps it a table.
        let doc = try blocks("[o]:o\n|-", options: [.tables, .cmarkBugCompatibility])
        let table = try #require(doc.first, "expected a block, got an empty document")
        try #require(table.kind == .table, "expected a table, got \(table.kind)")
        #expect(table.headerCells == ["[o]:o"])
        #expect(table.bodyRows == [])
        #expect(doc.count == 1)
    }

    @Test("the #134 incomplete-header table still forms under the fuzzer's option set")
    func incompleteHeaderDelimiterStaysTableUnderBugCompat() throws {
        // `[\n|-\n]:/` (the #134 case) under `.cmarkBugCompatibility`: line 2 `|-` is a pipe delimiter, so
        // the table opens with header `[` and body `]:/`. The bare-delimiter fix must not regress this.
        let doc = try blocks("[\n|-\n]:/", options: [.tables, .cmarkBugCompatibility])
        let table = try #require(doc.first, "expected a block, got an empty document")
        try #require(table.kind == .table, "expected a table, got \(table.kind)")
        #expect(table.headerCells == ["["])
        #expect(table.bodyRows == [["]:/"]])
        #expect(doc.count == 1)
    }

    @Test("a genuine multi-line ref-def still resolves under the fuzzer's option set")
    func genuineReferenceDefinitionStillResolvesUnderBugCompat() throws {
        // `[a\nb]: /u\n\n[a b]`: no delimiter row, so no table pends; the multi-line ref-def is extracted
        // and `[a b]` resolves to a link. Guards the fix against breaking real ref-defs under the fuzzer's
        // option set.
        let url = try #require(try firstLinkURL("[a\nb]: /u\n\n[a b]", options: [.tables, .cmarkBugCompatibility]),
                               "expected `[a b]` to resolve to a link")
        #expect(url == "/u")
    }
}
