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
/// These empty nodes are a `.cmarkBugCompatibility` STRUCTURAL quirk: the shipped (spec-correct) parser
/// keeps the clean tree with no empty siblings. Both guardrails live here - flag-ON reproduces cmark,
/// flag-OFF proves the deliverable is untouched.
@Suite("GFM autolink empty-text siblings (cmark bug-for-bug)")
struct AutolinkEmptySiblingTests {

    /// The differential-fuzzer configuration: GFM autolink on, cmark bug-compatibility on.
    private static let flagOn: MarkdownDocument.ParseOptions = [.gfmAutolink, .cmarkBugCompatibility]

    /// The shipped configuration: GFM autolink on, bug-compatibility deliberately off.
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

    // MARK: - Flag ON: reproduce cmark's empty siblings

    @Test("flag-ON email: empty Text siblings on BOTH sides")
    func emailFlagOn() {
        // `o@.x` - the email spans the whole paragraph, so cmark's `before` and `after` text nodes are
        // both empty and both survive: Text "" + Link(mailto:o@.x) + Text "".
        let ns = nodes(in: "o@.x", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, "", nil, "o@.x", ""])
        // Fixture-sanity: this really is a recognized email autolink, not stray text.
        #expect(ns.compactMap(\.url) == ["mailto:o@.x"])
    }

    @Test("flag-ON scheme URL: empty LEADING Text sibling only")
    func schemeURLFlagOn() {
        // `https://x.io` - `url_match` unputs "https" from its (scheme-only) text node, leaving it
        // empty: Text "" + Link. A scheme URL gets NO trailing empty node.
        let ns = nodes(in: "https://x.io", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "", nil, "https://x.io"])
        #expect(ns.compactMap(\.url) == ["https://x.io"])
    }

    // MARK: - Both modes: non-empty siblings are unchanged

    @Test("flag-ON email with trailing text: empty LEADING only, real trailing text preserved")
    func emailTrailingTextFlagOn() {
        // `o@.x y` - the email is at the start (empty `before`) but has real text after. cmark's `after`
        // node is " y" (non-empty), so no empty trailing node survives: the empty node the split emits
        // is folded into " y" by `consolidateTextNodes`. Result: Text "" + Link + Text " y".
        let ns = nodes(in: "o@.x y", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, "", nil, "o@.x", " y"])
        #expect(ns.compactMap(\.url) == ["mailto:o@.x"])
    }

    @Test("mid-text www: non-empty siblings, identical in BOTH modes")
    func wwwMidTextBothModes() {
        // `x www.example.com y` - genuine text on both sides; a `www.` match never adds an empty
        // sibling. The tree must be identical flag-ON and flag-OFF.
        for options in [Self.flagOn, Self.flagOff] {
            let ns = nodes(in: "x www.example.com y", options: options)
            #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text, .text])
            #expect(ns.map(\.text) == [nil, nil, "x ", nil, "www.example.com", " y"])
            #expect(ns.compactMap(\.url) == ["http://www.example.com"])
        }
    }

    @Test("scheme URL preceded by text: NO empty leading node, both modes")
    func schemeURLAfterTextBothModes() {
        // `x https://y.io` - the scheme's preceding text run is "x https"; cmark's unput leaves "x "
        // (non-empty), so there is no empty leading node. `emptyBefore` is false for the URI form here.
        // Identical flag-ON and flag-OFF.
        for options in [Self.flagOn, Self.flagOff] {
            let ns = nodes(in: "x https://y.io", options: options)
            #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
            #expect(ns.map(\.text) == [nil, nil, "x ", nil, "https://y.io"])
            #expect(ns.compactMap(\.url) == ["https://y.io"])
        }
    }

    @Test("www at start: NO empty leading node (the != .www guard), both modes")
    func wwwAtStartBothModes() {
        // `www.example.com` at the very start - a `www.` match rewinds nothing and its trigger fires
        // before any text is emitted, so cmark leaves no empty leading node. The `auto.form != .www`
        // guard must suppress the empty even though the before-region is empty. Identical in both modes.
        for options in [Self.flagOn, Self.flagOff] {
            let ns = nodes(in: "www.example.com", options: options)
            #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
            #expect(ns.map(\.text) == [nil, nil, nil, "www.example.com"])
            #expect(ns.compactMap(\.url) == ["http://www.example.com"])
        }
    }

    @Test("flag-ON email before emphasis: standalone empty trailing node survives")
    func emailBeforeEmphasisFlagOn() {
        // `o@.x*a*` - the email's `post` is empty (the emphasis is a separate node). cmark keeps that
        // empty `post` node standalone between the Link and the Emphasis; consolidation cannot fold it
        // (both neighbours are non-text). Structure: Text "" + Link + Text "" + Emphasis(Text "a").
        let ns = nodes(in: "o@.x*a*", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text, .text, .emphasis, .text])
        #expect(ns.map(\.text) == [nil, nil, "", nil, "o@.x", "", nil, "a"])
        #expect(ns.compactMap(\.url) == ["mailto:o@.x"])
    }

    // MARK: - Flag OFF: spec-correct, no empty siblings

    @Test("flag-OFF email: just the Link, no empty siblings")
    func emailFlagOff() {
        let ns = nodes(in: "o@.x", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@.x"])
        #expect(ns.compactMap(\.url) == ["mailto:o@.x"])
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
        let ns = nodes(in: "o@.x y", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@.x", " y"])
        #expect(ns.compactMap(\.url) == ["mailto:o@.x"])
    }

    /// GFM's extended email autolink yields just the link followed by the emphasis, whereas cmark-gfm also keeps the
    /// empty text nodes its split leaves on both sides of the link.
    @Test("flag-OFF email before emphasis: just the Link and the Emphasis")
    func emailBeforeEmphasisFlagOff() {
        let ns = nodes(in: "o@.x*a*", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .emphasis, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@.x", nil, "a"])
        #expect(ns.compactMap(\.url) == ["mailto:o@.x"])
    }
}
