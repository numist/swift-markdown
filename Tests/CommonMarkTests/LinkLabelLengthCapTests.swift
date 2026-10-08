/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Every `.link` node's destination URL, in document order.
private func linkURLs(_ doc: borrowing MarkdownDocument) -> [String] {
    var out: [String] = []
    collectLinkURLs(doc.root, into: &out)
    return out
}

private func collectLinkURLs(_ node: borrowing MarkdownNode, into out: inout [String]) {
    if node.kind == .link {
        out.append(node.url() ?? "")
    }
    node.children.forEach { collectLinkURLs($0, into: &out) }
}

/// A link label has at most 999 characters inside its brackets (Links). This holds for the label of a link reference
/// definition and for the label of a reference link, including one that spans a line ending.
@Suite("Link label length cap")
struct LinkLabelLengthCapTests {

    /// A label of `n` `a` bytes (no escapes, so scanned length == `n`).
    private func label(_ n: Int) -> String { String(repeating: "a", count: n) }

    // MARK: - Link reference definitions

    /// A link reference definition produces no block, so over the cap the line is a paragraph.
    @Test("reference definition registers at the cap but not one past it")
    func referenceDefinitionLabelCap() {
        MarkdownDocument.withParsedDocument("[\(label(999))]: /u", options: []) { doc in
            let kinds = dfs(doc).map(\.kind)
            #expect(!kinds.contains(.paragraph), "a 999-char definition must be consumed")
        }

        MarkdownDocument.withParsedDocument("[\(label(1000))]: /u", options: []) { doc in
            let nodes = dfs(doc)
            #expect(nodes.map(\.kind).contains(.paragraph), "a 1000-char definition must fall through to text")
            #expect(nodes.contains { $0.literal?.hasPrefix("[") == true },
                    "the over-cap definition line must survive as literal text")
        }
    }

    // MARK: - Shortcut reference links

    @Test("shortcut reference resolves at the cap but not one past it")
    func shortcutReferenceLabelCap() {
        MarkdownDocument.withParsedDocument("[\(label(999))]: /u\n\n[\(label(999))]", options: []) { doc in
            #expect(linkURLs(doc) == ["/u"], "a 999-char reference must resolve")
        }

        MarkdownDocument.withParsedDocument("[\(label(1000))]: /u\n\n[\(label(1000))]", options: []) { doc in
            #expect(linkURLs(doc).isEmpty, "a 1000-char reference must stay literal")
        }
    }

    // MARK: - Full reference links across a line ending

    /// The definition's label and the reference's label, which spans a line ending in a block quote, normalize to the
    /// same label (Links). Both are 1000 characters, so the reference doesn't resolve.
    @Test("a 1000-character full reference label across a line ending does not resolve")
    func multiSegmentReferenceLabelCap() {
        let left = label(500)
        let right = label(499)
        let source = "[\(left) \(right)]: /u\n\n>[t][\(left)\n\(right)]"

        MarkdownDocument.withParsedDocument(source, options: []) { doc in
            #expect(linkURLs(doc).isEmpty, "the 1000-character label defines nothing, so nothing resolves")
        }
    }

    // MARK: - Labels past the cap

    @Test("1000- and 1001-character labels neither define nor resolve")
    func overCapLabelsNeitherDefineNorResolve() {
        for length in [1000, 1001] {
            MarkdownDocument.withParsedDocument("[\(label(length))]: /u", options: []) { doc in
                let nodes = dfs(doc)
                #expect(nodes.map(\.kind) == [.document, .paragraph, .text], "length=\(length)")
                #expect(nodes.compactMap(\.literal) == ["[\(label(length))]: /u"], "length=\(length)")
            }

            MarkdownDocument.withParsedDocument("[\(label(length))]: /u\n\n[\(label(length))]", options: []) { doc in
                let nodes = dfs(doc)
                #expect(linkURLs(doc) == [], "length=\(length)")
                #expect(nodes.map(\.kind) == [.document, .paragraph, .text, .paragraph, .text], "length=\(length)")
                #expect(nodes.compactMap(\.literal) == ["[\(label(length))]: /u", "[\(label(length))]"], "length=\(length)")
            }
        }
    }
}
