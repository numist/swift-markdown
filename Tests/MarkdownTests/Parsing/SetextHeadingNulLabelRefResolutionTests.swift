/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// Resolution of a reference link whose text is a setext heading, when the reference definition's label
/// contains a NUL.
///
/// Ground truth is cmark-gfm. A NUL in a label folds to U+FFFD (CommonMark §2.3), so a definition
/// `[a` NUL `]: l` and a reference `[a` NUL `]` share a key and the reference resolves. The rewrite left
/// the reference unresolved (kept as literal text) only when the reference link was the content of a
/// SETEXT heading; ATX headings and paragraphs already resolved, and an ASCII-label setext heading
/// resolved too — so the defect was the NUL-in-definition-label × setext interaction. Resolving is
/// spec-correct, so both flag states resolve. Position-free compare surface.
///
/// Expected strings use explicit `\u{…}` escapes for the text content (U+FFFD, U+0001, U+2019) so an
/// invisible control byte cannot be dropped when authoring the literal.
class SetextHeadingNulLabelRefResolutionTests: XCTestCase {
    private func surface(_ bytes: [UInt8], cmarkBugCompatible: Bool) -> String {
        var options = ParseOptions(rawValue: 0)
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: String(decoding: bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    /// Minimal: definition label `a` NUL, referenced by the same label as an H2 setext heading.
    /// `[` `a` NUL `]` `:` `l` LF `[` `a` NUL `]` LF `-`
    func testNulLabelRefResolvesInSetextHeading() {
        let bytes: [UInt8] = [0x5b, 0x61, 0x00, 0x5d, 0x3a, 0x6c, 0x0a, 0x5b, 0x61, 0x00, 0x5d, 0x0a, 0x2d]
        let expected = "Document\n└─ Heading level: 2\n   └─ Link destination: \"l\"\n      └─ Text \"a\u{FFFD}\""
        XCTAssertEqual(expected, surface(bytes, cmarkBugCompatible: true))
        XCTAssertEqual(expected, surface(bytes, cmarkBugCompatible: false))
    }

    /// The fuzzer artifact: definition and reference labels are byte-different (a `0xFF` run vs a NUL run)
    /// but normalize equal once both the invalid byte and the NULs fold to U+FFFD. The resolved link text
    /// keeps every byte, including the literal U+0001 control character between the smart quote and the
    /// U+FFFD run.
    /// `[` `bar'` U+0001 0xFF NUL NUL `]` `:` `l` LF `[` `bar'` U+0001 NUL NUL NUL `]` LF `-`
    func testFuzzerArtifactResolvesInSetextHeading() {
        let bytes: [UInt8] = [
            0x5b, 0x62, 0x61, 0x72, 0x27, 0x01, 0xff, 0x00, 0x00, 0x5d, 0x3a, 0x6c, 0x0a,
            0x5b, 0x62, 0x61, 0x72, 0x27, 0x01, 0x00, 0x00, 0x00, 0x5d, 0x0a, 0x2d,
        ]
        let expected = "Document\n└─ Heading level: 2\n   └─ Link destination: \"l\"\n      └─ Text \"bar\u{2019}\u{0001}\u{FFFD}\u{FFFD}\u{FFFD}\""
        XCTAssertEqual(expected, surface(bytes, cmarkBugCompatible: true))
        XCTAssertEqual(expected, surface(bytes, cmarkBugCompatible: false))
    }
}
