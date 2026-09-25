/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @_spi(Footnotes) @testable import Markdown
import XCTest

/// cmark stops resolving reference links once their cumulative expansion size exceeds its budget.
///
/// Ground truth is cmark-gfm (flag-ON). cmark caps the total size of reference-link expansions at
/// `max(document size, 100000)` bytes (`blocks.c` `max_ref_size`, `map.c` lookup), so after enough uses of a
/// reference with a long destination, later `[bar]` uses stay literal text. With a 2001-byte destination and
/// 60 uses, cmark resolves 49 links. Position-free compare surface.
class ReferenceExpansionBudgetTests: XCTestCase {
    private static let markdown = "[bar]: /" + String(repeating: "a", count: 2000) + "\n\n"
        + Array(repeating: "[bar]", count: 60).joined(separator: " ")

    private func linkCount(cmarkBugCompatible: Bool) -> Int {
        var options: ParseOptions = []
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        let surface = Document(parsing: Self.markdown, options: options).debugDescription(options: [])
        return surface.components(separatedBy: "Link destination:").count - 1
    }

    func testFlagOnStopsResolvingPastBudget() {
        XCTAssertEqual(49, linkCount(cmarkBugCompatible: true))
    }

    func testUnderBudgetAllResolve() {
        let markdown = "[bar]: /" + String(repeating: "a", count: 2000) + "\n\n"
            + Array(repeating: "[bar]", count: 40).joined(separator: " ")
        var options: ParseOptions = []
        options.insert(.cmarkBugCompatibility)
        let surface = Document(parsing: markdown, options: options).debugDescription(options: [])
        XCTAssertEqual(40, surface.components(separatedBy: "Link destination:").count - 1)
    }

    // MARK: - Boundary probes. Expected counts derived from cmark's source: `blocks.c`
    // `finalize_document` sets the budget to `max(total_size, 100000)`, where `total_size` is the
    // byte count fed to `S_parser_feed`; `map.c` `cmark_map_lookup` rejects a found reference once
    // `r->size > max_ref_size - ref_size`, else charges `ref_size += r->size`; `references.c`
    // `cmark_reference_create` sets `r->size = url.len + title.len` of the cleaned (decoded) strings.

    private static func definition(_ label: String, destinationBytes: Int) -> String {
        "[\(label)]: /" + String(repeating: "a", count: destinationBytes - 1) + "\n\n"
    }

    private static func uses(_ use: String, _ count: Int) -> String {
        Array(repeating: use, count: count).joined(separator: " ")
    }

