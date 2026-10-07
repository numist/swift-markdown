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
/// must NOT link (`_a_@b.c`). Flag-OFF is the spec-correct deliverable (no empty siblings).
@Suite("GFM email autolink post-pass (emphasis ordering)")
struct AutolinkEmailPostPassTests {

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

    // MARK: - A leading flanking `_` folds into the email's local part

    @Test("`_@b.c`: the flanking `_` is the local part, not before-text")
    func leadingUnderscoreFlagOff() {
        // cmark's backward scan accepts `_` as a local-part char, so the whole `_@b.c` is the email; the
        // `before` text is empty. The rewrite must NOT double-emit the `_` (as before-text AND local part).
        let ns = nodes(in: "_@b.c", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "_@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:_@b.c"])
    }

    @Test("`a_@b.c`: local part is `a_`, whole thing links")
    func wordThenUnderscoreFlagOff() {
        let ns = nodes(in: "a_@b.c", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a_@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:a_@b.c"])
    }

    @Test("`x _@b.c`: the space bounds the local part; `x ` is real before-text")
    func spaceThenUnderscoreFlagOff() {
        // The backward scan stops at the space, so the local part is just `_`; `x ` stays as before-text.
        let ns = nodes(in: "x _@b.c", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "x ", nil, "_@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:_@b.c"])
    }

    // MARK: - An email inside a resolved emphasis run

    @Test("`_a@b.c_`: emphasis pairs; the email autolinks INSIDE it")
    func emailInsideEmphasisFlagOff() {
        // The two `_` pair into an Emphasis wrapping `a@b.c`; the post-pass then autolinks the email
        // inside the emphasis. Flag-OFF: no empty siblings, so Emphasis(Link(Text "a@b.c")).
        let ns = nodes(in: "_a@b.c_", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .emphasis, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, nil, "a@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c"])
    }

    // MARK: - Emphasis consumes the delimiters, leaving an empty local part

    @Test("`_a_@b.c`: emphasis consumes both `_`; residual `@b.c` has no local part → no link")
    func emphasisConsumesUnderscoresFlagOff() {
        // `_a_` resolves to Emphasis(Text "a"); the trailing `@b.c` starts the text node, so the email's
        // backward scan hits the node start with an empty local part and rejects. No link.
        let ns = nodes(in: "_a_@b.c", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .emphasis, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a", "@b.c"])
        #expect(ns.compactMap(\.url) == [])
    }

    // MARK: - Several emails in one text node (the single-pass split loop)

    @Test("`a@b.c x@y.z`: both emails link, with the real ` ` between them")
    func twoEmailsInOneRunFlagOff() {
        // The post-pass scans the consolidated text node once, splitting at each email; the ` ` between the
        // two matches is a real `between` run, and the empty ends are dropped flag-OFF.
        let ns = nodes(in: "a@b.c x@y.z", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c", " ", nil, "x@y.z"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c", "mailto:x@y.z"])
    }

}

/// A recognized `mailto:` / `xmpp:` scheme immediately before an email is FOLDED into the autolink.
///
/// cmark-gfm's `postprocess_text` backward scan (`extensions/autolink.c`) calls `validate_protocol` when
/// it meets a `:` while walking back from the `@`: if the bytes ending at that `:` are the lowercase
/// literal `mailto:` or `xmpp:` and sit at a boundary (the start of the scan window, or preceded by a
/// non-alphanumeric byte), the scheme is absorbed into the link. The link's destination and visible text
/// then both become the whole `scheme:local@domain` run - the synthetic `mailto:` prefix is suppressed
/// (`auto_mailto = false`), so `xmpp:` keeps its own scheme instead of getting the wrong `mailto:`
/// destination. With a scheme present an EMPTY local part is allowed (the scheme itself makes the
/// backward rewind non-zero, so `mailto:@a.b` links where a bare `@a.b` would not). `xmpp:` additionally
/// permits `/` in the domain (`c == '/' && is_xmpp`).
///
/// The recognition is strict: only the lowercase literals match (`MAILTO:` does not), and the scheme
/// must begin at a boundary (`amailto:` - preceded by an alphanumeric - does not fold). A non-recognized
/// scheme (`foo:`) is left as ordinary before-text and only the address links.
@Suite("GFM email autolink protocol-prefix folding (mailto:/xmpp:)")
struct AutolinkProtocolPrefixTests {

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

