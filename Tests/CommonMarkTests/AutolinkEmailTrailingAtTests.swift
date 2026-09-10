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

/// A GFM email autolink whose forward domain scan runs into a SECOND `@`.
///
/// cmark-gfm's `postprocess_text` (`extensions/autolink.c`) does `goto found_at` when the domain scan of a
/// `local@domain` candidate meets a second `@`: it does NOT emit that first candidate. Instead it RESTARTS
/// the match from the second `@` (the run between the two `@`s becomes the new local part) and links the
/// second email if the restart is valid. The restart is STATEFUL - the accumulated domain dot-count `np`,
/// which gates "domain must contain a dot", is declared at the top of the outer `while` loop, and the
/// `goto` jumps past its initializer, so it CARRIES across the restart. Only the local-part boundary and
/// the scan offset are recomputed.
///
/// The observable consequence is the reason a fresh re-match cannot reproduce cmark: `.e@b` does NOT link
/// standalone (its lone dot is in the LOCAL part, so a fresh scan sees `np == 0` in the domain `b` and
/// rejects), yet `o@.e@b` LINKS `.e@b` - the dot in `.e` was counted while scanning the first candidate's
/// domain, and that already-counted `np` survives the restart. Likewise `a@b.c@d` links `b.c@d`: the dot in
/// `b.c` counted during the first scan lets the restarted `b.c@d` pass. The rewrite reproduces this inside
/// `matchGFMEmailAutolink` with an internal restart that preserves the carried dot-count.
@Suite("GFM email autolink second-`@` restart (stateful goto found_at)")
struct AutolinkEmailTrailingAtTests {

    /// The shipped configuration: GFM autolink on, cmark bug-compatibility off (the spec-correct
    /// deliverable, so empty `before`/`after` siblings are dropped).
    private static let options: MarkdownDocument.ParseOptions = [.gfmAutolink]

