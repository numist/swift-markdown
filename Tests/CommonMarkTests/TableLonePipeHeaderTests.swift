/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A header row holding only a leading pipe (Tables (extension)), optionally with whitespace, has no
/// cells, so it never matches the delimiter row's cell count and no table forms.
@Suite("Lone-pipe table row column count")
struct TableLonePipeHeaderTests {

    private func firstKind(_ source: String) -> String {
        MarkdownDocument.withParsedDocument(source, options: [.tables]) { doc -> String in
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

    // MARK: - Lone pipe

    @Test("lone-pipe header vs a 1-column delimiter is not a table")
    func lonePipeHeaderTrailingDelim() {
        #expect(firstKind("|\n-|") == "paragraph")
    }

    @Test("lone-pipe header vs a leading-pipe delimiter is not a table")
    func lonePipeHeaderLeadingDelim() {
        #expect(firstKind("|\n|-") == "paragraph")
    }

    @Test("a lone pipe followed by a form-feed has no cells")
    func lonePipeFormFeed() {
        #expect(firstKind("|\u{0C}\n-|") == "paragraph")
    }

    @Test("a lone pipe followed by a space has no cells")
    func lonePipeSpace() {
        #expect(firstKind("| \n-|") == "paragraph")
    }

    // MARK: - Headers with cells

    @Test("a 1-column header with a 1-column delimiter forms a table")
    func oneColumnTable() {
        #expect(firstKind("a\n-|") == "table")
    }

    @Test("a leading+trailing pipe (one empty cell) vs a 2-column delimiter stays a paragraph")
    func doublePipeMismatch() {
        #expect(firstKind("||\n-|-") == "paragraph")
    }

    @Test("a two-column header with a two-column delimiter forms a table")
    func ordinaryTable() {
        #expect(firstKind("a|b\n-|-") == "table")
    }
}
