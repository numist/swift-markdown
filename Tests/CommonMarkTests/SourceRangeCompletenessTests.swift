/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CommonMark

/// Collects each node's kind, source range and whether it is a leaf, in depth-first order.
internal func dfsCompleteness(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, range: Range<MarkdownNode.SourcePosition>?, isLeaf: Bool)]
) {
    out.append((node.kind, node.sourceRange, node.isLeaf))
    node.children.forEach { child in
        dfsCompleteness(child, into: &out)
    }
}

@Suite("Source range completeness")
struct SourceRangeCompletenessTests {

    private static func loadSpec() throws -> [SpecExample] {
        let here = URL(fileURLWithPath: #filePath)
        let resource = here.deletingLastPathComponent().appendingPathComponent("spec.txt")
        let text = try String(contentsOf: resource, encoding: .utf8)
        return SpecParser.parse(text)
    }

    /// Every example parses with these options rather than its own spec annotation, so each check
    /// covers every example.
    private static let options: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    /// Every node has a source range whose start is not after its end, except soft and hard line
    /// breaks and the empty cells inserted into a body row with fewer cells than the header row
    /// (Tables (extension)), none of which has a source range. This checks presence and order, not values.
    @Test("every non-exempt node carries a valid source range")
    func everyNonExemptNodeHasValidRange() throws {
        let audit = try Self.audit(options: Self.options)

        // Fixture sanity: an empty corpus or a walk that never descends into children fails loudly.
        #expect(audit.totalNodes > 3000)
        // The tables section inserts exactly two empty cells; pinning the count keeps a childless
        // cell that should have a source range from passing as one of them.
        #expect(audit.exemptFillerCells == 2)
        #expect(audit.failures.isEmpty, Comment(rawValue: audit.failures.prefix(25).joined(separator: "\n")))
    }

    /// The same check with every `o` in every example replaced by a NUL, which becomes U+FFFD (Insecure characters) in
    /// paragraphs, headings, table cells and the inlines within them. A letter is replaced rather than a NUL inserted,
    /// so block markers and most inline syntax stay intact.
    @Test("every non-exempt node carries a valid source range when content contains NULs")
    func everyNonExemptNodeWithNULHasValidRange() throws {
        let audit = try Self.audit(options: Self.options) { $0.replacingOccurrences(of: "o", with: "\u{0}") }

        #expect(audit.totalNodes > 3000)
        #expect(audit.exemptFillerCells == 2)
        #expect(audit.failures.isEmpty, Comment(rawValue: audit.failures.prefix(25).joined(separator: "\n")))
    }

    /// A NUL is one source byte, as an `o` is, so replacing each `o` with a NUL leaves every node's source range unchanged
    /// wherever it leaves the node tree unchanged: this checks the values, not just the presence, of the ranges of
    /// content holding a NUL.
    @Test("a NUL projects onto its one source byte")
    func nulReplacementPreservesRanges() throws {
        func nodes(_ markdown: String) -> [(kind: String, range: String)] {
            var nodes: [(kind: MarkdownNode.Kind, range: Range<MarkdownNode.SourcePosition>?, isLeaf: Bool)] = []
            MarkdownDocument.withParsedDocument(markdown, options: Self.options) { doc in
                dfsCompleteness(doc.root, into: &nodes)
            }
            return nodes.map { ("\($0.kind)", String(describing: $0.range)) }
        }

        var compared = 0
        var failures: [String] = []
        for ex in try Self.loadSpec() {
            let original = nodes(ex.markdown)
            let withNUL = nodes(ex.markdown.replacingOccurrences(of: "o", with: "\u{0}"))
            // A NUL can change structure (an `o` in an entity or HTML tag name, U+FFFD's emphasis flanking), and then its ranges aren't comparable.
            guard ex.markdown.contains("o"), original.map(\.kind) == withNUL.map(\.kind) else { continue }
            compared += 1
            for (a, b) in zip(original, withNUL) where a.range != b.range {
                failures.append("#\(ex.number) [\(ex.section)] \(a.kind): \(a.range) became \(b.range); input=\(ex.markdown.debugDescription)")
            }
        }

        // Fixture sanity: most examples contain an `o` and keep their structure, so a substitution that broke structure wholesale fails loudly.
        #expect(compared > 500)
        #expect(failures.isEmpty, Comment(rawValue: failures.prefix(25).joined(separator: "\n")))
    }

    /// The same check over inline-only parsing (`.inlineOnly`, and `.preserveWhitespace`, which
    /// implies it), where each spec example becomes one paragraph of inline content. Each example
    /// also runs with CRLF line endings.
    @Test("every non-exempt node carries a valid source range in inline-only parsing", arguments: [
        MarkdownDocument.ParseOptions.inlineOnly, .preserveWhitespace,
    ], ["\n", "\r\n"])
    func everyNonExemptInlineOnlyNodeHasValidRange(mode: MarkdownDocument.ParseOptions, lineEnding: String) throws {
        let audit = try Self.audit(options: Self.options.union(mode)) { $0.replacingOccurrences(of: "\n", with: lineEnding) }

        // Fixture sanity: every example yields at least a document, a paragraph, and a child.
        #expect(audit.totalNodes > 3000)
        // Inline-only parsing builds no tables.
        #expect(audit.exemptFillerCells == 0)
        #expect(audit.failures.isEmpty, Comment(rawValue: audit.failures.prefix(25).joined(separator: "\n")))
    }

    /// A container to nest every spec example in, by prefixing each of its lines.
    enum Container: String, CaseIterable, Sendable {
        /// Every line prefixed with `> `.
        case blockQuote
        /// The first line prefixed with `- `, the rest indented by two spaces.
        case listItem
        /// The first line prefixed with `> - `, the rest with `>   `.
        case listItemInBlockQuote
        /// Every line prefixed with `>` and a tab.
        case tabAfterBlockQuoteMarker
        /// The first line prefixed with `-` and a tab, the rest indented by a tab.
        case tabIndentedListItem
        /// A `> a` paragraph line first, then the example's first line unprefixed, so it is a lazy continuation of that
        /// paragraph wherever it is paragraph text, and the rest prefixed with `> `. A table's header line is then lazy.
        case lazyFirstLine

        func nest(_ markdown: String) -> String {
            var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            // The example's final line ending ends its last line; it is not a line of its own to prefix.
            let trailingNewline = lines.last == ""
            if trailingNewline { lines.removeLast() }
            let (first, rest): (String, String) = switch self {
            case .blockQuote: ("> ", "> ")
            case .listItem: ("- ", "  ")
            case .listItemInBlockQuote: ("> - ", ">   ")
            case .tabAfterBlockQuoteMarker: (">\t", ">\t")
            case .tabIndentedListItem: ("-\t", "\t")
            case .lazyFirstLine: ("", "> ")
            }
            let nested = lines.enumerated().map { ($0.offset == 0 ? first : rest) + $0.element }
            let lead = self == .lazyFirstLine ? "> a\n" : ""
            return lead + nested.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        }
    }

    /// The same check with every spec example nested in each `Container`. A nested block's lines aren't
    /// contiguous in the source (each carries its container's prefix), so this covers content that maps
    /// back to source line by line: notably tables, whose rows, cells and cell inlines must each lie on
    /// their own source line.
    @Test("every non-exempt node carries a valid source range when nested in a container", arguments: Container.allCases)
    func everyNonExemptNestedNodeHasValidRange(container: Container) throws {
        let audit = try Self.audit(options: Self.options, transform: container.nest)

        #expect(audit.totalNodes > 3000)
        #expect(audit.exemptFillerCells == 2)
        #expect(audit.failures.isEmpty, Comment(rawValue: audit.failures.prefix(25).joined(separator: "\n")))
    }

    /// A range runs from the first byte of a node's own content to just past its last content byte, so no range starts
    /// or ends on whitespace outside the node's content: the literal whitespace of text, a code block or an HTML block,
    /// or whitespace a child's range holds. A code block or HTML block whose last line is blank ends at that line's
    /// start, and inline-only parsing keeps the whole input as the paragraph's content. The document covers the whole
    /// input. Each spec example runs with each line ending preceded by whitespace, as written and nested in each
    /// `Container`.
    @Test("no range starts or ends on whitespace outside its content", arguments: ["\n", "  \n", "\t\n", "\u{0B}\n", "\r\n"])
    func rangesEndOnContent(lineEnding: String) throws {
        var checked = 0
        var failures: [String] = []
        let optionSets: [MarkdownDocument.ParseOptions] = [
            Self.options, Self.options.union([.footnotes, .gfmAutolink]), Self.options.union(.inlineOnly),
        ]
        for ex in try Self.loadSpec() {
            let markdown = ex.markdown.replacingOccurrences(of: "\n", with: lineEnding)
            for source in [markdown] + Container.allCases.map({ $0.nest(markdown) }) {
                for options in optionSets {
                    let result = Self.boundaryFailures(source, options: options)
                    checked += result.checked
                    failures += result.failures.map { "#\(ex.number) [\(ex.section)] \($0); input=\(source.debugDescription)" }
                }
            }
        }

        #expect(checked > 80_000)
        #expect(failures.isEmpty, Comment(rawValue: failures.prefix(25).joined(separator: "\n")))
    }

    /// The nodes of `markdown` whose ranges break `rangesEndOnContent`'s rule, and the number of nodes checked.
    private static func boundaryFailures(_ markdown: String, options: MarkdownDocument.ParseOptions) -> (checked: Int, failures: [String]) {
        let bytes = Array(markdown.utf8)
        var lineStarts = [bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0]
        var i = lineStarts[0]
        while i < bytes.count {
            if bytes[i] == 0x0D, i + 1 < bytes.count, bytes[i + 1] == 0x0A { i += 1 }
            if bytes[i] == 0x0A || bytes[i] == 0x0D { lineStarts.append(i + 1) }
            i += 1
        }
        func offset(_ p: MarkdownNode.SourcePosition) -> Int { lineStarts[p.line - 1] + p.column - 1 }
        func isWhitespace(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D || b == 0x0B || b == 0x0C }

        var checked = 0
        var failures: [String] = []
        func check(_ node: borrowing MarkdownNode) {
            checked += 1
            node.children.forEach { check($0) }
            let kind = node.kind
            let literal = Array((node.literal() ?? "").utf8)
            var childStarts: Set<Int> = [], childEnds: Set<Int> = []
            node.children.forEach { child in
                if let r = child.sourceRange { childStarts.insert(offset(r.lowerBound)); childEnds.insert(offset(r.upperBound)) }
            }
            guard let range = node.sourceRange else { return }
            let start = offset(range.lowerBound), end = offset(range.upperBound)
            if case .document = kind {
                if start != lineStarts[0] || end != bytes.count {
                    failures.append("document \(range) is not the whole input")
                }
                return
            }
            guard start < end else { return }
            let lastLine = literal.last == 0x0A ? literal.dropLast() : literal[...]
            var blockLiteral = false
            switch kind {
            case .codeBlock, .htmlBlock: blockLiteral = true
            default: break
            }
            let startHeld = childStarts.contains(start) || (kind == .text || blockLiteral) && literal.first.map(isWhitespace) == true
            var endHeld = childEnds.contains(end) || kind == .text && literal.last.map(isWhitespace) == true
                || blockLiteral && lastLine.last.map(isWhitespace) == true
            if blockLiteral, bytes[end - 1] == 0x0A || bytes[end - 1] == 0x0D, lastLine.isEmpty || lastLine.last == 0x0A {
                endHeld = true
            }
            if kind == .paragraph, options.contains(.inlineOnly) {
                endHeld = true
            }
            if isWhitespace(bytes[start]) && !startHeld { failures.append("\(kind) \(range) starts on whitespace") }
            if isWhitespace(bytes[end - 1]) && !endHeld { failures.append("\(kind) \(range) ends on whitespace") }
        }
        MarkdownDocument.withParsedDocument(markdown, options: options) { check($0.root) }
        return (checked, failures)
    }

    /// Parses every spec example with `options`, its markdown passed through `transform`, and collects each
    /// node that lacks a valid source range, skipping the exemptions documented on
    /// `everyNonExemptNodeHasValidRange`.
    private static func audit(options: MarkdownDocument.ParseOptions, transform: (String) -> String = { $0 }) throws -> (totalNodes: Int, exemptFillerCells: Int, failures: [String]) {
        let examples = try Self.loadSpec()
        #expect(examples.count > 600)

        var totalNodes = 0
        var exemptFillerCells = 0
        var failures: [String] = []

        for ex in examples {
            var nodes: [(kind: MarkdownNode.Kind, range: Range<MarkdownNode.SourcePosition>?, isLeaf: Bool)] = []
            let markdown = transform(ex.markdown)
            MarkdownDocument.withParsedDocument(markdown, options: options) { doc in
                dfsCompleteness(doc.root, into: &nodes)
            }
            totalNodes += nodes.count

            for node in nodes {
                switch node.kind {
                case .softBreak, .lineBreak:
                    continue
                default:
                    break
                }

                guard let range = node.range else {
                    // A childless table cell is one inserted into a body row with fewer cells than the header row.
                    if case .tableCell = node.kind, node.isLeaf {
                        exemptFillerCells += 1
                        continue
                    }
                    failures.append("#\(ex.number) [\(ex.section)] \(node.kind): nil sourceRange; input=\(markdown.debugDescription)")
                    continue
                }
                // `MarkdownNode.sourceRange` reports a start after its end as nil, which the guard above
                // catches; this check holds if that contract changes.
                if range.lowerBound > range.upperBound {
                    failures.append("#\(ex.number) [\(ex.section)] \(node.kind): inverted range \(range); input=\(markdown.debugDescription)")
                }
            }
        }
        return (totalNodes, exemptFillerCells, failures)
    }
}
