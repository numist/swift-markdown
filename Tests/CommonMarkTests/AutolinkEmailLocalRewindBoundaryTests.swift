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

/// Extended email autolinks (Autolinks (extension)) are recognized left to right. When a candidate address is
/// rejected, the next address's local part starts no earlier than the character that ended the candidate's
/// domain: `+`, or a `.` not followed by an alphanumeric, ends a domain, while `-`, `_`, alphanumerics and a
/// `.` followed by an alphanumeric continue it. Such a local part follows `@` or a character of the rejected
/// domain, and neither may precede an extended autolink, so the address is text.
@Suite("Extended email autolink local part after a rejected candidate")
struct AutolinkEmailLocalRewindBoundaryTests {

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

    // MARK: - `+` ends a domain

    @Test("`l@o+@b.b` is text: the `+` bounds the second local part, which follows `o`")
    func plusBoundsLocalPart() {
        // `l@o` is rejected (its domain has no period), and its domain ends at `+`.
        let ns = nodes(in: "l@o+@b.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@o+@b.b"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`l@oo+@b.b` is text: the `+` bounds the second local part, which follows `o`")
    func plusBoundsLocalPartTwoChars() {
        let ns = nodes(in: "l@oo+@b.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@oo+@b.b"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`a@b+c@d.d` is text: the `+` bounds the second local part to `+c`, which follows `b`")
    func plusBoundsLocalPartWithTrailingAlnum() {
        let ns = nodes(in: "a@b+c@d.d")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@b+c@d.d"])
        #expect(ns.compactMap(\.url) == [])
    }

    // MARK: - `.`, `-`, `_` and alphanumerics continue a domain

    @Test("`l@o.p@b.b` is text: the local part `o.p` follows `@`")
    func dotContinuesDomain() {
        let ns = nodes(in: "l@o.p@b.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@o.p@b.b"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`l@o-p@b.b` is text: the local part `o-p` follows `@`")
    func hyphenContinuesDomain() {
        let ns = nodes(in: "l@o-p@b.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@o-p@b.b"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`l@o_p@b.b` is text: the local part `o_p` follows `@`")
    func underscoreContinuesDomain() {
        let ns = nodes(in: "l@o_p@b.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@o_p@b.b"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`l@abc@b.b` is text: the local part `abc` follows `@`")
    func alnumContinuesDomain() {
        let ns = nodes(in: "l@abc@b.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@abc@b.b"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`l@+@b.b` is text: the local part `+` follows `@`")
    func plusAtStart() {
        let ns = nodes(in: "l@+@b.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@+@b.b"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`xy@ab@c.c` is text: the local part `ab` follows `@`")
    func alnumFirstLocalPart() {
        let ns = nodes(in: "xy@ab@c.c")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "xy@ab@c.c"])
        #expect(ns.compactMap(\.url) == [])
    }

    // MARK: - A `.` not followed by an alphanumeric ends a domain

    @Test("`a@b.+@c.c` is text: the local part `.+` follows `b`")
    func dotThenPlusBoundary() {
        let ns = nodes(in: "a@b.+@c.c")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@b.+@c.c"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`a@b..c@d.d` is text: the local part `..c` follows `b`")
    func doubledDotBoundary() {
        let ns = nodes(in: "a@b..c@d.d")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@b..c@d.d"])
        #expect(ns.compactMap(\.url) == [])
    }
}
