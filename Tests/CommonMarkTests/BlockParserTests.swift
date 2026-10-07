/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Walks a document and returns a compact `(kind, optional-literal)` sequence in DFS order. Useful for asserting the shape of parsed trees in tests without writing nested forEach blocks.
internal func dfs(_ doc: borrowing MarkdownDocument) -> [(kind: MarkdownNode.Kind, literal: String?)] {
    var out: [(MarkdownNode.Kind, String?)] = []
    visit(doc.root, into: &out)
    return out.map { ($0.0, $0.1) }
}

private func visit(_ node: borrowing MarkdownNode, into out: inout [(MarkdownNode.Kind, String?)]) {
    out.append((node.kind, node.literal()))
    node.children.forEach { child in
        visit(child, into: &out)
    }
}

/// Collect `(info, literal)` for every code block in the document in DFS order, so tests can assert
/// on code blocks nested inside containers (e.g. a fenced block inside a list item).
internal func codeBlocks(_ doc: borrowing MarkdownDocument) -> [(info: String, literal: String)] {
    var out: [(String, String)] = []
    collectCodeBlocks(doc.root, into: &out)
    return out.map { (info: $0.0, literal: $0.1) }
}

private func collectCodeBlocks(_ node: borrowing MarkdownNode, into out: inout [(String, String)]) {
    if node.kind.isCodeBlock {
        out.append((node.codeBlockInfoString() ?? "", node.literal() ?? ""))
    }
    node.children.forEach { child in
        collectCodeBlocks(child, into: &out)
    }
}

// Shape-assertion helpers: build the `Kind` value a freshly-parsed list / indented code block carries, so structural `kinds == [...]` arrays stay readable. (`.list`/`.codeBlock` carry associated metadata.)
extension MarkdownNode.Kind {
    static func bulletList(
        _ marker: MarkdownNode.ListInfo.BulletMarker = .hyphen,
        tight: Bool = true
    ) -> MarkdownNode.Kind {
        .list(.init(kind: .bullet, start: 1, tight: tight, orderedDelimiter: .period, bulletMarker: marker))
    }

    static func orderedList(
        start: Int = 1,
        _ delimiter: MarkdownNode.ListInfo.OrderedDelimiter = .period,
        tight: Bool = true
    ) -> MarkdownNode.Kind {
        .list(.init(kind: .ordered, start: start, tight: tight, orderedDelimiter: delimiter, bulletMarker: .hyphen))
    }

    /// An indented (non-fenced) code block.
    static let indentedCode = MarkdownNode.Kind.codeBlock(
        .init(isFenced: false, fenceCharacter: nil, fenceLength: 0, fenceOffset: 0)
    )

    /// A fenced code block.
    static func fencedCode(
        _ character: MarkdownNode.CodeBlockInfo.FenceCharacter = .backtick,
        length: Int = 3,
        offset: Int = 0
    ) -> MarkdownNode.Kind {
        .codeBlock(.init(isFenced: true, fenceCharacter: character, fenceLength: length, fenceOffset: offset))
    }
}

@Suite("Block parser - paragraphs")
struct ParagraphTests {

    @Test("single-line paragraph")
    func singleLine() {
        let source = "hello world"
        MarkdownDocument.withParsedDocument(source) { doc in
        let shape = dfs(doc)
        #expect(shape.count == 3)
        #expect(shape[0].kind == .document)
        #expect(shape[1].kind == .paragraph)
        #expect(shape[2].kind == .text)
        #expect(shape[2].literal == "hello world")
        }
    }

    @Test("multi-line paragraph splits into text + softBreak nodes")
    func multiLine() {
        let source = "first line\nsecond line\nthird"
        MarkdownDocument.withParsedDocument(source) { doc in
        let shape = dfs(doc)
        let kinds = shape.map { $0.kind }
        #expect(kinds == [.document, .paragraph, .text, .softBreak, .text, .softBreak, .text])
        let texts = shape.compactMap { $0.literal }
        #expect(texts == ["first line", "second line", "third"])
        }
    }

    @Test("blank line separates paragraphs")
    func blankLineSeparates() {
        let source = "first paragraph\n\nsecond paragraph"
        MarkdownDocument.withParsedDocument(source) { doc in
        let shape = dfs(doc)
        let kinds = shape.map { $0.kind }
        #expect(kinds == [.document, .paragraph, .text, .paragraph, .text])
        let texts = shape.compactMap { $0.literal }
        #expect(texts == ["first paragraph", "second paragraph"])
        }
    }

    @Test("multiple blank lines collapse to one separator")
    func multipleBlankLines() {
        let source = "one\n\n\n\ntwo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .paragraph, .text, .paragraph, .text])
        }
    }

    @Test("a trailing line ending doesn't produce an extra empty paragraph")
    func trailingNewline() {
        let source = "alone\n"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .paragraph, .text])
        }
    }

    @Test("CRLF and lone CR are line endings")
    func crlfHandling() {
        let source = "one\r\ntwo\rthree"
        MarkdownDocument.withParsedDocument(source) { doc in
        let texts = dfs(doc).compactMap { $0.literal }
        // One paragraph with a soft line break between each line.
        #expect(texts == ["one", "two", "three"])
        }
    }

    @Test("BOM is stripped at the start")
    func bomStripping() {
        let source = "\u{FEFF}text"
        MarkdownDocument.withParsedDocument(source) { doc in
        let texts = dfs(doc).compactMap { $0.literal }
        #expect(texts == ["text"])
        }
    }

    @Test("empty input yields just the document node")
    func emptyInput() {
        let source = ""
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document])
        }
    }

    @Test("whitespace-only input yields just the document node")
    func whitespaceOnly() {
        let source = "   \n\t\n   "
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document])
        }
    }
}

@Suite("Block parser - ATX headings")
struct ATXHeadingTests {

    @Test("levels 1 through 6")
    func levels() {
        for level in 1...6 {
            let prefix = String(repeating: "#", count: level)
            let source = "\(prefix) heading\n"
            MarkdownDocument.withParsedDocument(source) { doc in
            let shape = dfs(doc)
            #expect(shape.count == 3, "level \(level)")
            #expect(shape[1].kind == .heading(level: level), "level \(level)")
            #expect(shape[2].literal == "heading", "level \(level)")
            }
        }
    }

