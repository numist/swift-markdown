/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A node's kind, with a list's or code block's metadata as the values of its public fields, so expected trees can be
/// written as literals.
private enum NodeShape: Equatable {
    case other(MarkdownNode.Kind)
    case list(
        MarkdownNode.ListInfo.Kind,
        start: Int,
        MarkdownNode.ListInfo.OrderedDelimiter,
        MarkdownNode.ListInfo.BulletMarker,
        tight: Bool
    )
    case codeBlock(fenced: Bool, MarkdownNode.CodeBlockInfo.FenceCharacter?, length: Int, offset: Int)

    init(_ kind: MarkdownNode.Kind) {
        switch kind {
        case .list(let info):
            self = .list(info.kind, start: info.start, info.orderedDelimiter, info.bulletMarker, tight: info.tight)
        case .codeBlock(let info):
            self = .codeBlock(fenced: info.isFenced, info.fenceCharacter, length: info.fenceLength, offset: info.fenceOffset)
        default:
            self = .other(kind)
        }
    }

    static func bulletList(
        _ marker: MarkdownNode.ListInfo.BulletMarker = .hyphen,
        tight: Bool = true
    ) -> NodeShape {
        .list(.bullet, start: 1, .period, marker, tight: tight)
    }

    static func orderedList(
        start: Int = 1,
        _ delimiter: MarkdownNode.ListInfo.OrderedDelimiter = .period,
        tight: Bool = true
    ) -> NodeShape {
        .list(.ordered, start: start, delimiter, .hyphen, tight: tight)
    }

    /// An indented (non-fenced) code block.
    static let indentedCode = NodeShape.codeBlock(fenced: false, nil, length: 0, offset: 0)

    /// A fenced code block.
    static func fencedCode(
        _ character: MarkdownNode.CodeBlockInfo.FenceCharacter = .backtick,
        length: Int = 3,
        offset: Int = 0
    ) -> NodeShape {
        .codeBlock(fenced: true, character, length: length, offset: offset)
    }

    static let document = NodeShape.other(.document)
    static let blockQuote = NodeShape.other(.blockQuote)
    static let paragraph = NodeShape.other(.paragraph)
    static let text = NodeShape.other(.text)
    static let softBreak = NodeShape.other(.softBreak)

    static func item(checked: Bool?) -> NodeShape {
        .other(.item(checked: checked))
    }
}

