/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// A line tabulation between the list marker and a task list item marker is initial whitespace of the
/// item's paragraph, which is removed (Paragraphs), so the paragraph begins with the task list item marker
/// (Task list items (extension)).
class TaskListCheckboxVerticalTabGapTests: XCTestCase {
    private static let options: ParseOptions = [.disableSmartOpts, .parseMinimalDoxygen, .disableSourcePosOpts]

    private func surface() -> String {
        Document(parsing: "- \u{B}[x] \n`", options: Self.options).debugDescription(options: [])
    }

    func testCheckboxRecognizedPastVerticalTabGap() {
        let expected = "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         └─ Text \"`\""
        XCTAssertEqual(expected, surface())
    }
}
