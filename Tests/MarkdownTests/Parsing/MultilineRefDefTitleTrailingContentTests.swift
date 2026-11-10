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
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: [])
    }

    /// The NUL is replaced by U+FFFD (Insecure characters).
    func testNulTitleWithTrailingImage() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"“\u{FFFD}”\"\n   └─ Image source: \"&\"\n      └─ Text \"f\"",
            tree("[f]:&\n\"\u{0}\"![f]"))
    }

    func testAsciiTitleWithTrailingImage() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   ├─ Text \"“x”\"\n   └─ Image source: \"&\"\n      └─ Text \"f\"",
            tree("[f]:&\n\"x\"![f]"))
    }
}
