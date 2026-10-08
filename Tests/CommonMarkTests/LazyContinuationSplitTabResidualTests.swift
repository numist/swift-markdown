/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Appends each node's kind and literal to `out` in document order.
private func dfsContent(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, literal: String?)]
) {
    out.append((node.kind, node.literal()))
    node.children.forEach { child in
        dfsContent(child, into: &out)
    }
}

/// A lazy continuation line of a nested block quote whose outer `>` and its optional following space consume only part
/// of a tab (Tabs; Block quotes). The tab's remaining columns are leading whitespace of the paragraph line, which the
/// paragraph's raw content drops (Paragraphs), so a code span crossing onto the line holds none of it.
@Suite("Partially consumed tab on a lazy continuation line in code spans")
struct LazyContinuationSplitTabResidualTests {

    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition]

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

    // `\u{60}` = backtick, `\t` = tab. Line 2 of each shape is a lazy continuation line whose outer block quote
    // marker consumes part of a tab.
    private static let depth2Spaced = "> > \u{60}x\n>\ty\u{60}"     // outer `> >`, line 2 `>` TAB
    private static let depth2Tight = ">> \u{60}x\n>\ty\u{60}"       // tight `>>`, same result
    private static let depth2LongOpen = "> > \u{60}xx\n>\ty\u{60}"  // longer opener content
    private static let depth2SecondTab = "> > \u{60}x\n>\t\ty\u{60}"// two tabs: first splits, second literal
    private static let depth3 = "> > > \u{60}x\n>>\ty\u{60}"        // depth 3, line 2 `>>` TAB

    // Shapes with no partially consumed tab.
    private static let noTab = "> > \u{60}x\n>y\u{60}"             // no tab
    private static let markerSpaceTab = "> > \u{60}x\n> \ty\u{60}" // `> ` consumes to the tab stop cleanly

    // MARK: - Partially consumed tab

    @Test("every partially consumed tab shape strips to the line ending's space")
    func splitTab_stripsResidual() {
        #expect(firstCodeInline(content(Self.depth2Spaced, Self.options)) == "x y")
        #expect(firstCodeInline(content(Self.depth2Tight, Self.options)) == "x y")
        #expect(firstCodeInline(content(Self.depth2LongOpen, Self.options)) == "xx y")
        #expect(firstCodeInline(content(Self.depth2SecondTab, Self.options)) == "x y")
        #expect(firstCodeInline(content(Self.depth3, Self.options)) == "x y")
    }

    // MARK: - No partially consumed tab

    @Test("no tab yields just the line ending's space")
    func noTab_control() throws {
        let literal = try #require(firstCodeInline(content(Self.noTab, Self.options)),
                                   "fixture must contain a code span")
        #expect(literal == "x y")
    }

    @Test("a tab after `> ` is stripped")
    func markerSpaceTab_control() throws {
        #expect(firstCodeInline(content(Self.markerSpaceTab, Self.options)) == "x y")
    }

    // MARK: - Text

    private func texts(_ nodes: [(kind: MarkdownNode.Kind, literal: String?)]) -> [String?] {
        nodes.filter { $0.kind == .text }.map { $0.literal }
    }

    @Test("text after a soft line break drops the tab's remaining columns")
    func textFlowSoftBreak_stripsResidual() {
        let nodes = content("> > x\n>\ty", Self.options)
        #expect(texts(nodes) == ["x", "y"])
    }

    @Test("text after a backslash hard line break drops the tab's remaining columns")
    func textFlowBackslashHardBreak_strips() {
        let nodes = content("> > x\\\n>\ty", Self.options)
        #expect(texts(nodes) == ["x", "y"])
        #expect(nodes.contains { $0.kind == .lineBreak })
    }
}
