/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// Minimized differential-fuzzer artifact.
/// Input is `[markdown …][option byte]`, split as the fuzzer does. Position-free compare surface.
class TableWsHeaderCellFuzzArtifactTests: XCTestCase {
    /// Flag-off (shipped) strips a lazy continuation line's leading whitespace like any paragraph line's
    /// (CommonMark paragraphs), so the header is a lone `|` and no table forms, where cmark keeps the spaces
    /// and opens a table headed by a whitespace cell.
    func testLazyTwoSpaceHeaderFlagOff() {
        let (markdown, options) = DocumentRegressionTests.splitInput([62, 120, 10, 32, 32, 124, 10, 62, 45, 124, 10])!
        XCTAssertEqual("Document\n└─ BlockQuote\n   └─ Paragraph\n      ├─ Text \"x\"\n      ├─ SoftBreak\n      ├─ Text \"|\"\n      ├─ SoftBreak\n      └─ Text \"-|\"", Document(parsing: markdown, options: options).debugDescription(options: []))
    }
}
