/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A table row that is a lone `|` (a single pipe, optionally with surrounding whitespace) has ZERO
/// columns, matching cmark's `row_from_string` (cells are created only inside its scan loop, which the
/// consumed leading pipe never enters). The rewrite counted it as one empty cell, so a `|` header
/// spuriously matched a 1-column delimiter and formed a table (`|\n-|` → Table) where cmark keeps a
/// paragraph (0 vs 1 columns). Spec-aligned `[fix]`, asserted WITHOUT `.cmarkBugCompatibility`.
@Suite("Lone-pipe table row column count")
struct TableLonePipeHeaderTests {

    private func firstKind(_ source: String) throws -> String {
        try MarkdownDocument.withParsedDocument(source, options: [.tables]) { doc -> String in
            var kinds: [String] = []
            doc.root.children.forEach {
                switch $0.kind {
                case .paragraph: kinds.append("paragraph")
                case .heading: kinds.append("heading")
                case .table: kinds.append("table")
                default: kinds.append("other")
                }
            }
            return kinds.first ?? "none"
        }
    }

    // MARK: - FIX: a lone-pipe header is 0 columns, so no table forms

    @Test("lone-pipe header vs a 1-column delimiter is not a table")
    func lonePipeHeaderTrailingDelim() throws {
        #expect(try firstKind("|\n-|") == "paragraph")
    }

    @Test("lone-pipe header vs a leading-pipe delimiter is not a table")
    func lonePipeHeaderLeadingDelim() throws {
        #expect(try firstKind("|\n|-") == "paragraph")
    }

    @Test("a lone pipe followed by a form-feed is still zero columns (spacechar includes FF)")
    func lonePipeFormFeed() throws {
        // cmark's `scan_table_cell_end` spacechar is [ \t\v\f], so `|\f` is a consumed pipe + whitespace →
        // 0 columns. FF passes the fuzzer's input filter, so this must not spuriously form a table.
        #expect(try firstKind("|\u{0C}\n-|") == "paragraph")
    }

    @Test("a lone pipe followed by a space is still zero columns")
    func lonePipeSpace() throws {
        #expect(try firstKind("| \n-|") == "paragraph")
    }

    // MARK: - LEAVE guards

    @Test("a 1-column header with a 1-column delimiter still forms a table")
    func oneColumnStillTable() throws {
        #expect(try firstKind("a\n-|") == "table")
    }

    @Test("a leading+trailing pipe (one empty cell) vs a 2-column delimiter stays a paragraph")
    func doublePipeMismatch() throws {
        // `||` is ONE empty cell (the cell between the pipes); a 2-column delimiter mismatches → paragraph.
        #expect(try firstKind("||\n-|-") == "paragraph")
    }

    @Test("an ordinary two-column table is unaffected")
    func ordinaryTable() throws {
        #expect(try firstKind("a|b\n-|-") == "table")
    }
}
