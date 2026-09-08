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
// AutolinkEmailPrecedingCharTests.dfsAutolinkNodes).
private func dfsAutolinkNodes(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?, url: String?)]
) {
    out.append((node.kind, node.literal(), node.url()))
    node.children.forEach { child in
        dfsAutolinkNodes(child, into: &out)
    }
}

/// GFM autolink domain-acceptance rules that differ between the `://`-scheme URL form and the email form.
///
/// cmark-gfm's `://`-scheme autolink (`url_match`, `extensions/autolink.c`) accepts any non-empty domain
/// whose first character is a valid host character (non-space, non-punctuation) - it does NOT require a
/// dot (`check_domain` is called with `allow_short = 1`). Its email autolink (`postprocess_text`), by
/// contrast, requires the domain to contain a dot that is immediately followed by an alphanumeric (its
/// `np` counter): a trailing dot yields an empty last label and does not count, so `o@b.` is not linked.
@Suite("GFM autolink domain rules")
struct AutolinkDomainRulesTests {

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

    // MARK: - Divergence 1: a `://`-scheme URL needs no dot in the domain

    @Test("scheme URL with a dotless domain autolinks (flag-OFF)")
    func schemeURLNoDotAutolinksFlagOff() throws {
        // `http://e` - `url_match` calls `check_domain(..., allow_short = 1)`, which accepts a domain with
        // no dot. The single valid host char `e` after `://` is enough.
        let ns = try nodes(in: "http://e", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://e"])
        #expect(ns.compactMap(\.url) == ["http://e"])
    }

    @Test("scheme URL with a dotless domain keeps Quirk M's empty leading sibling (flag-ON)")
    func schemeURLNoDotAutolinksFlagOn() throws {
        // Same match; flag-ON reproduces cmark's empty `before` node left by `cmark_node_unput` rewinding
        // the scheme letters out of the (scheme-only) preceding text node.
        let ns = try nodes(in: "http://e", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "", nil, "http://e"])
        #expect(ns.compactMap(\.url) == ["http://e"])
    }

    @Test("guard: scheme URL with a dot still autolinks")
    func schemeURLWithDotAutolinks() throws {
        let ns = try nodes(in: "http://x.io", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://x.io"])
        #expect(ns.compactMap(\.url) == ["http://x.io"])
    }

    @Test("guard: scheme with nothing after `://` stays plain text")
    func schemeURLEmptyDomainUnchanged() throws {
        let ns = try nodes(in: "http://", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "http://"])
        #expect(ns.compactMap(\.url) == [])
    }

    // MARK: - Divergence 1 faithfulness: relaxing the dot must not accept a punctuation-first domain

