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
// AutolinkDomainRulesTests.dfsAutolinkNodes).
private func dfsAutolinkNodes(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?, url: String?)]
) {
    out.append((node.kind, node.literal(), node.url()))
    node.children.forEach { child in
        dfsAutolinkNodes(child, into: &out)
    }
}

/// A `www.` with no valid domain after it: the shipped deliverable never autolinks it, but cmark-gfm does.
///
/// GFM's `www.` autolink requires a valid domain (at least one period, non-empty segments) after `www.`, so
/// the spec-correct deliverable (flag-OFF) leaves a domain-less `www.` as plain text. cmark-gfm's
/// `www_match` (`extensions/autolink.c`) over-trims: its `check_domain(data, size, allow_short: 0)` counts
/// the period *inside* `www.` toward the required-dot gate whenever the chunk holds at least one byte past
/// `www.` (its loop bound `i < size - 1` reaches that period only then), so it links a bare `www`
/// (destination `http://www`) once `autolink_delim` peels the trailing `.`. `www.` at end-of-input has
/// nothing after it, so the period is never counted and neither implementation links it. The over-trim is a
/// cmark defect, reproduced only under `.cmarkBugCompatibility` (flag-ON) to match the reference; flag-OFF
/// stays spec-correct.
@Suite("GFM www autolink domain-less over-trim")
struct AutolinkWWWBareTests {

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

    // MARK: - The deliverable does not link a domain-less `www.` (flag-OFF, spec-correct)

    @Test("domain-less `www.` before a boundary stays plain text (flag-OFF)")
    func domainlessWWWNotLinkedFlagOff() throws {
        // `www. x` - after `www.` there is only a space, so there is no valid domain. GFM requires one, so
        // the deliverable leaves the whole run as text.
        let ns = try nodes(in: "www. x", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "www. x"])
        #expect(ns.compactMap(\.url) == [])
    }

    // MARK: - Flag-ON reproduces cmark's over-trim (bare `www` linked)

    @Test("domain-less `www.` before a boundary links a bare `www` (flag-ON)")
    func domainlessWWWLinksBareWWWFlagOn() throws {
        // `www. x` - cmark's `www_match` counts the `www.` period (a byte follows it) and `autolink_delim`
        // peels the trailing `.`, leaving `www` linked to the useless `http://www`; the `.` and ` x` are
        // after-text.
        let ns = try nodes(in: "www. x", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "www", ". x"])
        #expect(ns.compactMap(\.url) == ["http://www"])
    }

    // MARK: - `www.` at end-of-input: neither mode links it

    @Test("`www.` at end-of-input stays plain text (flag-OFF)")
    func wwwAtEndOfInputNotLinkedFlagOff() throws {
        // Nothing follows `www.`, so cmark's `check_domain` loop (`i < size - 1`) never reaches the period;
        // `np == 0` and no link is produced.
        let ns = try nodes(in: "www.", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "www."])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("`www.` at end-of-input stays plain text (flag-ON)")
    func wwwAtEndOfInputNotLinkedFlagOn() throws {
        // Same as flag-OFF: the over-trim needs a byte after `www.` to count its period, and there is none.
        let ns = try nodes(in: "www.", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "www."])
        #expect(ns.compactMap(\.url) == [])
    }

    // MARK: - Guard: a real domain still autolinks in BOTH modes (unchanged)

    @Test("guard: `www.a.b` with a real domain autolinks (flag-OFF)")
    func validDomainAutolinksFlagOff() throws {
        let ns = try nodes(in: "www.a.b x", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "www.a.b", " x"])
        #expect(ns.compactMap(\.url) == ["http://www.a.b"])
    }

    @Test("guard: `www.a.b` with a real domain autolinks (flag-ON)")
    func validDomainAutolinksFlagOn() throws {
        let ns = try nodes(in: "www.a.b x", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "www.a.b", " x"])
        #expect(ns.compactMap(\.url) == ["http://www.a.b"])
    }

    // MARK: - Guard: the over-trim still honors `check_domain`'s underscore rejection (flag-ON)

    @Test("guard: a domain-less `www._` is rejected in both modes")
    func domainlessWWWUnderscoreRejectedBothModes() throws {
        // `www._ x` trims to a bare `www`, but cmark's `check_domain` rejects an underscore in the domain's
        // last two labels (`www`, `_`), so it does not link even flag-ON. Reproducing the over-trim must not
        // drop that rejection.
        for options in [Self.flagOff, Self.flagOn] {
            let ns = try nodes(in: "www._ x", options: options)
            #expect(ns.map(\.kind) == [.document, .paragraph, .text])
            #expect(ns.map(\.text) == [nil, nil, "www._ x"])
            #expect(ns.compactMap(\.url) == [])
        }
    }
}