    // MARK: - The scheme folds into destination AND visible text

    @Test("`mailto:x@a.b`: scheme folds into dest and text; before-text empty")
    func mailtoFoldsFlagOff() {
        let ns = nodes(in: "mailto:x@a.b", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "mailto:x@a.b"])
        #expect(ns.compactMap(\.url) == ["mailto:x@a.b"])
    }

    @Test("`xmpp:x@a.b`: scheme folds; destination keeps `xmpp:`, not `mailto:`")
    func xmppFoldsFlagOff() {
        let ns = nodes(in: "xmpp:x@a.b", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "xmpp:x@a.b"])
        #expect(ns.compactMap(\.url) == ["xmpp:x@a.b"])
    }

    @Test("`xmpp:x@a.b/c`: `/` is allowed in the xmpp domain")
    func xmppSlashInDomainFlagOff() {
        // `postprocess_text`'s forward domain scan admits `/` only when `is_xmpp` (from a folded `xmpp:`).
        let ns = nodes(in: "xmpp:x@a.b/c", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "xmpp:x@a.b/c"])
        #expect(ns.compactMap(\.url) == ["xmpp:x@a.b/c"])
    }

    @Test("`mailto:@a.b`: a scheme lets the local part be empty")
    func mailtoEmptyLocalFlagOff() {
        // A bare `@a.b` has an empty local part and does NOT link; the folded scheme makes the backward
        // rewind non-zero, so the email is accepted with the scheme absorbed.
        let ns = nodes(in: "mailto:@a.b", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "mailto:@a.b"])
        #expect(ns.compactMap(\.url) == ["mailto:@a.b"])
    }

    @Test("`x mailto:a@b.c`: the scheme folds; `x ` stays real before-text")
    func schemeAfterTextFlagOff() {
        let ns = nodes(in: "x mailto:a@b.c", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "x ", nil, "mailto:a@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c"])
    }

    @Test("`.mailto:x@a.b`: a local-part char before the scheme is absorbed too")
    func localCharBeforeSchemeFlagOff() {
        // After folding the scheme, cmark's backward scan keeps going: the leading `.` is a local-part
        // char (`.+-_`), so it is pulled into the link. Dest and text are the whole `.mailto:x@a.b`.
        let ns = nodes(in: ".mailto:x@a.b", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, ".mailto:x@a.b"])
        #expect(ns.compactMap(\.url) == [".mailto:x@a.b"])
    }

    // MARK: - Guards: schemes that must NOT fold (only the address links)

    @Test("`MAILTO:x@a.b`: uppercase is not recognized (case-sensitive)")
    func uppercaseNotFoldedFlagOff() {
        let ns = nodes(in: "MAILTO:x@a.b", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "MAILTO:", nil, "x@a.b"])
        #expect(ns.compactMap(\.url) == ["mailto:x@a.b"])
    }

    @Test("`foo:x@a.b`: an unrecognized scheme is not folded")
    func unknownSchemeNotFoldedFlagOff() {
        let ns = nodes(in: "foo:x@a.b", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "foo:", nil, "x@a.b"])
        #expect(ns.compactMap(\.url) == ["mailto:x@a.b"])
    }

    @Test("`amailto:x@a.b`: a scheme preceded by an alphanumeric is not at a boundary")
    func schemeNotAtBoundaryNotFoldedFlagOff() {
        let ns = nodes(in: "amailto:x@a.b", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "amailto:", nil, "x@a.b"])
        #expect(ns.compactMap(\.url) == ["mailto:x@a.b"])
    }

    @Test("`a@b.c`: a plain email with no scheme still links with a synthetic `mailto:`")
    func plainEmailUnchangedFlagOff() {
        let ns = nodes(in: "a@b.c", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c"])
    }
}
