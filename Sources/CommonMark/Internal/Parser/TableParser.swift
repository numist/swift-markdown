/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Tables (extension): turns a table-pending paragraph into a `.table` with `.tableRow` and `.tableCell` descendants.
extension BlockParser {

    /// Turns table-pending `node` into a `.table` and queues its cells for inline parsing. A paragraph is table-pending
    /// only once `opensTable` held for its header and delimiter row, and its pending content then holds just those
    /// rows and its body rows.
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
        precondition(splitCells(line: lines[0]).cells.count == alignments.count, "a table-pending paragraph's header has the delimiter row's column count")
        let columnCount = alignments.count
        storage[node].kind = .table
        storage[node].data = .table(columnCount: columnCount)
        // Per column, the cell a rowspan marker in the next row grows: the nearest cell above that isn't a rowspan filler. It is kept rather than searched for, so a long column of markers stays linear. Empty without `.tableSpans`.
        var rowspanOwners: [DocumentStorage.Index?] = storage.options.contains(.tableSpans) ? Array(repeating: nil, count: columnCount) : []
        // The delimiter row (line 1) is not a row.
        for k in lines.indices where k != 1 {
            appendRow(
                parent: node,
                line: lines[k],
                alignments: alignments,
                isHeader: k == 0,
                isLastLine: k == lines.count - 1,
                rowspanOwners: &rowspanOwners
            )
        }
    }

    /// Whether source lines `header` and `delimiter` open a table: `delimiter` is a delimiter row and `header` has as
    /// many cells (Tables (extension)). The block parser then marks the paragraph table-pending, so the table, not a
    /// paragraph, is the open block for the next line.
    ///
    /// Every delimiter-shaped paragraph line asks this, so it counts cells without building arrays.
    // Non-mutating, it measured 8% slower on a paragraph of delimiter-shaped lines.
    internal mutating func opensTable(header: Range<Int>, delimiter: Range<Int>) -> Bool {
        var columns = 0
        var isDelimiterRow = true
        forEachCell(in: delimiter) { cell in
            columns += 1
            if isDelimiterRow && delimiterAlignment(of: cell) == nil {
                isDelimiterRow = false
            }
        }
        guard isDelimiterRow else {
            return false
        }
        precondition(columns > 0, "a delimiter-candidate line holds a `-`, so it splits into at least one cell")
        var headerCells = 0
        forEachCell(in: header) { _ in headerCells += 1 }
        return headerCells == columns
    }

    /// Whether `sourceBytes[range]` holds only `-`, `:`, `|` and padding, with at least one `-`.
    /// This necessary condition for a delimiter row lets the block parser skip ordinary prose.
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

    /// Whether body-row `sourceBytes[range]`, from its first non-space byte, is a lone `|` with only padding
    /// after it. Such a row has no cells (`splitCells`), so it closes the table.
    internal func isLonePipeRow(range: Range<Int>) -> Bool {
        var s = range.lowerBound
        var e = range.upperBound
        precondition(s == e || !sourceBytes[s].isSpaceOrTab, "a body-row candidate starts at the line's first non-space byte")
        while e > s && sourceBytes[e - 1].isSpaceOrTab { e -= 1 }
        // Must lead with a pipe, ...
        guard s < e && sourceBytes[s] == UInt8(ascii: "|") else { return false }
        s += 1
        // ... with nothing but padding after it: a second pipe or any content forms at least one cell.
        for i in s..<e where !sourceBytes[i].isLineWhitespace {
            return false
        }
        return true
    }

    // MARK: - Row construction

    /// Appends a `.tableRow` and its cells under `parent`, padding missing cells and dropping extras.
    ///
    /// With `.tableSpans`, an empty `||` cell is a colspan filler (0) that grows the nearest real cell to its left, and a cell holding only the rowspan marker (`^`, or `"` with `.tableRowspanDitto`) is a rowspan filler (0) that, when its column has an owner above, grows that owner and drops its text. Every cell that isn't a rowspan marker, colspan fillers and padding cells included, becomes its column's owner.
    private mutating func appendRow(
        parent: DocumentStorage.Index,
        line: Range<Int>,
        alignments: [MarkdownNode.TableAlignment],
        isHeader: Bool,
        isLastLine: Bool,
        rowspanOwners: inout [DocumentStorage.Index?]
    ) {
        let rowIdx = storage.appendNode(NodeRecord(
            kind: .tableRow(isHeader: isHeader),
            parent: parent,
            data: nil
        ))
        storage.appendChild(rowIdx, to: parent)
        // A row covers its whole source line, trailing whitespace included. The last row ends where the table node,
        // already stamped with the paragraph's extent, ends. So does the rightmost cell of a row with no closing pipe.
        let rowEnd = isLastLine && positionsEnabled ? Int(storage.sourceRanges[parent].end) : line.upperBound
        storage.setSourceStart(rowIdx, line.lowerBound)
        storage.setSourceEnd(rowIdx, rowEnd)
        let (cells, hadClosingPipe, hadLeadingPipe) = splitCells(line: line)
        let columnCount = alignments.count
        // The content that is inline-parsed and tested for the rowspan marker: a cell's range trimmed of padding.
        func content(_ col: Int) -> Range<Int> {
            trimCellContent(range: cells[col], stripLeadingVTFF: col > 0 || hadLeadingPipe)
        }

        // Empty without `.tableSpans`, so the common path does not allocate.
        let spansEnabled = storage.options.contains(.tableSpans)
        var colspans: [Int] = []
        var rowspans: [Int] = []
        var skipContent: [Bool] = []
        if spansEnabled {
            // Colspan accumulates over every cell, so empty cells past `columnCount`, which are dropped, still
            // grow the nearest real cell to their left, uncapped.
            colspans = [Int](repeating: 1, count: max(columnCount, cells.count))
            rowspans = [Int](repeating: 1, count: columnCount)
            skipContent = [Bool](repeating: false, count: columnCount)
            let markerByte = storage.options.contains(.tableRowspanDitto) ? UInt8(ascii: "\"") : UInt8(ascii: "^")
            // The nearest cell to the left that isn't a colspan filler, kept so a long run of fillers stays linear.
            var lastRealCell: Int? = nil
            for col in 0..<cells.count {
                // A zero-width cell (`||`) in any column is a colspan filler; a leading one has no cell to grow.
                if cells[col].isEmpty {
                    colspans[col] = 0
                    if let lastRealCell {
                        colspans[lastRealCell] += 1
                    }
                } else {
                    lastRealCell = col
                }
                // A cell whose content is exactly the marker byte is a rowspan marker.
                if col < columnCount {
                    let trimmed = content(col)
                    if trimmed.count == 1 && sourceBytes[trimmed.lowerBound] == markerByte {
                        rowspans[col] = 0
                    }
                }
            }
            // The header has no row above to grow.
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
            // A cell covers its untrimmed span between pipes. A cell whose content trims to empty also covers its closing pipe, which it always has, because `splitCells` drops a trailing empty cell.
            let cr = cells[col]
            let cellRange = content(col)
            storage.setSourceStart(cellIdx, cr.lowerBound)
            if col == cells.count - 1 && !hadClosingPipe {
                // With no closing pipe, the rightmost cell runs to the row's untrimmed end.
                storage.setSourceEnd(cellIdx, rowEnd)
            } else {
                storage.setSourceEnd(cellIdx, cellRange.isEmpty ? cr.upperBound + 1 : cr.upperBound)
            }
            if cellRange.isEmpty || (spansEnabled && skipContent[col]) { continue }
            queueInlines(of: cellIdx, content: cellRange)
        }
    }

    private mutating func growRowspan(_ idx: DocumentStorage.Index) {
        guard case .tableCell(let alignment, let colspan, let rowspan) = storage[idx].kind else {
            preconditionFailure("a span row holds only table cells")
        }
        storage[idx].kind = .tableCell(alignment: alignment, columns: colspan, rows: rowspan + 1)
    }

    /// Queues source bytes `content` as `cell`'s content for inline parsing after the block pass, so a reference in a
    /// cell resolves against definitions anywhere in the document. `\|` includes a pipe in a cell's content, even inside
    /// a code span (Tables (extension)), and a NUL is replaced with U+FFFD (Insecure characters), so content holding
    /// either is copied with each `\|` replaced by `|` and each NUL by U+FFFD.
    private mutating func queueInlines(of cell: DocumentStorage.Index, content: Range<Int>) {
        // The number of bytes each source byte becomes.
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

    /// Whether `sourceBytes[i]` is a `|` directly after a backslash at or after `start`. Such a pipe is cell content,
    /// not a cell boundary, however many backslashes precede it (Tables (extension)).
    private func isEscapedPipe(at i: Int, from start: Int) -> Bool {
        sourceBytes[i] == UInt8(ascii: "|") && i > start && sourceBytes[i - 1] == UInt8(ascii: "\\")
    }

    // MARK: - Cell splitting

    /// Delimiter row `line`'s column alignments.
    private func parseDelimRow(line: Range<Int>) -> [MarkdownNode.TableAlignment] {
        let cells = splitCells(line: line).cells
        precondition(!cells.isEmpty, "a delimiter-candidate line holds a `-`, so it splits into at least one cell")
        return cells.map { cell in
            guard let alignment = delimiterAlignment(of: cell) else {
                preconditionFailure("a table-pending paragraph's delimiter line is a delimiter row")
            }
            return alignment
        }
    }

    /// A delimiter-row cell's alignment, or nil if `cell` isn't one: `:?-+:?` amid padding (spaces, tabs, line
    /// tabulations or form feeds).
    private func delimiterAlignment(of cell: Range<Int>) -> MarkdownNode.TableAlignment? {
        let marker = trim(cell, leading: \.isLineWhitespace, trailing: \.isLineWhitespace)
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

    /// `forEachCell`'s cells of `line`, collected.
    private func splitCells(line: Range<Int>) -> (cells: [Range<Int>], hadClosingPipe: Bool, hadLeadingPipe: Bool) {
        var cells: [Range<Int>] = []
        let pipes = forEachCell(in: line) { cells.append($0) }
        return (cells, pipes.hadClosingPipe, pipes.hadLeadingPipe)
    }

    /// Calls `body` with each cell of source line `line`, in order. Cells split on unescaped `|`, stripping a closing
    /// `|` and the padding after it, and a leading `|` only as the row's first byte.
    // Out of line, a table-heavy parse costs 0.7% more.
    @discardableResult @inline(__always)
    private func forEachCell(in line: Range<Int>, _ body: (Range<Int>) -> Void) -> (hadClosingPipe: Bool, hadLeadingPipe: Bool) {
        var s = line.lowerBound
        var e = line.upperBound
        while e > s && sourceBytes[e - 1].isSpaceOrTab {
            e -= 1
        }
        // A pipe after leading whitespace closes an empty first cell: ` |` is one empty cell, not a lone-pipe row.
        var hadLeadingPipe = false
        if s < e && sourceBytes[s] == UInt8(ascii: "|") {
            s += 1
            hadLeadingPipe = true
        }
        var hadClosingPipe = false
        // A closing pipe may be followed by line tabulations or form feeds; without one, they are the last
        // cell's content.
        var pipeEnd = e
        while pipeEnd > s && sourceBytes[pipeEnd - 1].isLineWhitespace {
            pipeEnd -= 1
        }
        if pipeEnd > s && sourceBytes[pipeEnd - 1] == UInt8(ascii: "|") && !isEscapedPipe(at: pipeEnd - 1, from: line.lowerBound) {
            e = pipeEnd - 1
            hadClosingPipe = true
        }
        var cellCount = 0
        var cellStart = s
        for i in s..<e where sourceBytes[i] == UInt8(ascii: "|") && !isEscapedPipe(at: i, from: line.lowerBound) {
            body(cellStart..<i)
            cellCount += 1
            cellStart = i + 1
        }
        // A lone leading pipe with only padding after it is zero cells, so `|\n-|` is a paragraph. `||` has
        // a closing pipe, so its one empty cell is kept.
        if cellCount == 0 && hadLeadingPipe && !hadClosingPipe
            && (cellStart..<e).allSatisfy({ sourceBytes[$0].isLineWhitespace }) {
            return (hadClosingPipe, hadLeadingPipe)
        }
        body(cellStart..<e)
        return (hadClosingPipe, hadLeadingPipe)
    }

    private func trim(_ range: Range<Int>, leading: (UInt8) -> Bool, trailing: (UInt8) -> Bool) -> Range<Int> {
        var s = range.lowerBound
        var e = range.upperBound
        while s < e && leading(sourceBytes[s]) {
            s += 1
        }
        while e > s && trailing(sourceBytes[e - 1]) {
            e -= 1
        }
        return s..<e
    }

    /// A cell's content. A pipe-preceded cell drops all leading padding; a row's first cell without a leading
    /// pipe keeps a leading line tabulation or form feed. A trailing line tabulation or form feed is content.
    private func trimCellContent(range: Range<Int>, stripLeadingVTFF: Bool) -> Range<Int> {
        precondition(stripLeadingVTFF || range.isEmpty || !sourceBytes[range.lowerBound].isSpaceOrTab, "a row's first cell starts past the row's leading spaces and tabs")
        return trim(range, leading: { stripLeadingVTFF && $0.isLineWhitespace }, trailing: \.isSpaceOrTab)
    }
}
