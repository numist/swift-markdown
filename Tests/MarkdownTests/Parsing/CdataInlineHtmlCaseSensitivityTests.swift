/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// A CDATA section begins with the string `<![CDATA[` (Raw HTML), so a keyword in any other case is text. The leading
/// `-` keeps the line from starting an HTML block.
class CdataInlineHtmlCaseSensitivityTests: XCTestCase {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: [])
    }

    func testMixedCaseKeywordIsText() {
        XCTAssertEqual(
            "Document\n└─ Paragraph\n   └─ Text \"-<![CDaTA[]]>\"",
            tree("-<![CDaTA[]]>"))
    }

    func testUppercaseKeywordIsInlineHtml() {
        let expected = "Document\n└─ Paragraph\n   ├─ Text \"-\"\n   └─ InlineHTML <![CDATA[]]>"
        XCTAssertEqual(expected, tree("-<![CDATA[]]>"))
    }
}