    @Test("seven hashes is a paragraph, not a heading")
    func sevenHashes() {
        let source = "####### too many"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .paragraph, .text])
        }
    }

    @Test("hash without trailing space is a paragraph")
    func hashWithoutSpace() {
        let source = "#hashtag"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .paragraph, .text])
        }
    }

    @Test("up to 3 leading spaces parses as heading")
    func leadingSpaces() {
        let source = "   ### heading"
        MarkdownDocument.withParsedDocument(source) { doc in
        let shape = dfs(doc)
        #expect(shape[1].kind == .heading(level: 3))
        #expect(shape[2].literal == "heading")
        }
    }

    @Test("4+ leading spaces is indented code, not a heading")
    func fourLeadingSpaces() {
        let source = "    # not a heading"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .indentedCode])
        }
    }

    @Test("trailing closing hashes are stripped")
    func closingHashes() {
        let source = "## heading ##\n"
        MarkdownDocument.withParsedDocument(source) { doc in
        let texts = dfs(doc).compactMap { $0.literal }
        #expect(texts == ["heading"])
        }
    }

    @Test("closing hashes without preceding space are part of content")
    func closingHashesNoSpace() {
        let source = "## foo#bar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let texts = dfs(doc).compactMap { $0.literal }
        #expect(texts == ["foo#bar"])
        }
    }

    @Test("empty heading is fine")
    func emptyHeading() {
        let source = "##\n"
        MarkdownDocument.withParsedDocument(source) { doc in
        let shape = dfs(doc)
        #expect(shape.count == 2) // document + heading, no text child
        #expect(shape[1].kind == .heading(level: 2))
        }
    }

    @Test("heading interrupts a paragraph")
    func interruptsParagraph() {
        let source = "paragraph text\n# heading\nnext paragraph"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [
            .document,
            .paragraph, .text,
            .heading(level: 1), .text,
            .paragraph, .text,
        ])
        }
    }
}

@Suite("Block parser - thematic breaks")
struct ThematicBreakTests {

    @Test("three dashes")
    func threeDashes() {
        let source = "---"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .thematicBreak])
        }
    }

    @Test("three asterisks")
    func threeAsterisks() {
        let source = "***"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .thematicBreak])
        }
    }

    @Test("three underscores")
    func threeUnderscores() {
        let source = "___"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .thematicBreak])
        }
    }

    @Test("more than three markers are a single thematic break")
    func manyMarkers() {
        let source = "------------"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .thematicBreak])
        }
    }

    @Test("markers may be separated by spaces or tabs")
    func spacedMarkers() {
        let source = "- - -"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .thematicBreak])
        }
    }

    @Test("up to 3 leading spaces parses as thematic break")
    func leadingSpaces() {
        let source = "   ---"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .thematicBreak])
        }
    }

    @Test("4+ leading spaces is indented code, not a thematic break")
    func fourLeadingSpaces() {
        let source = "    ---"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .indentedCode])
        }
    }

    @Test("only two markers is not a thematic break")
    func twoMarkers() {
        let source = "--"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .paragraph, .text])
        }
    }

    @Test("mixed markers are not a thematic break")
    func mixedMarkers() {
        let source = "-*-"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        // The `*` delimiter run has no matching closer, so the line is a single text node.
        #expect(kinds == [.document, .paragraph, .text])
        }
    }

    @Test("non-whitespace, non-marker characters disqualify the line")
    func extraCharacters() {
        let source = "--- and more"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .paragraph, .text])
        }
    }

    @Test("thematic break separates paragraphs")
    func separatesParagraphs() {
        // A `---` on its own line (surrounded by blank lines, with no paragraph directly above) is a thematic break, not a setext H2 underline.
        let source = "before\n\n---\n\nafter"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [
            .document,
            .paragraph, .text,
            .thematicBreak,
            .paragraph, .text,
        ])
        }
    }

    @Test("consecutive thematic breaks produce multiple nodes")
    func consecutive() {
        let source = "---\n***\n___"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [
            .document,
            .thematicBreak,
            .thematicBreak,
            .thematicBreak,
        ])
        }
    }
}

@Suite("Block parser - setext headings")
struct SetextHeadingTests {

    @Test("equals underline produces level 1")
    func equalsIsLevel1() {
        let source = "Title\n====="
        MarkdownDocument.withParsedDocument(source) { doc in
        let shape = dfs(doc)
        #expect(shape.count == 3)
        #expect(shape[1].kind == .heading(level: 1))
        #expect(shape[2].literal == "Title")
        }
    }

    @Test("dash underline produces level 2")
    func dashIsLevel2() {
        let source = "Title\n-----"
        MarkdownDocument.withParsedDocument(source) { doc in
        let shape = dfs(doc)
        #expect(shape.count == 3)
        #expect(shape[1].kind == .heading(level: 2))
        }
    }

    @Test("single marker character is sufficient")
    func singleMarker() {
        let source = "Title\n="
        MarkdownDocument.withParsedDocument(source) { doc in
        let shape = dfs(doc)
        #expect(shape[1].kind == .heading(level: 1))
        #expect(shape[2].literal == "Title")
        }
    }

    @Test("multi-line paragraph above is all part of heading content")
    func multiLineContent() {
        let source = "first\nsecond\n==="
        MarkdownDocument.withParsedDocument(source) { doc in
        let texts = dfs(doc).compactMap { $0.literal }
        #expect(texts == ["first", "second"])
        }
    }

    @Test("underline may have ≤3 leading spaces")
    func leadingSpacesOnUnderline() {
        let source = "Title\n   ==="
        MarkdownDocument.withParsedDocument(source) { doc in
        let shape = dfs(doc)
        #expect(shape[1].kind == .heading(level: 1))
        }
    }

    @Test("underline with 4+ leading spaces is paragraph continuation")
    func tooManyLeadingSpaces() {
        let source = "Title\n    ==="
        MarkdownDocument.withParsedDocument(source) { doc in
        let shape = dfs(doc)
        // Whole thing remains a paragraph; multi-line → text + softBreak + text.
        #expect(shape[1].kind == .paragraph)
        let texts = shape.compactMap { $0.literal }
        #expect(texts == ["Title", "==="])
        }
    }

    @Test("trailing spaces/tabs after the underline are allowed")
    func trailingSpaces() {
        let source = "Title\n===   \t  "
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(dfs(doc)[1].kind == .heading(level: 1))
        }
    }

    @Test("blank line between content and underline breaks the heading")
    func blankLineBetween() {
        let source = "Title\n\n==="
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        // Without paragraph open when `===` is processed, it's just paragraph text.
        #expect(kinds == [.document, .paragraph, .text, .paragraph, .text])
        }
    }

    @Test("dash underline takes precedence over thematic break when paragraph open")
    func dashOverridesThematic() {
        let source = "Title\n---"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        // Setext H2 - NOT thematic break.
        #expect(kinds == [.document, .heading(level: 2), .text])
        }
    }

    @Test("mixed markers on underline are not setext")
    func mixedMarkers() {
        let source = "Title\n=-="
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        // Falls through to paragraph continuation.
        #expect(kinds == [.document, .paragraph, .text, .softBreak, .text])
        }
    }

    @Test("setext underline is not valid with no preceding paragraph")
    func noPrecedingParagraph() {
        let source = "==="
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        // `=` is not a thematic break marker, so it stays a paragraph.
        #expect(kinds == [.document, .paragraph, .text])
        }
    }
}

