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

/// GFM autolink domain-acceptance rules (spec "Autolinks (extension)"). An extended www or url
/// autolink needs a valid domain: segments of alphanumerics, `_` and `-` separated by periods, with at
/// least one period and no underscore in the last two segments. An extended email autolink's domain is
/// one or more segments of alphanumerics, `-` and `_` separated by periods, with at least one period,
/// whose last character is neither `-` nor `_`; a final period is not part of the address.
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

    @Test("scheme URL with a dotless domain is text")
    func schemeURLNoDotIsText() {
        let ns = nodes(in: "http://e", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "http://e"])
        #expect(ns.compactMap(\.url) == [])
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

    @Test("scheme URL whose host is dotless once the trailing underscore is trimmed is text")
    func schemeURLTrailingUnderscoreTrims() {
        let ns = nodes(in: "http://a_", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "http://a_"])
        #expect(ns.compactMap(\.url) == [])
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

    @Test("email with a digit-only last segment autolinks")
    func emailDigitLastLabelAutolinks() {
        let ns = nodes(in: "a@1.2", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@1.2"])
        #expect(ns.compactMap(\.url) == ["mailto:a@1.2"])
    }

    @Test("email whose last segment ends in a digit autolinks")
    func emailLastLabelTrailingDigitAutolinks() {
        let ns = nodes(in: "a@b.c9", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c9"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c9"])
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

    @Test("email followed by a period after a digit links without the period")
    func emailDomainDotBoundaryDigitLabelAutolinks() {
        let ns = nodes(in: "a@b.c9.", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c9", "."])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c9"])
    }

    @Test("email domain segment may start with a hyphen")
    func emailDomainHyphenSegmentAutolinks() {
        let ns = nodes(in: "a@x.y.-5", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@x.y.-5"])
        #expect(ns.compactMap(\.url) == ["mailto:a@x.y.-5"])
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

    // A valid domain, used by extended www and url autolinks, may not hold an underscore in its last two
    // segments. An extended email autolink's domain may hold one anywhere but its last character.

    @Test("email whose last domain segment contains an underscore autolinks")
    func emailLastLabelUnderscoreAutolinks() {
        let ns = nodes(in: "a@b.c_d", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c_d"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c_d"])
    }

    @Test("email with an empty first domain segment is text")
    func emailEmptyFirstLabelIsText() {
        let ns = nodes(in: "a@.b_o", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@.b_o"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("email with a hyphen local part and an empty first domain segment is text")
    func emailHyphenLocalEmptyFirstLabelIsText() {
        let ns = nodes(in: "-@.b_o", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "-@.b_o"])
        #expect(ns.compactMap(\.url) == [])
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
    func wwwInvalidByteDomainIsText() {
        // The invalid byte 0xFF decodes to U+FFFD.
        let src = String(decoding: [0x77, 0x77, 0x77, 0x2e, 0xff, 0x5f, 0x5f] as [UInt8], as: UTF8.self)
        // U+FFFD is a symbol, not an alphanumeric, so no valid domain follows `www.`.
        let ns = nodes(in: src, options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "www.\u{FFFD}__"])
    }

    @Test("www domain with a non-ASCII letter")
    func wwwNonASCIILetterDomainNeedsPeriod() {
        // `éx` is alphanumeric but holds no period, so it is no valid domain; with one it links.
        let ns = nodes(in: "www.\u{E9}x y", options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        let dotted = nodes(in: "www.\u{E9}x.y z", options: Self.options)
        #expect(dotted.map(\.text) == [nil, nil, nil, "www.\u{E9}x.y", " z"])
        #expect(dotted.compactMap(\.url) == ["http://www.\u{E9}x.y"])
    }

    @Test("scheme URL whose domain holds a U+FFFD before an underscore")
    func schemeURLReplacementCharacterInDomainIsText() {
        // `http://a` + 0xFF (repaired to U+FFFD) + `_b`.
        let src = String(decoding: [0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x61, 0xff, 0x5f, 0x62] as [UInt8], as: UTF8.self)
        // The domain ends at the symbol U+FFFD, leaving `a`, which holds no period.
        let ns = nodes(in: src, options: Self.options)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
    }
}
