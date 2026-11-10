/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

extension DocumentStorage {
    /// Checks this parse of `source` for source ranges that are present, in bounds, on scalar boundaries, within their
    /// parent's, and in order among their siblings.
    ///
    /// Returns `false` at the first violation, and `true` if there is none.
    internal func validateOutput(source: Span<UInt8>) -> Bool {
        RangeValidator(view: StorageView(storage: self, source: source), lineCount: lineCount).validate()
    }
}

private struct RangeValidator: ~Escapable {
    private let view: StorageView
    private let lineCount: Int

    /// Where the first line's content begins, past any byte order mark; no range but the document's starts before it.
    private let contentStart: Int

    @_lifetime(copy view)
    init(view: StorageView, lineCount: Int) {
        self.view = view
        self.lineCount = lineCount
        let source = view.source
        self.contentStart = source.count >= 3 && source[0] == 0xEF && source[1] == 0xBB && source[2] == 0xBF ? 3 : 0
    }

    /// Visits every node reachable from the document in pre-order, following child and sibling links, so any depth runs
    /// in constant stack.
    func validate() -> Bool {
        guard view.options.contains(.sourcePosition) else {
            return view.sourceRanges.isEmpty
        }
        guard view.sourceRanges.count == view.nodes.count else {
            return false
        }
        var node = 0
        descending: while true {
            guard validateRange(node) else {
                return false
            }
            if let child = view.nodes[node].firstChild {
                node = child
                continue
            }
            while node != 0 {
                if let next = view.nodes[node].next {
                    node = next
                    continue descending
                }
                node = view.nodes[node].parent!
            }
            return true
        }
    }

    private func rangeIfSet(_ node: DocumentStorage.Index) -> DocumentStorage.SourceByteRange? {
        let range = view.sourceRanges[node]
        return range == .unset ? nil : range
    }

    /// Every node has a range within the source and within its parent's, starting and ending on scalar boundaries and
    /// starting no earlier than its previous sibling ends. Line breaks, cells inserted into a short body row, and the
    /// document of empty input have none.
    private func validateRange(_ node: DocumentStorage.Index) -> Bool {
        let record = view.nodes[node]
        let range = rangeIfSet(node)
        switch record.kind {
        case .softBreak, .lineBreak:
            return range == nil
        case .document where lineCount == 0:
            return range == nil
        case .tableCell where range == nil:
            guard let row = record.parent, case .tableRow(isHeader: false) = view.nodes[row].kind else {
                return false
            }
            return record.firstChild == nil
        default:
            break
        }
        guard let range else {
            return false
        }
        guard (record.kind == .document ? 0 : contentStart) <= range.start && range.start <= range.end && range.end <= view.source.count else {
            return false
        }
        guard Self.isScalarBoundary(range.start, in: view.source) && Self.isScalarBoundary(range.end, in: view.source) else {
            return false
        }
        if let parent = record.parent, let parentRange = rangeIfSet(parent) {
            guard parentRange.start <= range.start && range.end <= parentRange.end else {
                return false
            }
        }
        // Footnote definitions move to the document's end in reference order, so their ranges are out of source order.
        if record.kind != .footnoteDefinition, let previous = record.previous, let previousRange = rangeIfSet(previous) {
            return previousRange.end <= range.start
        }
        return true
    }

    private static func isScalarBoundary(_ offset: Int, in bytes: Span<UInt8>) -> Bool {
        offset == bytes.count || bytes[offset] & 0xC0 != 0x80
    }
}