@Suite("Block parser - indented code blocks")
struct IndentedCodeTests {

    @Test("4 spaces of indent opens an indented code block")
    func basic() {
        let source = "    foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let shape = dfs(doc)
        #expect(shape.count == 2)
        #expect(shape[1].kind.isCodeBlock)
        #expect(shape[1].literal == "foo\n")
        }
    }

    @Test("a code block's content always ends in a line ending")
    func trailingNewline() {
        let source = "    foo\n"
        MarkdownDocument.withParsedDocument(source) { doc in
        let shape = dfs(doc)
        #expect(shape[1].literal == "foo\n")
        }
    }

    @Test("multiple indented lines join with line endings")
    func multipleLines() {
        let source = "    foo\n    bar\n    baz"
        MarkdownDocument.withParsedDocument(source) { doc in
        let shape = dfs(doc)
        #expect(shape[1].kind.isCodeBlock)
        #expect(shape[1].literal == "foo\nbar\nbaz\n")
        }
    }

    @Test("blank lines within indented code are preserved")
    func interiorBlankLines() {
        let source = "    foo\n\n    bar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let shape = dfs(doc)
        #expect(shape[1].kind.isCodeBlock)
        #expect(shape[1].literal == "foo\n\nbar\n")
        }
    }

    @Test("trailing blank lines are stripped from indented code")
    func trailingBlankLines() {
        let source = "    foo\n\n\n"
        MarkdownDocument.withParsedDocument(source) { doc in
        let shape = dfs(doc)
        #expect(shape[1].kind.isCodeBlock)
        #expect(shape[1].literal == "foo\n")
        }
    }

    @Test("non-indented non-blank line closes the code block")
    func paragraphAfter() {
        let source = "    code\nparagraph"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .indentedCode, .paragraph, .text])
        }
    }

    @Test("indented code cannot interrupt a paragraph")
    func cannotInterruptParagraph() {
        let source = "paragraph\n    not code"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .paragraph, .text, .softBreak, .text])
        let texts = dfs(doc).compactMap { $0.literal }
        #expect(texts == ["paragraph", "not code"])
        }
    }

    @Test("more than 4 spaces - extras are part of the content")
    func extraIndent() {
        let source = "        deeper"
        MarkdownDocument.withParsedDocument(source) { doc in
        let shape = dfs(doc)
        #expect(shape[1].kind.isCodeBlock)
        #expect(shape[1].literal == "    deeper\n")
        }
    }

    @Test("only 3 spaces is not a code block")
    func threeSpaces() {
        let source = "   foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .paragraph, .text])
        }
    }

    @Test("a four-space indent produces an indented (non-fenced) code block")
    func fourSpacesIsIndentedCodeBlock() {
        let source = "    let x = 1"
        MarkdownDocument.withParsedDocument(source) { doc in
        let shape = dfs(doc)
        #expect(shape.count == 2)
        #expect(shape[1].kind.isCodeBlock)
        #expect(shape[1].literal == "let x = 1\n")

        // The code block came from indentation, not a ``` / ~~~ fence.
        let root = doc.root
        var isFenced: Bool?
        root.children.forEach { child in
            if case .codeBlock(let info) = child.kind {
                isFenced = info.isFenced
            }
        }
        #expect(isFenced == false)
        }
    }
}

@Suite("Block parser - fenced code blocks")
struct FencedCodeTests {

    /// Helper that pulls codeBlockInfo from a MarkdownDocument's first child if it's a codeBlock.
    private static func codeInfo(_ doc: borrowing MarkdownDocument) -> (literal: String?, info: String?, fenced: Bool?) {
        var literal: String?
        var info: String?
        var fenced: Bool?
        let root = doc.root
        root.children.forEach { child in
            if case .codeBlock(let cbInfo) = child.kind {
                literal = child.literal()
                info = child.codeBlockInfoString()
                fenced = cbInfo.isFenced
            }
        }
        return (literal, info, fenced)
    }

    @Test("backtick fence")
    func backtickFence() {
        let source = "```\nfoo\n```"
        MarkdownDocument.withParsedDocument(source) { doc in
        let (literal, info, fenced) = Self.codeInfo(doc)
        #expect(fenced == true)
        #expect(literal == "foo\n")
        #expect(info == "")
        }
    }

    @Test("tilde fence")
    func tildeFence() {
        let source = "~~~\nfoo\n~~~"
        MarkdownDocument.withParsedDocument(source) { doc in
        let (literal, info, fenced) = Self.codeInfo(doc)
        #expect(fenced == true)
        #expect(literal == "foo\n")
        #expect(info == "")
        }
    }

    @Test("info string after backtick fence")
    func infoString() {
        let source = "```swift\nlet x = 1\n```"
        MarkdownDocument.withParsedDocument(source) { doc in
        let (literal, info, _) = Self.codeInfo(doc)
        #expect(info == "swift")
        #expect(literal == "let x = 1\n")
        }
    }

    @Test("info string in a tab-indented list item")
    func infoStringInTabIndentedListItem() {
        // The tab after `*` is expanded into a copy of the line, whose bytes are offset from the source. The
        // unindented ``` line opens a second, top-level fence with an empty info string.
        let source = "*\t```n\na\n```"
        MarkdownDocument.withParsedDocument(source) { doc in
            let blocks = codeBlocks(doc)
            #expect(blocks.map(\.info) == ["n", ""])
        }
    }

    @Test("unclosed info string in a tab-indented list item does not crash")
    func unclosedInfoStringInTabIndentedListItem() {
        // The tab-expanded copy of the line is longer than the source, and the info string runs to the end of
        // input.
        let source = "*\t```n"
        MarkdownDocument.withParsedDocument(source) { doc in
            let blocks = codeBlocks(doc)
            #expect(blocks.map(\.info) == ["n"])
        }
    }

    @Test("escaped info string in a tab-indented list item is decoded")
    func escapedInfoStringInTabIndentedListItem() {
        // Per Backslash escapes, `\+` in the info string is `+`.
        let source = "*\t```foo\\+bar\nx\n```"
        MarkdownDocument.withParsedDocument(source) { doc in
            let blocks = codeBlocks(doc)
            #expect(blocks.first?.info == "foo+bar")
        }
    }

    @Test("info string with trailing whitespace is trimmed")
    func infoTrimmed() {
        let source = "```   swift   \nbody\n```"
        MarkdownDocument.withParsedDocument(source) { doc in
        let (_, info, _) = Self.codeInfo(doc)
        #expect(info == "swift")
        }
    }