/// The shape of every node in the document, depth-first.
private func shapes(_ doc: borrowing MarkdownDocument) -> [NodeShape] {
    dfs(doc).map { NodeShape($0.kind) }
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
        let kinds = shapes(doc)
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
        MarkdownDocument.withParsedDocument("*\t*\t*") { doc in
        #expect(dfs(doc).map { $0.kind } == [.document, .thematicBreak])
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
        let kinds = shapes(doc)
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
        #expect(NodeShape(shape[1].kind) == .indentedCode)
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
        #expect(NodeShape(shape[1].kind) == .indentedCode)
        #expect(shape[1].literal == "foo\nbar\nbaz\n")
        }
    }

    @Test("blank lines within indented code are preserved")
    func interiorBlankLines() {
        let source = "    foo\n\n    bar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let shape = dfs(doc)
        #expect(NodeShape(shape[1].kind) == .indentedCode)
        #expect(shape[1].literal == "foo\n\nbar\n")
        }
    }

    @Test("trailing blank lines are stripped from indented code")
    func trailingBlankLines() {
        let source = "    foo\n\n\n"
        MarkdownDocument.withParsedDocument(source) { doc in
        let shape = dfs(doc)
        #expect(NodeShape(shape[1].kind) == .indentedCode)
        #expect(shape[1].literal == "foo\n")
        }
    }

    @Test("non-indented non-blank line closes the code block")
    func paragraphAfter() {
        let source = "    code\nparagraph"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = shapes(doc)
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
        #expect(NodeShape(shape[1].kind) == .indentedCode)
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
        #expect(NodeShape(shape[1].kind) == .indentedCode)
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

    @Test("a three-backtick line inside a four-backtick fence is content")
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
        let kinds = shapes(doc)
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
        #expect(literal == "")
        }
    }

    @Test("fenced code interrupts a paragraph")
    func interruptsParagraph() {
        let source = "paragraph\n```\ncode\n```"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = shapes(doc)
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

    @Test("the space after `>` is optional")
    func spaceOptional() {
        let source = ">foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let texts = dfs(doc).compactMap { $0.literal }
        #expect(texts == ["foo"])
        }
    }

    @Test("the optional space after `>` is consumed")
    func spaceConsumed() {
        let source = ">     code"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = shapes(doc)
        #expect(kinds == [.document, .blockQuote, .indentedCode])
        let texts = dfs(doc).compactMap { $0.literal }
        #expect(texts == ["code\n"])
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
        let kinds = shapes(doc)
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
        let kinds = shapes(doc)
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
        let kinds = shapes(doc)
        #expect(kinds == [.document, .bulletList(), .item(checked: nil), .paragraph, .text])
        let texts = dfs(doc).compactMap { $0.literal }
        #expect(texts == ["foo"])
        }
    }

    @Test("an unindented block quote after list items closes the list")
    func blockQuoteInterruptsList() {
        let source = "1. eggs\n1. milk\n> quote\n1. flour\n"
        MarkdownDocument.withParsedDocument(source) { doc in
        // The block quote is a top-level sibling between two separate lists, not nested in the first.
        var topKinds: [NodeShape] = []
        let root = doc.root
        root.children.forEach { topKinds.append(NodeShape($0.kind)) }
        #expect(topKinds == [.orderedList(), .blockQuote, .orderedList()])
        }
    }

    @Test("single bullet item with plus")
    func bulletPlus() {
        let source = "+ foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = shapes(doc)
        #expect(kinds == [.document, .bulletList(.plus), .item(checked: nil), .paragraph, .text])
        }
    }

    @Test("single bullet item with asterisk")
    func bulletAsterisk() {
        let source = "* foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = shapes(doc)
        #expect(kinds == [.document, .bulletList(.asterisk), .item(checked: nil), .paragraph, .text])
        }
    }

    @Test("ordered item with period")
    func orderedPeriod() {
        let source = "1. foo"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = shapes(doc)
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
        let kinds = shapes(doc)
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
        let kinds = shapes(doc)
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
        let kinds = shapes(doc)
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
        let kinds = shapes(doc)
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
        let kinds = shapes(doc)
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
        let kinds = shapes(doc)
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
        let kinds = shapes(doc)
        #expect(kinds == [.document, .bulletList(), .item(checked: nil)])
        }
    }

    @Test("list interrupts a paragraph (only when first ordered start is 1)")
    func interruptsParagraph() {
        let source = "paragraph\n- bullet"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = shapes(doc)
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
        let kinds = shapes(doc)
        #expect(kinds == [.document, .indentedCode])
        }
    }

    @Test("type 7: a complete open tag whose name is not a type 6 tag name")
    func type7NonBlockTag() {
        let source = "<foo>\nbar"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        // `<foo>` is a complete open tag alone on its line, so it starts a type 7 HTML block, which ends at a blank
        // line and so includes `bar`.
        #expect(kinds == [.document, .htmlBlock])
        }
        // A type 7 HTML block cannot interrupt a paragraph.
        MarkdownDocument.withParsedDocument("x\n<foo>") { doc in
        #expect(dfs(doc).map { $0.kind } == [.document, .paragraph, .text, .softBreak, .htmlInline])
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
}

@Suite("Reference link definitions")
struct ReferenceDefinitionTests {

    /// The destination and title of a link.
    private struct LinkTarget: Equatable {
        var url: String?
        var title: String?
    }

    /// The destination and title of every link in the document, depth-first.
    private static func links(_ doc: borrowing MarkdownDocument) -> [LinkTarget] {
        var out: [LinkTarget] = []
        func visit(_ node: borrowing MarkdownNode) {
            if node.kind == .link {
                out.append(LinkTarget(url: node.url(), title: node.title()))
            }
            node.children.forEach { visit($0) }
        }
        visit(doc.root)
        return out
    }

