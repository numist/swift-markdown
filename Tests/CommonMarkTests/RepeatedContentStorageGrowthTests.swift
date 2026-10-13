/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Storage growth for a repetition of each of many small units, one per way the parser copies, carves, merges, splits or
/// materializes content.
///
/// Node content is stored as runs of segments over the source and a buffer of materialized bytes. A step that re-copies a
/// run growing with the input - merging text, splitting it into links, joining a construct across lines, projecting a table cell,
/// expanding a tab, replacing a NUL - makes a document of repeated units store content with the square of its size and
/// exhausts memory on inputs of a few tens of kilobytes. Each unit is repeated a thousand times, under every option set
/// that reaches its step, and both stores must stay within sixteen entries per source byte.
@Suite("Repeated content stores linear content")
struct RepeatedContentStorageGrowthTests {

    struct Shape: Sendable, CustomTestStringConvertible {
        let make: @Sendable (Int) -> String
        let options: [MarkdownDocument.ParseOptions]
        let testDescription: String

        init(_ testDescription: String, _ options: [MarkdownDocument.ParseOptions], _ make: @escaping @Sendable (Int) -> String) {
            self.testDescription = testDescription
            self.options = options
            self.make = make
        }
    }

    /// `options` in block parsing only.
    static func blockOnly(_ options: MarkdownDocument.ParseOptions) -> [MarkdownDocument.ParseOptions] {
        [options]
    }

    /// `options` in block and inline-only parsing.
    static func blockAndInlineOnly(_ options: MarkdownDocument.ParseOptions) -> [MarkdownDocument.ParseOptions] {
        [options, options.union(.inlineOnly)]
    }

    static func repeated(_ unit: String, _ count: Int) -> String {
        String(repeating: unit, count: count)
    }

    static let inlineShapes: [Shape] = [
        Shape("smart double quotes", blockAndInlineOnly(.smart)) { repeated("\"a\" ", $0) },
        Shape("smart single quotes", blockAndInlineOnly(.smart)) { repeated("'a' ", $0) },
        Shape("smart ellipses", blockAndInlineOnly(.smart)) { repeated("a... ", $0) },
        Shape("smart dashes", blockAndInlineOnly(.smart)) { repeated("a--- ", $0) },
        Shape("unmatched smart quotes", blockAndInlineOnly(.smart)) { repeated("x'a\"b", $0) },
        Shape("smart quotes before bangs", blockAndInlineOnly(.smart)) { "''" + repeated("!", $0) },
        Shape("smart quotes before entities", blockAndInlineOnly(.smart)) { "''" + repeated("&amp;", $0) },
        Shape("smart quotes before escapes", blockAndInlineOnly(.smart)) { "''" + repeated("\\*", $0) },
        Shape("smart quotes before backticks", blockAndInlineOnly(.smart)) { "''" + repeated("`", $0) },
        Shape("nested smart quotes", blockAndInlineOnly(.smart)) { repeated("\"", $0) + "a" + repeated("\"", $0) },
        Shape("entities", blockAndInlineOnly([])) { repeated("&amp;", $0) },
        Shape("an entity before brackets", blockAndInlineOnly([])) { "&amp;" + repeated("[a]", $0) },
        Shape("a numeric entity before emphasis openers", blockAndInlineOnly([])) { "&#65;" + repeated("*a", $0) },
        Shape("backslash escapes", blockAndInlineOnly([])) { repeated("\\*a", $0) },
        Shape("NULs", blockAndInlineOnly([])) { repeated("a\u{0}", $0) },
        Shape("a NUL before brackets", blockAndInlineOnly([])) { "\u{0}" + repeated("[a]", $0) },
        Shape("unmatched emphasis openers", blockAndInlineOnly([])) { repeated("*a", $0) },
        Shape("mismatched emphasis openers", blockAndInlineOnly([])) { repeated("*a **a ", $0) },
        Shape("underscore emphasis", blockAndInlineOnly([])) { repeated("_a_ ", $0) },
        Shape("unmatched strikethrough", blockOnly(.strikethrough)) { repeated("~a", $0) },
        Shape("unclosed brackets", blockAndInlineOnly([])) { repeated("[", $0) + "a" },
        Shape("nested brackets", blockAndInlineOnly([])) { repeated("[", $0) + "a" + repeated("]", $0) },
        Shape("inline links", blockAndInlineOnly([])) { repeated("[a](b) ", $0) },
        Shape("links nested in link text", blockAndInlineOnly([])) { repeated("[", $0) + "a" + repeated("](b)", $0) },
        Shape("unclosed link destinations", blockAndInlineOnly([])) { repeated("[a](", $0) },
        Shape("unclosed angle-bracket destinations", blockAndInlineOnly([])) { repeated("[a](<", $0) },
        Shape("link titles with entities and escapes", blockAndInlineOnly([])) { repeated("[a](b \"&amp;\\\"\") ", $0) },
        Shape("links with NULs in destinations", blockOnly([])) { repeated("[a](b\u{0}) ", $0) },
        Shape("unmatched code span openers", blockAndInlineOnly([])) { repeated("`a", $0) },
        Shape("raw HTML", blockAndInlineOnly([])) { repeated("<a><!-- x -->", $0) },
        Shape("unclosed raw HTML", blockAndInlineOnly([])) { repeated("<a ", $0) },
        Shape("angle autolinks", blockAndInlineOnly([])) { repeated("<http://a> <a@b.c> ", $0) },
        Shape("backslash hard breaks", blockAndInlineOnly([])) { repeated("a\\\n", $0) },
    ]

