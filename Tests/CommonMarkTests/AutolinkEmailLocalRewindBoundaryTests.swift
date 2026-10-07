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
/// `.` followed by an alphanumeric continue it.
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

    @Test("`l@o+@b.b`: the `+` bounds the second local part; before-text `l@o`")
    func plusBoundsLocalPart() {
        // `l@o` is rejected (its domain has no period), and its domain ends at `+`.
        let ns = nodes(in: "l@o+@b.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@o", nil, "+@b.b"])
        #expect(ns.compactMap(\.url) == ["mailto:+@b.b"])
    }

    @Test("`l@oo+@b.b`: the `+` bounds the second local part; before-text `l@oo`")
    func plusBoundsLocalPartTwoChars() {
        let ns = nodes(in: "l@oo+@b.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@oo", nil, "+@b.b"])
        #expect(ns.compactMap(\.url) == ["mailto:+@b.b"])
    }

    @Test("`a@b+c@d.d`: the `+` bounds the second local part to `+c`; before-text `a@b`")
    func plusBoundsLocalPartWithTrailingAlnum() {
        let ns = nodes(in: "a@b+c@d.d")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@b", nil, "+c@d.d"])
        #expect(ns.compactMap(\.url) == ["mailto:+c@d.d"])
    }

    // MARK: - `.`, `-`, `_` and alphanumerics continue a domain

    @Test("`l@o.p@b.b`: the local part is `o.p`; before-text `l@`")
    func dotContinuesDomain() {
        let ns = nodes(in: "l@o.p@b.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@", nil, "o.p@b.b"])
        #expect(ns.compactMap(\.url) == ["mailto:o.p@b.b"])
    }

    @Test("`l@o-p@b.b`: the local part is `o-p`; before-text `l@`")
    func hyphenContinuesDomain() {
        let ns = nodes(in: "l@o-p@b.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@", nil, "o-p@b.b"])
        #expect(ns.compactMap(\.url) == ["mailto:o-p@b.b"])
    }

    @Test("`l@o_p@b.b`: the local part is `o_p`; before-text `l@`")
    func underscoreContinuesDomain() {
        let ns = nodes(in: "l@o_p@b.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@", nil, "o_p@b.b"])
        #expect(ns.compactMap(\.url) == ["mailto:o_p@b.b"])
    }

    @Test("`l@abc@b.b`: the local part is `abc`; before-text `l@`")
    func alnumContinuesDomain() {
        let ns = nodes(in: "l@abc@b.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@", nil, "abc@b.b"])
        #expect(ns.compactMap(\.url) == ["mailto:abc@b.b"])
    }

    @Test("`l@+@b.b`: the local part is `+`; before-text `l@`")
    func plusAtStart() {
        let ns = nodes(in: "l@+@b.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@", nil, "+@b.b"])
        #expect(ns.compactMap(\.url) == ["mailto:+@b.b"])
    }

    @Test("`xy@ab@c.c`: the local part is `ab`; before-text `xy@`")
    func alnumFirstLocalPart() {
        let ns = nodes(in: "xy@ab@c.c")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "xy@", nil, "ab@c.c"])
        #expect(ns.compactMap(\.url) == ["mailto:ab@c.c"])
    }

    // MARK: - A `.` not followed by an alphanumeric ends a domain

    @Test("`a@b.+@c.c`: the local part is `.+`; before-text `a@b`")
    func dotThenPlusBoundary() {
        let ns = nodes(in: "a@b.+@c.c")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@b", nil, ".+@c.c"])
        #expect(ns.compactMap(\.url) == ["mailto:.+@c.c"])
    }

    @Test("`a@b..c@d.d`: the local part is `..c`; before-text `a@b`")
    func doubledDotBoundary() {
        let ns = nodes(in: "a@b..c@d.d")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@b", nil, "..c@d.d"])
        #expect(ns.compactMap(\.url) == ["mailto:..c@d.d"])
    }
}