    private func surface(_ markdown: String, cmarkBugCompatible: Bool = true, options extra: ParseOptions = []) -> String {
        var options = extra
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    private func count(_ needle: String, in surface: String) -> Int {
        surface.components(separatedBy: needle).count - 1
    }

    private func links(_ markdown: String, cmarkBugCompatible: Bool = true, options: ParseOptions = []) -> Int {
        count("Link destination:", in: surface(markdown, cmarkBugCompatible: cmarkBugCompatible, options: options))
    }

    /// Flag-OFF is spec-correct: CommonMark has no expansion budget, so every use resolves.
    func testFlagOffResolvesEveryUse() {
        XCTAssertEqual(60, linkCount(cmarkBugCompatible: false))
    }

    /// 50 uses of a 2000-byte reference spend exactly 100000 bytes, which the `>` test still admits.
    func testExactlyAtBudgetResolves() {
        let markdown = Self.definition("bar", destinationBytes: 2000) + Self.uses("[bar]", 50)
        XCTAssertEqual(50, links(markdown))
    }

    /// The 51st use of a 2000-byte reference would spend 102000 bytes; it stays literal.
    func testOneUsePastBudgetStaysLiteral() {
        let markdown = Self.definition("bar", destinationBytes: 2000) + Self.uses("[bar]", 51)
        XCTAssertEqual(50, links(markdown))
    }

    /// After 49 uses of a 2000-byte `[a]` (98000 bytes), a 2001-byte `[b]` is one byte over the
    /// remaining 2000 and stays literal without consuming budget, so a following `[a]` still fits.
    func testRejectedLookupConsumesNothingAndLabelsShareBudget() {
        let markdown = Self.definition("a", destinationBytes: 2000) + Self.definition("b", destinationBytes: 2001)
            + Self.uses("[a]", 49) + " [b] [a] [a]"
        let result = surface(markdown)
        XCTAssertEqual(50, count("Link destination:", in: result))
        XCTAssertEqual(0, count("Link destination: \"/" + String(repeating: "a", count: 2000) + "\"", in: result))
    }

    /// A full reference `[a][b]` whose `b` is over budget stays literal rather than falling back to
    /// the `[a]` shortcut (cmark looks up only the full label), so the budget left after it still admits
    /// one more 2000-byte `[a]`.
    func testOverBudgetFullReferenceDoesNotFallBackToShortcut() {
        let markdown = Self.definition("a", destinationBytes: 2000) + Self.definition("b", destinationBytes: 2001)
            + Self.uses("[a]", 49) + " [a][b] [a] [a]"
        let result = surface(markdown)
        XCTAssertEqual(50, count("Link destination:", in: result))
        XCTAssertEqual(1, count("[a][b]", in: result))
    }

    /// Full `[t][bar]` and collapsed `[bar][]` forms are charged exactly like the shortcut form.
    func testFullAndCollapsedFormsShareBudget() {
        let markdown = Self.definition("bar", destinationBytes: 2001)
            + Self.uses("[bar]", 20) + " " + Self.uses("[bar][]", 20) + " " + Self.uses("[t][bar]", 20)
        XCTAssertEqual(49, links(markdown))
    }

    /// Image references resolve through the same lookup, so they draw on the same budget as links.
    func testImageReferencesShareBudget() {
        let images = Self.definition("bar", destinationBytes: 2001) + Self.uses("![bar]", 60)
        XCTAssertEqual(49, count("Image source:", in: surface(images)))
        let mixed = Self.definition("bar", destinationBytes: 2001) + Self.uses("[bar] ![bar]", 30)
        let result = surface(mixed)
        XCTAssertEqual(49, count("Link destination:", in: result) + count("Image source:", in: result))
    }

    /// A reference's cost is its destination plus its title (without the quotes): 1000 + 1000 bytes.
    func testTitleCountsTowardReferenceSize() {
        let markdown = "[bar]: /" + String(repeating: "a", count: 999) + " \"" + String(repeating: "t", count: 1000) + "\"\n\n"
            + Self.uses("[bar]", 51)
        XCTAssertEqual(50, links(markdown))
    }

    /// The cost is the decoded destination: 1999 `&amp;` entities decode to 1999 bytes, so with the
    /// leading `/` each use costs 2000 bytes (not the 9996 source bytes).
    func testEntitiesInDestinationCountDecodedBytes() {
        let markdown = "[bar]: /" + String(repeating: "&amp;", count: 1999) + "\n\n" + Self.uses("[bar]", 51)
        XCTAssertEqual(50, links(markdown))
    }

    /// Backslash escapes and entities in the title count after decoding: 500 `\\*` (500 bytes) plus
    /// 250 `&eacute;` (500 bytes) with a 1000-byte destination cost 2000 bytes per use.
    func testEscapesAndEntitiesInTitleCountDecodedBytes() {
        let title = String(repeating: "\\*", count: 500) + String(repeating: "&eacute;", count: 250)
        let markdown = "[bar]: /" + String(repeating: "a", count: 999) + " \"" + title + "\"\n\n"
            + Self.uses("[bar]", 51)
        XCTAssertEqual(50, links(markdown))
    }

    /// A NUL in the destination is stored as the 3-byte U+FFFD, so `/` + 666 NULs + `a` costs 2000 bytes.
    func testNULInDestinationCountsReplacementBytes() {
        let markdown = "[bar]: /" + String(repeating: "\u{0}", count: 666) + "a\n\n" + Self.uses("[bar]", 51)
        XCTAssertEqual(50, links(markdown))
    }

    /// Above 100000 source bytes the budget is the document's UTF-8 byte count. With 150 uses of a
    /// 2001-byte reference, a 202101-byte document (101 × 2001) admits 101 uses; one byte less admits 100.
    func testLargeDocumentBudgetIsSourceByteCount() {
        // Everything but the filler paragraph: definition (2010) + uses (150 × 5 + 149) + filler's "\n\n".
        let rest = Self.definition("bar", destinationBytes: 2001) + Self.uses("[bar]", 150)
        let fillerBytes = 101 * 2001 - rest.utf8.count - 2
        XCTAssertEqual(199190, fillerBytes)
        // Two-byte `é` filler, so a character count would undershoot the byte count.
        let exact = String(repeating: "\u{E9}", count: fillerBytes / 2) + "\n\n" + rest
        XCTAssertEqual(202101, exact.utf8.count)
        XCTAssertEqual(101, links(exact))
        let oneShort = String(repeating: "\u{E9}", count: fillerBytes / 2 - 1) + "x\n\n" + rest
        XCTAssertEqual(202100, oneShort.utf8.count)
        XCTAssertEqual(100, links(oneShort))
    }

    /// cmark's attribute bracket `^[t][bar]` looks `bar` up in the same refmap: a link reference found
    /// there is charged even though the attribute then fails. 10 such lookups spend 20010 bytes,
    /// leaving 79990 for `floor(79990 / 2001)` = 39 links.
    func testAttributeLookupOfLinkReferenceIsCharged() {
        let markdown = Self.definition("bar", destinationBytes: 2001) + Self.uses("^[t][bar]", 10) + " " + Self.uses("[bar]", 60)
        let result = surface(markdown)
        XCTAssertEqual(0, count("InlineAttributes", in: result))
        XCTAssertEqual(39, count("Link destination:", in: result))
    }

    /// cmark's attribute bracket runs the `[label]` lookup even after its inline `(attrs)` form matched,
    /// so `^[t](a)[bar]` still charges `bar` (and keeps its inline attributes): 39 links remain, as above.
    func testAttributeLookupAfterInlineFormIsCharged() {
        let markdown = Self.definition("bar", destinationBytes: 2001) + Self.uses("^[t](a)[bar]", 10) + " " + Self.uses("[bar]", 60)
        let result = surface(markdown)
        XCTAssertEqual(10, count("InlineAttributes", in: result))
        XCTAssertEqual(39, count("Link destination:", in: result))
    }

    /// Footnote references resolve against a separate, unbudgeted map, so they spend nothing.
    func testFootnoteReferencesDoNotSpendBudget() {
        let markdown = "[^n]: note\n\n" + Self.definition("bar", destinationBytes: 2001)
            + Self.uses("[^n]", 100) + " " + Self.uses("[bar]", 60)
        let result = surface(markdown, options: .footnotes)
        XCTAssertEqual(100, count("FootnoteReference", in: result))
        XCTAssertEqual(49, count("Link destination:", in: result))
    }

    /// The budget is spent in document order across blocks: a heading's 30 uses resolve first, leaving
    /// 19 for the following paragraph.
    func testBudgetIsSpentInDocumentOrder() {
        let markdown = Self.definition("bar", destinationBytes: 2001) + "# " + Self.uses("[bar]", 30) + "\n\n"
            + Self.uses("[bar]", 30)
        let result = surface(markdown)
        let paragraph = result.components(separatedBy: "Paragraph").last!
        XCTAssertEqual(49, count("Link destination:", in: result))
        XCTAssertEqual(19, count("Link destination:", in: paragraph))
    }
}
