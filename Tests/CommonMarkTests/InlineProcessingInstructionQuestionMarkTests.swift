/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// The literal content of the first raw HTML node in document order, or nil if the tree has none.
private func firstInlineHTML(_ node: borrowing MarkdownNode) -> String? {
    if case .htmlInline = node.kind, case .text(let s) = node.stringContent {
        return s
    }
    var found: String? = nil
    node.children.forEach { child in
        if found == nil {
            found = firstInlineHTML(child)
        }
    }
    return found
}

/// The content of the first HTML block in document order, or nil if the tree has none.
private func firstHTMLBlock(_ node: borrowing MarkdownNode) -> String? {
    if case .htmlBlock = node.kind, case .htmlBlock(let body) = node.stringContent {
        return body
    }
    var found: String? = nil
    node.children.forEach { child in
        if found == nil {
            found = firstHTMLBlock(child)
        }
    }
    return found
}

/// The concatenated literal content of every text node in document order.
private func collectText(_ node: borrowing MarkdownNode) -> String {
    var result = ""
    if case .text = node.kind, case .text(let s) = node.stringContent {
        result += s
    }
    node.children.forEach { child in
        result += collectText(child)
    }
    return result
}

/// A processing instruction (Raw HTML) is `<?`, a string not containing `?>`, and `?>`, so `<???>` is a processing
/// instruction whose content is `?`.
@Suite("Inline processing instructions made of question marks")
struct InlineProcessingInstructionQuestionMarkTests {

    private static let options: MarkdownDocument.ParseOptions = []

    private func inlineHTML(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) -> String? {
        MarkdownDocument.withParsedDocument(src, options: options) { doc -> String? in
            firstInlineHTML(doc.root)
        }
    }

    private func text(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) -> String {
        MarkdownDocument.withParsedDocument(src, options: options) { doc -> String in
            collectText(doc.root)
        }
    }

    @Test("`f<???>` recognizes the inline processing instruction")
    func threeQuestionMarks() {
        #expect(inlineHTML("f<???>", options: Self.options) == "<???>")
        #expect(text("f<???>", options: Self.options) == "f")
    }

    @Test("`\\u{0000}<???>` recognizes the inline processing instruction")
    func threeQuestionMarksAfterNUL() {
        #expect(inlineHTML("\u{0000}<???>", options: Self.options) == "<???>")
        #expect(text("\u{0000}<???>", options: Self.options) == "\u{FFFD}")
    }

    @Test("`f<?x?>` recognizes the inline processing instruction (content `x`)")
    func inlinePIBodyX() {
        #expect(inlineHTML("f<?x?>", options: Self.options) == "<?x?>")
    }

    @Test("`a<?b?>c` recognizes the inline processing instruction mid-text")
    func inlinePIMidText() {
        #expect(inlineHTML("a<?b?>c", options: Self.options) == "<?b?>")
        #expect(text("a<?b?>c", options: Self.options) == "ac")
    }

    @Test("`f<? ?>` recognizes the inline processing instruction (space content)")
    func inlinePISpaceBody() {
        #expect(inlineHTML("f<? ?>", options: Self.options) == "<? ?>")
    }

    @Test("`f<??>` recognizes the empty inline processing instruction")
    func inlinePIEmptyBody() {
        #expect(inlineHTML("f<??>", options: Self.options) == "<??>")
    }

    @Test("`f<????>` recognizes the inline processing instruction (content `??`)")
    func inlinePIFourQuestionMarks() {
        #expect(inlineHTML("f<????>", options: Self.options) == "<????>")
    }

    @Test("`<???>` alone on a line is an HTML block (start condition 3)")
    func standaloneIsHTMLBlock() throws {
        #expect(inlineHTML("<???>", options: Self.options) == nil)
        let block = MarkdownDocument.withParsedDocument("<???>", options: Self.options) { doc -> String? in
            firstHTMLBlock(doc.root)
        }
        let body = try #require(block, "expected an HTML block")
        #expect(body.contains("<???>"))
        #expect(body == "<???>\n")
    }
}
