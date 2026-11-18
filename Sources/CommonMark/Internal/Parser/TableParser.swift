/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// GFM-tables detection and transformation.
extension BlockParser {

    internal mutating func parseTable(node: DocumentStorage.Index, pending: consuming PendingLeaf?) {
        precondition(pending != nil, "an open paragraph always holds its accumulated content")
        let leaf = pending!
        precondition(leaf.node == node, "the pending leaf is the open paragraph's")
        var lines: [Range<Int>] = []
        // A `.lazy` range, and a segment made from one, can hold several lines contiguous in the source.
        func appendLines(of range: Range<Int>) {
            var lineStart = range.lowerBound
            for i in range where sourceBytes[i] == UInt8(ascii: "\n") {
                lines.append(lineStart..<i)
                lineStart = i + 1
            }
            lines.append(lineStart..<range.upperBound)
        }
        switch consume leaf.content {
        case .lazy(let range, let joinPending):
            precondition(!joinPending, "a deferred line join is always consumed by the next line")
            appendLines(of: range)
        case .segments(let segs):
            let nl = storage.newlineSegment
            for i in 0..<segs.count where segs[i] != nl {
                precondition(segs[i].inSource && (i == 0 || segs[i - 1] == nl), "a paragraph's lines are source segments joined by line joins")
                appendLines(of: segs[i].chunk.range)
            }
        }
        precondition(lines.count >= 2, "a table-pending paragraph holds its header and delimiter lines")
        let alignments = parseDelimRow(line: lines[1])
        precondition(splitCells(line: lines[0]).count == alignments.count, "a table-pending paragraph's header has the delimiter row's column count")
        let columnCount = alignments.count
        // Mutate the paragraph node in place.
        storage[node].kind = .table
        // Each column's owner is kept rather than found by scanning up the rows, so a long column of rowspan fillers
        // stays linear.
        var rowspanOwners: [DocumentStorage.Index?] = storage.options.contains(.tableSpans) ? Array(repeating: nil, count: columnCount) : []
        for k in lines.indices where k != 1 {
            appendRow(
                parent: node,
                line: lines[k],
                alignments: alignments,
                isHeader: k == 0,
                rowspanOwners: &rowspanOwners
            )
        }
        storage.setSourceStart(node, rowRange(lines[0]).lowerBound)
        storage.setSourceEnd(node, rowRange(lines[lines.count - 1]).upperBound)
    }

    // Every delimiter-candidate paragraph line asks this, so it counts cells without building arrays.
    internal mutating func opensTable(header: Range<Int>, delimiter: Range<Int>) -> Int? {
        var columns = 0
        var isDelimiterRow = true
        forEachCell(in: delimiter) { cell in
            columns += 1
            if isDelimiterRow && delimiterAlignment(of: cell) == nil {
                isDelimiterRow = false
            }
        }
        guard isDelimiterRow, columns <= limits.maxTableRowCells else {
            return nil
        }
        precondition(columns > 0, "a delimiter-candidate line holds a `-`, so it splits into at least one cell")
        // GFM: header column count must equal delimiter column count, else not a table - leave the paragraph alone.
        var headerCells = 0
        forEachCell(in: header) { _ in headerCells += 1 }
        return headerCells == columns ? columns : nil
    }

    internal mutating func holdsLineOverRowCellLimit(_ lines: Range<Int>) -> Bool {
        var lineStart = lines.lowerBound
        for i in lines where sourceBytes[i] == UInt8(ascii: "\n") {
            if exceedsRowCellLimit(line: lineStart..<i) {
                return true
            }
            lineStart = i + 1
        }
        return exceedsRowCellLimit(line: lineStart..<lines.upperBound)
    }

    internal mutating func tableLimitsAdmitRow(_ line: Range<Int>, autocompletedCells: Int) -> Bool {
        // A negative limit behaves as zero, the nearest meaningful value (`ParseLimits`).
        autocompletedCells <= max(limits.maxTableAutocompletedCells, 0) && !exceedsRowCellLimit(line: line)
    }

