/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// Depth-first: each node's kind, text literal, and (for links) destination URL.
private func dfsAutolinkNodes(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?, url: String?)]
) {
    out.append((node.kind, node.literal(), node.url()))
    node.children.forEach { child in
        dfsAutolinkNodes(child, into: &out)
    }
}

/// An extended email autolink candidate whose domain runs into a second `@`.
///
/// The first candidate is abandoned and the match restarts from the second `@`, with the run between the
/// two `@`s as the new local part. That local part follows `@`, which may not precede an extended autolink
/// (spec "Autolinks (extension)"), so the restarted address is text whatever its domain.
@Suite("Extended email autolink candidate with a second `@`")
struct AutolinkEmailTrailingAtTests {

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

    @Test("a plain email links with a `mailto:` destination")
    func plainEmailLinks() throws {
        let ns = nodes(in: "a@b.c")
        try #require(ns.count == 4, "expected document > paragraph > link > text")
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c"])
        #expect(try #require(ns.compactMap(\.url).first) == "mailto:a@b.c")
    }

    // MARK: - Nothing follows the last `@`

    @Test("`o@.e@`: the second `@` has no domain after it, so the run is text")
    func trailingAtNoLink() {
        // The candidate restarted at the second `@` has an empty domain.
        let ns = nodes(in: "o@.e@")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "o@.e@"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`d@.d@` is text")
    func trailingAtNoLinkD() {
        let ns = nodes(in: "d@.d@")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "d@.d@"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`o@.o@` is text")
    func trailingAtNoLinkO() {
        let ns = nodes(in: "o@.o@")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "o@.o@"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`a@.d@` is text")
    func trailingAtNoLinkA() {
        let ns = nodes(in: "a@.d@")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@.d@"])
        #expect(ns.compactMap(\.url) == [])
    }

    // MARK: - The restarted address follows `@`

    @Test("`o@.e@b`: `.e@b` follows `@`, so the run is text")
    func restartNeedsOwnPeriod() {
        let ns = nodes(in: "o@.e@b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "o@.e@b"])
    }

    @Test("`a@b.c@d`: `b.c@d` follows `@`, so the run is text")
    func restartWithValidPrefixNeedsOwnPeriod() {
        let ns = nodes(in: "a@b.c@d")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@b.c@d"])
    }

    @Test("`a@b@c.d`: `b@c.d` follows `@`, so the run is text")
    func restartAfterAtSignIsText() {
        let ns = nodes(in: "a@b@c.d")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@b@c.d"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`o@.e@ x@y.z`: the valid email after a rejected `@` run links")
    func failedChainThenValidEmail() {
        let ns = nodes(in: "o@.e@ x@y.z")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "o@.e@ ", nil, "x@y.z"])
        #expect(ns.compactMap(\.url) == ["mailto:x@y.z"])
    }

    // MARK: - Valid addresses

    @Test("`o@e.e` links")
    func bareEmailLinks() {
        let ns = nodes(in: "o@e.e")
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@e.e"])
        #expect(ns.compactMap(\.url) == ["mailto:o@e.e"])
    }

    @Test("`o@e.e `: the email links with no after-text")
    func emailTrailingSpaceLinks() {
        // A paragraph's final spaces are stripped before inline parsing (Paragraphs).
        let ns = nodes(in: "o@e.e ")
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@e.e"])
        #expect(ns.compactMap(\.url) == ["mailto:o@e.e"])
    }

    @Test("`@o@e.e`: the leading `@` has an empty local part, and `o@e.e` follows `@`, so the run is text")
    func leadingAtIsText() {
        let ns = nodes(in: "@o@e.e")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "@o@e.e"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`o@e.ex`: the email links")
    func emailTrailingLetterLinks() {
        let ns = nodes(in: "o@e.ex")
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@e.ex"])
        #expect(ns.compactMap(\.url) == ["mailto:o@e.ex"])
    }

    // MARK: - Addresses whose domain has no period

    @Test("`.e@b` is text: its domain has no period")
    func standaloneDotLocalNoLink() {
        let ns = nodes(in: ".e@b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, ".e@b"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`e@b` is text: its domain has no period")
    func standaloneNoDotNoLink() {
        let ns = nodes(in: "e@b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "e@b"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`b.c@d` is text: its domain has no period")
    func standaloneDotLocalDomainNoDotNoLink() {
        let ns = nodes(in: "b.c@d")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "b.c@d"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`b@d` is text: its domain has no period")
    func standaloneShortNoLink() {
        let ns = nodes(in: "b@d")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "b@d"])
        #expect(ns.compactMap(\.url) == [])
    }
}
