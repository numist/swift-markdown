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
// AutolinkEmailPostPassTests.dfsAutolinkNodes).
private func dfsAutolinkNodes(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?, url: String?)]
) {
    out.append((node.kind, node.literal(), node.url()))
    node.children.forEach { child in
        dfsAutolinkNodes(child, into: &out)
    }
}

/// A GFM email autolink whose domain scan runs into a second `@` must not emit a link for the
/// candidate before that `@`.
///
/// cmark-gfm's `postprocess_text` forward domain scan (`extensions/autolink.c`) has a dedicated arm for
/// `@`: on meeting a second `@` it does `goto found_at`, abandoning the current `local@domain` candidate
/// and RESTARTING the whole match from the second `@` (the text between the two `@`s becomes the new
/// local part). It never emits the pre-`@` candidate. So `o@.e@` links nothing (the restart at the
/// trailing `@` fails: no domain follows), while `a@b@c.d` links only `b@c.d` after restarting.
///
/// The rewrite mirrors this by treating a domain-terminating `@` as a non-match in `matchGFMEmailAutolink`
/// and letting the post-pass loop retry from the next `@` (which stops its backward local-part scan at the
/// prior `@` regardless, so the two agree). Before the fix the rewrite's forward scan treated `@` like any
/// other terminator - it stopped the domain there and emitted the pre-`@` candidate, over-linking `o@.e`
/// out of `o@.e@`.
@Suite("GFM email autolink domain-terminating `@` (second-`@` restart)")
struct AutolinkEmailTrailingAtTests {

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

    // MARK: - Fixture sanity: the node-walk is meaningful (a valid email really does link)

    @Test("fixture sanity: a plain valid email links with a synthetic `mailto:`")
    func fixtureSanity() throws {
        // Guards against a vacuous pass: if the walk returned a degenerate tree, this valid email would
        // fail to produce the [.document, .paragraph, .link, .text] shape with a `mailto:` URL.
        let ns = try nodes(in: "a@b.c", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c"])
    }

    // MARK: - The finding: a domain immediately followed by `@` links nothing

    @Test("`o@.e@`: the trailing `@` restarts the match and fails; no link (flag-OFF)")
    func trailingAtNoLinkFlagOff() throws {
        // The domain scan of `o@.e` hits the trailing `@`, so cmark restarts from it; the restart finds no
        // domain and fails, leaving the whole run as one plain text node.
        let ns = try nodes(in: "o@.e@", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "o@.e@"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`o@.e@`: no link under the differential-fuzzer flag-ON config either")
    func trailingAtNoLinkFlagOn() throws {
        // No email matches, so there is no split and hence no empty siblings; flag-ON matches flag-OFF.
        let ns = try nodes(in: "o@.e@", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "o@.e@"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`d@.d@`: second fuzzer hit, same shape → no link")
    func fuzzHitDNoLink() throws {
        let ns = try nodes(in: "d@.d@", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "d@.d@"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`o@.o@`: third fuzzer hit → no link")
    func fuzzHitONoLink() throws {
        let ns = try nodes(in: "o@.o@", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "o@.o@"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`a@.d@`: fourth fuzzer hit → no link")
    func fuzzHitANoLink() throws {
        let ns = try nodes(in: "a@.d@", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@.d@"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`o@.e@b`: a non-`@` char after the trailing `@` still yields no link")
    func trailingAtThenCharNoLink() throws {
        // Restart at the second `@` gives local part `.e` and domain `b`, which has no dot (`np == 0`), so
        // the restart fails too; nothing links.
        let ns = try nodes(in: "o@.e@b", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "o@.e@b"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`a@b.c@d`: a valid email followed by `@d` links nothing")
    func validEmailThenAtNoLink() throws {
        // The domain scan of the valid `a@b.c` hits `@`; cmark restarts from it (local part `b.c`, domain
        // `d` with no dot) and fails, so the whole run stays plain text.
        let ns = try nodes(in: "a@b.c@d", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@b.c@d"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`x o@.e@ y`: the trailing `@` is decisive regardless of surrounding context")
    func trailingAtInContextNoLink() throws {
        let ns = try nodes(in: "x o@.e@ y", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "x o@.e@ y"])
        #expect(ns.compactMap(\.url) == [])
    }

    // MARK: - The restart can SUCCEED: it is a retry, not a blanket rejection

    @Test("`a@b@c.d`: restart at the second `@` links `b@c.d`, leaving `a@` before")
    func restartLinksLaterEmail() throws {
        // The domain scan of `a@b` hits `@`; the restart treats `b` as the new local part and finds the
        // valid domain `c.d`, so `b@c.d` links and `a@` is the before-text.
        let ns = try nodes(in: "a@b@c.d", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@", nil, "b@c.d"])
        #expect(ns.compactMap(\.url) == ["mailto:b@c.d"])
    }

    @Test("`a@b@c@d.e`: repeated restarts link only the final `c@d.e`")
    func repeatedRestartLinksFinalEmail() throws {
        let ns = try nodes(in: "a@b@c@d.e", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@b@", nil, "c@d.e"])
        #expect(ns.compactMap(\.url) == ["mailto:c@d.e"])
    }

    // MARK: - Positive controls: valid emails must keep linking (no over-correction)

    @Test("`o@.e`: the bare valid email still links")
    func bareEmailLinks() throws {
        let ns = try nodes(in: "o@.e", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@.e"])
        #expect(ns.compactMap(\.url) == ["mailto:o@.e"])
    }

    @Test("`o@.e `: a trailing space (not `@`) bounds the domain; the email links")
    func emailTrailingSpaceLinks() throws {
        // The domain scan stops at the space - a plain terminator, not the `@` restart - so `o@.e` links.
        // The trailing space is stripped from the paragraph's final line before inline parsing (CommonMark
        // §4.8), so the text node the post-pass sees is already `o@.e`: the whole node links, no after-text.
        let ns = try nodes(in: "o@.e ", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@.e"])
        #expect(ns.compactMap(\.url) == ["mailto:o@.e"])
    }

    @Test("`o@.e x`: a mid-run space bounds the domain; ` x` survives as after-text")
    func emailInteriorSpaceLinks() throws {
        // Unlike a trailing space, an interior space is not stripped, so it shows the domain scan stopping
        // at a plain terminator (the email links `o@.e`) and leaving ` x` as real after-text.
        let ns = try nodes(in: "o@.e x", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@.e", " x"])
        #expect(ns.compactMap(\.url) == ["mailto:o@.e"])
    }

    @Test("`@o@.e`: a leading `@` is skipped (empty local part); the real email links")
    func leadingAtLinks() throws {
        let ns = try nodes(in: "@o@.e", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "@", nil, "o@.e"])
        #expect(ns.compactMap(\.url) == ["mailto:o@.e"])
    }

    @Test("`o@.ex`: a letter after the domain (not `@`) extends the last label; the email links")
    func emailTrailingLetterLinks() throws {
        let ns = try nodes(in: "o@.ex", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@.ex"])
        #expect(ns.compactMap(\.url) == ["mailto:o@.ex"])
    }
}