    @Test("backtick fence info may not contain backticks")
    func backticksInInfoRejected() {
        // A single line, because a later ``` line would open a fence of its own.
        let source = "```foo`bar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .paragraph, .text])
        }
    }

    @Test("tilde fence info may contain backticks")
    func backticksInTildeInfo() {
        let source = "~~~ foo`bar\nbody\n~~~"
        MarkdownDocument.withParsedDocument(source) { doc in
        let (_, info, _) = Self.codeInfo(doc)
        #expect(info == "foo`bar")
        }
    }

    @Test("4+ backticks are required to fence over a backtick info")
    func longerFence() {
        let source = "````\n```\n````"
        MarkdownDocument.withParsedDocument(source) { doc in
        let (literal, _, fenced) = Self.codeInfo(doc)
        #expect(fenced == true)
        #expect(literal == "```\n")
        }
    }

    @Test("closing fence must be at least as long as opening")
    func closingFenceLength() {
        // Closing `` ``` `` is too short for opening ` ```` `; body continues.
        let source = "````\nfoo\n```\nbar\n````"
        MarkdownDocument.withParsedDocument(source) { doc in
        let (literal, _, _) = Self.codeInfo(doc)
        #expect(literal == "foo\n```\nbar\n")
        }
    }

    @Test("missing closing fence is allowed (EOF closes the block)")
    func missingClosingFence() {
        let source = "```\nfoo\nbar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let (literal, _, fenced) = Self.codeInfo(doc)
        #expect(fenced == true)
        #expect(literal == "foo\nbar\n")
        }
    }

    @Test("up to 3 leading spaces on opening fence")
    func leadingSpaces() {
        let source = "   ```\nfoo\n```"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .fencedCode(offset: 3)])
        }
    }

    @Test("4+ leading spaces on opening fence becomes indented code")
    func tooManyLeadingSpaces() {
        let source = "    ```\nfoo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let (literal, _, fenced) = Self.codeInfo(doc)
        #expect(fenced == false)
        // Whole line goes in as indented code; subsequent "foo" is not in the block since it has no indent.
        #expect(literal == "```\n")
        }
    }

    @Test("empty body produces empty literal")
    func emptyBody() {
        let source = "```\n```"
        MarkdownDocument.withParsedDocument(source) { doc in
        let (literal, _, fenced) = Self.codeInfo(doc)
        #expect(fenced == true)
        // Spec: empty fenced body → empty literal (renders as `<pre><code></code></pre>`).
        #expect(literal == nil || literal == "")
        }
    }

    @Test("fenced code interrupts a paragraph")
    func interruptsParagraph() {
        let source = "paragraph\n```\ncode\n```"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .paragraph, .text, .fencedCode()])
        }
    }

    @Test("blank lines inside fenced code are preserved")
    func interiorBlanks() {
        let source = "```\nfoo\n\n\nbar\n```"
        MarkdownDocument.withParsedDocument(source) { doc in
        let (literal, _, _) = Self.codeInfo(doc)
        #expect(literal == "foo\n\n\nbar\n")
        }
    }

    @Test("indent stripping: body lines lose up to opening-fence offset of leading space")
    func indentStripping() {
        let source = "  ```\n  foo\n  bar\n  ```"
        MarkdownDocument.withParsedDocument(source) { doc in
        let (literal, _, _) = Self.codeInfo(doc)
        #expect(literal == "foo\nbar\n")
        }
    }
}

@Suite("Block parser - block quotes")
struct BlockQuoteTests {

    @Test("single quoted line")
    func single() {
        let source = "> foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .blockQuote, .paragraph, .text])
        let texts = dfs(doc).compactMap { $0.literal }
        #expect(texts == ["foo"])
        }
    }

    @Test("multiple quoted lines join into one paragraph")
    func multipleLines() {
        let source = "> foo\n> bar\n> baz"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .blockQuote, .paragraph, .text, .softBreak, .text, .softBreak, .text])
        let texts = dfs(doc).compactMap { $0.literal }
        #expect(texts == ["foo", "bar", "baz"])
        }
    }

    @Test("optional space after `>` is consumed")
    func spaceConsumed() {
        let source = ">foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let texts = dfs(doc).compactMap { $0.literal }
        #expect(texts == ["foo"])
        }
    }

    @Test("up to 3 leading spaces before `>` are allowed")
    func leadingSpaces() {
        let source = "   > foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .blockQuote, .paragraph, .text])
        }
    }

    @Test("4+ leading spaces is indented code, not block quote")
    func fourLeadingSpaces() {
        let source = "    > foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .indentedCode])
        }
    }

    @Test("lazy continuation: no `>` on subsequent paragraph line")
    func lazyContinuation() {
        let source = "> foo\nbar\nbaz"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .blockQuote, .paragraph, .text, .softBreak, .text, .softBreak, .text])
        let texts = dfs(doc).compactMap { $0.literal }
        #expect(texts == ["foo", "bar", "baz"])
        }
    }

    @Test("thematic break interrupts a quoted paragraph and closes the quote")
    func thematicBreakInterrupts() {
        let source = "> foo\n---"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        // Quote with paragraph "foo", then thematic break at document level.
        #expect(kinds == [
            .document,
            .blockQuote, .paragraph, .text,
            .thematicBreak,
        ])
        }
    }

    @Test("blank line without `>` closes the quote")
    func blankClosesQuote() {
        let source = "> foo\n\n> bar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        // Two separate quotes.
        #expect(kinds == [
            .document,
            .blockQuote, .paragraph, .text,
            .blockQuote, .paragraph, .text,
        ])
        }
    }

    @Test("blank line with `>` keeps the quote open")
    func blankWithMarkerKeepsOpen() {
        let source = "> foo\n>\n> bar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        // One quote with two paragraphs.
        #expect(kinds == [
            .document,
            .blockQuote,
            .paragraph, .text,
            .paragraph, .text,
        ])
        }
    }

    @Test("nested block quotes")
    func nested() {
        let source = "> > foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [
            .document,
            .blockQuote,
            .blockQuote,
            .paragraph, .text,
        ])
        }
    }

    @Test("block quote can contain a heading")
    func containsHeading() {
        let source = "> # foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [
            .document,
            .blockQuote,
            .heading(level: 1), .text,
        ])
        }
    }

    @Test("setext heading inside a quote when underline is also quoted")
    func setextInside() {
        let source = "> Title\n> ---"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [
            .document,
            .blockQuote,
            .heading(level: 2), .text,
        ])
        }
    }

    @Test("block quote can contain a fenced code block")
    func containsFencedCode() {
        let source = "> ```\n> foo\n> ```"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .blockQuote, .fencedCode()])
        }
    }

    @Test("quote followed by separate paragraph at document level")
    func separateParagraphAfter() {
        let source = "> foo\n\nbar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [
            .document,
            .blockQuote, .paragraph, .text,
            .paragraph, .text,
        ])
        }
    }
}

@Suite("Block parser - lists")
struct ListTests {

