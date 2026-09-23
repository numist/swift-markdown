/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A `[^^]:` footnote-definition-shaped line (label `^`) following a paragraph that already contains a
/// `[^^]` footnote-reference-shaped span must not register a footnote definition.
///
/// Ground truth is cmark-gfm. For `[^ [^^]]` newline `[^^]:` cmark emits only `Paragraph` `Text
/// "[^ [^^]]"` — it registers NO footnote definition (and resolves no reference). The rewrite (flag-on)
/// kept the paragraph literal but still registered a spurious `FootnoteDefinition label: "^"`. Neither the
/// bare `[^^]:` line on its own nor a def with content reproduces it — the preceding `[^ [^^]]` paragraph
/// is required. This asserts the flag-on (fuzzer) surface: it must match cmark's no-definition output.
class FootnoteDefAfterCaretRefParagraphTests: XCTestCase {
    // "[^ [^^]]" LF "[^^]:"
    private static let bytes: [UInt8] = [
        0x5b, 0x5e, 0x20, 0x5b, 0x5e, 0x5e, 0x5d, 0x5d, 0x0a, 0x5b, 0x5e, 0x5e, 0x5d, 0x3a,
    ]
    private static let fuzzedBits = ParseOptions(rawValue: UInt(0xf0 & 0b11011111))

    func testFlagOnRegistersNoFootnoteDefinition() {
        var options = Self.fuzzedBits
        options.insert(.cmarkBugCompatibility)
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Text \"[^ [^^]]\"",
            Document(parsing: String(decoding: Self.bytes, as: UTF8.self), options: options)
                .debugDescription(options: []))
    }
}