    private func nodes(
        in src: String
    ) throws -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] {
        try MarkdownDocument.withParsedDocument(src, options: Self.options) {
            doc -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?, url: String?)] = []
            dfsAutolinkNodes(doc.root, into: &out)
            return out
        }
    }

    // MARK: - Fixture sanity: the node-walk is meaningful (a valid email really does link)

    @Test("fixture sanity: a plain valid email links with a synthetic `mailto:`")
    func fixtureSanity() throws {
        // Guards against a vacuous pass: if the walk returned a degenerate tree, this valid email would fail
        // to produce the [.document, .paragraph, .link, .text] shape with a `mailto:` URL.
        let ns = try nodes(in: "a@b.c")
        try #require(ns.count == 4, "expected document > paragraph > link > text")
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c"])
        #expect(try #require(ns.compactMap(\.url).first) == "mailto:a@b.c")
    }

    // MARK: - The restart fails (empty tail after the last `@`): no link

    @Test("`o@.e@`: restart at the trailing `@` finds no domain → no link")
    func trailingAtNoLink() throws {
        // The first candidate `o@.e` is abandoned at the second `@`; the restart (local part `.e`) has an
        // empty domain, so it fails and the whole run stays one plain text node.
        let ns = try nodes(in: "o@.e@")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "o@.e@"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`d@.d@`: same shape → no link")
    func trailingAtNoLinkD() throws {
        let ns = try nodes(in: "d@.d@")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "d@.d@"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`o@.o@`: same shape → no link")
    func trailingAtNoLinkO() throws {
        let ns = try nodes(in: "o@.o@")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "o@.o@"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`a@.d@`: same shape → no link")
    func trailingAtNoLinkA() throws {
        let ns = try nodes(in: "a@.d@")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@.d@"])
        #expect(ns.compactMap(\.url) == [])
    }

    // MARK: - The restart SUCCEEDS via the carried dot-count: links the second email

    @Test("`o@.e@b`: restart links `.e@b` (carried dot from the first scan), before-text `o@`")
    func restartLinksTailAfterAt() throws {
        // Standalone `.e@b` does NOT link (its dot is in the local part, `np == 0` in domain `b`), but here
        // the dot in `.e` was counted while scanning the first candidate's domain, and that `np` survives
        // the restart - so `.e@b` links, leaving `o@` as before-text.
        let ns = try nodes(in: "o@.e@b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "o@", nil, ".e@b"])
        #expect(ns.compactMap(\.url) == ["mailto:.e@b"])
    }

    @Test("`a@b.c@d`: restart links `b.c@d` (carried dot from `b.c`), before-text `a@`")
    func restartLinksValidEmailTail() throws {
        // The dot in `b.c` is counted during the first scan of the valid candidate `a@b.c`; the restart at
        // the second `@` (local part `b.c`, domain `d`) inherits that dot, so `b.c@d` links.
        let ns = try nodes(in: "a@b.c@d")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@", nil, "b.c@d"])
        #expect(ns.compactMap(\.url) == ["mailto:b.c@d"])
    }

    @Test("`a@b@c.d`: restart links `b@c.d` on its own valid domain, before-text `a@`")
    func restartLinksOnOwnDomain() throws {
        // A restart-succeeds control derived from the same mechanism: the domain scan of `a@b` meets `@`, the
        // restart treats `b` as the new local part, and the domain `c.d` has its own dot - so `b@c.d` links
        // regardless of any carried count.
        let ns = try nodes(in: "a@b@c.d")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@", nil, "b@c.d"])
        #expect(ns.compactMap(\.url) == ["mailto:b@c.d"])
    }

    @Test("`o@.e@ x@y.z`: a failed `@`-chain does not swallow the valid email after it")
    func failedChainThenValidEmail() throws {
        // The `o@.e@` chain fails (empty tail after the last `@`) and is consumed as before-text up to the
        // valid `x@y.z`, which links. Guards the failure path's forward skip: it must resume PAST the failed
        // chain without over-skipping the following email.
        let ns = try nodes(in: "o@.e@ x@y.z")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "o@.e@ ", nil, "x@y.z"])
        #expect(ns.compactMap(\.url) == ["mailto:x@y.z"])
    }

    // MARK: - Positive controls: valid emails must keep linking (no over-correction)

    @Test("`o@.e`: the bare valid email still links")
    func bareEmailLinks() throws {
        let ns = try nodes(in: "o@.e")
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@.e"])
        #expect(ns.compactMap(\.url) == ["mailto:o@.e"])
    }

    @Test("`o@.e `: a trailing space is stripped before inline parse; the email links, no after-text")
    func emailTrailingSpaceLinks() throws {
        // CommonMark strips a paragraph's trailing spaces before inline parsing, so the text node the
        // post-pass sees is already `o@.e`: the whole node links and there is no after-text.
        let ns = try nodes(in: "o@.e ")
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@.e"])
        #expect(ns.compactMap(\.url) == ["mailto:o@.e"])
    }

    @Test("`@o@.e`: a leading `@` is skipped (empty local part); the real email links after `@`")
    func leadingAtLinks() throws {
        let ns = try nodes(in: "@o@.e")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "@", nil, "o@.e"])
        #expect(ns.compactMap(\.url) == ["mailto:o@.e"])
    }

    @Test("`o@.ex`: a letter after the domain (not `@`) extends the last label; the email links")
    func emailTrailingLetterLinks() throws {
        let ns = try nodes(in: "o@.ex")
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@.ex"])
        #expect(ns.compactMap(\.url) == ["mailto:o@.ex"])
    }

    // MARK: - Standalone non-linkers (controls): these must NOT link on their own

    @Test("`.e@b`: standalone, the lone dot is in the local part (domain has none) → no link")
    func standaloneDotLocalNoLink() throws {
        let ns = try nodes(in: ".e@b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, ".e@b"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`e@b`: standalone, domain `b` has no dot → no link")
    func standaloneNoDotNoLink() throws {
        let ns = try nodes(in: "e@b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "e@b"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`b.c@d`: standalone, the dot is in the local part (domain `d` has none) → no link")
    func standaloneDotLocalDomainNoDotNoLink() throws {
        let ns = try nodes(in: "b.c@d")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "b.c@d"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`b@d`: standalone, domain `d` has no dot → no link")
    func standaloneShortNoLink() throws {
        let ns = try nodes(in: "b@d")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "b@d"])
        #expect(ns.compactMap(\.url) == [])
    }
}