    @Test("single bullet item with hyphen")
    func bulletHyphen() {
        let source = "- foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .bulletList(), .item(checked: nil), .paragraph, .text])
        let texts = dfs(doc).compactMap { $0.literal }
        #expect(texts == ["foo"])
        }
    }

    @Test("a block quote after list items closes the list (block quotes can't be list children)")
    func blockQuoteInterruptsList() {
        let source = "1. eggs\n1. milk\n> quote\n1. flour\n"
        MarkdownDocument.withParsedDocument(source) { doc in
        // The block quote is a top-level sibling between two separate lists, not nested in the first.
        var topKinds: [MarkdownNode.Kind] = []
        let root = doc.root
        root.children.forEach { topKinds.append($0.kind) }
        #expect(topKinds == [.orderedList(), .blockQuote, .orderedList()])
        }
    }

    @Test("single bullet item with plus")
    func bulletPlus() {
        let source = "+ foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .bulletList(.plus), .item(checked: nil), .paragraph, .text])
        }
    }

    @Test("single bullet item with asterisk")
    func bulletAsterisk() {
        let source = "* foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .bulletList(.asterisk), .item(checked: nil), .paragraph, .text])
        }
    }

    @Test("ordered item with period")
    func orderedPeriod() {
        let source = "1. foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .orderedList(), .item(checked: nil), .paragraph, .text])
        var listKind: MarkdownNode.ListInfo.Kind?
        var listStart: Int?
        let root = doc.root
        root.children.forEach { list in
            if case .list(let info) = list.kind {
                listKind = info.kind
                listStart = info.start
            }
        }
        #expect(listKind == .ordered)
        #expect(listStart == 1)
        }
    }

    @Test("ordered item with paren")
    func orderedParen() {
        let source = "1) foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .orderedList(.paren), .item(checked: nil), .paragraph, .text])
        var listDelim: MarkdownNode.ListInfo.OrderedDelimiter?
        let root = doc.root
        root.children.forEach { list in
            if case .list(let info) = list.kind { listDelim = info.orderedDelimiter }
        }
        #expect(listDelim == .paren)
        }
    }

    @Test("ordered list starting at non-1")
    func orderedStart() {
        let source = "5. foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        var listStart: Int?
        let root = doc.root
        root.children.forEach { list in
            if case .list(let info) = list.kind { listStart = info.start }
        }
        #expect(listStart == 5)
        }
    }

    @Test("multiple bullet items in one list")
    func multipleItems() {
        let source = "- foo\n- bar\n- baz"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [
            .document,
            .bulletList(),
            .item(checked: nil), .paragraph, .text,
            .item(checked: nil), .paragraph, .text,
            .item(checked: nil), .paragraph, .text,
        ])
        }
    }

    @Test("bullet markers of different chars start separate lists")
    func differentMarkers() {
        let source = "- foo\n+ bar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [
            .document,
            .bulletList(), .item(checked: nil), .paragraph, .text,
            .bulletList(.plus), .item(checked: nil), .paragraph, .text,
        ])
        }
    }

    @Test("ordered after bullet starts new list")
    func bulletThenOrdered() {
        let source = "- foo\n1. bar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [
            .document,
            .bulletList(), .item(checked: nil), .paragraph, .text,
            .orderedList(), .item(checked: nil), .paragraph, .text,
        ])
        }
    }

    @Test("indented continuation line stays in the item")
    func indentedContinuation() {
        let source = "- foo\n  bar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        // Item with paragraph "foo" + softBreak + "bar" (continuation indented to match item padding).
        #expect(kinds == [
            .document,
            .bulletList(), .item(checked: nil), .paragraph, .text, .softBreak, .text,
        ])
        let texts = dfs(doc).compactMap { $0.literal }
        #expect(texts == ["foo", "bar"])
        }
    }

    @Test("nested list via deeper indent")
    func nested() {
        let source = "- a\n  - b"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        // Outer list → outer item → paragraph "a", then nested list → nested item → paragraph "b".
        #expect(kinds == [
            .document,
            .bulletList(),
            .item(checked: nil), .paragraph, .text,
            .bulletList(),
            .item(checked: nil), .paragraph, .text,
        ])
        }
    }

    @Test("`- - -` is a thematic break, not nested lists")
    func dashSpaceDashIsThematic() {
        let source = "- - -"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .thematicBreak])
        }
    }

    @Test("list marker without content is a valid empty item")
    func emptyItem() {
        let source = "-"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .bulletList(), .item(checked: nil)])
        }
    }

    @Test("list interrupts a paragraph (only when first ordered start is 1)")
    func interruptsParagraph() {
        let source = "paragraph\n- bullet"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [
            .document,
            .paragraph, .text,
            .bulletList(), .item(checked: nil), .paragraph, .text,
        ])
        }
    }

    @Test("ordered list with start != 1 does NOT interrupt a paragraph")
    func orderedNon1DoesNotInterrupt() {
        let source = "paragraph\n5. not a list"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .paragraph, .text, .softBreak, .text])
        }
    }
}

@Suite("Block parser - HTML blocks")
struct HTMLBlockTests {