    static let autolinkShapes: [Shape] = [
        Shape("www autolinks", blockAndInlineOnly(.gfmAutolink)) { repeated("www.a.b ", $0) },
        Shape("scheme autolinks", blockAndInlineOnly(.gfmAutolink)) { repeated("http://a.b ", $0) },
        Shape("email autolinks", blockAndInlineOnly(.gfmAutolink)) { repeated("a@b.c ", $0) },
        Shape("adjoining email autolinks", blockAndInlineOnly(.gfmAutolink)) { repeated("a@b.c", $0) },
        Shape("at signs without domains", blockAndInlineOnly(.gfmAutolink)) { repeated("a@", $0) },
        Shape("an email with a long domain", blockAndInlineOnly(.gfmAutolink)) { "a@" + repeated("b.", $0) + "c" },
        Shape("emails among entities", blockAndInlineOnly(.gfmAutolink)) { repeated("a@b.c &amp; ", $0) },
        Shape("emails among escapes", blockAndInlineOnly(.gfmAutolink)) { repeated("a@b.c \\* ", $0) },
        Shape("emails among emphasis", blockAndInlineOnly(.gfmAutolink)) { repeated("a@b.c *x* ", $0) },
        Shape("emails among NULs", blockAndInlineOnly(.gfmAutolink)) { repeated("a@b.c \u{0} ", $0) },
        Shape("emails in link text", blockOnly(.gfmAutolink)) { "[" + repeated("a@b.c ", $0) + "](u)" },
        Shape("emails on soft-broken lines", blockAndInlineOnly(.gfmAutolink)) { repeated("a@b.c\n", $0) },
        Shape("emails on block quote lines", blockOnly(.gfmAutolink)) { repeated("> a@b.c\n", $0) },
        Shape("emails and smart quotes on CRLF lines", blockAndInlineOnly([.gfmAutolink, .smart])) { repeated("a@b.c \"x\"\r\n", $0) },
        Shape("emails and smart quotes on block quote CRLF lines", blockOnly([.gfmAutolink, .smart])) { repeated("> a@b.c \"x\"\r\n", $0) },
        Shape("emails and smart quotes in a setext heading", blockOnly([.gfmAutolink, .smart])) { repeated("> a@b.c \"x\"\n", $0) + "> ===\n" },
        Shape("emails and smart quotes after split tabs", blockOnly([.gfmAutolink, .smart])) { "> a\n" + repeated(">\t\ta@b.c \"x\"\n", $0) },
        Shape("emails, NULs and smart quotes", blockAndInlineOnly([.gfmAutolink, .smart])) { repeated("a@b.c\u{0}\"x\" ", $0) },
        Shape("www autolinks among smart quotes", blockAndInlineOnly([.gfmAutolink, .smart])) { repeated("www.a.b 'x' ", $0) },
        Shape("www autolinks in emphasis", blockAndInlineOnly(.gfmAutolink)) { repeated("*www.a.b* ", $0) },
        Shape("a URL with nested parentheses", blockAndInlineOnly(.gfmAutolink)) { "www.a.b/" + repeated("(", $0) + repeated(")", $0) },
        Shape("a URL with trailing entities", blockAndInlineOnly(.gfmAutolink)) { "www.a.b/" + repeated("&a;", $0) },
    ]