    internal mutating func autocompletedCells(_ autocompletedCells: Int, afterRow line: Range<Int>, columns: Int) -> Int {
        guard limits.maxTableAutocompletedCells < .max else {
            return autocompletedCells
        }
        var cells = 0
        forEachCell(in: line) { _ in cells += 1 }
        let (sum, overflow) = autocompletedCells.addingReportingOverflow(max(columns - cells, 0))
        return overflow ? .max : sum
    }

    private mutating func exceedsRowCellLimit(line: Range<Int>) -> Bool {
        let limit = limits.maxTableRowCells
        // A line has no more cells than bytes, apart from an empty line's one cell.
        guard max(line.count, 1) > limit else {
            return false
        }
        var cells = 0
        forEachCell(in: line) { _ in cells += 1 }
        return cells > limit
    }

    internal func couldBeDelimiterRow(range: Range<Int>) -> Bool {
        var sawDash = false
        for i in range {
            switch sourceBytes[i] {
            case UInt8(ascii: "-"):
                sawDash = true
            case UInt8(ascii: ":"), UInt8(ascii: "|"):
                break
            case let b where b.isLineWhitespace:
                break
            default:
                return false
            }
        }
        return sawDash
    }

    internal func isLonePipeRow(range: Range<Int>) -> Bool {
        var i = range.lowerBound
        while i < range.upperBound && sourceBytes[i].isLineWhitespace {
            i += 1
        }
        guard i < range.upperBound && sourceBytes[i] == UInt8(ascii: "|") else {
            return false
        }
        i += 1
        while i < range.upperBound && sourceBytes[i].isLineWhitespace {
            i += 1
        }
        return i == range.upperBound
    }

    // MARK: - Row construction

    /// Build a `.tableRow` node + its cells under `parent`. Missing trailing cells are emitted as empty; extras beyond `columnCount` are dropped.
    ///
    /// When `spansEnabled`, each cell carries `.tableCell` span data: an empty `||` cell becomes a colspan filler (colspan 0) and grows the preceding cell's colspan; a cell whose content is the lone rowspan marker (`^`, or `"` when `.tableRowspanDitto`) becomes a rowspan filler (rowspan 0) and grows the matching cell in the nearest non-filler row above, with its marker text suppressed.
    private mutating func appendRow(
        parent: DocumentStorage.Index,
        line: Range<Int>,
        alignments: [MarkdownNode.TableAlignment],
        isHeader: Bool,
        rowspanOwners: inout [DocumentStorage.Index?]
    ) {
        let rowIdx = storage.appendNode(NodeRecord(
            kind: .tableRow(isHeader: isHeader),
            parent: parent,
            data: nil
        ))
        storage.appendChild(rowIdx, to: parent)
        let range = rowRange(line)
        storage.setSourceStart(rowIdx, range.lowerBound)
        storage.setSourceEnd(rowIdx, range.upperBound)
        let cells = splitCells(line: line)
        let columnCount = alignments.count

        // Span bookkeeping is only allocated/computed when `.tableSpans` is on. With spans off these stay empty (the empty `Array` is a non-allocating singleton) and every per-cell read below is guarded by `spansEnabled`, so the common table path does no extra allocation or work.
        let spansEnabled = storage.options.contains(.tableSpans)
        var colspans: [Int] = []
        var rowspans: [Int] = []
        var skipContent: [Bool] = []
        if spansEnabled {
            // Sized to every cell, not just the columns kept: a colspan filler past the last column is dropped but
            // still grows the cell to its left, even past the table's width.
            colspans = [Int](repeating: 1, count: max(columnCount, cells.count))
            rowspans = [Int](repeating: 1, count: columnCount)
            skipContent = [Bool](repeating: false, count: columnCount)
            let markerByte = storage.options.contains(.tableRowspanDitto) ? UInt8(ascii: "\"") : UInt8(ascii: "^")
            // Kept rather than found by scanning left, so a long run of colspan fillers stays linear.
            var lastRealCell: Int? = nil
            for col in 0..<cells.count {
                if cells[col].isEmpty {
                    colspans[col] = 0
                    if let lastRealCell {
                        colspans[lastRealCell] += 1
                    }
                } else {
                    lastRealCell = col
                }
                // Rowspan marker: the trimmed cell is exactly the marker byte.
                if col < columnCount {
                    let content = trimmingPadding(cells[col])
                    if content.count == 1 && sourceBytes[content.lowerBound] == markerByte {
                        rowspans[col] = 0
                    }
                }
            }
            if !isHeader {
                for col in 0..<columnCount where rowspans[col] == 0 {
                    if let spanning = rowspanOwners[col] {
                        growRowspan(spanning)
                        skipContent[col] = true
                    }
                }
            }
        }

        for col in 0..<columnCount {
            let cellIdx = storage.appendNode(NodeRecord(
                kind: .tableCell(
                    alignment: alignments[col],
                    columns: spansEnabled ? colspans[col] : 1,
                    rows: spansEnabled ? rowspans[col] : 1
                ),
                parent: rowIdx,
                data: nil
            ))
            storage.appendChild(cellIdx, to: rowIdx)
            if spansEnabled && rowspans[col] != 0 {
                rowspanOwners[col] = cellIdx
            }
            guard col < cells.count else { continue }
            let content = trimmingPadding(cells[col])
            storage.setSourceStart(cellIdx, content.isEmpty ? cells[col].lowerBound : content.lowerBound)
            storage.setSourceEnd(cellIdx, content.isEmpty ? cells[col].lowerBound : content.upperBound)
            if content.isEmpty || (spansEnabled && skipContent[col]) { continue }
            queueInlines(of: cellIdx, content: content)
        }
    }

