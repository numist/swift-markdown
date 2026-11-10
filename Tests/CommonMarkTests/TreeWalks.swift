/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark

/// Walks a document and returns a compact `(kind, optional-literal)` sequence in DFS order.
internal func dfs(_ doc: borrowing MarkdownDocument) -> [(kind: MarkdownNode.Kind, literal: String?)] {
    var out: [(MarkdownNode.Kind, String?)] = []
    visit(doc.root, into: &out)
    return out.map { ($0.0, $0.1) }
}

private func visit(_ node: borrowing MarkdownNode, into out: inout [(MarkdownNode.Kind, String?)]) {
    out.append((node.kind, node.literal()))
    node.children.forEach { child in
        visit(child, into: &out)
    }
}

/// Collects each node's kind and source range, depth-first.
internal func dfsRanges(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, range: Range<MarkdownNode.SourcePosition>?)]
) {
    out.append((node.kind, node.sourceRange))
    node.children.forEach { child in
        dfsRanges(child, into: &out)
    }
}

/// The tightness of every list in `markdown` parsed with `options`, in document order.
internal func listTightness(_ markdown: String, options: MarkdownDocument.ParseOptions) -> [Bool] {
    MarkdownDocument.withParsedDocument(markdown, options: options) { document in
        var tight: [Bool] = []
        collectTightness(document.root, into: &tight)
        return tight
    }
}

private func collectTightness(_ node: borrowing MarkdownNode, into tight: inout [Bool]) {
    if case .list(let info) = node.kind {
        tight.append(info.tight)
    }
    node.children.forEach { child in
        collectTightness(child, into: &tight)
    }
}

/// Collects `(info, literal)` for every code block in the document in DFS order.
internal func codeBlocks(_ doc: borrowing MarkdownDocument) -> [(info: String, literal: String)] {
    var out: [(String, String)] = []
    collectCodeBlocks(doc.root, into: &out)
    return out.map { (info: $0.0, literal: $0.1) }
}

private func collectCodeBlocks(_ node: borrowing MarkdownNode, into out: inout [(String, String)]) {
    if case .codeBlock = node.kind {
        out.append((node.codeBlockInfoString() ?? "", node.literal() ?? ""))
    }
    node.children.forEach { child in
        collectCodeBlocks(child, into: &out)
    }
}

/// The kind of every code block in `markdown`, depth-first, as `TreeDump.describe` gives it, which tells a fenced code
/// block from an indented one.
internal func codeBlockKinds(_ markdown: String, options: MarkdownDocument.ParseOptions = []) -> [String] {
    MarkdownDocument.withParsedDocument(markdown, options: options) { doc in
        var kinds: [String] = []
        func visit(_ node: borrowing MarkdownNode) {
            if case .codeBlock = node.kind {
                kinds.append(TreeDump.describe(node.kind))
            }
            node.children.forEach { visit($0) }
        }
        visit(doc.root)
        return kinds
    }
}

/// Walks the inline children of every top-level paragraph and heading in the document, returning a compact `(kind, literal)` list.
internal func paragraphInlines(_ doc: borrowing MarkdownDocument) -> [(kind: MarkdownNode.Kind, literal: String?)] {
    var out: [(MarkdownNode.Kind, String?)] = []
    let root = doc.root
    root.children.forEach { block in
        switch block.kind {
        case .paragraph, .heading:
            block.children.forEach { inline in
                out.append((inline.kind, inline.literal()))
            }
        default:
            break
        }
    }
    return out.map { ($0.0, $0.1) }
}
