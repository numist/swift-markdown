/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @_spi(InlineOnly) @testable import Markdown
import XCTest

/// A GFM extended autolink whose host begins with a multi-byte punctuation or whitespace character.
/// Expected surfaces are the cmark-gfm reference's output bytes; inputs are `[markdown …][option byte]`,
/// split as the fuzzer does.
class AutolinkHostLeadingPunctuationTests: XCTestCase {
    private func surface(_ bytes: [UInt8], cmarkBugCompatible: Bool = true) -> String {
        var (markdown, options) = FuzzRegressionTests.splitInput(bytes)!
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: markdown, options: options).debugDescription(options: [])
    }

    func testCase0() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"http://«\"", surface([104, 116, 116, 112, 58, 47, 47, 194, 171, 66]))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"http://«\"", surface([104, 116, 116, 112, 58, 47, 47, 194, 171, 66], cmarkBugCompatible: false))
    }

    func testCase1() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"https://«\"", surface([104, 116, 116, 112, 115, 58, 47, 47, 194, 171, 68]))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"https://«\"", surface([104, 116, 116, 112, 115, 58, 47, 47, 194, 171, 68], cmarkBugCompatible: false))
    }

    func testCase2() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"ftp://«)\"", surface([102, 116, 112, 58, 47, 47, 194, 171, 41, 68]))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"ftp://«)\"", surface([102, 116, 112, 58, 47, 47, 194, 171, 41, 68], cmarkBugCompatible: false))
    }

    func testCase3() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"x http://«.\"", surface([120, 32, 104, 116, 116, 112, 58, 47, 47, 194, 171, 46, 68]))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"x http://«.\"", surface([120, 32, 104, 116, 116, 112, 58, 47, 47, 194, 171, 46, 68], cmarkBugCompatible: false))
    }

    func testCase4() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"HTTP://«*\"", surface([72, 84, 84, 80, 58, 47, 47, 194, 171, 42, 68]))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"HTTP://«*\"", surface([72, 84, 84, 80, 58, 47, 47, 194, 171, 42, 68], cmarkBugCompatible: false))
    }

    func testCase5() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Link destination: \"http://www.«\"\n      └─ Text \"www.«\"", surface([119, 119, 119, 46, 194, 171, 68]))
    }

    func testCase6() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"http://«a.b\"", surface([104, 116, 116, 112, 58, 47, 47, 194, 171, 97, 46, 98, 68]))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"http://«a.b\"", surface([104, 116, 116, 112, 58, 47, 47, 194, 171, 97, 46, 98, 68], cmarkBugCompatible: false))
    }

    func testCase7() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"\"\n   └─ Link destination: \"http://a.«\"\n      └─ Text \"http://a.«\"", surface([104, 116, 116, 112, 58, 47, 47, 97, 46, 194, 171, 68]))
    }

    func testCase8() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"\"\n   └─ Link destination: \"http://é\"\n      └─ Text \"http://é\"", surface([104, 116, 116, 112, 58, 47, 47, 195, 169, 68]))
    }

    func testCase9() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"http://¡x\"", surface([104, 116, 116, 112, 58, 47, 47, 194, 161, 120, 68]))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"http://¡x\"", surface([104, 116, 116, 112, 58, 47, 47, 194, 161, 120, 68], cmarkBugCompatible: false))
    }

    func testCase10() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"http://—x\"", surface([104, 116, 116, 112, 58, 47, 47, 226, 128, 148, 120, 68]))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"http://—x\"", surface([104, 116, 116, 112, 58, 47, 47, 226, 128, 148, 120, 68], cmarkBugCompatible: false))
    }

    func testCase11() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"http://“x\"", surface([104, 116, 116, 112, 58, 47, 47, 226, 128, 156, 120, 68]))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"http://“x\"", surface([104, 116, 116, 112, 58, 47, 47, 226, 128, 156, 120, 68], cmarkBugCompatible: false))
    }

    // MARK: - Category probes
    //
    // cmark-gfm's `sd_autolink_issafe` runs `is_valid_hostchar` on the first host scalar after `://`: it
    // decodes the scalar (`cmark_utf8proc_iterate`) and rejects it if `cmark_utf8proc_is_space` or
    // `cmark_utf8proc_is_punctuation` (the P[cdefios] table) holds. Symbols, letters, marks and emoji are not
    // in either table, so they are valid. Past the first scalar, `check_domain` breaks at the first multi-byte
    // scalar either way (punctuation at its lead byte, otherwise at the continuation byte), so a non-ASCII
    // scalar at a label start or end never changes the outcome.

    private func probeSurface(_ markdown: String, options: ParseOptions = .cmarkBugCompatibility) -> String {
        let (markdown, parsed) = FuzzRegressionTests.splitInput(Array(markdown.utf8) + [0x44])!
        return Document(parsing: markdown, options: parsed.union(options)).debugDescription(options: [])
    }

    private func text(_ literal: String) -> String {
        "Document\n└─ Paragraph\n   └─ Text \"\(literal)\""
    }

    private func schemeLink(_ url: String) -> String {
        "Document\n└─ Paragraph\n   ├─ Text \"\"\n   └─ Link destination: \"\(url)\"\n      └─ Text \"\(url)\""
    }

    private func wwwLink(_ host: String) -> String {
        "Document\n└─ Paragraph\n   └─ Link destination: \"http://\(host)\"\n      └─ Text \"\(host)\""
    }

    /// Punctuation (P[cdefios]) and Unicode whitespace (Zs) at the host start: never a link.
    func testHostStartPunctuationOrSpaceIsNotALink() {
        let rejected: [(category: String, scalar: String)] = [
            ("Pd hyphen", "\u{2010}"), ("Pd em dash", "\u{2014}"),
            ("Ps fullwidth paren", "\u{FF08}"), ("Pe fullwidth paren", "\u{FF09}"), ("Ps corner bracket", "\u{300C}"),
            ("Pi left quote", "\u{201C}"), ("Pf right quote", "\u{201D}"), ("Pi single guillemet", "\u{2039}"), ("Pf guillemet", "\u{00BB}"),
            ("Po inverted question", "\u{00BF}"), ("Po ideographic full stop", "\u{3002}"), ("Po double exclamation", "\u{203C}"),
            ("Pc undertie", "\u{203F}"), ("Po Aegean word separator (4-byte)", "\u{10100}"),
            ("Zs no-break space", "\u{00A0}"), ("Zs ideographic space", "\u{3000}"),
        ]
        for (category, scalar) in rejected {
            XCTAssertEqual(text("http://\(scalar)a.b"), probeSurface("http://\(scalar)a.b"), category)
            XCTAssertEqual(text("http://\(scalar)a.b"), probeSurface("http://\(scalar)a.b", options: []), category)
        }
    }

    /// Symbols, letters, combining marks and emoji at the host start: a link.
    func testHostStartNonPunctuationIsALink() {
        let accepted: [(category: String, scalar: String)] = [
            ("Sm multiplication", "\u{00D7}"), ("Sm infinity", "\u{221E}"),
            ("Sc euro", "\u{20AC}"), ("Sc pound", "\u{00A3}"),
            ("So copyright", "\u{00A9}"), ("So degree", "\u{00B0}"),
            ("emoji", "\u{1F600}"), ("CJK letter", "\u{4E2D}"), ("combining acute", "\u{0301}"),
        ]
        for (category, scalar) in accepted {
            XCTAssertEqual(schemeLink("http://\(scalar)a.b"), probeSurface("http://\(scalar)a.b"), category)
        }
    }

    /// Any non-ASCII scalar at a label start or end, in either autolink form: a link.
    func testLabelBoundaryScalarIsALink() {
        let scalars: [(category: String, scalar: String)] = [
            ("Pd", "\u{2014}"), ("Ps", "\u{FF08}"), ("Pi", "\u{201C}"), ("Po", "\u{00A1}"), ("Zs", "\u{00A0}"),
            ("Sm", "\u{00D7}"), ("Sc", "\u{20AC}"), ("So", "\u{00A9}"),
            ("emoji", "\u{1F600}"), ("CJK", "\u{4E2D}"), ("Mn", "\u{0301}"),
        ]
        for (category, scalar) in scalars {
            XCTAssertEqual(schemeLink("http://a.\(scalar)b"), probeSurface("http://a.\(scalar)b"), "scheme label start \(category)")
            XCTAssertEqual(schemeLink("http://a\(scalar).b"), probeSurface("http://a\(scalar).b"), "scheme label end \(category)")
            XCTAssertEqual(wwwLink("www.\(scalar)a"), probeSurface("www.\(scalar)a"), "www label start \(category)")
            XCTAssertEqual(wwwLink("www.a\(scalar).b"), probeSurface("www.a\(scalar).b"), "www label end \(category)")
        }
    }

    /// The rejection is spec-correct (punctuation is not a valid domain character), so the shipped flag-OFF
    /// parser agrees.
    func testHostStartPunctuationIsNotALinkWithoutBugCompatibility() {
        for scalar in ["\u{2014}", "\u{00AB}", "\u{00A1}", "\u{00A0}"] {
            XCTAssertEqual(text("http://\(scalar)a.b"), probeSurface("http://\(scalar)a.b", options: []), scalar)
        }
    }

    /// A letter is a valid domain character at a label's start or end, so a host holding one links; flag-off the
    /// scheme autolink is the paragraph's only child, whereas cmark-gfm leaves an empty text node where it
    /// rewinds over the scheme.
    func testLetterInHostIsALinkWithoutBugCompatibility() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Link destination: \"http://\u{4E2D}a.b\"\n      └─ Text \"http://\u{4E2D}a.b\"", probeSurface("http://\u{4E2D}a.b", options: []))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Link destination: \"http://a.\u{4E2D}b\"\n      └─ Text \"http://a.\u{4E2D}b\"", probeSurface("http://a.\u{4E2D}b", options: []))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Link destination: \"http://a\u{4E2D}.b\"\n      └─ Text \"http://a\u{4E2D}.b\"", probeSurface("http://a\u{4E2D}.b", options: []))
        XCTAssertEqual(wwwLink("www.a\u{4E2D}.b"), probeSurface("www.a\u{4E2D}.b", options: []))
    }

}
