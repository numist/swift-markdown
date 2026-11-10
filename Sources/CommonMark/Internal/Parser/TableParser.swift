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
        precondition(splitCells(line: lines[0]).count == alignments.count, "a table-pending paragraph's header has the delimiter row's column count")
        let columnCount = alignments.count
        storage[node].kind = .table
        storage[node].data = .table(columnCount: columnCount)
        // Per column, the cell a rowspan filler in the next row grows: the nearest cell above that isn't a rowspan filler. It is kept rather than searched for, so a long column of markers stays linear. Empty without `.tableSpans`.
        var rowspanOwners: [DocumentStorage.Index?] = storage.options.contains(.tableSpans) ? Array(repeating: nil, count: columnCount) : []
        // The delimiter row (line 1) makes no `.tableRow`.
        for k in lines.indices where k != 1 {
            appendRow(
                parent: node,
                line: lines[k],
                alignments: alignments,
                isHeader: k == 0,
                rowspanOwners: &rowspanOwners
            )
        }
        // The table runs from its header row to its last line, the delimiter row when it has no body.
        storage.setSourceStart(node, rowRange(lines[0]).lowerBound)
        storage.setSourceEnd(node, rowRange(lines[lines.count - 1]).upperBound)
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

    /// Whether body-row candidate `sourceBytes[range]` is a lone `|` amid padding. Such a row has no cells
    /// (`forEachCell`), so it closes the table.
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

    /// Appends a `.tableRow` and its cells under `parent`, inserting missing cells and dropping extras.
    ///
    /// With `.tableSpans`, a zero-width `||` cell is a colspan filler (`columns: 0`) that grows the nearest cell to its left that isn't one, and a cell holding only the rowspan marker (`^`, or `"` with `.tableRowspanDitto`) is a rowspan filler (`rows: 0`) that, when its column has an owner above, grows that owner and drops its text. Every cell that isn't a rowspan filler, colspan fillers and inserted cells included, becomes its column's owner.
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

        // Empty without `.tableSpans`, so the common path does not allocate.
        let spansEnabled = storage.options.contains(.tableSpans)
        var colspans: [Int] = []
        var rowspans: [Int] = []
        var skipContent: [Bool] = []
        if spansEnabled {
            // Colspan accumulates over every cell, so colspan fillers past `columnCount`, which are dropped, still
            // grow the nearest cell to their left that isn't one, uncapped.
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
                // A cell whose content is exactly the marker byte is a rowspan filler.
                if col < columnCount {
                    let content = trimmingPadding(cells[col])
                    if content.count == 1 && sourceBytes[content.lowerBound] == markerByte {
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
            // A cell covers its content, without the padding between it and the pipes; a cell with no content has an
            // empty range just past its opening pipe.
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
    /// not a cell boundary, however many backslashes precede it.
    private func isEscapedPipe(at i: Int, from start: Int) -> Bool {
        sourceBytes[i] == UInt8(ascii: "|") && i > start && sourceBytes[i - 1] == UInt8(ascii: "\\")
    }

    // MARK: - Cell splitting

    /// Delimiter row `line`'s column alignments.
    private func parseDelimRow(line: Range<Int>) -> [MarkdownNode.TableAlignment] {
        let cells = splitCells(line: line)
        precondition(!cells.isEmpty, "a delimiter-candidate line holds a `-`, so it splits into at least one cell")
        return cells.map { cell in
            guard let alignment = delimiterAlignment(of: cell) else {
                preconditionFailure("a table-pending paragraph's delimiter line is a delimiter row")
            }
            return alignment
        }
    }

    /// A delimiter-row cell's alignment, or nil if `cell` isn't one: `:?-+:?` amid padding.
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

    /// `forEachCell`'s cells of `line`, collected.
    private func splitCells(line: Range<Int>) -> [Range<Int>] {
        var cells: [Range<Int>] = []
        forEachCell(in: line) { cells.append($0) }
        return cells
    }

    /// Calls `body` with each cell of source line `line`, in order. Cells split on each `|` that doesn't directly follow
    /// a backslash (`isEscapedPipe`). Padding may precede a leading `|` and follow a closing one; both pipes and that
    /// padding are stripped.
    // Out of line, a table-heavy parse costs 0.7% more.
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

    /// Source line `line`'s range as a row, from its leading pipe or first cell's content to its closing pipe or last
    /// cell's content, without padding: empty at its start when it holds only padding, as its one empty cell is.
    private func rowRange(_ line: Range<Int>) -> Range<Int> {
        let content = trimmingPadding(line)
        return content.isEmpty ? line.lowerBound..<line.lowerBound : content
    }

    /// `range` without its leading and trailing padding: every whitespace character other than a line ending, as
    /// the spec trims spaces between pipes and cell content (Tables (extension)).
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
