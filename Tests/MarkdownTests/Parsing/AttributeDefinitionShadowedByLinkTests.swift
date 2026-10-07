/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// Flag-OFF the two definition kinds are separate namespaces, so both resolve regardless of order.
/// Position-free compare surface.
class AttributeDefinitionShadowedByLinkTests: XCTestCase {
    func testInlineAttributesAfterShadowedDefinition() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ InlineAttributes attributes: `b`\n      └─ Text \"t\"", surfaceSpec("[foo]: /u\n^[foo]: attrs\n\n^[t](b)"))
    }

    /// The attributes grammar has no collapsed or shortcut reference form: an empty `[]` label never resolves, and a bare `^[foo]` never looks up its content. A label that resolves to no attribute definition is text in the shipped parser.
    func testNoCollapsedOrShortcutForm() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"^[foo][]\"", surfaceSpec("[foo]: /u\n^[foo]: attrs\n\n^[foo][]"))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"^[foo]\"", surfaceSpec("[foo]: /u\n^[foo]: attrs\n\n^[foo]"))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"^[foo][]\"", surfaceSpec("^[foo]: attrs\n\n^[foo][]"))
    }

    // MARK: - Flag-OFF: link and attribute definitions are separate namespaces

    private func surfaceSpec(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: [])
    }

    func testFlagOffAttributeDefinitionAfterLinkDefinitionResolves() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Link destination: \"/u\"\n   │  └─ Text \"foo\"\n   ├─ Text \" \"\n   └─ InlineAttributes attributes: `attrs`\n      └─ Text \"t\"", surfaceSpec("[foo]: /u\n^[foo]: attrs\n\n[foo] ^[t][foo]"))
    }

    func testFlagOffLinkDefinitionAfterAttributeDefinitionResolves() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ InlineAttributes attributes: `attrs`\n   │  └─ Text \"t\"\n   ├─ Text \" \"\n   └─ Link destination: \"/u\"\n      └─ Text \"foo\"", surfaceSpec("^[foo]: attrs\n[foo]: /u\n\n^[t][foo] [foo]"))
    }

    /// An attribute definition resolves even after a same-label link definition, whereas cmark-gfm's shared refmap lets the earlier link definition shadow it and leaves `^[t]` literal.
    func testFlagOffAttributeDefinitionNotShadowedByEarlierLinkDefinition() {
        let attributed = "Document\n└─ Paragraph\n   └─ InlineAttributes attributes: `attrs`\n      └─ Text \"t\""
        XCTAssertEqual(attributed, surfaceSpec("[foo]: /u\n^[foo]: attrs\n\n^[t][foo]"))
        XCTAssertEqual(attributed, surfaceSpec("[foo]: /u\n\n^[foo]: attrs\n\n^[t][foo]"))
        XCTAssertEqual(attributed, surfaceSpec("[FOO]: /u\n^[foo]: attrs\n\n^[t][Foo]"))
        XCTAssertEqual("Document\n├─ BlockQuote\n└─ Paragraph\n   └─ InlineAttributes attributes: `attrs`\n      └─ Text \"t\"", surfaceSpec("[foo]: /u\n\n> ^[foo]: attrs\n\n^[t][foo]"))
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Link destination: \"/u\"\n   │  └─ Text \"foo\"\n   ├─ Text \" \"\n   ├─ InlineAttributes attributes: `attrs`\n   │  └─ Text \"t\"\n   └─ Text \" x\"", surfaceSpec("[foo]: /u\n^[foo]: attrs\n\n[foo] ^[t][foo] x"))
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ InlineAttributes attributes: `attrs`\n   │  └─ Text \"t\"\n   └─ Link destination: \"/u\"\n      └─ Text \"foo\"", surfaceSpec("[foo]: /u\n^[foo]: attrs\n\n^[t][foo][foo]"))
    }

    /// The inline `(attrs)` form completes the attribute, so the label after it is a link reference of its own.
    func testFlagOffLabelAfterInlineAttributesIsLink() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ InlineAttributes attributes: `b`\n   │  └─ Text \"t\"\n   └─ Link destination: \"/u\"\n      └─ Text \"foo\"", surfaceSpec("[foo]: /u\n^[foo]: attrs\n\n^[t](b)[foo]"))
    }

    /// A link definition resolves even after a same-label attribute definition in an earlier paragraph, whereas cmark-gfm's shared refmap lets the attribute definition shadow it and leaves `[foo]` literal.
    func testFlagOffLinkDefinitionInLaterParagraphResolves() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Link destination: \"/u\"\n      └─ Text \"foo\"", surfaceSpec("^[foo]: attrs\n\n[foo]: /u\n\n[foo]"))
    }
}
