/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// Block structure for a multiline link reference definition whose title is on a continuation line that
/// also carries trailing content (`[f]:dest` newline `"title"![f]`), where the trailing `![f]` resolves
/// against the definition.
///
/// Ground truth is cmark-gfm. cmark-gfm keeps the continuation-line title on the definition even though
/// non-whitespace (`![f]`) follows it on that line, so the image resolves WITH the title. That violates the
/// CommonMark rule that no further character may follow a title (spec example 209; and cmark's own
/// single-line behavior drops the title when content trails it). So flag-on reproduces cmark's quirk (the
/// image keeps the title); flag-off stays spec-correct — the title is dropped, `"title"` becomes paragraph
/// text, and the image has no title. Position-free compare surface.
class MultilineRefDefTitleTrailingContentTests: XCTestCase {
    private func surface(_ bytes: [UInt8], cmarkBugCompatible: Bool) -> String {
        var options = ParseOptions(rawValue: 0)
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: String(decoding: bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    /// The fuzzer artifact: a NUL-only title (materialized to U+FFFD) on the continuation line.
    /// `[` `f` `]` `:` `&` LF `"` NUL `"` `!` `[` `f` `]`
    func testNulTitleWithTrailingImage() {
        let bytes: [UInt8] = [0x5b, 0x66, 0x5d, 0x3a, 0x26, 0x0a, 0x22, 0x00, 0x22, 0x21, 0x5b, 0x66, 0x5d]
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"“�”\"\n   └─ Image source: \"&\" title: \"�\"\n      └─ Text \"f\"",
            surface(bytes, cmarkBugCompatible: true))
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"“�”\"\n   └─ Image source: \"&\"\n      └─ Text \"f\"",
            surface(bytes, cmarkBugCompatible: false))
    }

    /// The same shape with an ordinary ASCII title, isolating the multiline-trailing-content trigger from
    /// the NUL→U+FFFD replacement.
    func testAsciiTitleWithTrailingImage() {
        let bytes: [UInt8] = [0x5b, 0x66, 0x5d, 0x3a, 0x26, 0x0a, 0x22, 0x78, 0x22, 0x21, 0x5b, 0x66, 0x5d]
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"“x”\"\n   └─ Image source: \"&\" title: \"x\"\n      └─ Text \"f\"",
            surface(bytes, cmarkBugCompatible: true))
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"“x”\"\n   └─ Image source: \"&\"\n      └─ Text \"f\"",
            surface(bytes, cmarkBugCompatible: false))
    }
}
