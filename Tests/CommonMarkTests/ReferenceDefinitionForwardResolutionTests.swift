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

    /// The shipped parser's source-position configuration.
    private static let specOptions: MarkdownDocument.ParseOptions = [.sourcePosition]

    private func tree(_ src: String, options: MarkdownDocument.ParseOptions) -> [String] {
        MarkdownDocument.withParsedDocument(src, options: options) { doc -> [String] in
            var out: [String] = []
            describeTree(doc.root, depth: 0, into: &out)
            return out
        }
    }

    @Test("without cmark bug compatibility: multi-line reference resolves against a definition nested in a later list item")
    func multiLineReferenceResolvesAgainstNestedForwardDefinitionSpecCompliant() throws {
        let lines = tree(" ][ar\n]\n- [ar]:[", options: Self.specOptions)
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

    @Test("without cmark bug compatibility: single-line reference resolves against a definition nested in a later list item")
    func singleLineReferenceResolvesAgainstNestedForwardDefinitionSpecCompliant() throws {
        let lines = tree(" ][ar]\n- [ar]:[", options: Self.specOptions)
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

    @Test("without cmark bug compatibility: reference resolves against a definition defined LATER at top level")
    func referenceResolvesAgainstLaterTopLevelDefinitionSpecCompliant() throws {
        let lines = tree("[a]\n\n[a]: /u", options: Self.specOptions)
        try #require(lines.contains(where: { $0.contains("link:") }), "fixture must form a link; got \(lines)")
        #expect(lines == [
            "document",
            "  paragraph",
            "    link:/u",
            "      text:a",
        ])
    }

    @Test("without cmark bug compatibility: reference resolves against a definition defined LATER inside a list item")
    func referenceResolvesAgainstLaterNestedDefinitionSpecCompliant() throws {
        let lines = tree("[a]\n\n- [a]: /u", options: Self.specOptions)
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
