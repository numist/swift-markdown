/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark

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
