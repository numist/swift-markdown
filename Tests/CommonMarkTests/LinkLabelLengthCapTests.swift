/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// DFS-collect every `.link` node's destination URL, in document order. File-scope + `borrowing
/// MarkdownNode` to satisfy the noncopyable-borrow rules (see `dfs`).
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

/// The maximum link-label length cmark accepts is `MAX_LINK_LABEL_LENGTH` (1000): `link_label`
/// rejects only `length > 1000` (`src/inlines.c`), so it accepts a 1000-character label. CommonMark
/// §6.6 caps a label at "at most 999 characters", so 1000 is a cmark off-by-one. The shipped
/// deliverable is spec-correct (reject `> 999`); under `.cmarkBugCompatibility` (adopted only by the
/// differential fuzzer) it reproduces cmark and accepts up to 1000. cmark's single constant governs
/// every label site, so these tests pin both the block reference-definition label scanner and the
/// inline (contiguous + multi-segment) reference label scanners at the boundary in both flag modes.
@Suite("Link label length cap - cmark MAX_LINK_LABEL_LENGTH")
struct LinkLabelLengthCapTests {

    /// A label of `n` `a` bytes (no escapes, so scanned length == `n`).
    private func label(_ n: Int) -> String { String(repeating: "a", count: n) }

    /// The highest label length that resolves in each flag mode: 999 spec-correct, 1000 under
    /// `.cmarkBugCompatibility`.
    private static let modes: [(options: MarkdownDocument.ParseOptions, cap: Int)] = [
        (options: [], cap: 999),
        (options: [.cmarkBugCompatibility], cap: 1000),
    ]

    // MARK: - Block reference-definition label scanner (`parseOneLinkDefinition`)

    /// A lone reference definition `[label]: /u` is registered — and thus consumed to no block — only
    /// when its label passes the cap. Over the cap the whole line falls through to a paragraph of
    /// literal text. The presence/absence of that paragraph isolates the block reference-definition
    /// label scanner (`parseOneLinkDefinition` → the contiguous `matchLinkLabel`).
    @Test("reference definition registers at the cap but not one past it")
    func referenceDefinitionLabelCap() throws {
        for (options, cap) in Self.modes {
            // At the cap: the definition is valid, so the line is consumed and no block remains.
            try MarkdownDocument.withParsedDocument("[\(label(cap))]: /u", options: options) { doc in
                let kinds = dfs(doc).map(\.kind)
                #expect(!kinds.contains(.paragraph),
                        "options=\(options.rawValue): a \(cap)-char definition must be consumed")
            }

            // One past the cap: the label scan rewinds, so the line stays a literal paragraph.
            try MarkdownDocument.withParsedDocument("[\(label(cap + 1))]: /u", options: options) { doc in
                let nodes = dfs(doc)
                #expect(nodes.map(\.kind).contains(.paragraph),
                        "options=\(options.rawValue): a \(cap + 1)-char definition must fall through to text")
                #expect(nodes.contains { $0.literal?.hasPrefix("[") == true },
                        "the over-cap definition line must survive as literal text")
            }
        }
    }

    // MARK: - Inline shortcut reference label scanner (contiguous `matchLinkLabel`)

    /// A shortcut reference `[label]` (same label as its definition, so both scans see the same
    /// length) resolves to a link only at or below the cap; one past it the reference stays literal
    /// text. Exercises the inline reference label scanner together with the definition scanner.
    @Test("shortcut reference resolves at the cap but not one past it")
    func shortcutReferenceLabelCap() throws {
        for (options, cap) in Self.modes {
            try MarkdownDocument.withParsedDocument("[\(label(cap))]: /u\n\n[\(label(cap))]", options: options) { doc in
                #expect(linkURLs(doc) == ["/u"],
                        "options=\(options.rawValue): a \(cap)-char reference must resolve")
            }

            try MarkdownDocument.withParsedDocument("[\(label(cap + 1))]: /u\n\n[\(label(cap + 1))]", options: options) { doc in
                #expect(linkURLs(doc).isEmpty,
                        "options=\(options.rawValue): a \(cap + 1)-char reference must stay literal")
            }
        }
    }

    // MARK: - Multi-segment full-reference label scanner (`matchLinkLabel(from:end:in:)`)

    /// A cross-line full reference `[t][A\nB]` inside a block quote drives the multi-segment
    /// `matchLinkLabel(from:end:in:)` overload (the contiguous window can't image the straddling
    /// label). Its scanned length counts the newline join, so at the flag-ON cap (500 + 1 + 499 =
    /// 1000) the reference resolves — which it could not if that overload's cap were left ungated.
    /// Flag-OFF the same input yields no link, though there the definition `[A B]: /u` (1000
    /// contiguous chars) is already rejected by the contiguous scanner, so no key is ever registered.
    /// The definition normalizes to the same key as the reference (interior whitespace collapses to
    /// one space), which is why both labels must be the same length.
    @Test("cross-line full reference respects the gated cap")
    func multiSegmentReferenceLabelCap() throws {
        // 500 + newline + 499 = 1000 scanned bytes; normalizes to a 500-a / space / 499-a key.
        let left = label(500)
        let right = label(499)
        let source = "[\(left) \(right)]: /u\n\n>[t][\(left)\n\(right)]"

        try MarkdownDocument.withParsedDocument(source, options: [.cmarkBugCompatibility]) { doc in
            #expect(linkURLs(doc) == ["/u"], "flag-ON: a 1000-length cross-line label must resolve")
        }

        try MarkdownDocument.withParsedDocument(source, options: []) { doc in
            #expect(linkURLs(doc).isEmpty, "flag-OFF: the 1000-char definition is rejected, so nothing resolves")
        }
    }
}
