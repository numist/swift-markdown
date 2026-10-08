/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark

/// Walks a document and returns a compact `(kind, optional-literal)` sequence in DFS order. Useful for asserting the shape of parsed trees in tests without writing nested forEach blocks.
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

/// Collect `(info, literal)` for every code block in the document in DFS order, so tests can assert
/// on code blocks nested inside containers (e.g. a fenced block inside a list item).
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
