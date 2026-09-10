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
// AutolinkEmailPostPassTests.dfsAutolinkNodes).
private func dfsAutolinkNodes(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, text: String?, url: String?)]
) {
    out.append((node.kind, node.literal(), node.url()))
    node.children.forEach { child in
        dfsAutolinkNodes(child, into: &out)
    }
}

/// The backward local-part scan of a GFM email autolink must not rewind past a preceding candidate's
/// forward-scan break point.
///
/// cmark-gfm's `postprocess_text` (`extensions/autolink.c`) runs a single monotonic cursor `start + offset`.
/// When a `local@domain` candidate's FORWARD domain scan breaks at a char the domain grammar rejects
/// (e.g. `+`, or a `.` not immediately followed by an alphanumeric), cmark advances `offset` past that
/// break point (`offset += max_rewind + link_end`). The NEXT `@`'s backward local-part scan is bounded by
/// `max_rewind = at - (data + start + offset)`, so it can only rewind back to that advanced cursor - never
/// into the abandoned candidate's local part.
///
/// The subtlety: cmark's backward scan DOES accept `+` (and `.`) as local-part chars (`strchr(".+-_", c)`),
/// so `+`/`.` are not themselves rewind boundaries. The boundary is created by the forward domain scan
/// breaking on those chars, which advances the cursor. This is why `.`, `-`, `_`, and alphanumerics rewind
/// THROUGH (the forward scan CONTINUES on `-`, `_`, alnum, and `.`-followed-by-alnum, so no cursor advance
/// happens between the two `@`s), while `+` (always breaks) and a boundary `.` (breaks when not followed by
/// alnum) act as left boundaries for the next email's local part.
@Suite("GFM email autolink backward local-part rewind boundary (forward-scan break)")
struct AutolinkEmailLocalRewindBoundaryTests {

    /// The shipped configuration: GFM autolink on, cmark bug-compatibility off (the spec-correct
    /// deliverable, so empty `before`/`after` siblings are dropped).
    private static let options: MarkdownDocument.ParseOptions = [.gfmAutolink]

