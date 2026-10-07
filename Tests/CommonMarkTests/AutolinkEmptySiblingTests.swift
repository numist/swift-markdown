/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// DFS-collect each node's kind, text literal, and (for links) destination URL. File-scope +
// `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules (see
// EmptyTextBeforeSoftBreakTests.dfsKindsAndText).
private func dfsAutolinkNodes(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?, url: String?)]
) {
    out.append((node.kind, node.literal(), node.url()))
    node.children.forEach { child in
        dfsAutolinkNodes(child, into: &out)
    }
}

/// Empty `Text ""` siblings that cmark-gfm's GFM autolink extension leaves around an autolink.
///
/// cmark's autolink extension splits the text flow into `[before, link, after]`. For an EMAIL match the
/// extension's `postprocess_text` (`extensions/autolink.c`) always inserts a `before` and an `after`
/// text node bounding the link, keeping each even when it is empty. For a `://`-scheme URL match,
/// `url_match` rewinds the scheme letters out of the preceding text node with `cmark_node_unput`; when
/// that node held only the scheme, it is left EMPTY - an empty LEADING text node (a scheme URL never
/// gets a trailing one). A `www.` match (`www_match`) rewinds nothing and its trigger fires before any
/// text is emitted, so it gets NO empty sibling on either side. When a `before`/`after` portion is
/// non-empty the existing behavior already matches (e.g. `x www.example.com y` yields `Text "x "` +
/// Link + `Text " y"`), so only the empty case differs.
///
/// The shipped (spec-correct) parser keeps the clean tree with no empty siblings.
@Suite("GFM autolink empty-text siblings (cmark bug-for-bug)")
struct AutolinkEmptySiblingTests {

    /// The shipped configuration: GFM autolink on.
    private static let flagOff: MarkdownDocument.ParseOptions = [.gfmAutolink]

    private func nodes(
        in src: String, options: MarkdownDocument.ParseOptions
    ) -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] {
        MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?, url: String?)] = []
            dfsAutolinkNodes(doc.root, into: &out)
            return out
        }
    }

    // MARK: - Both modes: non-empty siblings are unchanged

    @Test("mid-text www: non-empty siblings, identical in BOTH modes")
    func wwwMidTextBothModes() {
        // `x www.example.com y` - genuine text on both sides; a `www.` match never adds an empty
        // sibling.
        let ns = nodes(in: "x www.example.com y", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, "x ", nil, "www.example.com", " y"])
        #expect(ns.compactMap(\.url) == ["http://www.example.com"])
    }

    @Test("scheme URL preceded by text: NO empty leading node, both modes")
    func schemeURLAfterTextBothModes() {
        // `x https://y.io` - the scheme's preceding text run is "x https"; cmark's unput leaves "x "
        // (non-empty), so there is no empty leading node. `emptyBefore` is false for the URI form here.
        let ns = nodes(in: "x https://y.io", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "x ", nil, "https://y.io"])
        #expect(ns.compactMap(\.url) == ["https://y.io"])
    }

    @Test("www at start: NO empty leading node (the != .www guard), both modes")
    func wwwAtStartBothModes() {
        // `www.example.com` at the very start - a `www.` match rewinds nothing and its trigger fires
        // before any text is emitted, so cmark leaves no empty leading node. The `auto.form != .www`
        // guard must suppress the empty even though the before-region is empty.
        let ns = nodes(in: "www.example.com", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "www.example.com"])
        #expect(ns.compactMap(\.url) == ["http://www.example.com"])
    }

    // MARK: - Flag OFF: spec-correct, no empty siblings

    @Test("flag-OFF email: just the Link, no empty siblings")
    func emailFlagOff() {
        let ns = nodes(in: "o@x.x", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@x.x"])
        #expect(ns.compactMap(\.url) == ["mailto:o@x.x"])
    }

    @Test("flag-OFF scheme URL: just the Link, no empty siblings")
    func schemeURLFlagOff() {
        let ns = nodes(in: "https://x.io", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "https://x.io"])
        #expect(ns.compactMap(\.url) == ["https://x.io"])
    }

    /// GFM's extended email autolink yields just the link followed by the real trailing text, whereas cmark-gfm also
    /// keeps the empty text node its split leaves before the link.
    @Test("flag-OFF email with trailing text: just the Link and the real trailing text")
    func emailTrailingTextFlagOff() {
        let ns = nodes(in: "o@x.x y", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@x.x", " y"])
        #expect(ns.compactMap(\.url) == ["mailto:o@x.x"])
    }

    /// GFM's extended email autolink yields just the link followed by the emphasis, whereas cmark-gfm also keeps the
    /// empty text nodes its split leaves on both sides of the link.
    @Test("flag-OFF email before emphasis: just the Link and the Emphasis")
    func emailBeforeEmphasisFlagOff() {
        let ns = nodes(in: "o@x.x*a*", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .emphasis, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@x.x", nil, "a"])
        #expect(ns.compactMap(\.url) == ["mailto:o@x.x"])
    }
}