    private mutating func growRowspan(_ idx: DocumentStorage.Index) {
        guard case .tableCell(let alignment, let colspan, let rowspan) = storage[idx].kind else {
            preconditionFailure("a span row holds only table cells")
        }
        storage[idx].kind = .tableCell(alignment: alignment, columns: colspan, rows: rowspan + 1)
    }

    // Pre-process: replace `\|` with `|` so that whatever pipe-escaping the writer used to keep the cell intact is invisible to inline parsing - even inside a code span.
    private mutating func queueInlines(of cell: DocumentStorage.Index, content: Range<Int>) {
        func copies(_ i: Int) -> Int {
            if sourceBytes[i] == 0 {
                return 3
            }
            return i + 1 < content.upperBound && isEscapedPipe(at: i + 1, from: content.lowerBound) ? 0 : 1
        }
        let source = Chunk(offset: content.lowerBound, length: content.count, inSource: true)
        guard content.contains(where: { copies($0) != 1 }) else {
            pendingInlines.append((cell, storage.intern(source)))
            return
        }
        let offset = storage.strings.count
        for i in content where copies(i) > 0 {
            if sourceBytes[i] == 0 {
                appendReplacementCharacter()
            } else {
                storage.strings.append(sourceBytes[i])
            }
        }
        if positionsEnabled {
            arenaSourceMaps[cell] = rewrittenMap(sourceImage(of: source, map: []), of: source, copies: copies)
        }
        pendingInlines.append((cell, storage.intern(arenaChunk(from: offset))))
    }

    // A pipe directly after a backslash is cell content however many backslashes precede it, so `\\|` ends no cell.
    private func isEscapedPipe(at i: Int, from start: Int) -> Bool {
        sourceBytes[i] == UInt8(ascii: "|") && i > start && sourceBytes[i - 1] == UInt8(ascii: "\\")
    }

    // MARK: - Cell splitting

