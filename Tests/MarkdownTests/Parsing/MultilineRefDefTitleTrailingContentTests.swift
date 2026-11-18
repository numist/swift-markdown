/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

// Non-whitespace after the title on its line keeps the title out of the definition (Link reference definitions), so the
// definition ends at its destination and the second line is paragraph text.
class MultilineRefDefTitleTrailingContentTests: XCTestCase {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: [])
    }

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