    @Test("type 1: pre tag")
    func type1Pre() {
        let source = "<pre>\nfoo\n</pre>"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .htmlBlock])
        let texts = dfs(doc).compactMap { $0.literal }
        #expect(texts == ["<pre>\nfoo\n</pre>\n"])
        }
    }

    @Test("type 1: script tag, end on closing tag")
    func type1Script() {
        let source = "<script>\nvar x = 1;\n</script>\n\nparagraph"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .htmlBlock, .paragraph, .text])
        }
    }

    @Test("type 2: HTML comment")
    func type2Comment() {
        let source = "<!-- comment -->\nnext paragraph"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .htmlBlock, .paragraph, .text])
        let texts = dfs(doc).compactMap { $0.literal }
        #expect(texts == ["<!-- comment -->\n", "next paragraph"])
        }
    }

    @Test("type 2: multi-line comment")
    func type2MultilineComment() {
        let source = "<!--\nline 1\nline 2\n-->"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .htmlBlock])
        let texts = dfs(doc).compactMap { $0.literal }
        #expect(texts == ["<!--\nline 1\nline 2\n-->\n"])
        }
    }

    @Test("type 3: processing instruction")
    func type3PI() {
        let source = "<?php echo 1; ?>"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .htmlBlock])
        }
    }

    @Test("type 4: declaration")
    func type4Declaration() {
        let source = "<!DOCTYPE html>"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .htmlBlock])
        }
    }

    @Test("type 4: requires an uppercase ASCII letter after `<!`")
    func type4RequiresUppercaseLetter() {
        MarkdownDocument.withParsedDocument("<!Baz") { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .htmlBlock])
        }
        MarkdownDocument.withParsedDocument("<!baz") { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .paragraph, .text])
        }
    }

    @Test("type 5: CDATA")
    func type5CDATA() {
        let source = "<![CDATA[\nfoo\n]]>"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .htmlBlock])
        }
    }

    @Test("type 6: standard block tag, ends on blank line")
    func type6BlockTag() {
        let source = "<div>\nfoo\n</div>\n\nparagraph"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .htmlBlock, .paragraph, .text])
        let texts = dfs(doc).compactMap { $0.literal }
        #expect(texts == ["<div>\nfoo\n</div>\n", "paragraph"])
        }
    }

    @Test("type 6: closing tag form")
    func type6ClosingTag() {
        let source = "</div>\nfoo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .htmlBlock])
        }
    }

    @Test("type 6: self-closing form")
    func type6SelfClosing() {
        let source = "<hr/>"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .htmlBlock])
        }
    }

    @Test("type 6 with up to 3 leading spaces")
    func type6LeadingSpaces() {
        let source = "   <div>\nbody\n</div>"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .htmlBlock])
        }
    }

    @Test("4+ leading spaces is indented code, not HTML block")
    func tooManyLeadingSpaces() {
        let source = "    <div>"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .indentedCode])
        }
    }

    @Test("non-block-tag like <foo> does not start a type-6 block")
    func nonBlockTagIsParagraph() {
        let source = "<foo>\nbar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        // `<foo>` is a complete open tag alone on its line, so it starts a type 7 HTML block, which ends at a blank
        // line and so includes `bar`.
        #expect(kinds == [.document, .htmlBlock])
        }
    }

    @Test("HTML block interrupts a paragraph")
    func interruptsParagraph() {
        let source = "paragraph\n<div>\nbody\n</div>"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .paragraph, .text, .htmlBlock])
        }
    }

    @Test("HTML block start and end on the same line")
    func sameLineEnd() {
        let source = "<!-- foo -->"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .htmlBlock])
        let texts = dfs(doc).compactMap { $0.literal }
        #expect(texts == ["<!-- foo -->\n"])
        }
    }

    // Line tabulation and form feed are whitespace characters (Characters and lines), so they end a tag name
    // as a space does.

    @Test("type 1: form feed after a raw-text tag name starts an HTML block")
    func type1FormFeedWhitespace() {
        let source = "<pre\u{0C}>"
        MarkdownDocument.withParsedDocument(source) { doc in
            let kinds = dfs(doc).map { $0.kind }
            #expect(kinds == [.document, .htmlBlock])
        }
    }

    @Test("type 6: vertical tab / form feed after a block tag name starts an HTML block")
    func type6VerticalTabFormFeed() {
        for source in ["<div\u{0C}>", "<div\u{0B}>"] {
            MarkdownDocument.withParsedDocument(source) { doc in
                let kinds = dfs(doc).map { $0.kind }
                #expect(kinds == [.document, .htmlBlock], "\(source.debugDescription) should be an HTML block")
            }
        }
    }

    @Test("type 7: form feed as intra-tag whitespace starts an HTML block")
    func type7FormFeedWhitespace() {
        let source = "<a\u{0C}ref=\"x\">"
        MarkdownDocument.withParsedDocument(source) { doc in
            let kinds = dfs(doc).map { $0.kind }
            #expect(kinds == [.document, .htmlBlock])
        }
    }

    // After a type 7 open tag, the rest of the line may hold spaces, tabs and form feeds, but not a line
    // tabulation.
    @Test("type 7: form feed trailing the tag starts an HTML block")
    func type7TrailingFormFeed() {
        MarkdownDocument.withParsedDocument("<a>\u{0C}") { doc in
            let kinds = dfs(doc).map { $0.kind }
            #expect(kinds == [.document, .htmlBlock])
        }
    }

    @Test("type 7: vertical tab trailing the tag does not start an HTML block")
    func type7TrailingVerticalTabIsParagraph() {
        MarkdownDocument.withParsedDocument("<a>\u{0B}") { doc in
            let kinds = dfs(doc).map { $0.kind }
            #expect(kinds.contains(.paragraph) && !kinds.contains(.htmlBlock))
        }
    }

    // An unquoted attribute value is nonempty, while a quoted one may be empty (Raw HTML).
    @Test("type 7: empty unquoted attribute value does not start an HTML block")
    func type7EmptyUnquotedValueIsParagraph() {
        for source in ["<a b=>", "<a b= >"] {
            MarkdownDocument.withParsedDocument(source) { doc in
                let kinds = dfs(doc).map { $0.kind }
                #expect(kinds.contains(.paragraph) && !kinds.contains(.htmlBlock),
                        "\(source.debugDescription) should be a paragraph, not an HTML block")
            }
        }
    }

    @Test("type 7: non-empty unquoted and empty quoted attribute values start an HTML block")
    func type7NonEmptyAndQuotedValueIsHTMLBlock() {
        for source in ["<a b=c>", "<a b=\"\">"] {
            MarkdownDocument.withParsedDocument(source) { doc in
                let kinds = dfs(doc).map { $0.kind }
                #expect(kinds == [.document, .htmlBlock],
                        "\(source.debugDescription) should be an HTML block")
            }
        }
    }
}

@Suite("Reference link definitions")
struct ReferenceDefinitionTests {