    @Test("standalone definition produces no paragraph node")
    func standaloneDefinition() {
        let source = "[foo]: /url\n\n[foo]"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map { $0.kind }
        #expect(kinds == [.document, .paragraph, .link, .text])
        #expect(Self.links(doc) == [LinkTarget(url: "/url", title: "")])
        }
    }

    @Test("definition with double-quoted title")
    func doubleQuotedTitle() {
        let source = "[foo]: /url \"the title\"\n\n[foo]"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(dfs(doc).map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(Self.links(doc) == [LinkTarget(url: "/url", title: "the title")])
        }
    }

    @Test("definition with single-quoted title")
    func singleQuotedTitle() {
        let source = "[foo]: /url 'the title'\n\n[foo]"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(Self.links(doc) == [LinkTarget(url: "/url", title: "the title")])
        }
    }

    @Test("definition with paren title")
    func parenTitle() {
        let source = "[foo]: /url (the title)\n\n[foo]"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(Self.links(doc) == [LinkTarget(url: "/url", title: "the title")])
        }
    }

    @Test("title on next line")
    func titleOnNextLine() {
        let source = "[foo]: /url\n   \"the title\"\n\n[foo]"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(dfs(doc).map(\.kind) == [.document, .paragraph, .link, .text])
        #expect(Self.links(doc) == [LinkTarget(url: "/url", title: "the title")])
        }
    }

    @Test("angle-bracketed destination")
    func angleBracketedDestination() {
        let source = "[foo]: <http://example.com/path>\n\n[foo]"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(Self.links(doc) == [LinkTarget(url: "http://example.com/path", title: "")])
        }
    }

    @Test("multiple definitions in a row leave no paragraph of their own")
    func multipleDefs() {
        let source = "[a]: /1\n[b]: /2 \"two\"\n[c]: /3\n\n[a] [b] [c]"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(dfs(doc).map(\.kind) == [.document, .paragraph, .link, .text, .text, .link, .text, .text, .link, .text])
        #expect(Self.links(doc) == [
            LinkTarget(url: "/1", title: ""),
            LinkTarget(url: "/2", title: "two"),
            LinkTarget(url: "/3", title: ""),
        ])
        }
    }

    @Test("definition followed by paragraph content")
    func defThenParagraph() {
        let source = "[foo]: /url\n\nhello [foo]"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map(\.kind)
        #expect(kinds == [.document, .paragraph, .text, .link, .text])
        #expect(Self.links(doc) == [LinkTarget(url: "/url", title: "")])
        let texts = dfs(doc).compactMap(\.literal)
        #expect(texts == ["hello ", "foo"])
        }
    }

    @Test("definition then paragraph with no blank line between")
    func defThenInlineParagraph() {
        let source = "[foo]: /url\nhello [foo]"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map(\.kind)
        #expect(kinds == [.document, .paragraph, .text, .link, .text])
        #expect(Self.links(doc) == [LinkTarget(url: "/url", title: "")])
        }
    }

    @Test("first definition wins for duplicate labels")
    func duplicateLabelsFirstWins() {
        let source = "[foo]: /first\n[foo]: /second\n\n[foo]"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(Self.links(doc) == [LinkTarget(url: "/first", title: "")])
        }
    }

    @Test("label normalization: case-fold and collapse whitespace")
    func labelNormalization() {
        let source = "[Foo \t Bar]: /url\n\n[foo bar]"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(Self.links(doc) == [LinkTarget(url: "/url", title: "")])
        }
    }

    @Test("invalid definition: empty label stays as paragraph")
    func invalidEmptyLabel() {
        let source = "[]: /url"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map(\.kind)
        #expect(kinds == [.document, .paragraph, .text])
        #expect(dfs(doc).compactMap(\.literal) == ["[]: /url"])
        }
    }

    @Test("invalid definition: missing destination stays as paragraph")
    func invalidMissingDestination() {
        let source = "[foo]:\n\n[foo]"
        MarkdownDocument.withParsedDocument(source) { doc in
        let kinds = dfs(doc).map(\.kind)
        #expect(kinds == [.document, .paragraph, .text, .paragraph, .text])
        #expect(dfs(doc).compactMap(\.literal) == ["[foo]:", "[foo]"])
        }
    }

    @Test("text after the title on its line leaves no definition")
    func titleWithTrailingJunk() {
        // Per Link reference definitions, no non-whitespace character may follow the title on its line. Without the
        // title, the destination is followed by other text on its line, so there is no definition.
        let source = "[foo]: /url \"title\" extra\n\n[foo]"
        MarkdownDocument.withParsedDocument(source) { doc in
        #expect(dfs(doc).map(\.kind) == [.document, .paragraph, .text, .paragraph, .text])
        #expect(dfs(doc).compactMap(\.literal) == ["[foo]: /url \"title\" extra", "[foo]"])
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
        #expect(info.text == "[ ] foo")
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

    @Test("`[y]` is no task marker and stays as paragraph text")
    func notATaskMarker() {
        let source = "- [y] foo"
        MarkdownDocument.withParsedDocument(source, options: .tasklist) { doc in
        let info = Self.firstItem(doc)
        #expect(info.checked == nil)
        #expect(info.text == "[y] foo")
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

    /// The cells of the document's first top-level table, row by row, as each cell's alignment and the literal of its first inline that has one.
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
        #expect(kinds == [.document, .paragraph, .text, .softBreak, .text, .softBreak, .text])
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
        #expect(kinds == [.document, .paragraph, .text, .softBreak, .text, .softBreak, .text])
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
}