    static let footnoteAndAttributeShapes: [Shape] = [
        Shape("footnote references", blockOnly(.footnotes)) { repeated("[^a] ", $0) + "\n\n[^a]: x\n" },
        Shape("unresolved footnote references", blockAndInlineOnly(.footnotes)) { repeated("x[^a]", $0) },
        Shape("footnote definitions", blockOnly(.footnotes)) { repeated("[^a]: x\n", $0) },
        Shape("cross-line footnote brackets", blockAndInlineOnly(.footnotes)) { repeated("[^a\nb] ", $0) },
        Shape("cross-line footnote brackets in a block quote", blockOnly(.footnotes)) { repeated("> [^a\n> b] ", $0) },
        Shape("footnote brackets nested across lines", blockAndInlineOnly(.footnotes)) { repeated("[^\n", $0) + "a" + repeated("]", $0) },
        Shape("footnote brackets nested around replaced bytes across a line", blockAndInlineOnly(.footnotes)) {
            String(decoding: Array(repeating: Array("[^".utf8), count: $0).joined() + Array(repeating: 0xD9, count: 17) + [0x0A]
                + Array(repeating: 0x99, count: 26) + Array(repeating: UInt8(ascii: "]"), count: $0), as: UTF8.self)
        },
        Shape("image-shaped footnote brackets nested across a line", blockAndInlineOnly(.footnotes)) { repeated("![^", $0) + "abc\ndef" + repeated("]", $0) },
        Shape("escaped-caret footnote brackets nested", blockAndInlineOnly(.footnotes)) { repeated("[\\^", $0) + "x" + repeated("]", $0) },
        Shape("escaped-caret image brackets nested", blockAndInlineOnly(.footnotes)) { repeated("![\\^", $0) + "x" + repeated("]", $0) },
        Shape("footnote openers on block quote lines", blockOnly(.footnotes)) { repeated("> [^\n", $0) + "> " + repeated("]", $0) },
        Shape("caret brackets around empty brackets", blockAndInlineOnly(.footnotes)) { repeated("x[^[]]", $0) },
        Shape("unclosed footnote openers", blockAndInlineOnly(.footnotes)) { repeated("[^", $0) },
        Shape("inline attributes", blockAndInlineOnly(.attributes)) { repeated("^[a](b: c) ", $0) },
        Shape("attribute references", blockOnly(.attributes)) { "^[a]: b: c\n\n" + repeated("^[a] ", $0) },
        Shape("unclosed attributes", blockAndInlineOnly(.attributes)) { repeated("^[a](", $0) },
        Shape("attribute brackets nested across block quote lines", blockOnly(.attributes)) { repeated("> ^[\n", $0) + "> a" + repeated("]", $0) },
    ]

    static let tableShapes: [Shape] = [
        Shape("table rows", [.tables, [.tables, .sourcePosition]]) { "|a|b|\n|-|-|\n" + repeated("|x|y|\n", $0) },
        Shape("a wide table", blockOnly(.tables)) { "|" + repeated("a|", $0) + "\n|" + repeated("-|", $0) + "\n|" + repeated("x|", $0) + "\n" },
        Shape("table cells with escaped pipes", [.tables, [.tables, .sourcePosition]]) { "|a|b|\n|-|-|\n" + repeated("|x\\|y|z|\n", $0) },
        Shape("table code spans with escaped pipes", blockOnly(.tables)) { "|a|b|\n|-|-|\n" + repeated("|`x\\|y`|z|\n", $0) },
        Shape("table cells with NULs", blockOnly(.tables)) { "|a|b|\n|-|-|\n" + repeated("|x\u{0}|y|\n", $0) },
        Shape("table cells with smart quotes and emails", blockOnly([.tables, .smart, .gfmAutolink])) { "|a|b|\n|-|-|\n" + repeated("|\"x\" a@b.c|*y*|\n", $0) },
        Shape("a long table cell of emails and smart quotes", blockOnly([.tables, .gfmAutolink, .smart])) { "|a|\n|-|\n|" + repeated("a@b.c \"x\" ", $0) + "|\n" },
        Shape("rowspan markers", blockOnly([.tables, .tableSpans])) { "|a|b|\n|-|-|\n|x|y|\n" + repeated("|^|^|\n", $0) },
        Shape("ditto rowspan markers", blockOnly([.tables, .tableSpans, .tableRowspanDitto])) { "|a|b|\n|-|-|\n|x|y|\n" + repeated("|\"|\"|\n", $0) },
        Shape("colspan fillers", blockOnly([.tables, .tableSpans])) { "|a|b|\n|-|-|\n" + repeated("|x||\n", $0) },
        Shape("paragraph lines before a table", blockOnly(.tables)) { repeated("p\n", $0) + "|a|\n|-|\n" },
        Shape("block quote lines before a table", blockOnly(.tables)) { repeated("> p\n", $0) + "> |a|\n> |-|\n" },
        Shape("table rows in a block quote", blockOnly(.tables)) { "> |a|b|\n> |-|-|\n" + repeated("> |x|y|\n", $0) },
        Shape("delimiter-shaped lines in a block quote", blockOnly(.tables)) { "> a\n" + repeated("> -:-\n", $0) },
        Shape("many tables", blockOnly(.tables)) { repeated("|a|\n|-|\n\n", $0) },
    ]

