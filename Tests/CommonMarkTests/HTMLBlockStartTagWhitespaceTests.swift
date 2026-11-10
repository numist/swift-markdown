/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Whitespace includes line tabulation and form feed (Characters and lines). It ends the tag name that starts a type 1
/// or type 6 HTML block, separates the parts of a type 7 start tag (Raw HTML), and may follow that tag on its line
/// (HTML blocks).
@Suite("Whitespace in and after an HTML block start tag")
struct HTMLBlockStartTagWhitespaceTests {
    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition]

    private func tree(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options, sourceRanges: true)
    }

    @Test func formFeedAfterType1TagNameStartsHTMLBlock() {
        #expect(tree("<pre\u{0C}>") == "document @1:1-1:7\n  html_block \"<pre\\u{C}>\\n\" @1:1-1:7\n")
    }

    @Test func formFeedAfterType6TagNameStartsHTMLBlock() {
        #expect(tree("<div\u{0C}>") == "document @1:1-1:7\n  html_block \"<div\\u{C}>\\n\" @1:1-1:7\n")
    }

    @Test func lineTabulationAfterType6TagNameStartsHTMLBlock() {
        #expect(tree("<div\u{0B}>") == "document @1:1-1:7\n  html_block \"<div\\u{B}>\\n\" @1:1-1:7\n")
    }

    @Test func formFeedBeforeType7AttributeStartsHTMLBlock() {
        #expect(tree("<a\u{0C}ref=\"x\">") == "document @1:1-1:12\n  html_block \"<a\\u{C}ref=\\\"x\\\">\\n\" @1:1-1:12\n")
    }

    @Test func lineTabulationAfterOpenTagStartsHTMLBlock() {
        #expect(tree("<a>\u{0B}") == "document @1:1-1:5\n  html_block \"<a>\\u{B}\\n\" @1:1-1:5\n")
    }

    @Test func formFeedAfterOpenTagStartsHTMLBlock() {
        #expect(tree("<a>\u{0C}") == "document @1:1-1:5\n  html_block \"<a>\\u{C}\\n\" @1:1-1:5\n")
    }

    @Test func lineTabulationAfterClosingTagStartsHTMLBlock() {
        #expect(tree("</a>\u{0B}\nx") == "document @1:1-2:2\n  html_block \"</a>\\u{B}\\nx\\n\" @1:1-2:2\n")
    }

    @Test func textAfterLineTabulationIsParagraph() {
        #expect(tree("<a>\u{0B}x") == "document @1:1-1:6\n  paragraph @1:1-1:6\n    html_inline \"<a>\" @1:1-1:4\n    text \"\\u{B}x\" @1:4-1:6\n")
    }
}
