/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// No further non-whitespace characters may follow a link reference definition's title on its line (Link
/// reference definitions). In `[f]:&` / `"title"![f]`, the definition ends at its destination, the second
/// line is paragraph text, and its `![f]` is an image without a title.
class MultilineRefDefTitleTrailingContentTests: XCTestCase {
    private func surface(_ bytes: [UInt8]) -> String {
        let options = ParseOptions(rawValue: 0)
        return Document(parsing: String(decoding: bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    /// The NUL is replaced by U+FFFD (Insecure characters).
    /// `[` `f` `]` `:` `&` LF `"` NUL `"` `!` `[` `f` `]`
    func testNulTitleWithTrailingImage() {
        let bytes: [UInt8] = [0x5b, 0x66, 0x5d, 0x3a, 0x26, 0x0a, 0x22, 0x00, 0x22, 0x21, 0x5b, 0x66, 0x5d]
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"“�”\"\n   └─ Image source: \"&\"\n      └─ Text \"f\"",
            surface(bytes))
    }

    func testAsciiTitleWithTrailingImage() {
        let bytes: [UInt8] = [0x5b, 0x66, 0x5d, 0x3a, 0x26, 0x0a, 0x22, 0x78, 0x22, 0x21, 0x5b, 0x66, 0x5d]
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"“x”\"\n   └─ Image source: \"&\"\n      └─ Text \"f\"",
            surface(bytes))
    }
}
