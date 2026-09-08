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
// AutolinkEmptySiblingTests.dfsAutolinkNodes).
private func dfsAutolinkNodes(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?, url: String?)]
) {
    out.append((node.kind, node.literal(), node.url()))
    node.children.forEach { child in
        dfsAutolinkNodes(child, into: &out)
    }
}

/// GFM email autolinks that abut an emphasis delimiter (`_`/`*`).
///
/// cmark-gfm detects email autolinks in `postprocess_text` (`extensions/autolink.c`), a pass that runs
/// AFTER emphasis resolution and `cmark_consolidate_text_nodes` and scans the finished text nodes,
/// splitting each into `[before, link, after]`. Detecting the email during the forward inline pass -
/// before emphasis delimiters are paired - cannot reproduce this: a flanking `_`/`*` next to an email
/// is still an unresolved delimiter at that point, so the two engines disagree on whether the delimiter
/// belongs to the email's local part, to a resolved emphasis run, or to plain text.
///
/// These cases exercise every ordering the fuzzer surfaced: a flanking `_` folded INTO the local part
/// (`_@b.c`, `a_@b.c`, `x _@b.c`), an email that must be found INSIDE a resolved emphasis (`_a@b.c_`),
/// and a `_..._` run that consumes the delimiters so the residual `@b.c` has an empty local part and
/// must NOT link (`_a_@b.c`). Flag-OFF is the spec-correct deliverable (no empty siblings); flag-ON
/// reproduces cmark's Quirk M empty `before`/`after` text nodes.
@Suite("GFM email autolink post-pass (emphasis ordering)")
struct AutolinkEmailPostPassTests {

    /// The differential-fuzzer configuration: GFM autolink on, cmark bug-compatibility on.
    private static let flagOn: MarkdownDocument.ParseOptions = [.gfmAutolink, .cmarkBugCompatibility]

    /// The shipped configuration: GFM autolink on, bug-compatibility deliberately off.
    private static let flagOff: MarkdownDocument.ParseOptions = [.gfmAutolink]

    private func nodes(
        in src: String, options: MarkdownDocument.ParseOptions
    ) throws -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] {
        try MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?, url: String?)] = []
            dfsAutolinkNodes(doc.root, into: &out)
            return out
        }
    }

    // MARK: - A leading flanking `_` folds into the email's local part

    @Test("`_@b.c`: the flanking `_` is the local part, not before-text")
    func leadingUnderscoreFlagOff() throws {
        // cmark's backward scan accepts `_` as a local-part char, so the whole `_@b.c` is the email; the
        // `before` text is empty. The rewrite must NOT double-emit the `_` (as before-text AND local part).
        let ns = try nodes(in: "_@b.c", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "_@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:_@b.c"])
    }

    @Test("`_@b.c` flag-ON: empty before/after siblings (Quirk M)")
    func leadingUnderscoreFlagOn() throws {
        let ns = try nodes(in: "_@b.c", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, "", nil, "_@b.c", ""])
        #expect(ns.compactMap(\.url) == ["mailto:_@b.c"])
    }

    @Test("`a_@b.c`: local part is `a_`, whole thing links")
    func wordThenUnderscoreFlagOff() throws {
        let ns = try nodes(in: "a_@b.c", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a_@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:a_@b.c"])
    }

    @Test("`a_@b.c` flag-ON: empty before/after siblings")
    func wordThenUnderscoreFlagOn() throws {
        let ns = try nodes(in: "a_@b.c", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, "", nil, "a_@b.c", ""])
        #expect(ns.compactMap(\.url) == ["mailto:a_@b.c"])
    }

    @Test("`x _@b.c`: the space bounds the local part; `x ` is real before-text")
    func spaceThenUnderscoreFlagOff() throws {
        // The backward scan stops at the space, so the local part is just `_`; `x ` stays as before-text.
        let ns = try nodes(in: "x _@b.c", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "x ", nil, "_@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:_@b.c"])
    }

    @Test("`x _@b.c` flag-ON: real before-text `x `, empty after")
    func spaceThenUnderscoreFlagOn() throws {
        let ns = try nodes(in: "x _@b.c", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, "x ", nil, "_@b.c", ""])
        #expect(ns.compactMap(\.url) == ["mailto:_@b.c"])
    }

    // MARK: - An email inside a resolved emphasis run

    @Test("`_a@b.c_`: emphasis pairs; the email autolinks INSIDE it")
    func emailInsideEmphasisFlagOff() throws {
        // The two `_` pair into an Emphasis wrapping `a@b.c`; the post-pass then autolinks the email
        // inside the emphasis. Flag-OFF: no empty siblings, so Emphasis(Link(Text "a@b.c")).
        let ns = try nodes(in: "_a@b.c_", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .emphasis, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, nil, "a@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c"])
    }

    @Test("`_a@b.c_` flag-ON: empty siblings live INSIDE the emphasis")
    func emailInsideEmphasisFlagOn() throws {
        let ns = try nodes(in: "_a@b.c_", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .emphasis, .text, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "", nil, "a@b.c", ""])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c"])
    }

    // MARK: - Emphasis consumes the delimiters, leaving an empty local part

    @Test("`_a_@b.c`: emphasis consumes both `_`; residual `@b.c` has no local part → no link")
    func emphasisConsumesUnderscoresFlagOff() throws {
        // `_a_` resolves to Emphasis(Text "a"); the trailing `@b.c` starts the text node, so the email's
        // backward scan hits the node start with an empty local part and rejects. No link.
        let ns = try nodes(in: "_a_@b.c", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .emphasis, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a", "@b.c"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`_a_@b.c` flag-ON: identical (no email match → no empty siblings)")
    func emphasisConsumesUnderscoresFlagOn() throws {
        let ns = try nodes(in: "_a_@b.c", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .emphasis, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a", "@b.c"])
        #expect(ns.compactMap(\.url) == [])
    }

    // MARK: - Several emails in one text node (the single-pass split loop)

    @Test("`a@b.c x@y.z`: both emails link, with the real ` ` between them")
    func twoEmailsInOneRunFlagOff() throws {
        // The post-pass scans the consolidated text node once, splitting at each email; the ` ` between the
        // two matches is a real `between` run, and the empty ends are dropped flag-OFF.
        let ns = try nodes(in: "a@b.c x@y.z", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c", " ", nil, "x@y.z"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c", "mailto:x@y.z"])
    }

    @Test("`a@b.c x@y.z` flag-ON: empty leading/trailing siblings bound the run")
    func twoEmailsInOneRunFlagOn() throws {
        let ns = try nodes(in: "a@b.c x@y.z", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text, .text, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, "", nil, "a@b.c", " ", nil, "x@y.z", ""])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c", "mailto:x@y.z"])
    }
}