    static let blockShapes: [Shape] = [
        Shape("NUL lines in a paragraph", [[], .sourcePosition]) { repeated("a\u{0}\n", $0) },
        Shape("NUL lines in a block quote", [[], .sourcePosition]) { repeated("> a\u{0}\n", $0) },
        Shape("NUL lines in fenced code", blockOnly([])) { "```\n" + repeated("a\u{0}\n", $0) + "```\n" },
        Shape("headings with NULs", blockOnly([])) { repeated("# a\u{0}\n", $0) },
        Shape("list items after tabs", [[], .sourcePosition]) { repeated("-\tfoo\n", $0) },
        Shape("lazy lines after tabs", blockOnly([])) { "> a\n" + repeated(" \tb\n", $0) },
        Shape("block quote lines with split tabs", [[], .sourcePosition]) { repeated(">\t\ta\n", $0) },
        Shape("paragraphs with split-tab residuals", [[], .sourcePosition]) { repeated("> > a\n>\tb\n\n", $0) },
        Shape("indented code split by tabs", blockOnly([])) { repeated(" - a\n\n  \t\tb\n", $0) },
        Shape("fenced code lines after tabs", blockOnly([])) { "  ```\n" + repeated("\t a\n", $0) + "```\n" },
        Shape("a setext heading in a block quote", blockOnly([])) { repeated("> a\n", $0) + "> ===\n" },
        Shape("setext headings", blockOnly([])) { repeated("a\n===\n", $0) },
        Shape("a setext heading with CRLF lines", blockOnly([])) { repeated("a\r\n", $0) + "===\r\n" },
        Shape("CRLF paragraph lines", [[], .sourcePosition]) { repeated("a\r\n", $0) },
        Shape("reference definitions", blockOnly([])) { repeated("[a]: /u\n", $0) + "x" },
        Shape("reference definitions in a block quote", blockOnly([])) { repeated("> [a]: /u\n", $0) + "> x" },
        Shape("reference definitions before a setext heading", blockOnly([])) { repeated("[a]: /u\n", $0) + "x\n===" },
        Shape("reference definitions before a block quote setext heading", blockOnly([])) { repeated("> [a]: /u\n", $0) + "> x\n> ===" },
        Shape("setext underlines after a definition", blockOnly([])) { "[a]: /u\n" + repeated("===\n", $0) },
        Shape("setext underlines after a block quote definition", blockOnly([])) { "> [a]: /u\n" + repeated("> ===\n", $0) },
        Shape("a multi-line code span in a block quote", blockOnly([])) { "> `" + repeated("a\n> ", $0) + "`" },
        Shape("a multi-line link title in a block quote", blockOnly([])) { "> [a](b \"" + repeated("x\n> ", $0) + "\")" },
        Shape("nested brackets across block quote lines", blockOnly([])) { repeated("> [\n", $0) + "> a" + repeated("]", $0) },
        Shape("task list items", blockOnly(.tasklist)) { repeated("- [ ] a\n", $0) },
        Shape("task list checkboxes on continuation lines", blockOnly(.tasklist)) { repeated("- \n  [ ] a\n", $0) },
        Shape("hard breaks in a block quote", blockOnly([])) { repeated("> a  \n", $0) },
        Shape("an HTML block", blockOnly([])) { "<div>\n" + repeated("a\n", $0) },
        Shape("indented code lines", blockOnly([])) { repeated("    a\n", $0) },
        Shape("whitespace-preserving lines", [.preserveWhitespace]) { repeated("a\r\n", $0) },
        Shape("GFM features mixed", blockOnly([.tables, .strikethrough, .tasklist, .gfmAutolink, .footnotes, .smart])) { repeated("*a* 'b' [^c] www.d.e f@g.h ~i~ ", $0) },
    ]

    struct Case: Sendable, CustomTestStringConvertible {
        let shape: Shape
        let options: MarkdownDocument.ParseOptions

        var testDescription: String {
            "\(shape.testDescription), options \(options.rawValue)"
        }
    }

    static let cases: [Case] = (inlineShapes + autolinkShapes + footnoteAndAttributeShapes + tableShapes + blockShapes).flatMap { shape in
        shape.options.map { Case(shape: shape, options: $0) }
    }

    @Test("storage grows linearly with the repetitions", arguments: cases)
    func linearStorage(_ testCase: Case) {
        let source = testCase.shape.make(1000)
        // Every unit is at least a byte, so the repetitions alone make a source this long.
        #expect(source.utf8.count >= 1000)
        let (segments, materialized) = MarkdownDocument.withParsedDocument(source, options: testCase.options) {
            ($0._segmentCount, $0._materializedStringSize)
        }
        let bound = 16 * source.utf8.count + 256
        #expect(segments <= bound, "\(segments) segments for \(source.utf8.count) bytes")
        #expect(materialized <= bound, "\(materialized) materialized bytes for \(source.utf8.count) bytes")
    }
}
