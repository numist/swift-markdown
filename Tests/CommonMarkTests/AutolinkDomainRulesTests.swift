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

/// GFM autolink domain-acceptance rules (spec "Autolinks (extension)"). An extended www or url
/// autolink needs a valid domain: segments of alphanumerics, `_` and `-` separated by periods, with at
/// least one period and no underscore in the last two segments. An extended email autolink's domain is
/// one or more segments of alphanumerics, `-` and `_` separated by periods, with at least one period,
/// whose last character is neither `-` nor `_`; a final period is not part of the address. Tests under
/// `flagOn` pin `.cmarkBugCompatibility`.
@Suite("GFM autolink domain rules")
struct AutolinkDomainRulesTests {

    /// The differential-fuzzer configuration: GFM autolink on, cmark bug-compatibility on.
    private static let flagOn: MarkdownDocument.ParseOptions = [.gfmAutolink, .cmarkBugCompatibility]

    /// The shipped configuration: GFM autolink on, bug-compatibility deliberately off.
    private static let flagOff: MarkdownDocument.ParseOptions = [.gfmAutolink]

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

    // MARK: - Divergence 1: a `://`-scheme URL needs no dot in the domain

    @Test("scheme URL with a dotless domain is text")
    func schemeURLNoDotIsTextFlagOff() {
        let ns = nodes(in: "http://e", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "http://e"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("scheme URL with a dotless domain keeps Quirk M's empty leading sibling (flag-ON)")
    func schemeURLNoDotAutolinksFlagOn() {
        // Same match; flag-ON reproduces cmark's empty `before` node left by `cmark_node_unput` rewinding
        // the scheme letters out of the (scheme-only) preceding text node.
        let ns = nodes(in: "http://e", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "", nil, "http://e"])
        #expect(ns.compactMap(\.url) == ["http://e"])
    }

    @Test("guard: scheme URL with a dot still autolinks")
    func schemeURLWithDotAutolinks() {
        let ns = nodes(in: "http://x.io", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "http://x.io"])
        #expect(ns.compactMap(\.url) == ["http://x.io"])
    }

