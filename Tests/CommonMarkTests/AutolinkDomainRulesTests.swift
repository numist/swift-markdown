/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

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

/// Extended autolink domain-acceptance rules. An extended url autolink's domain begins with a character that is
/// neither whitespace nor punctuation; an extended www autolink's domain holds a period. Neither may have an
/// underscore in its last two period-separated segments. An extended email autolink's domain is a run of ASCII
/// alphanumerics, `-`, `_`, and periods each followed by an alphanumeric; it holds a period and ends in a letter.
@Suite("GFM autolink domain rules")
struct AutolinkDomainRulesTests {

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

    // MARK: - Extended url autolink domains

    @Test("scheme URL with a dotless domain autolinks")
    func schemeURLNoDotAutolinks() {
        let ns = nodes(in: "http://e", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://e"])
        #expect(ns.compactMap(\.url) == ["http://e"])
    }

    @Test("scheme URL with a dotted domain autolinks")
    func schemeURLWithDotAutolinks() {
        let ns = nodes(in: "http://x.io", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://x.io"])
        #expect(ns.compactMap(\.url) == ["http://x.io"])
    }

    @Test("scheme with nothing after `://` is text")
    func schemeURLEmptyDomainIsText() {
        let ns = nodes(in: "http://", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "http://"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("scheme URL whose dotless domain starts with a hyphen is text")
    func schemeURLHyphenFirstDotlessDomainIsText() {
        let ns = nodes(in: "http://-x", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "http://-x"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("scheme URL ending in an underscore links without it")
    func schemeURLTrailingUnderscoreTrims() {
        let ns = nodes(in: "http://a_", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a", "_"])
        #expect(ns.compactMap(\.url) == ["http://a"])
    }

    // MARK: - Extended email autolink domains

    @Test("email with a trailing-dot domain does not autolink")
    func emailTrailingDotNoAutolink() {
        // A final period is not part of the address, which leaves the domain `b` with no period.
        let ns = nodes(in: "o@b.", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "o@b."])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("email with a non-empty last segment autolinks")
    func emailWithLastLabelAutolinks() {
        let ns = nodes(in: "o@b.c", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:o@b.c"])
    }

    @Test("email with an underscore in its first domain segment autolinks")
    func emailUnderscoreLabelAutolinks() {
        let ns = nodes(in: "o@b_c.d", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@b_c.d"])
        #expect(ns.compactMap(\.url) == ["mailto:o@b_c.d"])
    }

    @Test("email whose domain has an empty first segment and ends in a digit is text")
    func emailEmptyFirstSegmentDigitDomainIsText() {
        let ns = nodes(in: "f@.0", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "f@.0"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("email with a digit-only last segment is text")
    func emailDigitLastLabelIsText() {
        let ns = nodes(in: "a@1.2", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@1.2"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("email whose last segment ends in a digit is text")
    func emailLastLabelTrailingDigitIsText() {
        let ns = nodes(in: "a@b.c9", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@b.c9"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("email with a digit inside its domain autolinks")
    func emailInteriorDigitLetterLastAutolinks() {
        let ns = nodes(in: "o@b2.co", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@b2.co"])
        #expect(ns.compactMap(\.url) == ["mailto:o@b2.co"])
    }

    @Test("email whose domain has an empty first segment and a final period is text")
    func emailDomainDotBoundaryDigitLastNoAutolink() {
        // A final period is not part of the address, and `.0` has an empty first segment.
        let ns = nodes(in: "a@.0.", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@.0."])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("email whose domain ends in a digit before a final period is text")
    func emailDomainDotBoundaryDigitLabelIsText() {
        let ns = nodes(in: "a@b.c9.", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@b.c9."])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("email domain ends before a period that no alphanumeric follows")
    func emailDomainEndsBeforeHyphenSegment() {
        let ns = nodes(in: "a@x.y.-5", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@x.y", ".-5"])
        #expect(ns.compactMap(\.url) == ["mailto:a@x.y"])
    }

    @Test("email with three domain segments autolinks")
    func emailMultiDotDomainAutolinks() {
        let ns = nodes(in: "a@b.c.d", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c.d"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c.d"])
    }

    @Test("email with two domain segments autolinks")
    func emailSimpleTwoLabelAutolinks() {
        let ns = nodes(in: "a@b.c", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c"])
    }

    // MARK: - Underscores in domains

    // An extended www or url autolink's domain may not hold an underscore in its last two segments. An extended
    // email autolink's domain may hold one anywhere but its last character.

    @Test("email whose last domain segment contains an underscore autolinks")
    func emailLastLabelUnderscoreAutolinks() {
        let ns = nodes(in: "a@b.c_d", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c_d"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c_d"])
    }

    @Test("email with an empty first domain segment autolinks")
    func emailEmptyFirstLabelAutolinks() {
        let ns = nodes(in: "a@.b_o", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@.b_o"])
        #expect(ns.compactMap(\.url) == ["mailto:a@.b_o"])
    }

    @Test("email with a hyphen local part and an empty first domain segment autolinks")
    func emailHyphenLocalEmptyFirstLabelAutolinks() {
        let ns = nodes(in: "-@.b_o", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "-@.b_o"])
        #expect(ns.compactMap(\.url) == ["mailto:-@.b_o"])
    }

    @Test("email with an underscore in a non-last domain segment autolinks")
    func emailNonLastLabelUnderscoreAutolinks() {
        let ns = nodes(in: "a@b_c.d", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b_c.d"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b_c.d"])
    }

    @Test("email with a hyphen local part and a plain domain autolinks")
    func emailHyphenLocalPlainDomainAutolinks() {
        let ns = nodes(in: "-@b.c", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "-@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:-@b.c"])
    }

    @Test("scheme URL with underscores in its last two domain segments is text")
    func schemeURLUnderscoreLastTwoLabelsIsText() {
        let ns = nodes(in: "http://a_b.c_d", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "http://a_b.c_d"])
        #expect(ns.compactMap(\.url) == [])
    }

    // MARK: - Extended www autolink domains

    @Test("www domain with an underscore in its last segment is text")
    func wwwUnderscoreLastLabelNoAutolink() {
        let ns = nodes(in: "www.a_b x", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "www.a_b x"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("www domain with an underscore outside its last two segments autolinks")
    func wwwUnderscoreOutsideLastTwoLabelsAutolinks() {
        let ns = nodes(in: "www.a_b.c.d x", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "www.a_b.c.d", " x"])
        #expect(ns.compactMap(\.url) == ["http://www.a_b.c.d"])
    }

    // MARK: - Non-ASCII domains

    @Test("www domain beginning with an invalid byte repaired to U+FFFD")
    func wwwInvalidByteDomainAutolinks() {
        // The invalid byte 0xFF decodes to U+FFFD.
        let src = String(decoding: [0x77, 0x77, 0x77, 0x2e, 0xff, 0x5f, 0x5f] as [UInt8], as: UTF8.self)
        // The domain scan stops at U+FFFD, short of the underscores, which the trailing punctuation trim removes.
        let ns = nodes(in: src, options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "www.\u{FFFD}", "__"])
        #expect(ns.compactMap(\.url) == ["http://www.\u{FFFD}"])
    }

    @Test("www domain with a non-ASCII letter")
    func wwwNonASCIILetterDomainAutolinks() {
        let ns = nodes(in: "www.\u{E9}x y", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        let dotted = nodes(in: "www.\u{E9}x.y z", options: Self.options)
        #expect(dotted.map(\.text) == [nil, nil, nil, "www.\u{E9}x.y", " z"])
        #expect(dotted.compactMap(\.url) == ["http://www.\u{E9}x.y"])
    }

    @Test("scheme URL whose domain holds a U+FFFD before an underscore")
    func schemeURLReplacementCharacterInDomainAutolinks() {
        // `http://a` + 0xFF (repaired to U+FFFD) + `_b`.
        let src = String(decoding: [0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x61, 0xff, 0x5f, 0x62] as [UInt8], as: UTF8.self)
        // The domain scan stops at U+FFFD, short of the underscore.
        let ns = nodes(in: src, options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a\u{FFFD}_b"])
        #expect(ns.compactMap(\.url) == ["http://a\u{FFFD}_b"])
    }
}