    /// Decode a `Chunk` against the document's storage/source. Adapted for tests because `MarkdownNode.url()`/`literal()` are kind-specific accessors.
    private static func decodeChunk(
        _ chunk: Chunk,
        doc: borrowing MarkdownDocument
    ) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(chunk.length)
        if chunk.inSource {
            let span = doc._source
            for i in 0..<chunk.length {
                bytes.append(span[chunk.offset + i])
            }
        } else {
            for i in 0..<chunk.length {
                bytes.append(doc._storage.strings[chunk.offset + i])
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    @Test("standalone definition produces no paragraph node")
    func standaloneDefinition() throws {
        let source = "[foo]: /url"
        try MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document])
        #expect(doc._storage.referenceMap.count == 1)
        let entry = try #require(doc._storage.referenceMap["foo"])
        #expect(Self.decodeChunk(entry.destination, doc: doc) == "/url")
        #expect(entry.title.isEmpty)
        }
    }

    @Test("definition with double-quoted title")
    func doubleQuotedTitle() throws {
        let source = "[foo]: /url \"the title\""
        try MarkdownDocument.withParsedDocument(source) { doc in
        #expect(dfs(doc).map(\.kind) == [.document])
        let entry = try #require(doc._storage.referenceMap["foo"])
        #expect(Self.decodeChunk(entry.destination, doc: doc) == "/url")
        #expect(Self.decodeChunk(entry.title, doc: doc) == "the title")
        }
    }

    @Test("definition with single-quoted title")
    func singleQuotedTitle() throws {
        let source = "[foo]: /url 'the title'"
        try MarkdownDocument.withParsedDocument(source) { doc in
        let entry = try #require(doc._storage.referenceMap["foo"])
        #expect(Self.decodeChunk(entry.title, doc: doc) == "the title")
        }
    }

    @Test("definition with paren title")
    func parenTitle() throws {
        let source = "[foo]: /url (the title)"
        try MarkdownDocument.withParsedDocument(source) { doc in
        let entry = try #require(doc._storage.referenceMap["foo"])
        #expect(Self.decodeChunk(entry.title, doc: doc) == "the title")
        }
    }

    @Test("title on next line")
    func titleOnNextLine() throws {
        let source = "[foo]: /url\n   \"the title\""
        try MarkdownDocument.withParsedDocument(source) { doc in
        #expect(dfs(doc).map(\.kind) == [.document])
        let entry = try #require(doc._storage.referenceMap["foo"])
        #expect(Self.decodeChunk(entry.destination, doc: doc) == "/url")
        #expect(Self.decodeChunk(entry.title, doc: doc) == "the title")
        }
    }

    @Test("angle-bracketed destination")
    func angleBracketedDestination() throws {
        let source = "[foo]: <http://example.com/path>"
        try MarkdownDocument.withParsedDocument(source) { doc in
        let entry = try #require(doc._storage.referenceMap["foo"])
        #expect(Self.decodeChunk(entry.destination, doc: doc) == "http://example.com/path")
        }
    }

    @Test("multiple definitions in a row, no surviving paragraph")
    func multipleDefs() {
        let source = "[a]: /1\n[b]: /2 \"two\"\n[c]: /3"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(dfs(doc).map(\.kind) == [.document])
        #expect(doc._storage.referenceMap.count == 3)
        #expect(Self.decodeChunk(doc._storage.referenceMap["a"]!.destination, doc: doc) == "/1")
        #expect(Self.decodeChunk(doc._storage.referenceMap["b"]!.destination, doc: doc) == "/2")
        #expect(Self.decodeChunk(doc._storage.referenceMap["b"]!.title, doc: doc) == "two")
        #expect(Self.decodeChunk(doc._storage.referenceMap["c"]!.destination, doc: doc) == "/3")
        }
    }

    @Test("definition followed by paragraph content")
    func defThenParagraph() {
        let source = "[foo]: /url\n\nhello"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map(\.kind)
        // MarkdownDocument then a single paragraph for "hello".
        #expect(kinds == [.document, .paragraph, .text])
        #expect(doc._storage.referenceMap["foo"] != nil)
        let texts = dfs(doc).compactMap(\.literal)
        #expect(texts == ["hello"])
        }
    }

    @Test("definition then paragraph with no blank line between")
    func defThenInlineParagraph() {
        let source = "[foo]: /url\nhello"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map(\.kind)
        #expect(kinds == [.document, .paragraph, .text])
        #expect(doc._storage.referenceMap["foo"] != nil)
        }
    }

    @Test("first definition wins for duplicate labels")
    func duplicateLabelsFirstWins() throws {
        let source = "[foo]: /first\n[foo]: /second"
        try MarkdownDocument.withParsedDocument(source) { doc in
        let entry = try #require(doc._storage.referenceMap["foo"])
        #expect(Self.decodeChunk(entry.destination, doc: doc) == "/first")
        }
    }

    @Test("label normalization: case-fold and collapse whitespace")
    func labelNormalization() {
        let source = "[Foo Bar]: /url"
        MarkdownDocument.withParsedDocument(source) { doc in
        // Stored under normalized key.
        #expect(doc._storage.referenceMap["foo bar"] != nil)
        // Unnormalized key not present.
        #expect(doc._storage.referenceMap["Foo Bar"] == nil)
        }
    }

    @Test("invalid definition: empty label stays as paragraph")
    func invalidEmptyLabel() {
        let source = "[]: /url"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map(\.kind)
        #expect(kinds.contains(.paragraph))
        #expect(doc._storage.referenceMap.isEmpty)
        }
    }

    @Test("invalid definition: missing destination stays as paragraph")
    func invalidMissingDestination() {
        let source = "[foo]:"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map(\.kind)
        #expect(kinds.contains(.paragraph))
        #expect(doc._storage.referenceMap.isEmpty)
        }
    }

    @Test("text after the title on its line leaves no definition")
    func titleWithTrailingJunk() {
        // Per Link reference definitions, only spaces or tabs may follow the title on its line. Without the title,
        // the destination is followed by other text on its line, so there is no definition.
        let source = "[foo]: /url \"title\" extra\n\nhello"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(doc._storage.referenceMap["foo"] == nil)
        #expect(dfs(doc).map(\.kind).contains(.paragraph))
        }
    }
}

@Suite("GFM extensions - tasklist")
struct TasklistTests {

    /// Find the first list item and return its `isChecked` state plus the first text node's literal. Returns `(nil, nil)` if no item found.
    private static func firstItem(_ doc: borrowing MarkdownDocument) -> (checked: Bool?, text: String?) {
        var checked: Bool? = nil
        var text: String? = nil
        var found = false
        let root = doc.root
        root.children.forEach { block in
            if found { return }
            visit(block, into: &checked, &text, &found)
        }
        return (checked, text)
    }

    private static func visit(
        _ node: borrowing MarkdownNode,
        into checked: inout Bool?,
        _ text: inout String?,
        _ found: inout Bool
    ) {
        if found { return }
        if case .item(let isChecked) = node.kind {
            checked = isChecked
            collectFirstText(node, into: &text)
            found = true
            return
        }
        node.children.forEach { child in
            visit(child, into: &checked, &text, &found)
        }
    }

    private static func collectFirstText(_ node: borrowing MarkdownNode, into out: inout String?) {
        if out != nil { return }
        if let lit = node.literal() {
            out = lit
            return
        }
        node.children.forEach { child in
            collectFirstText(child, into: &out)
        }
    }

    @Test("without the tasklist option, [ ] is text in the item")
    func defaultDisabled() {
        let source = "- [ ] foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let info = Self.firstItem(doc)
        #expect(info.checked == nil)
        }
    }

    @Test("unchecked: - [ ] foo")
    func uncheckedItem() {
        let source = "- [ ] foo"
        MarkdownDocument.withParsedDocument(source, options: .tasklist) { doc in
        let info = Self.firstItem(doc)
        #expect(info.checked == false)
        #expect(info.text == "foo")
        }
    }

    @Test("checked: - [x] foo")
    func checkedItemLowercase() {
        let source = "- [x] foo"
        MarkdownDocument.withParsedDocument(source, options: .tasklist) { doc in
        let info = Self.firstItem(doc)
        #expect(info.checked == true)
        #expect(info.text == "foo")
        }
    }

    @Test("checked: - [X] foo")
    func checkedItemUppercase() {
        let source = "- [X] foo"
        MarkdownDocument.withParsedDocument(source, options: .tasklist) { doc in
        let info = Self.firstItem(doc)
        #expect(info.checked == true)
        #expect(info.text == "foo")
        }
    }

    @Test("checked: ordered list 1. [x] foo")
    func checkedOrderedItem() {
        let source = "1. [x] foo"
        MarkdownDocument.withParsedDocument(source, options: .tasklist) { doc in
        let info = Self.firstItem(doc)
        #expect(info.checked == true)
        }
    }

    @Test("non-marker [ y ] stays as paragraph text")
    func notATaskMarker() {
        let source = "- [y] foo"
        MarkdownDocument.withParsedDocument(source, options: .tasklist) { doc in
        let info = Self.firstItem(doc)
        #expect(info.checked == nil)
        }
    }

    @Test("multiple task items in one list")
    func multipleItems() {
        let source = "- [ ] one\n- [x] two\n- [ ] three"
        MarkdownDocument.withParsedDocument(source, options: .tasklist) { doc in
        var states: [Bool?] = []
        let root = doc.root
        root.children.forEach { block in
            block.children.forEach { item in
                if case .item(let checked) = item.kind {
                    states.append(checked)
                }
            }
        }
        #expect(states == [false, true, false])
        }
    }

    @Test("non-first paragraph in item is not a task marker")
    func nonFirstParagraphIsNotMarker() {
        // Per Task list items (extension), only the item's first block can begin with the marker.
        let source = "- foo\n\n  [ ] bar"
        MarkdownDocument.withParsedDocument(source, options: .tasklist) { doc in
        let info = Self.firstItem(doc)
        #expect(info.checked == nil)
        }
    }
}

