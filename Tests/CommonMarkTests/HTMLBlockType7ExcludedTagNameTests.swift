/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Start condition 7 (HTML blocks) takes an open tag with any tag name other than `script`, `style` or `pre`, so a
/// self-closing `<script/>`, which meets neither start condition 1 nor 7, is a paragraph. The exclusion applies to open
/// tags only, so a closing `</script>` meets start condition 7.
@Suite("Type 1 tag names in a type 7 HTML block start")
struct HTMLBlockType7ExcludedTagNameTests {
    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition]

    private func surface(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options, sourceRanges: true)
    }

    @Test func testSelfClosingScriptIsParagraph() {
        #expect(surface("<script/>") == "document @1:1-1:10\n  paragraph @1:1-1:10\n    html_inline \"<script/>\" @1:1-1:10\n")
    }

    @Test func testSelfClosingUppercasePreIsParagraph() {
        #expect(surface("<PRE/>") == "document @1:1-1:7\n  paragraph @1:1-1:7\n    html_inline \"<PRE/>\" @1:1-1:7\n")
    }

    @Test func testSelfClosingMixedCaseStyleIsParagraph() {
        #expect(surface("<Style/>") == "document @1:1-1:9\n  paragraph @1:1-1:9\n    html_inline \"<Style/>\" @1:1-1:9\n")
    }

    @Test func testClosingScriptTagStartsHTMLBlock() {
        #expect(surface("</script>") == "document @1:1-1:10\n  html_block \"</script>\\n\" @1:1-1:10\n")
    }

    @Test func testSelfClosingScriptingStartsHTMLBlock() {
        #expect(surface("<scripting/>") == "document @1:1-1:13\n  html_block \"<scripting/>\\n\" @1:1-1:13\n")
    }
}
