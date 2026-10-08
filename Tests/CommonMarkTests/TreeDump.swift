/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark

/// Renders a parsed tree one node per line, two spaces of indent per depth, so a test can compare the whole tree
/// with a literal.
///
/// Each line is a snake_case name for the node's kind (`block_quote`, `table_header`, `tasklist`, ...) followed by
/// the node's defining values: the literal of text-like nodes, the info string and body of a code block, the URL and
/// title of a link or image, the heading level, a list's marker, start, delimiter and tightness, the checkbox state of
/// a task list item, the alignment and span of a table cell, and the label of a footnote definition or the number of a
/// footnote reference. Quoted values escape `\`, `"`, line feed and tab, and write any other control character or DEL
/// as `\u{…}` in uppercase hexadecimal.
///
/// With `sourceRanges`, each line ends with the node's source range as `@line:column-line:column` (the end is
/// half-open), or `@-` for a node without one.
internal enum TreeDump {

    internal static func dump(_ source: String, options: MarkdownDocument.ParseOptions, sourceRanges: Bool = false) -> String {
        MarkdownDocument.withParsedDocument(source, options: options) { doc in
            var out = ""
            dump(doc.root, depth: 0, sourceRanges: sourceRanges, into: &out)
            return out
        }
    }

    private static func dump(_ node: borrowing MarkdownNode, depth: Int, sourceRanges: Bool, into out: inout String) {
        out += String(repeating: "  ", count: depth) + line(node)
        if sourceRanges {
            if let range = node.sourceRange {
                out += " @\(range.lowerBound.line):\(range.lowerBound.column)-\(range.upperBound.line):\(range.upperBound.column)"
            } else {
                out += " @-"
            }
        }
        out += "\n"
        node.children.forEach { dump($0, depth: depth + 1, sourceRanges: sourceRanges, into: &out) }
    }

    /// The snake_case name of `kind` followed by every value that applies to it, so a test can compare a node's kind
    /// with a literal: a bullet list's marker or an ordered list's start and delimiter, a list's tightness, the
    /// checkbox state of a task list item, whether a code block is fenced with its fence character, length and offset,
    /// the heading level, the alignment and span of a table cell, the backtick count of a code span, and the number of
    /// a footnote reference.
    internal static func describe(_ kind: MarkdownNode.Kind) -> String {
        switch kind {
        case .document: return "document"
        case .blockQuote: return "block_quote"
        case .list(let info):
            let tightness = info.tight ? "tight" : "loose"
            switch info.kind {
            case .bullet:
                let marker = switch info.bulletMarker {
                case .hyphen: "-"
                case .plus: "+"
                case .asterisk: "*"
                }
                return "list bullet '\(marker)' \(tightness)"
            case .ordered:
                let delimiter = info.orderedDelimiter == .paren ? "paren" : "period"
                return "list ordered start=\(info.start) delim=\(delimiter) \(tightness)"
            }
        case .item(let checked):
            guard let checked else { return "item" }
            return "tasklist " + (checked ? "checked" : "unchecked")
        case .codeBlock(let info):
            let fence = switch info.fenceCharacter {
            case .backtick: "'`'"
            case .tilde: "'~'"
            case nil: "none"
            }
            let style = info.isFenced ? "fenced" : "indented"
            return "code_block \(style) fence=\(fence) length=\(info.fenceLength) offset=\(info.fenceOffset)"
        case .htmlBlock: return "html_block"
        case .customBlock: return "custom_block"
        case .paragraph: return "paragraph"
        case .heading(let level): return "heading \(level)"
        case .thematicBreak: return "thematic_break"
        case .footnoteDefinition: return "footnote_definition"
        case .table: return "table"
        case .tableRow(let isHeader): return isHeader ? "table_header" : "table_row"
        case .tableCell(let alignment, let columns, let rows):
            return "table_cell align=\(alignment) colspan=\(columns) rowspan=\(rows)"
        case .text: return "text"
        case .softBreak: return "softbreak"
        case .lineBreak: return "linebreak"
        case .codeInline(let backtickCount): return "code backticks=\(backtickCount)"
        case .htmlInline: return "html_inline"
        case .customInline: return "custom_inline"
        case .emphasis: return "emph"
        case .strong: return "strong"
        case .link: return "link"
        case .image: return "image"
        case .footnoteReference(let index): return "footnote_reference \(index)"
        case .strikethrough: return "strikethrough"
        case .attribute: return "attribute"
        }
    }

    private static func line(_ node: borrowing MarkdownNode) -> String {
        let content = node.stringContent
        switch node.kind {
        case .codeBlock:
            guard case .codeBlock(let info, let body) = content else { return "code_block <no content>" }
            return "code_block \(quoted(info)) \(quoted(body))"
        case .htmlBlock: return "html_block " + quotedText(content)
        case .footnoteDefinition:
            guard case .footnote(let label) = content else { return "footnote_definition <no content>" }
            return "footnote_definition " + quoted(label)
        case .text: return "text " + quotedText(content)
        case .codeInline: return "code " + quotedText(content)
        case .htmlInline: return "html_inline " + quotedText(content)
        case .link: return "link " + quotedLink(content)
        case .image: return "image " + quotedLink(content)
        case .footnoteReference(let index): return "footnote_reference \(quoted(String(index)))"
        case .attribute:
            guard case .attribute(let raw) = content else { return "attribute <no content>" }
            return "attribute " + quoted(raw)
        case .document, .blockQuote, .list, .item, .customBlock, .paragraph, .heading, .thematicBreak, .table,
             .tableRow, .tableCell, .softBreak, .lineBreak, .customInline, .emphasis, .strong, .strikethrough:
            return describe(node.kind)
        }
    }

    private static func quotedText(_ content: MarkdownNode.StringContent) -> String {
        switch content {
        case .text(let s), .htmlBlock(let s): return quoted(s)
        default: return "<no text>"
        }
    }

    private static func quotedLink(_ content: MarkdownNode.StringContent) -> String {
        guard case .link(let url, let title) = content else { return "<no link>" }
        return "\(quoted(url)) \(quoted(title))"
    }

    private static func quoted(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\u{0}"..."\u{1F}", "\u{7F}": out += "\\u{" + String(scalar.value, radix: 16, uppercase: true) + "}"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
