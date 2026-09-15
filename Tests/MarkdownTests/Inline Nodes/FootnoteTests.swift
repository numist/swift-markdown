/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
@testable import Markdown

class FootnoteTests: XCTestCase {
    func testFootnoteReferenceProperties() {
        let ref = FootnoteReference(label: "a", index: 1)
        XCTAssertEqual(ref.footnoteLabel, "a")
        XCTAssertEqual(ref.footnoteIndex, 1)
    }

    func testFootnoteDefinitionProperties() {
        let def = FootnoteDefinition(label: "a", [Paragraph(Text("note"))])
        XCTAssertEqual(def.footnoteLabel, "a")
        XCTAssertEqual(def.childCount, 1)
    }

    func testFootnoteDump() {
        let doc = Document(
            Paragraph(Text("see "), FootnoteReference(label: "a", index: 1)),
            FootnoteDefinition(label: "a", [Paragraph(Text("note"))])
        )
        let expected = """
        Document
        ├─ Paragraph
        │  ├─ Text "see "
        │  └─ FootnoteReference label: "a" index: 1
        └─ FootnoteDefinition label: "a"
           └─ Paragraph
              └─ Text "note"
        """
        XCTAssertEqual(doc.debugDescription(), expected)
    }
}
