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
// AutolinkEmptySiblingTests.dfsAutolinkNodes).
private func dfsAutolinkNodes(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?, url: String?)]
) {
    out.append((node.kind, node.literal(), node.url()))
    node.children.forEach { child in
        dfsAutolinkNodes(child, into: &out)
    }
}

/// A GFM email autolink must fire regardless of the character immediately preceding its local part.
///
/// cmark-gfm's autolink extension detects emails in `postprocess_text` (`extensions/autolink.c`), a pass
/// over the finished text node: it scans backward from `@` over local-part chars and simply STOPS at the
/// first non-local char, leaving whatever precedes as ordinary "before" text - there is no rule that the
/// preceding char be whitespace or `(`. (Only the `www.` and `://`-scheme forms - `www_match`/`url_match`
/// - restrict the preceding char.) So a leading `<` that failed as an angle autolink / inline HTML does
/// not block the email match: `<o@.e` yields Text "<" + Link(mailto:o@.e).
@Suite("GFM email autolink preceding-character")
struct AutolinkEmailPrecedingCharTests {

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

    // MARK: - The fix: `<` before the local part does not block the email

    @Test("flag-OFF: email autolinks after a leading `<`")
    func emailAfterAngleFlagOff() throws {
        // The `<` is not a valid `<...>` autolink/HTML (no `>`), so it is literal text; the email still
        // autolinks. Flag-OFF: no empty trailing sibling. Text "<" + Link(mailto:o@.e)[Text "o@.e"].
        let ns = try nodes(in: "<o@.e", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "<", nil, "o@.e"])
        #expect(ns.compactMap(\.url) == ["mailto:o@.e"])
    }

    @Test("flag-ON: email after a leading `<` keeps Quirk M's empty trailing sibling")
    func emailAfterAngleFlagOn() throws {
        // Same match; flag-ON reproduces cmark's empty `after` node: Text "<" + Link + Text "o@.e" + Text "".
        let ns = try nodes(in: "<o@.e", options: Self.flagOn)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text, .text])
        #expect(ns.map(\.text) == [nil, nil, "<", nil, "o@.e", ""])
        #expect(ns.compactMap(\.url) == ["mailto:o@.e"])
    }

    // MARK: - Guards: preceding contexts that already autolink must stay working

    @Test("guard: standalone email still autolinks")
    func emailStandalone() throws {
        let ns = try nodes(in: "o@.e", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "o@.e"])
        #expect(ns.compactMap(\.url) == ["mailto:o@.e"])
    }

    @Test("guard: email after text + space still autolinks")
    func emailAfterTextSpace() throws {
        let ns = try nodes(in: "x o@.e", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "x ", nil, "o@.e"])
        #expect(ns.compactMap(\.url) == ["mailto:o@.e"])
    }

    @Test("guard: email after `(` still autolinks")
    func emailAfterParen() throws {
        let ns = try nodes(in: "(o@.e", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "(", nil, "o@.e"])
        #expect(ns.compactMap(\.url) == ["mailto:o@.e"])
    }

    // MARK: - Guards: the local-part scan must accept only cmark's set

    // cmark-gfm's `postprocess_text` backward scan (autolink.c) accepts only alnum + `.+-_` for the local
    // part; it STOPS (and, for a length-0 local part, rejects the whole match) at any other char - including
    // the extra CommonMark §6.4 email chars (`!#$%&'*/=?^\`{|}~`). Because those chars are not in cmark's set,
    // a `@` reached with only such chars before it does not autolink. These stay plain text in both engines.

    @Test("guard: `!` before `@` is not a GFM local-part char - no autolink")
    func bangBeforeAtNoLink() throws {
        // `<a!@.e`: cmark's backward scan hits `!` immediately and rejects; `a!` is not swallowed into a
        // local part. Whole thing stays plain text.
        let ns = try nodes(in: "<a!@.e", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "<a!@.e"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("guard: `!` local-part char at line start is still not a GFM local-part char")
    func bangLocalAtStartNoLink() throws {
        // `x!@.e` at the very start (local part touches the content start, so the old preceding-char guard
        // never applied): cmark still rejects because `!` breaks its backward scan. Plain text.
        let ns = try nodes(in: "x!@.e", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .text])
        #expect(ns.map(\.text) == [nil, nil, "x!@.e"])
        #expect(ns.compactMap(\.url) == [])
    }

    @Test("guard: the CommonMark §6.4 angle-email form keeps its broad local-part set")
    func angleEmailKeepsBroadLocalSet() throws {
        // `<a!b@c.de>` - a valid `<...>` autolink. The §6.4 form's local part admits `!` (unlike the GFM
        // extended form narrowed above), so this must still autolink. Guards that narrowing the GFM scan
        // did not narrow the shared angle-email path.
        let ns = try nodes(in: "<a!b@c.de>", options: Self.flagOff)
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a!b@c.de"])
        #expect(ns.compactMap(\.url) == ["mailto:a!b@c.de"])
    }
}
