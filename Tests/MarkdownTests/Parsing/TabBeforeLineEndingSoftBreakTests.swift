/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A tab immediately before a line ending must not produce a hard line break.
///
/// Ground truth is cmark-gfm. A CommonMark hard line break requires two or more trailing SPACES (or a
/// backslash) before the line ending; a trailing tab does not qualify — it yields a soft break. In the
/// minimized fuzzer artifact the third line `*` TAB CR `*` therefore joins with a `SoftBreak`, not a
/// `LineBreak`. The rewrite's flag-off path already matches cmark; its `.cmarkBugCompatibility` path wrongly
/// treated the trailing tab as hard-break whitespace and emitted a `LineBreak`. Spec-correct, so both flag
/// states must use a soft break. Position-free compare surface.
class TabBeforeLineEndingSoftBreakTests: XCTestCase {
    // The minimized artifact: "[" 0xC0 CR " ]:" 0xFF LF "=" LF "*" TAB CR "*"
    private static let bytes: [UInt8] = [
        0x5b, 0xc0, 0x0d, 0x20, 0x5d, 0x3a, 0xff, 0x0a, 0x3d, 0x0a, 0x2a, 0x09, 0x0d, 0x2a,
    ]
    private static let fuzzedBits = ParseOptions(rawValue: UInt(0x09 & 0b11011111))

    private func surface(cmarkBugCompatible: Bool) -> String {
        var options = Self.fuzzedBits
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: String(decoding: Self.bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    func testTrailingTabIsSoftBreak() {
        let expected = "Document\n└─ Paragraph\n   ├─ Text \"=\"\n   ├─ SoftBreak\n   ├─ Text \"*\"\n   ├─ SoftBreak\n   └─ Text \"*\""
        XCTAssertEqual(expected, surface(cmarkBugCompatible: true))
        XCTAssertEqual(expected, surface(cmarkBugCompatible: false))
    }
}