@Suite("GFM extensions - tables")
struct TableTests {

    /// Walks the doc and pulls (kind, alignment-or-text) for the first table found. Returns rows of cells: each row is an array of `(alignment: TableAlignment?, text: String?)`.
    private static func firstTable(_ doc: borrowing MarkdownDocument) -> [[(MarkdownNode.TableAlignment?, String?)]] {
        var rows: [[(MarkdownNode.TableAlignment?, String?)]] = []
        var foundTable = false
        let root = doc.root
        root.children.forEach { block in
            if foundTable { return }
            if block.kind == .table {
                foundTable = true
                block.children.forEach { row in
                    if case .tableRow = row.kind {
                        var cells: [(MarkdownNode.TableAlignment?, String?)] = []
                        row.children.forEach { cell in
                            if case .tableCell(let alignment, _, _) = cell.kind {
                                var text: String?
                                cell.children.forEach { inline in
                                    if text == nil, let lit = inline.literal() {
                                        text = lit
                                    }
                                }
                                cells.append((alignment, text))
                            }
                        }
                        rows.append(cells)
                    }
                }
            }
        }
        return rows
    }

    @Test("without the tables option, pipe lines are a paragraph")
    func defaultDisabled() {
        let source = "| a | b |\n|---|---|\n| 1 | 2 |"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map(\.kind)
        #expect(!kinds.contains(.table))
        }
    }

    @Test("simple table with delim row")
    func simpleTable() {
        let source = "| a | b |\n|---|---|\n| 1 | 2 |"
        MarkdownDocument.withParsedDocument(source, options: .tables) { doc in
        let rows = Self.firstTable(doc)
        #expect(rows.count == 2)
        #expect(rows[0].map { $0.1 } == ["a", "b"])
        #expect(rows[1].map { $0.1 } == ["1", "2"])
        }
    }

    @Test("alignments: left, right, center, none")
    func alignments() {
        let source = "| a | b | c | d |\n|:--|---|--:|:-:|\n| 1 | 2 | 3 | 4 |"
        MarkdownDocument.withParsedDocument(source, options: .tables) { doc in
        let rows = Self.firstTable(doc)
        let aligns = rows[0].map { $0.0 }
        let expected: [MarkdownNode.TableAlignment?] = [.left, MarkdownNode.TableAlignment.none, .right, .center]
        #expect(aligns == expected)
        }
    }

    @Test("optional outer pipes")
    func noPipesOnEnds() {
        let source = "a | b\n---|---\n1 | 2"
        MarkdownDocument.withParsedDocument(source, options: .tables) { doc in
        let rows = Self.firstTable(doc)
        #expect(rows.count == 2)
        #expect(rows[0].map { $0.1 } == ["a", "b"])
        #expect(rows[1].map { $0.1 } == ["1", "2"])
        }
    }

    @Test("missing trailing cells are filled empty")
    func missingCells() {
        let source = "| a | b | c |\n|---|---|---|\n| 1 | 2 |"
        MarkdownDocument.withParsedDocument(source, options: .tables) { doc in
        let rows = Self.firstTable(doc)
        #expect(rows[1].count == 3)
        #expect(rows[1].map { $0.1 } == ["1", "2", nil])
        }
    }

    @Test("extra cells are dropped")
    func extraCells() {
        let source = "| a | b |\n|---|---|\n| 1 | 2 | 3 | 4 |"
        MarkdownDocument.withParsedDocument(source, options: .tables) { doc in
        let rows = Self.firstTable(doc)
        #expect(rows[1].count == 2)
        #expect(rows[1].map { $0.1 } == ["1", "2"])
        }
    }

    @Test("malformed delim row stays as paragraph")
    func malformedDelim() {
        let source = "| a | b |\n| not | delim |\n| 1 | 2 |"
        MarkdownDocument.withParsedDocument(source, options: .tables) { doc in
        let kinds = dfs(doc).map(\.kind)
        #expect(!kinds.contains(.table))
        }
    }

    @Test("inline content in cells is parsed")
    func inlineInCells() {
        let source = "| *em* | **strong** |\n|---|---|\n| `code` | text |"
        MarkdownDocument.withParsedDocument(source, options: .tables) { doc in
        var sawEmphasis = false
        var sawStrong = false
        var sawCode = false
        let root = doc.root
        root.children.forEach { block in
            if block.kind == .table {
                block.children.forEach { row in
                    row.children.forEach { cell in
                        cell.children.forEach { inline in
                            if inline.kind == .emphasis { sawEmphasis = true }
                            if inline.kind == .strong { sawStrong = true }
                            if case .codeInline = inline.kind { sawCode = true }
                        }
                    }
                }
            }
        }
        #expect(sawEmphasis)
        #expect(sawStrong)
        #expect(sawCode)
        }
    }

    @Test("header-only table (no body rows) is valid")
    func headerOnly() {
        let source = "| a | b |\n|---|---|"
        MarkdownDocument.withParsedDocument(source, options: .tables) { doc in
        let rows = Self.firstTable(doc)
        #expect(rows.count == 1)
        #expect(rows[0].map { $0.1 } == ["a", "b"])
        }
    }

    @Test("table column count is recorded")
    func columnCount() {
        let source = "| a | b | c |\n|---|---|---|"
        MarkdownDocument.withParsedDocument(source, options: .tables) { doc in
        var foundCols: Int?
        let root = doc.root
        root.children.forEach { block in
            if block.kind == .table {
                if case .table(let cols, _) = doc._storage[block._index].data {
                    foundCols = cols
                }
            }
        }
        #expect(foundCols == 3)
        }
    }
}
