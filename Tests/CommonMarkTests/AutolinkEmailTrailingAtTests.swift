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
/// The first candidate is abandoned and the match restarts from the second `@`, with the run between the
/// two `@`s as the new local part. The restarted address is an extended email autolink only when its own
/// domain is valid (spec "Autolinks (extension)"): one or more segments separated by periods, with at least
/// one period.
@Suite("GFM email autolink second-`@` restart (stateful goto found_at)")
struct AutolinkEmailTrailingAtTests {

    /// The shipped configuration: GFM autolink on, cmark bug-compatibility off (the spec-correct
    /// deliverable, so empty `before`/`after` siblings are dropped).
    private static let options: MarkdownDocument.ParseOptions = [.gfmAutolink]

    private func nodes(
        in src: String
    ) -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] {
        MarkdownDocument.withParsedDocument(src, options: Self.options) {
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
        let ns = nodes(in: "a@b.c")
        try #require(ns.count == 4, "expected document > paragraph > link > text")
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c"])
        #expect(try #require(ns.compactMap(\.url).first) == "mailto:a@b.c")
    }

    // MARK: - The restart fails (empty tail after the last `@`): no link

    @Test("`o@.e@`: restart at the trailing `@` finds no domain → no link")
    func trailingAtNoLink() {
        // The first candidate `o@.e` is abandoned at the second `@`; the restart (local part `.e`) has an
        // empty domain, so it fails and the whole run stays one plain text node.
        let ns = nodes(in: "o@.e@")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "o@.e@"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`d@.d@`: same shape → no link")
    func trailingAtNoLinkD() {
        let ns = nodes(in: "d@.d@")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "d@.d@"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`o@.o@`: same shape → no link")
    func trailingAtNoLinkO() {
        let ns = nodes(in: "o@.o@")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "o@.o@"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`a@.d@`: same shape → no link")
    func trailingAtNoLinkA() {
        let ns = nodes(in: "a@.d@")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@.d@"])
        #expect(ns.compactMap(\.url) == [])
    }

    // MARK: - The restarted address needs a period in its own domain

    @Test("`o@.e@b`: the restarted `.e@b` has a dotless domain → no link")
    func restartNeedsOwnPeriod() {
        let ns = nodes(in: "o@.e@b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "o@.e@b"])
    }

    @Test("`a@b.c@d`: the restarted `b.c@d` has a dotless domain → no link")
    func restartWithValidPrefixNeedsOwnPeriod() {
        let ns = nodes(in: "a@b.c@d")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@b.c@d"])
    }

    @Test("`a@b@c.d`: restart links `b@c.d` on its own valid domain, before-text `a@`")
    func restartLinksOnOwnDomain() {
        // The domain scan of `a@b` meets `@`, the restart treats `b` as the new local part, and the domain
        // `c.d` has its own period, so `b@c.d` links.
        let ns = nodes(in: "a@b@c.d")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@", nil, "b@c.d"])
        #expect(ns.compactMap(\.url) == ["mailto:b@c.d"])
    }

    @Test("`o@.e@ x@y.z`: a failed `@`-chain does not swallow the valid email after it")
    func failedChainThenValidEmail() {
        // The `o@.e@` chain fails (empty tail after the last `@`) and is consumed as before-text up to the
        // valid `x@y.z`, which links. Guards the failure path's forward skip: it must resume PAST the failed
        // chain without over-skipping the following email.
        let ns = nodes(in: "o@.e@ x@y.z")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "o@.e@ ", nil, "x@y.z"])
        #expect(ns.compactMap(\.url) == ["mailto:x@y.z"])
    }

    // MARK: - Positive controls: valid emails must keep linking (no over-correction)

    @Test("`o@e.e`: the bare valid email still links")
    func bareEmailLinks() {
        let ns = nodes(in: "o@e.e")
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@e.e"])
        #expect(ns.compactMap(\.url) == ["mailto:o@e.e"])
    }

    @Test("`o@e.e `: a trailing space is stripped before inline parse; the email links, no after-text")
    func emailTrailingSpaceLinks() {
        // CommonMark strips a paragraph's trailing spaces before inline parsing, so the text node the
        // post-pass sees is already `o@e.e`: the whole node links and there is no after-text.
        let ns = nodes(in: "o@e.e ")
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@e.e"])
        #expect(ns.compactMap(\.url) == ["mailto:o@e.e"])
    }

    @Test("`@o@e.e`: a leading `@` is skipped (empty local part); the real email links after `@`")
    func leadingAtLinks() {
        let ns = nodes(in: "@o@e.e")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "@", nil, "o@e.e"])
        #expect(ns.compactMap(\.url) == ["mailto:o@e.e"])
    }

    @Test("`o@e.ex`: a letter after the domain (not `@`) extends the last label; the email links")
    func emailTrailingLetterLinks() {
        let ns = nodes(in: "o@e.ex")
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@e.ex"])
        #expect(ns.compactMap(\.url) == ["mailto:o@e.ex"])
    }

    // MARK: - Standalone non-linkers (controls): these must NOT link on their own

    @Test("`.e@b`: standalone, the lone dot is in the local part (domain has none) → no link")
    func standaloneDotLocalNoLink() {
        let ns = nodes(in: ".e@b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, ".e@b"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`e@b`: standalone, domain `b` has no dot → no link")
    func standaloneNoDotNoLink() {
        let ns = nodes(in: "e@b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "e@b"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`b.c@d`: standalone, the dot is in the local part (domain `d` has none) → no link")
    func standaloneDotLocalDomainNoDotNoLink() {
        let ns = nodes(in: "b.c@d")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "b.c@d"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`b@d`: standalone, domain `d` has no dot → no link")
    func standaloneShortNoLink() {
        let ns = nodes(in: "b@d")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "b@d"])
        #expect(ns.compactMap(\.url) == [])
    }
}