    private func nodes(
        in src: String
    ) throws -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] {
        try MarkdownDocument.withParsedDocument(src, options: Self.options) {
            doc -> [(kind: MarkdownNode.Kind, text: String?, url: String?)] in
            var out: [(kind: MarkdownNode.Kind, text: String?, url: String?)] = []
            dfsAutolinkNodes(doc.root, into: &out)
            return out
        }
    }

    // MARK: - Fixture sanity: the node-walk is meaningful (a valid email really does link)

    @Test("fixture sanity: a plain valid email links with a synthetic `mailto:`")
    func fixtureSanity() throws {
        // Guards against a vacuous pass: if the walk returned a degenerate tree, this valid email would fail
        // to produce the [.document, .paragraph, .link, .text] shape with a `mailto:` URL.
        let ns = try nodes(in: "a@b.c")
        try #require(ns.count == 4, "expected document > paragraph > link > text")
        #expect(ns.map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, nil, "a@b.c"])
        #expect(try #require(ns.compactMap(\.url).first) == "mailto:a@b.c")
    }

    // MARK: - `+` breaks the forward scan, bounding the next local part

    @Test("`l@o+@.b`: the `+` bounds the second local part; before-text `l@o`")
    func plusBoundsLocalPart() throws {
        // `l@o` fails (domain `o` has no dot, and the scan breaks at `+`), advancing the cursor to the `+`.
        // The second `@`'s local part may only rewind back to the `+`, so it is `+@.b`, leaving `l@o` before.
        let ns = try nodes(in: "l@o+@.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@o", nil, "+@.b"])
        #expect(ns.compactMap(\.url) == ["mailto:+@.b"])
    }

    @Test("`l@oo+@.b`: the `+` bounds the second local part; before-text `l@oo`")
    func plusBoundsLocalPartTwoChars() throws {
        let ns = try nodes(in: "l@oo+@.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@oo", nil, "+@.b"])
        #expect(ns.compactMap(\.url) == ["mailto:+@.b"])
    }

    @Test("`a@b+c@.d`: the `+` bounds the second local part to `+c`; before-text `a@b`")
    func plusBoundsLocalPartWithTrailingAlnum() throws {
        let ns = try nodes(in: "a@b+c@.d")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@b", nil, "+c@.d"])
        #expect(ns.compactMap(\.url) == ["mailto:+c@.d"])
    }

    // MARK: - Controls that ALREADY MATCH: `.`, `-`, `_`, alnum rewind THROUGH (forward scan continues)

    @Test("`l@o.p@.b`: `.`-followed-by-alnum rewinds through; before-text `l@`")
    func dotRewindsThrough() throws {
        let ns = try nodes(in: "l@o.p@.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@", nil, "o.p@.b"])
        #expect(ns.compactMap(\.url) == ["mailto:o.p@.b"])
    }

    @Test("`l@o-p@.b`: `-` rewinds through; before-text `l@`")
    func hyphenRewindsThrough() throws {
        let ns = try nodes(in: "l@o-p@.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@", nil, "o-p@.b"])
        #expect(ns.compactMap(\.url) == ["mailto:o-p@.b"])
    }

    @Test("`l@o_p@.b`: `_` rewinds through; before-text `l@`")
    func underscoreRewindsThrough() throws {
        let ns = try nodes(in: "l@o_p@.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@", nil, "o_p@.b"])
        #expect(ns.compactMap(\.url) == ["mailto:o_p@.b"])
    }

    @Test("`l@abc@.b`: alphanumerics rewind through; before-text `l@`")
    func alnumRewindsThrough() throws {
        let ns = try nodes(in: "l@abc@.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@", nil, "abc@.b"])
        #expect(ns.compactMap(\.url) == ["mailto:abc@.b"])
    }

    @Test("`l@+@.b`: `+` at the local-part start; nothing before it to keep; before-text `l@`")
    func plusAtStart() throws {
        // The `@` between `l` and `+` stops the backward scan regardless of the floor, so the local part is
        // `+` no matter where the floor sits - a guard that the boundary rule does not over-correct here.
        let ns = try nodes(in: "l@+@.b")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "l@", nil, "+@.b"])
        #expect(ns.compactMap(\.url) == ["mailto:+@.b"])
    }

    @Test("`xy@ab@.c`: an alnum-only first local part rewinds through; before-text `xy@`")
    func alnumFirstLocalPart() throws {
        let ns = try nodes(in: "xy@ab@.c")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "xy@", nil, "ab@.c"])
        #expect(ns.compactMap(\.url) == ["mailto:ab@.c"])
    }

    // MARK: - A `.` NOT immediately followed by an alnum also breaks the forward scan

    @Test("`a@b.+@.c`: a `.`-then-`+` boundary bounds the second local part to `.+`; before-text `a@b`")
    func dotThenPlusBoundary() throws {
        // The first candidate `a@b` breaks at the `.` (it is followed by `+`, not an alnum), advancing the
        // cursor to the `.`. The second `@`'s backward scan rewinds through `+` and `.` only to that cursor,
        // giving local part `.+`, so the link is `.+@.c` with before-text `a@b`. Same class as the `+`
        // cases - a forward-scan break creates the boundary - with the break driven by a boundary `.`.
        let ns = try nodes(in: "a@b.+@.c")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@b", nil, ".+@.c"])
        #expect(ns.compactMap(\.url) == ["mailto:.+@.c"])
    }

    @Test("`a@b..c@.d`: a doubled `.` (first not followed by alnum) bounds the second local part to `..c`")
    func doubledDotBoundary() throws {
        // The first candidate `a@b` breaks at the first `.` of `..` (it is followed by another `.`, not an
        // alnum), advancing the cursor. The second `@`'s backward scan rewinds through `..c` only to that
        // cursor, giving local part `..c` and before-text `a@b`.
        let ns = try nodes(in: "a@b..c@.d")
        #expect(ns.map(\.kind) == [.document, .paragraph, .text, .link, .text])
        #expect(ns.map(\.text) == [nil, nil, "a@b", nil, "..c@.d"])
        #expect(ns.compactMap(\.url) == ["mailto:..c@.d"])
    }
}