    /// Parse the delimiter row into per-column alignments. Each cell must match `\s*:?-+:?\s*` after pipe splitting, with at least one column.
    private mutating func parseDelimRow(line: Range<Int>) -> [MarkdownNode.TableAlignment] {
        let cells = splitCells(line: line)
        precondition(!cells.isEmpty, "a delimiter-candidate line holds a `-`, so it splits into at least one cell")
        return cells.map { cell in
            guard let alignment = delimiterAlignment(of: cell) else {
                preconditionFailure("a table-pending paragraph's delimiter line is a delimiter row")
            }
            return alignment
        }
    }

    private func delimiterAlignment(of cell: Range<Int>) -> MarkdownNode.TableAlignment? {
        let marker = trimmingPadding(cell)
        guard !marker.isEmpty else {
            return nil
        }
        let leftColon = sourceBytes[marker.lowerBound] == UInt8(ascii: ":")
        let rightColon = marker.count > 1 && sourceBytes[marker.upperBound - 1] == UInt8(ascii: ":")
        let dashes = (marker.lowerBound + (leftColon ? 1 : 0))..<(marker.upperBound - (rightColon ? 1 : 0))
        if dashes.isEmpty {
            return nil
        }
        for i in dashes where sourceBytes[i] != UInt8(ascii: "-") {
            return nil
        }
        switch (leftColon, rightColon) {
        case (true, true): return .center
        case (true, false): return .left
        case (false, true): return .right
        case (false, false): return MarkdownNode.TableAlignment.none
        }
    }

    /// Split `line` into cells on unescaped `|`. Strips a single leading and trailing `|` if present (with optional surrounding whitespace).
    private func splitCells(line: Range<Int>) -> [Range<Int>] {
        var cells: [Range<Int>] = []
        forEachCell(in: line) { cells.append($0) }
        return cells
    }

    @inline(__always)
    private func forEachCell(in line: Range<Int>, _ body: (Range<Int>) -> Void) {
        var s = line.lowerBound
        var e = line.upperBound
        while e > s && sourceBytes[e - 1].isLineWhitespace {
            e -= 1
        }
        var pipe = s
        while pipe < e && sourceBytes[pipe].isLineWhitespace {
            pipe += 1
        }
        var hadLeadingPipe = false
        if pipe < e && sourceBytes[pipe] == UInt8(ascii: "|") {
            s = pipe + 1
            hadLeadingPipe = true
        }
        var hadClosingPipe = false
        // Don't strip a backslash-escaped pipe.
        if e > s && sourceBytes[e - 1] == UInt8(ascii: "|") && !isEscapedPipe(at: e - 1, from: line.lowerBound) {
            e -= 1
            hadClosingPipe = true
        }
        // A leading pipe with only padding after it is zero cells, so `|\n-|` is a paragraph. `||` has a closing
        // pipe, so its one empty cell is kept.
        if hadLeadingPipe && !hadClosingPipe && s == e {
            return
        }
        var cellStart = s
        for i in s..<e where sourceBytes[i] == UInt8(ascii: "|") && !isEscapedPipe(at: i, from: line.lowerBound) {
            body(cellStart..<i)
            cellStart = i + 1
        }
        body(cellStart..<e)
    }

    private mutating func rowRange(_ line: Range<Int>) -> Range<Int> {
        let content = trimmingPadding(line)
        return content.isEmpty ? line.lowerBound..<line.lowerBound : content
    }

    // Tab, line tabulation and form feed are whitespace characters (Characters and lines), so they pad a cell as
    // spaces do (Tables (extension)).
    private func trimmingPadding(_ range: Range<Int>) -> Range<Int> {
        var s = range.lowerBound
        var e = range.upperBound
        while s < e && sourceBytes[s].isLineWhitespace {
            s += 1
        }
        while e > s && sourceBytes[e - 1].isLineWhitespace {
            e -= 1
        }
        return s..<e
    }
}
