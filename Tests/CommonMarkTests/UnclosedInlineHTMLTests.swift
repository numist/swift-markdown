/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

private func inlineHTMLLiterals(_ node: borrowing MarkdownNode) -> [String] {
    var literals: [String] = []
    if case .htmlInline = node.kind {
        literals.append(node.literal() ?? "")
    }
    node.children.forEach { child in
        literals += inlineHTMLLiterals(child)
    }
    return literals
}

@Suite("Unclosed inline raw HTML openers")
struct UnclosedInlineHTMLTests {

    private func htmlLiterals(_ src: String, options: MarkdownDocument.ParseOptions) -> [String] {
        MarkdownDocument.withParsedDocument(src, options: options) { doc -> [String] in
            inlineHTMLLiterals(doc.root)
        }
    }

    @Test("unclosed openers of one kind all stay literal")
    func unclosedOpenersStayLiteral() {
        #expect(htmlLiterals("x<!--a <!--b\ny<!--c", options: []) == [])
        #expect(htmlLiterals("x<?a <?b\ny<?c", options: []) == [])
        #expect(htmlLiterals("x<!A a <!B b\ny<!C c", options: []) == [])
        #expect(htmlLiterals("x<![CDATA[a <![CDATA[b\ny<![CDATA[c", options: []) == [])
    }

    @Test("`<!->` opens no comment")
    func dashGreaterThanOpensNoComment() {
        #expect(htmlLiterals("x<!-> <!--a-->", options: []) == ["<!--a-->"])
    }

    @Test("a later `<!-->` closes an earlier comment at its `-->`")
    func laterEmptyCommentClosesEarlierComment() {
        #expect(htmlLiterals("x<!--a <!-->", options: []) == ["<!--a <!-->"])
    }

    @Test("a later `<!--->` closes an earlier comment at its `-->`")
    func laterDashEmptyCommentClosesEarlierComment() {
        #expect(htmlLiterals("x<!--a <!--->", options: []) == ["<!--a <!--->"])
    }

    @Test("the empty comments `<!-->` and `<!--->` match without a later closer")
    func emptyComments() {
        #expect(htmlLiterals("x<!--> <!--a", options: []) == ["<!-->"])
        #expect(htmlLiterals("x<!---> <!--a", options: []) == ["<!--->"])
    }

    @Test("the processing-instruction closer search starts after `<?`")
    func processingInstructionCloserSearchStartsAfterOpener() {
        #expect(htmlLiterals("x<?>", options: []) == [])
        #expect(htmlLiterals("x<?a <?>", options: []) == ["<?a <?>"])
        #expect(htmlLiterals("x<?a <?b ?>", options: []) == ["<?a <?b ?>"])
    }

    @Test("a CDATA section's body may hold `<![CDATA[`")
    func cdataBodyHoldsCDATAOpener() {
        #expect(htmlLiterals("x<![CDATA[a <![CDATA[]]>", options: []) == ["<![CDATA[a <![CDATA[]]>"])
    }

    @Test("a declaration's body may hold `<!B`")
    func declarationBodyHoldsBangName() {
        #expect(htmlLiterals("x<!A a <!B>", options: []) == ["<!A a <!B>"])
        #expect(htmlLiterals("x<!A a\nb<!B c>", options: []) == ["<!A a\nb<!B c>"])
    }

    @Test("a failed processing instruction leaves later comments, CDATA, and declarations matchable")
    func failedProcessingInstructionLeavesOtherKinds() {
        #expect(htmlLiterals("x<?a <!--b-->", options: []) == ["<!--b-->"])
        #expect(htmlLiterals("x<?a <![CDATA[b]]>", options: []) == ["<![CDATA[b]]>"])
        #expect(htmlLiterals("x<?a <!B b>", options: []) == ["<!B b>"])
    }

    @Test("a failed CDATA leaves later declarations and processing instructions matchable")
    func failedCDATALeavesOtherKinds() {
        #expect(htmlLiterals("x<![CDATA[a <!B b>", options: []) == ["<!B b>"])
        #expect(htmlLiterals("x<![CDATA[a <?b?>", options: []) == ["<?b?>"])
    }

    @Test("a failed comment leaves a later processing instruction matchable")
    func failedCommentLeavesProcessingInstruction() {
        #expect(htmlLiterals("x<!--a <?b?>", options: []) == ["<?b?>"])
    }

    @Test("a failed comment leaves later CDATA and declarations matchable")
    func failedCommentLeavesBangForms() {
        #expect(htmlLiterals("x<!--a <![CDATA[b]]>", options: []) == ["<![CDATA[b]]>"])
        #expect(htmlLiterals("x<!--a <!B b>", options: []) == ["<!B b>"])
    }

    @Test("closed openers after a matched construct of the same kind match")
    func closedOpenersAfterMatchMatch() {
        #expect(htmlLiterals("x<!--a--> <!--b--> <!--c", options: []) == ["<!--a-->", "<!--b-->"])
        #expect(htmlLiterals("x<?a?> <?b?> <?c", options: []) == ["<?a?>", "<?b?>"])
        #expect(htmlLiterals("x<!A a> <!B b> <!C c", options: []) == ["<!A a>", "<!B b>"])
        #expect(htmlLiterals("x<![CDATA[a]]> <![CDATA[b]]> <![CDATA[c", options: []) == ["<![CDATA[a]]>", "<![CDATA[b]]>"])
    }

    @Test("a NUL in a construct's body is replaced and does not end the closer search")
    func nulDoesNotEndCloserSearch() {
        #expect(htmlLiterals("x<!--a\u{0}<!--b-->", options: []) == ["<!--a\u{FFFD}<!--b-->"])
        #expect(htmlLiterals("x<?a\u{0}<?b?>", options: []) == ["<?a\u{FFFD}<?b?>"])
        #expect(htmlLiterals("x<!A a\u{0}<!B b>", options: []) == ["<!A a\u{FFFD}<!B b>"])
        #expect(htmlLiterals("x<![CDATA[a\u{0}<![CDATA[b]]>", options: []) == ["<![CDATA[a\u{FFFD}<![CDATA[b]]>"])
    }

    @Test("a failed scan in one paragraph does not suppress a match in the next")
    func failedScanDoesNotCrossParagraphs() {
        #expect(htmlLiterals("x<!--a\n\nx<!--b-->", options: []) == ["<!--b-->"])
        #expect(htmlLiterals("x<?a\n\nx<?b?>", options: []) == ["<?b?>"])
        #expect(htmlLiterals("x<!A a\n\nx<!B b>", options: []) == ["<!B b>"])
        #expect(htmlLiterals("x<![CDATA[a\n\nx<![CDATA[b]]>", options: []) == ["<![CDATA[b]]>"])
    }
}
