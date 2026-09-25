/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// An attribute definition registered after a same-label link definition is shadowed by it.
///
/// Ground truth is cmark-gfm (flag-ON). cmark keeps link and attribute definitions in one refmap where the
/// first-registered entry wins. With `[foo]: /u` defined before `^[foo]: attrs`, `^[t][foo]` finds the link
/// entry, forms no attribute, and the `[foo]` label is consumed, leaving literal `^[t]`. The reverse order
/// (an attribute definition shadowing a later link definition) is covered as a control. Flag-OFF the two
/// definition kinds are separate namespaces, so both resolve regardless of order. Position-free compare
/// surface.
class AttributeDefinitionShadowedByLinkTests: XCTestCase {
    private func surface(_ markdown: String) -> String {
        Document(parsing: markdown, options: [.cmarkBugCompatibility]).debugDescription(options: [])
    }

    func testAttributeDefinitionAfterLinkDefinition() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"^[t]\"", surface("[foo]: /u\n^[foo]: attrs\n\n^[t][foo]"))
    }

    func testAttributeDefinitionInLaterParagraph() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"^[t]\"", surface("[foo]: /u\n\n^[foo]: attrs\n\n^[t][foo]"))
    }

    func testLinkUseStillResolves() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Link destination: \"/u\"\n   │  └─ Text \"foo\"\n   └─ Text \" ^[t] x\"", surface("[foo]: /u\n^[foo]: attrs\n\n[foo] ^[t][foo] x"))
    }

    func testFollowingLinkAfterShadowedAttribute() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"^[t]\"\n   └─ Link destination: \"/u\"\n      └─ Text \"foo\"", surface("[foo]: /u\n^[foo]: attrs\n\n^[t][foo][foo]"))
    }

    func testAttributeFirstControl() {
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ InlineAttributes attributes: `attrs`\n   │  └─ Text \"t\"\n   └─ Text \" [foo]\"", surface("^[foo]: attrs\n[foo]: /u\n\n^[t][foo] [foo]"))
    }

    func testCaseFoldedLabels() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"^[t]\"", surface("[FOO]: /u\n^[foo]: attrs\n\n^[t][Foo]"))
    }

    func testAttributeDefinitionInsideContainer() {
        XCTAssertEqual("Document\n├─ BlockQuote\n└─ Paragraph\n   └─ Text \"^[t]\"", surface("[foo]: /u\n\n> ^[foo]: attrs\n\n^[t][foo]"))
    }

    func testInlineAttributesAfterShadowedDefinition() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ InlineAttributes attributes: `b`\n      └─ Text \"t\"", surface("[foo]: /u\n^[foo]: attrs\n\n^[t](b)"))
    }

    /// cmark scans a `[label]` after an inline `(attrs)` too; a label whose surviving entry is a link ref keeps the inline attributes, and the label is consumed.
    func testInlineAttributesThenShadowedLabel() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ InlineAttributes attributes: `b`\n      └─ Text \"t\"", surface("[foo]: /u\n^[foo]: attrs\n\n^[t](b)[foo]"))
    }

    /// The attributes grammar has no collapsed or shortcut reference form: an empty `[]` label never resolves (and is consumed), and a bare `^[foo]` never looks up its content.
    func testNoCollapsedOrShortcutForm() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"^[foo]\"", surface("[foo]: /u\n^[foo]: attrs\n\n^[foo][]"))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"^[foo]\"", surface("[foo]: /u\n^[foo]: attrs\n\n^[foo]"))
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"^[foo]\"", surface("^[foo]: attrs\n\n^[foo][]"))
    }

    func testLinkDefinitionInLaterParagraphShadowedByAttribute() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[foo]\"", surface("^[foo]: attrs\n\n[foo]: /u\n\n[foo]"))
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
}