    @Test("guard: scheme with nothing after `://` stays plain text")
    func schemeURLEmptyDomainUnchanged() {
        let ns = nodes(in: "http://", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "http://"])
        #expect(ns.compactMap(\.url) == [])
    }

    // MARK: - Divergence 1 faithfulness: relaxing the dot must not accept a punctuation-first domain

    @Test("guard: scheme URL whose domain starts with punctuation does not autolink")
    func schemeURLPunctuationFirstCharNoAutolink() {
        // `http://-x` - cmark's `sd_autolink_issafe` runs `is_valid_hostchar` on the first char after
        // `://`; `-` is punctuation, so the match is rejected. Removing only the dot requirement (without
        // this host-char gate) would wrongly link it.
        let ns = nodes(in: "http://-x", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "http://-x"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("guard: scheme URL whose host is dotless once the trailing underscore is trimmed is text")
    func schemeURLTrailingUnderscoreTrims() {
        let ns = nodes(in: "http://a_", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "http://a_"])
        #expect(ns.compactMap(\.url) == [])
    }

    // MARK: - Divergence 2: an email domain's last label must be non-empty (no trailing dot)

    @Test("email with a trailing-dot domain does not autolink")
    func emailTrailingDotNoAutolink() {
        // `o@b.` - the domain `b.` has an empty last label. cmark's `postprocess_text` only counts a dot
        // toward its required-dot (`np`) when the dot is immediately followed by an alphanumeric; a
        // trailing dot does not, so `np == 0` and the match is rejected.
        let ns = nodes(in: "o@b.", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "o@b."])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("guard: email with a non-empty last label autolinks")
    func emailWithLastLabelAutolinks() {
        let ns = nodes(in: "o@b.c", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:o@b.c"])
    }

    @Test("guard: email with an underscore label plus a proper last label autolinks")
    func emailUnderscoreLabelAutolinks() {
        let ns = nodes(in: "o@b_c.d", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@b_c.d"])
        #expect(ns.compactMap(\.url) == ["mailto:o@b_c.d"])
    }

    // MARK: - Divergence 3: an email domain's pre-trim last char must be a letter or dot (not a digit)

    @Test("email whose domain ends in a digit does not autolink")
    func emailDomainEndingInDigitNoAutolink() {
        // `f@.0` - cmark's `postprocess_text` gates on the domain's last scanned char (before any
        // trailing-punctuation trim) being `cmark_isalpha(c) || c == '.'`. A digit fails that gate, so the
        // match is rejected. The empty first label (`.0`) is otherwise a valid domain shape.
        let ns = nodes(in: "f@.0", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "f@.0"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("email with a digit-only last label autolinks")
    func emailDigitLastLabelAutolinks() {
        let ns = nodes(in: "a@1.2", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@1.2"])
        #expect(ns.compactMap(\.url) == ["mailto:a@1.2"])
    }

    @Test("email whose last label ends in a digit autolinks")
    func emailLastLabelTrailingDigitAutolinks() {
        let ns = nodes(in: "a@b.c9", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c9"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c9"])
    }

    @Test("guard: email with an interior digit but a letter-ending domain autolinks")
    func emailInteriorDigitLetterLastAutolinks() {
        // `o@b2.co` - digits are allowed inside the domain; only the final scanned char must be a letter or
        // `.`. Here it is `o`, so the email links.
        let ns = nodes(in: "o@b2.co", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@b2.co"])
        #expect(ns.compactMap(\.url) == ["mailto:o@b2.co"])
    }

    // MARK: - Divergence 4: the domain scan ends at a dot not immediately followed by an alphanumeric

    @Test("email whose domain ends at a trailing dot after a digit does not autolink")
    func emailDomainDotBoundaryDigitLastNoAutolink() {
        // `a@.0.` - cmark's `postprocess_text` domain scan advances past a `.` only when the next char is an
        // alphanumeric. The final `.` is not, so the scan stops there, leaving the domain as `.0`; its last
        // scanned char `0` is a digit, which fails the letter-or-dot gate, so the match is rejected.
        let ns = nodes(in: "a@.0.", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@.0."])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("email followed by a period after a digit label links without the period")
    func emailDomainDotBoundaryDigitLabelAutolinks() {
        let ns = nodes(in: "a@b.c9.", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c9", "."])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c9"])
    }

    @Test("email domain segment may start with a hyphen")
    func emailDomainHyphenSegmentAutolinks() {
        let ns = nodes(in: "a@x.y.-5", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@x.y.-5"])
        #expect(ns.compactMap(\.url) == ["mailto:a@x.y.-5"])
    }

    @Test("guard: multi-label email with every dot followed by a letter autolinks")
    func emailMultiDotDomainAutolinks() {
        // `a@b.c.d` - every `.` is immediately followed by an alphanumeric, so the scan consumes the whole
        // domain; its last char `d` is a letter.
        let ns = nodes(in: "a@b.c.d", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c.d"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c.d"])
    }

    @Test("guard: simple two-label email still autolinks")
    func emailSimpleTwoLabelAutolinks() {
        let ns = nodes(in: "a@b.c", options: Self.flagOff)
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
    func emailLastLabelUnderscoreAutolinks() {
        // `a@b.c_d` - last label `c_d` has an `_`; it ends in the letter `d`, so cmark links it.
        let ns = nodes(in: "a@b.c_d", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c_d"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b.c_d"])
    }

    @Test("email with an empty first label is text")
    func emailEmptyFirstLabelIsText() {
        let ns = nodes(in: "a@.b_o", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@.b_o"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("email with a hyphen local part and an empty first label is text")
    func emailHyphenLocalEmptyFirstLabelIsText() {
        let ns = nodes(in: "-@.b_o", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "-@.b_o"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("guard: email with an underscore in a non-last label autolinks")
    func emailNonLastLabelUnderscoreAutolinks() {
        // `a@b_c.d` - `_` in the first label, proper last label `d`; linked before and after this fix.
        let ns = nodes(in: "a@b_c.d", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b_c.d"])
        #expect(ns.compactMap(\.url) == ["mailto:a@b_c.d"])
    }

    @Test("guard: email with a hyphen local part and a plain domain autolinks")
    func emailHyphenLocalPlainDomainAutolinks() {
        let ns = nodes(in: "-@b.c", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "-@b.c"])
        #expect(ns.compactMap(\.url) == ["mailto:-@b.c"])
    }

    @Test("guard: the scheme-URL underscore-in-last-two-labels rejection is unchanged")
    func schemeURLUnderscoreLastTwoLabelsStillRejected() {
        // `http://a_b.c_d` - both of the domain's last two labels (`a_b`, `c_d`) contain `_`, so
        // cmark's `check_domain` rejects the whole URL. Removing the EMAIL last-label rule must not
        // touch this: the scheme URL stays plain text.
        let ns = nodes(in: "http://a_b.c_d", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "http://a_b.c_d"])
        #expect(ns.compactMap(\.url) == [])
    }

    // MARK: - Divergence 6: a `www.` domain is rejected for an underscore in its last two labels

    // Like the `://`-scheme form, cmark's `www_match` (`extensions/autolink.c`) gates on
    // `check_domain(data, size, allow_short: 0)` before scanning the URL body, so a `www.` domain
    // bearing an underscore in either of its last two `.`-separated labels is rejected outright. The
    // rejection is GFM-spec-correct (a host name may not contain an underscore), so it applies in both
    // modes - unlike the bare-`www` over-trim quirk, which is flag-ON only.

    @Test("www domain with an underscore in its last label does not autolink (both modes)")
    func wwwUnderscoreLastLabelNoAutolink() {
        // `www.a_b x` - the domain's last two labels are `www` and `a_b`; `a_b` has an underscore, so
        // cmark's `check_domain` returns 0 and the whole run stays plain text.
        for options in [Self.flagOff, Self.flagOn] {
            let ns = nodes(in: "www.a_b x", options: options)
            #expect(ns.map(\.kind) == [.document, .paragraph, .text])
            #expect(ns.map(\.text) == [nil, nil, "www.a_b x"])
            #expect(ns.compactMap(\.url) == [])
        }
    }

    @Test("guard: www domain with an underscore outside its last two labels still autolinks (both modes)")
    func wwwUnderscoreOutsideLastTwoLabelsAutolinks() {
        // `www.a_b.c.d x` - the underscore is in `a_b`, which is NOT among the last two labels (`c`, `d`),
        // so `check_domain` accepts the domain and the URL links. The boundary between this and the
        // rejected case above is exactly cmark's last-two-labels rule.
        for options in [Self.flagOff, Self.flagOn] {
            let ns = nodes(in: "www.a_b.c.d x", options: options)
            #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
            #expect(ns.map(\.text) == [nil, nil, nil, "www.a_b.c.d", " x"])
            #expect(ns.compactMap(\.url) == ["http://www.a_b.c.d"])
        }
    }

    // MARK: - Divergence 7: the domain scan stops inside a non-ASCII codepoint

    // cmark's `check_domain` (`extensions/autolink.c`) advances one byte at a time, and its
    // `is_valid_hostchar` runs `cmark_utf8proc_iterate`, which fails (returns 0) on a UTF-8 continuation
    // byte. So after accepting the LEADING byte of a multibyte codepoint the scan lands on the
    // continuation byte and breaks: the domain scan stops inside the first non-ASCII codepoint and never
    // reaches a later `_`/`.`. A trailing `__` after a `�` (U+FFFD) is therefore left to the URL-body
    // scan + `autolink_delim` trim rather than tripping the underscore-in-last-label rejection. The
    // fuzzer harness (like `String(decoding:as:UTF8.self)`) repairs an invalid UTF-8 byte to U+FFFD
    // before parsing, so the domain's `�` is three ordinary UTF-8 bytes the zero-copy scan already sees.

    @Test("www domain beginning with an invalid byte repaired to U+FFFD")
    func wwwInvalidByteDomainAutolinks() {
        // `www.` + 0xFF + `__` - the lone 0xFF is invalid UTF-8, repaired to U+FFFD as the harness
        // decodes it. cmark links `www.�`: the domain scan stops within the U+FFFD, and `autolink_delim`
        // peels the trailing `__`. The U+FFFD's bytes appear verbatim in both the destination and the
        // link text.
        let src = String(decoding: [0x77, 0x77, 0x77, 0x2e, 0xff, 0x5f, 0x5f] as [UInt8], as: UTF8.self)
        let ns = nodes(in: src, options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "www.\u{FFFD}", "__"])
        #expect(ns.compactMap(\.url) == ["http://www.\u{FFFD}"])
        // U+FFFD is a symbol, not an alphanumeric, so no valid domain follows `www.`.
        let shipped = nodes(in: src, options: Self.flagOff)
        #expect(shipped.map(\.kind) == [.document, .paragraph, .text])
        #expect(shipped.map(\.text) == [nil, nil, "www.\u{FFFD}__"])
    }

    @Test("www domain with a non-ASCII letter")
    func wwwValidMultibyteDomainAutolinks() {
        // `www.éx y` (é = U+00E9, valid two-byte UTF-8) - the domain scan stops within `é`, the URL body
        // links `www.éx` (up to the space), and ` y` is left as trailing text. Rejecting continuation
        // bytes must not regress ordinary non-ASCII domains.
        let ns = nodes(in: "www.\u{E9}x y", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "www.\u{E9}x", " y"])
        #expect(ns.compactMap(\.url) == ["http://www.\u{E9}x"])
        // `éx` is alphanumeric but holds no period, so it is no valid domain; with one it links.
        let shipped = nodes(in: "www.\u{E9}x y", options: Self.flagOff)
        #expect(shipped.map(\.kind) == [.document, .paragraph, .text])
        let dotted = nodes(in: "www.\u{E9}x.y z", options: Self.flagOff)
        #expect(dotted.map(\.text) == [nil, nil, nil, "www.\u{E9}x.y", " z"])
        #expect(dotted.compactMap(\.url) == ["http://www.\u{E9}x.y"])
    }

    @Test("scheme URL whose domain holds a U+FFFD before an underscore")
    func schemeURLNonASCIIThenUnderscoreAutolinks() {
        // `http://a` + 0xFF (repaired to U+FFFD) + `_b` - drives `checkDomainAccepted` through the
        // `://`-scheme call site (`schemeURLDomainAccepted`), which shares the same continuation-byte
        // fix. cmark's `check_domain` breaks inside the U+FFFD (its `is_valid_hostchar` fails on the
        // continuation byte) before reaching the `_`, so the underscore-in-last-label rule never fires;
        // the forward URL scan then reclaims `_b` and `autolink_delim` keeps it (the last char `b` is not
        // trailing punctuation), linking the whole `http://a�_b`. Without the fix the domain scan would
        // reach the `_` and wrongly reject the URL. `allow_short` means the scheme form needs no dot.
        let src = String(decoding: [0x68, 0x74, 0x74, 0x70, 0x3a, 0x2f, 0x2f, 0x61, 0xff, 0x5f, 0x62] as [UInt8], as: UTF8.self)
        let ns = nodes(in: src, options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "", nil, "http://a\u{FFFD}_b"])
        #expect(ns.compactMap(\.url) == ["http://a\u{FFFD}_b"])
        // The domain ends at the symbol U+FFFD, leaving `a`, which holds no period.
        let shipped = nodes(in: src, options: Self.flagOff)
        #expect(shipped.map(\.kind) == [.document, .paragraph, .text])
    }
}
