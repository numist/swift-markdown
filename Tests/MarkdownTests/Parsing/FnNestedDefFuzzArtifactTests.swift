/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @_spi(InlineOnly) @testable import Markdown
import XCTest

/// Minimized differential-fuzzer artifact; the expected surface is the cmark-gfm reference's output bytes.
/// Input is `[markdown …][option byte]`, split as the fuzzer does. Position-free compare surface.
class FnNestedDefFuzzArtifactTests: XCTestCase {
    func testFuzzedArtifact() {
        let (markdown, options) = FuzzRegressionTests.splitInput([91, 94, 98, 93, 10, 91, 94, 98, 93, 58, 91, 94, 98, 93, 58, 65, 128])!
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ FootnoteReference label: \"b\" index: 1\n└─ FootnoteDefinition label: \"b\"\n   └─ Paragraph\n      └─ Text \"A\"", Document(parsing: markdown, options: options.union(.cmarkBugCompatibility)).debugDescription(options: []))
        XCTAssertEqual("Document\n├─ Paragraph\n│  └─ FootnoteReference label: \"b\" index: 1\n└─ FootnoteDefinition label: \"b\"\n   └─ Paragraph\n      └─ Text \"A\"", Document(parsing: markdown, options: options).debugDescription(options: []))
    }
}
