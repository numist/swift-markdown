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

/// Extended email autolinks (Autolinks (extension)) are recognized in text after emphasis is resolved, so a `_`
/// that is not part of an emphasis run may be part of an address's local part.
@Suite("Extended email autolinks next to emphasis delimiters")
struct AutolinkEmailEmphasisTests {

    private static let options: MarkdownDocument.ParseOptions = [.gfmAutolink]

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

    // MARK: - A `_` outside emphasis joins the local part

    @Test("`_@b.c`: the flanking `_` is the local part, not text before the link")
    func leadingUnderscore() {
        let ns = nodes(in: "_@b.c", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "_@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:_@b.c"])
    }

    @Test("`a_@b.c`: local part is `a_`, whole thing links")
    func wordThenUnderscore() {
        let ns = nodes(in: "a_@b.c", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a_@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:a_@b.c"])
    }

    @Test("`x _@b.c`: the space bounds the local part; `x ` is text before the link")
    func spaceThenUnderscore() {
        let ns = nodes(in: "x _@b.c", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "x ", nil, "_@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:_@b.c"])
    }

    // MARK: - An email inside a resolved emphasis run

    @Test("`_a@b.c_`: the email autolinks inside the emphasis")
    func emailInsideEmphasis() {
        let ns = nodes(in: "_a@b.c_", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .emphasis, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, nil, "a@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c"])
    }

    // MARK: - Emphasis consumes the delimiters, leaving an empty local part

    @Test("`_a_@b.c`: emphasis consumes both `_`, so `@b.c` has no local part and is text")
    func emphasisConsumesUnderscores() {
        let ns = nodes(in: "_a_@b.c", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .emphasis, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a", "@b.c"])
        #expect(ns.compactMap(\.url) == [])
    }

    // MARK: - Several addresses in one text

    @Test("`a@b.c x@y.z`: both emails link, with the ` ` between them")
    func twoEmailsInOneRun() {
        let ns = nodes(in: "a@b.c x@y.z", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c", " ", nil, "x@y.z"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c", "mailto:x@y.z"])
    }

}

/// A lowercase `mailto:` or `xmpp:` directly before an extended email autolink, and not preceded by an
/// alphanumeric or other local-part character, is part of the autolink: it becomes the destination's scheme in place of `mailto:` and is part of
/// the link text. With such a scheme the local part may be empty, and after `xmpp:` the domain may hold `/`.
@Suite("Extended email autolinks with a scheme")
struct AutolinkProtocolPrefixTests {

    private static let options: MarkdownDocument.ParseOptions = [.gfmAutolink]

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

    // MARK: - The scheme is part of the destination and link text

    @Test("`mailto:x@a.b`: the scheme is part of the destination and text")
    func mailtoFolds() {
        let ns = nodes(in: "mailto:x@a.b", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "mailto:x@a.b"])
        #expect(ns.compactMap(\.url) == ["mailto:x@a.b"])
    }

    @Test("`xmpp:x@a.b`: the destination keeps `xmpp:`, not `mailto:`")
    func xmppFolds() {
        let ns = nodes(in: "xmpp:x@a.b", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "xmpp:x@a.b"])
        #expect(ns.compactMap(\.url) == ["xmpp:x@a.b"])
    }

    @Test("`xmpp:x@a.b/c`: `/` is allowed in the xmpp domain")
    func xmppSlashInDomain() {
        let ns = nodes(in: "xmpp:x@a.b/c", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "xmpp:x@a.b/c"])
        #expect(ns.compactMap(\.url) == ["xmpp:x@a.b/c"])
    }

    @Test("`mailto:@a.b`: a scheme lets the local part be empty")
    func mailtoEmptyLocal() {
        // A bare `@a.b` has an empty local part and is text.
        let ns = nodes(in: "mailto:@a.b", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "mailto:@a.b"])
        #expect(ns.compactMap(\.url) == ["mailto:@a.b"])
    }

    @Test("`x mailto:a@b.c`: the scheme is part of the link; `x ` is text before the link")
    func schemeAfterText() {
        let ns = nodes(in: "x mailto:a@b.c", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "x ", nil, "mailto:a@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c"])
    }

    @Test("`.mailto:x@a.b`: a local-part character before the scheme is part of the link")
    func localCharBeforeScheme() {
        // The `.` before the scheme is a local-part character.
        let ns = nodes(in: ".mailto:x@a.b", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, ".mailto:x@a.b"])
        #expect(ns.compactMap(\.url) == [".mailto:x@a.b"])
    }

    // MARK: - Schemes that are not part of the autolink

    @Test("`MAILTO:x@a.b`: uppercase is not recognized (case-sensitive)")
    func uppercaseNotFolded() {
        let ns = nodes(in: "MAILTO:x@a.b", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "MAILTO:", nil, "x@a.b"])
        #expect(ns.compactMap(\.url) == ["mailto:x@a.b"])
    }

    @Test("`foo:x@a.b`: another scheme is not part of the link")
    func unknownSchemeNotFolded() {
        let ns = nodes(in: "foo:x@a.b", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "foo:", nil, "x@a.b"])
        #expect(ns.compactMap(\.url) == ["mailto:x@a.b"])
    }

    @Test("`amailto:x@a.b`: a scheme preceded by an alphanumeric is not at a boundary")
    func schemeNotAtBoundaryNotFolded() {
        let ns = nodes(in: "amailto:x@a.b", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "amailto:", nil, "x@a.b"])
        #expect(ns.compactMap(\.url) == ["mailto:x@a.b"])
    }

    @Test("`a@b.c`: an email with no scheme links with a `mailto:` destination")
    func plainEmailUnchanged() {
        let ns = nodes(in: "a@b.c", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c"])
    }
}