    @Test("guard: scheme URL whose domain starts with punctuation does not autolink")
    func schemeURLPunctuationFirstCharNoAutolink() throws {
        // `http://-x` - cmark's `sd_autolink_issafe` runs `is_valid_hostchar` on the first char after
        // `://`; `-` is punctuation, so the match is rejected. Removing only the dot requirement (without
        // this host-char gate) would wrongly link it.
        let ns = try nodes(in: "http://-x", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "http://-x"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("guard: scheme URL with a trailing underscore links the trimmed host")
    func schemeURLTrailingUnderscoreTrims() throws {
        // `http://a_` - the first char `a` is a valid host char (no dot required), and the trailing `_`
        // is peeled by the autolink trim rules, leaving `http://a`.
        let ns = try nodes(in: "http://a_", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://a", "_"])
        #expect(ns.compactMap(\.url) == ["http://a"])
    }

    // MARK: - Divergence 2: an email domain's last label must be non-empty (no trailing dot)

    @Test("email with a trailing-dot domain does not autolink")
    func emailTrailingDotNoAutolink() throws {
        // `o@b.` - the domain `b.` has an empty last label. cmark's `postprocess_text` only counts a dot
        // toward its required-dot (`np`) when the dot is immediately followed by an alphanumeric; a
        // trailing dot does not, so `np == 0` and the match is rejected.
        let ns = try nodes(in: "o@b.", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "o@b."])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("guard: email with a non-empty last label autolinks")
    func emailWithLastLabelAutolinks() throws {
        let ns = try nodes(in: "o@b.c", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:o@b.c"])
    }

    @Test("guard: email with an underscore label plus a proper last label autolinks")
    func emailUnderscoreLabelAutolinks() throws {
        let ns = try nodes(in: "o@b_c.d", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@b_c.d"])
        #expect(ns.compactMap(\.url) == ["mailto:o@b_c.d"])
    }

    // MARK: - Divergence 3: an email domain's pre-trim last char must be a letter or dot (not a digit)

    @Test("email whose domain ends in a digit does not autolink")
    func emailDomainEndingInDigitNoAutolink() throws {
        // `f@.0` - cmark's `postprocess_text` gates on the domain's last scanned char (before any
        // trailing-punctuation trim) being `cmark_isalpha(c) || c == '.'`. A digit fails that gate, so the
        // match is rejected. The empty first label (`.0`) is otherwise a valid domain shape.
        let ns = try nodes(in: "f@.0", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "f@.0"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("guard: email with a digit-only last label does not autolink")
    func emailDigitLastLabelNoAutolink() throws {
        // `a@1.2` - both labels end in a digit; the final scanned char `2` is not a letter or `.`.
        let ns = try nodes(in: "a@1.2", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@1.2"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("guard: email whose last label ends in a digit does not autolink")
    func emailLastLabelTrailingDigitNoAutolink() throws {
        // `a@b.c9` - the last label `c9` starts with a letter but ends in a digit; the final scanned char
        // `9` fails the letter-or-dot gate.
        let ns = try nodes(in: "a@b.c9", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@b.c9"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("guard: email with an interior digit but a letter-ending domain autolinks")
    func emailInteriorDigitLetterLastAutolinks() throws {
        // `o@b2.co` - digits are allowed inside the domain; only the final scanned char must be a letter or
        // `.`. Here it is `o`, so the email links.
        let ns = try nodes(in: "o@b2.co", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@b2.co"])
        #expect(ns.compactMap(\.url) == ["mailto:o@b2.co"])
    }

    // MARK: - Divergence 4: the domain scan ends at a dot not immediately followed by an alphanumeric

    @Test("email whose domain ends at a trailing dot after a digit does not autolink")
    func emailDomainDotBoundaryDigitLastNoAutolink() throws {
        // `a@.0.` - cmark's `postprocess_text` domain scan advances past a `.` only when the next char is an
        // alphanumeric. The final `.` is not, so the scan stops there, leaving the domain as `.0`; its last
        // scanned char `0` is a digit, which fails the letter-or-dot gate, so the match is rejected.
        let ns = try nodes(in: "a@.0.", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@.0."])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("email whose domain ends at a trailing dot after a digit label does not autolink")
    func emailDomainDotBoundaryDigitLabelNoAutolink() throws {
        // `a@b.c9.` - the scan stops at the trailing `.` (not followed by an alphanumeric); the domain
        // `b.c9` ends in the digit `9`, which fails the letter-or-dot gate.
        let ns = try nodes(in: "a@b.c9.", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@b.c9."])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("email links only the prefix when a dot precedes a non-alphanumeric")
    func emailDomainDotBoundaryLinksPrefix() throws {
        // `a@x.y.-5` - the scan stops at the `.` before `-` (not an alphanumeric), so the domain is `x.y`,
        // ending in the letter `y` (valid). The link is `mailto:a@x.y`; the remaining `.-5` is after-text.
        let ns = try nodes(in: "a@x.y.-5", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@x.y", ".-5"])
        #expect(ns.compactMap(\.url) == ["mailto:a@x.y"])
    }

    @Test("guard: multi-label email with every dot followed by a letter autolinks")
    func emailMultiDotDomainAutolinks() throws {
        // `a@b.c.d` - every `.` is immediately followed by an alphanumeric, so the scan consumes the whole
        // domain; its last char `d` is a letter.
        let ns = try nodes(in: "a@b.c.d", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c.d"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c.d"])
    }

    @Test("guard: simple two-label email still autolinks")
    func emailSimpleTwoLabelAutolinks() throws {
        let ns = try nodes(in: "a@b.c", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c"])
    }

    // MARK: - Divergence 5: an email domain's LAST label may contain an underscore

    // cmark's email autolink (`postprocess_text`, `extensions/autolink.c`) does NOT apply the URL
    // `check_domain` underscore restriction: its forward domain scan treats `_` exactly like `-`
    // (`c != '-' && c != '_'` never breaks), and it never calls `check_domain`. So `_` is accepted
    // anywhere in the domain, including the last label - the only gates are the letter-or-dot
    // pre-trim check and the trailing-alphanumeric check. The `://`-scheme form (Divergence 1's
    // `schemeURLDomainAccepted`) keeps the underscore-in-last-two-labels rejection; email must not.

    @Test("email whose last domain label contains an underscore autolinks")
    func emailLastLabelUnderscoreAutolinks() throws {
        // `a@b.c_d` - last label `c_d` has an `_`; it ends in the letter `d`, so cmark links it.
        let ns = try nodes(in: "a@b.c_d", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c_d"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c_d"])
    }

    @Test("email with an empty first label and an underscore last label autolinks")
    func emailEmptyFirstLabelUnderscoreLastAutolinks() throws {
        // `a@.b_o` - empty first label (leading `.`), last label `b_o` has an `_` and ends in `o`.
        let ns = try nodes(in: "a@.b_o", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@.b_o"])
        #expect(ns.compactMap(\.url) == ["mailto:a@.b_o"])
    }

    @Test("email with a hyphen local part and an underscore last label autolinks")
    func emailHyphenLocalUnderscoreLastAutolinks() throws {
        // `-@.b_o` - local part is a lone `-` (a valid GFM local-part char), domain `.b_o`.
        let ns = try nodes(in: "-@.b_o", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "-@.b_o"])
        #expect(ns.compactMap(\.url) == ["mailto:-@.b_o"])
    }

    @Test("guard: email with an underscore in a non-last label autolinks")
    func emailNonLastLabelUnderscoreAutolinks() throws {
        // `a@b_c.d` - `_` in the first label, proper last label `d`; linked before and after this fix.
        let ns = try nodes(in: "a@b_c.d", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b_c.d"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b_c.d"])
    }

    @Test("guard: email with a hyphen local part and a plain domain autolinks")
    func emailHyphenLocalPlainDomainAutolinks() throws {
        let ns = try nodes(in: "-@b.c", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "-@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:-@b.c"])
    }

    @Test("guard: the scheme-URL underscore-in-last-two-labels rejection is unchanged")
    func schemeURLUnderscoreLastTwoLabelsStillRejected() throws {
        // `http://a_b.c_d` - both of the domain's last two labels (`a_b`, `c_d`) contain `_`, so
        // cmark's `check_domain` rejects the whole URL. Removing the EMAIL last-label rule must not
        // touch this: the scheme URL stays plain text.
        let ns = try nodes(in: "http://a_b.c_d", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "http://a_b.c_d"])
        #expect(ns.compactMap(\.url) == [])
    }
}
