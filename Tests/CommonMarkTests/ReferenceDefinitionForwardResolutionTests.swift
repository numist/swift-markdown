/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// DFS-render each node as an indented `kind[:detail]` line, so a whole tree can be asserted at once.
// File-scope + `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules (see `dfsRanges`).
internal func describeTree(_ node: borrowing MarkdownNode, depth: Int, into out: inout [String]) {
    let label: String
    switch node.kind {
    case .document: label = "document"
    case .paragraph: label = "paragraph"
    case .text: label = "text:" + (node.literal() ?? "")
    case .softBreak: label = "softBreak"
    case .lineBreak: label = "lineBreak"
    case .link: label = "link:" + (node.url() ?? "")
    case .list: label = "list"
    case .item: label = "item"
    default: label = "\(node.kind)"
    }
    out.append(String(repeating: "  ", count: depth) + label)
    node.children.forEach { child in
        describeTree(child, depth: depth + 1, into: &out)
    }
}

/// Link reference definitions are document-global: a reference resolves against a definition that
/// appears LATER in the document, including one nested inside a container (a list item), and the
/// reference's label may span a soft line break.
///
/// cmark collects every definition into `parser->refmap` during parsing — `try_parsing_reference`
/// runs at paragraph finalize wherever a paragraph closes, containers included — and resolves
/// references only afterward, during inline processing (`handle_close_bracket`, `src/inlines.c`),
/// against the complete map. So the order and nesting of a definition relative to its reference does
/// not matter, and a multi-line `[label]` reference matches a definition registered for the
/// whitespace-normalized label.
@Suite("Forward / nested link reference definition resolution")
struct ReferenceDefinitionForwardResolutionTests {

    // The finding surfaces only with both `.sourcePosition` and `.cmarkBugCompatibility` on — the
    // configuration the differential fuzzer parses under (the shipped `Markdown` module always enables
    // source positions, and the fuzzer forces bug-compatibility). Reference resolution is core
    // CommonMark and must not depend on either flag, so the whole family is exercised under them.
    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition, .cmarkBugCompatibility]

    private func tree(_ src: String) throws -> [String] {
        try MarkdownDocument.withParsedDocument(src, options: Self.options) { doc -> [String] in
            var out: [String] = []
            describeTree(doc.root, depth: 0, into: &out)
            return out
        }
    }

    @Test("multi-line reference resolves against a definition nested in a later list item")
    func multiLineReferenceResolvesAgainstNestedForwardDefinition() throws {
        // ` ][ar\n]\n- [ar]:[`: the paragraph is ` ][ar<nl>]` — a `]` text followed by a shortcut
        // reference `[ar<nl>]` whose label `ar` spans the soft break. It resolves against the ref-def
        // `[ar]:[` (label `ar`, destination `[`) defined LATER, inside the list item. The link text is
        // `ar` + a soft break; a leading `]` stays as text.
        let lines = try tree(" ][ar\n]\n- [ar]:[")
        // Fixture sanity: the list block must form regardless of whether the reference resolves.
        try #require(lines.contains("  list"), "fixture must form a list; got \(lines)")
        #expect(lines == [
            "document",
            "  paragraph",
            "    text:]",
            "    link:[",
            "      text:ar",
            "      softBreak",
            "  list",
            "    item",
        ])
    }

    @Test("single-line reference resolves against a definition nested in a later list item")
    func singleLineReferenceResolvesAgainstNestedForwardDefinition() throws {
        // The single-line analog of the finding, isolating the multi-line-label aspect: ` ][ar]` is a
        // `]` text then a shortcut reference `[ar]` (label all on one line), resolving against the same
        // later, nested ref-def `[ar]:[`.
        let lines = try tree(" ][ar]\n- [ar]:[")
        try #require(lines.contains("  list"), "fixture must form a list; got \(lines)")
        #expect(lines == [
            "document",
            "  paragraph",
            "    text:]",
            "    link:[",
            "      text:ar",
            "  list",
            "    item",
        ])
    }

    @Test("reference resolves against a definition defined LATER at top level")
    func referenceResolvesAgainstLaterTopLevelDefinition() throws {
        // The canonical forward reference: `[a]` on line 1, blank line, then the ref-def `[a]: /u`.
        // The definition paragraph is consumed, leaving one paragraph whose `[a]` is a resolved link.
        let lines = try tree("[a]\n\n[a]: /u")
        try #require(lines.contains(where: { $0.contains("link:") }), "fixture must form a link; got \(lines)")
        #expect(lines == [
            "document",
            "  paragraph",
            "    link:/u",
            "      text:a",
        ])
    }

    @Test("reference resolves against a definition defined LATER inside a list item")
    func referenceResolvesAgainstLaterNestedDefinition() throws {
        // A forward reference whose definition is nested in a later list item: `[a]`, blank line, then
        // `- [a]: /u`. The item's only content is the ref-def, so it is consumed, leaving an empty item;
        // the leading `[a]` resolves to a link.
        let lines = try tree("[a]\n\n- [a]: /u")
        try #require(lines.contains("  list"), "fixture must form a list; got \(lines)")
        #expect(lines == [
            "document",
            "  paragraph",
            "    link:/u",
            "      text:a",
            "  list",
            "    item",
        ])
    }
}
