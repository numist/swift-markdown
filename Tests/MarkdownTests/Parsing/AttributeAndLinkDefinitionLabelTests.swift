/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// Link reference definitions and inline attribute definitions have separate labels, so a definition of one
/// kind never hides a same-label definition of the other, whatever their order.
class AttributeAndLinkDefinitionLabelTests: XCTestCase {
    func testInlineFormAlongsideBothDefinitionKinds() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ InlineAttributes attributes: `b`\n      └─ Text \"t\"", tree("[foo]: /u\n^[foo]: attrs\n\n^[t](b)"))
    }

    /// Inline attributes have no collapsed or shortcut reference form: an empty `[]` label never resolves,
    /// and a bare `^[foo]` never looks up its content.
    func testNoCollapsedOrShortcutForm() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"^[foo][]\"", tree("[foo]: /u\n^[foo]: attrs\n\n^[foo][]"))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"^[foo]\"", tree("[foo]: /u\n^[foo]: attrs\n\n^[foo]"))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"^[foo][]\"", tree("^[foo]: attrs\n\n^[foo][]"))
    }


    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: [])
    }

    func testAttributeDefinitionAfterLinkDefinitionResolves() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Link destination: \"/u\"\n   │  └─ Text \"foo\"\n   ├─ Text \" \"\n   └─ InlineAttributes attributes: `attrs`\n      └─ Text \"t\"", tree("[foo]: /u\n^[foo]: attrs\n\n[foo] ^[t][foo]"))
    }

    func testLinkDefinitionAfterAttributeDefinitionResolves() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ InlineAttributes attributes: `attrs`\n   │  └─ Text \"t\"\n   ├─ Text \" \"\n   └─ Link destination: \"/u\"\n      └─ Text \"foo\"", tree("^[foo]: attrs\n[foo]: /u\n\n^[t][foo] [foo]"))
    }

    func testAttributeDefinitionNotShadowedByEarlierLinkDefinition() {
        let attributed = "Document\n└─ Paragraph\n   └─ InlineAttributes attributes: `attrs`\n      └─ Text \"t\""
        XCTAssertEqual(attributed, tree("[foo]: /u\n^[foo]: attrs\n\n^[t][foo]"))
        XCTAssertEqual(attributed, tree("[foo]: /u\n\n^[foo]: attrs\n\n^[t][foo]"))
        XCTAssertEqual(attributed, tree("[FOO]: /u\n^[foo]: attrs\n\n^[t][Foo]"))
        XCTAssertEqual("Document\n├─ BlockQuote\n└─ Paragraph\n   └─ InlineAttributes attributes: `attrs`\n      └─ Text \"t\"", tree("[foo]: /u\n\n> ^[foo]: attrs\n\n^[t][foo]"))
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Link destination: \"/u\"\n   │  └─ Text \"foo\"\n   ├─ Text \" \"\n   ├─ InlineAttributes attributes: `attrs`\n   │  └─ Text \"t\"\n   └─ Text \" x\"", tree("[foo]: /u\n^[foo]: attrs\n\n[foo] ^[t][foo] x"))
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ InlineAttributes attributes: `attrs`\n   │  └─ Text \"t\"\n   └─ Link destination: \"/u\"\n      └─ Text \"foo\"", tree("[foo]: /u\n^[foo]: attrs\n\n^[t][foo][foo]"))
    }

    /// The inline `(attributes)` form completes the inline attribute, so the label after it is a link reference.
    func testLabelAfterInlineAttributesIsLink() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ InlineAttributes attributes: `b`\n   │  └─ Text \"t\"\n   └─ Link destination: \"/u\"\n      └─ Text \"foo\"", tree("[foo]: /u\n^[foo]: attrs\n\n^[t](b)[foo]"))
    }

    func testLinkDefinitionInLaterParagraphResolves() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Link destination: \"/u\"\n      └─ Text \"foo\"", tree("^[foo]: attrs\n\n[foo]: /u\n\n[foo]"))
    }
}
