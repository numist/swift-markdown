/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

class LazyUnclosedProcessingInstructionTests: XCTestCase {
    /// `<?` without a closing `?>` is not a processing instruction (Raw HTML), and `[x]` that doesn't begin
    /// the item's paragraph is not a task list item marker (Task list items (extension)), so both are text.
    func testUnclosedProcessingInstructionAndLateCheckboxAreText() {
        let (markdown, options) = DocumentRegressionTests.splitInput([45, 32, 62, 250, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 0])!
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"\u{fffd}<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", Document(parsing: markdown, options: options).debugDescription(options: []))
    }
}
