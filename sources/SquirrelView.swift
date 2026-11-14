//
//  SquirrelView.swift
//  Squirrel
//
//  Created by Leo Liu on 5/9/24.
//

import AppKit

private class SquirrelLayoutDelegate: NSObject, NSTextLayoutManagerDelegate {
  func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, shouldBreakLineBefore location: any NSTextLocation, hyphenating: Bool) -> Bool {
    let index = textLayoutManager.offset(from: textLayoutManager.documentRange.location, to: location)
    if let attributes = textLayoutManager.textContainer?.textView?.textContentStorage?.attributedString?.attributes(at: index, effectiveRange: nil),
       let noBreak = attributes[.noBreak] as? Bool, noBreak {
      return false
    }
    return true
  }
}

extension NSAttributedString.Key {
  static let noBreak = NSAttributedString.Key("noBreak")
}

final class CandidateGridView: NSView {
  struct Cell {
    let globalIndex: Int
    let text: String
    let frame: NSRect
    let textWidth: CGFloat
  }

  struct GridRow {
    let minY: CGFloat
    var cells: [Cell]
  }

  var rowHeight: CGFloat {
    max(28, ceil(theme.font.ascender - theme.font.descender) + 4)
  }
  static let maxVisibleRows = 5
  static let horizontalInset: CGFloat = 6
  static let labelGutter: CGFloat = 14
  static let minColumnUnit: CGFloat = 60
  static let maxItemsPerRow = 9

  private(set) var rows: [GridRow] = []
  private(set) var candidates: [String] = []
  private var indexMap: [Int: (row: Int, col: Int)] = [:]
  var highlightedIndex: Int = 0 {
    didSet {
      if oldValue != highlightedIndex {
        needsDisplay = true
      }
    }
  }
  var theme = SquirrelTheme()

  override var isFlipped: Bool { true }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  func updateLayout(candidates: [String], width: CGFloat, theme: SquirrelTheme) {
    self.candidates = candidates
    self.theme = theme
    rows.removeAll(keepingCapacity: true)
    indexMap.removeAll(keepingCapacity: true)

    let usableWidth = max(120, width - Self.horizontalInset * 2)
    let numUnitCols = max(1, min(Self.maxItemsPerRow, Int(floor(usableWidth / Self.minColumnUnit))))
    let colUnit = usableWidth / CGFloat(numUnitCols)
    let maxTextWidth = max(24, usableWidth - Self.labelGutter - 8)

    var usedCols = 0
    var rowIndex = 0
    var currentCells = [Cell]()

    for (idx, raw) in candidates.enumerated() {
      let text = raw.precomposedStringWithCanonicalMapping
      let rawWidth = ceil((text as NSString).size(withAttributes: theme.attrs).width)
      let textWidth = min(rawWidth, maxTextWidth)
      let neededWidth = Self.labelGutter + textWidth + 12
      let span = min(numUnitCols, max(1, Int(ceil(neededWidth / colUnit))))

      if !currentCells.isEmpty && (usedCols + span > numUnitCols || currentCells.count >= Self.maxItemsPerRow) {
        rows.append(GridRow(minY: CGFloat(rowIndex) * rowHeight, cells: currentCells))
        for col in currentCells.indices {
          indexMap[currentCells[col].globalIndex] = (rowIndex, col)
        }
        rowIndex += 1
        usedCols = 0
        currentCells.removeAll(keepingCapacity: true)
      }

      let minX = Self.horizontalInset + CGFloat(usedCols) * colUnit
      let cellFrame = NSRect(x: minX, y: CGFloat(rowIndex) * rowHeight, width: CGFloat(span) * colUnit, height: rowHeight)
      currentCells.append(Cell(globalIndex: idx, text: text, frame: cellFrame, textWidth: textWidth))
      usedCols += span
    }

    if !currentCells.isEmpty {
      rows.append(GridRow(minY: CGFloat(rowIndex) * rowHeight, cells: currentCells))
      for col in currentCells.indices {
        indexMap[currentCells[col].globalIndex] = (rowIndex, col)
      }
    }

    let totalHeight = max(rowHeight, CGFloat(rows.count) * rowHeight)
    frame = NSRect(x: 0, y: 0, width: width, height: totalHeight)
    needsDisplay = true
  }

  func location(of globalIndex: Int) -> (row: Int, col: Int)? {
    indexMap[globalIndex]
  }

  func candidateIndex(at point: NSPoint) -> Int? {
    guard point.x >= 0, point.x <= bounds.width, point.y >= 0 else { return nil }
    let rowIdx = Int(floor(point.y / rowHeight))
    guard rows.indices.contains(rowIdx) else { return nil }
    for cell in rows[rowIdx].cells where point.x >= cell.frame.minX - 4 && point.x < cell.frame.maxX {
      return cell.globalIndex
    }
    return nil
  }

  override func draw(_ dirtyRect: NSRect) {
    guard !rows.isEmpty else { return }
    let activeRow = indexMap[highlightedIndex]?.row
    let firstRow = max(0, Int(floor(dirtyRect.minY / rowHeight)))
    let lastRow = min(rows.count - 1, Int(ceil(dirtyRect.maxY / rowHeight)))
    guard firstRow <= lastRow else { return }

    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail

    let font = theme.font
    let labelFont = theme.labelFont
    let textLineHeight = font.ascender - font.descender
    let textYOffset = (rowHeight - textLineHeight) / 2
    let baselineOffset = (font.pointSize - labelFont.pointSize) / 2.5
    let labelYOffset = textYOffset + font.ascender - baselineOffset - labelFont.ascender

    for rowIdx in firstRow...lastRow {
      let row = rows[rowIdx]
      for (col, cell) in row.cells.enumerated() {
        let isHighlighted = cell.globalIndex == highlightedIndex
        if isHighlighted, let highlightColor = theme.highlightedBackColor {
          let pillX = max(2, cell.frame.minX - 4)
          let pillWidth = min(Self.labelGutter + cell.textWidth + 9, bounds.width - pillX - 2)
          let pillRect = NSRect(x: pillX, y: row.minY + 2, width: pillWidth, height: rowHeight - 4)
          let radius = min(theme.hilitedCornerRadius, min(pillRect.width, pillRect.height) / 2)
          let pill = NSBezierPath(roundedRect: pillRect, xRadius: radius, yRadius: radius)
          highlightColor.setFill()
          pill.fill()
        }
        if rowIdx == activeRow {
          let labelAttrs = isHighlighted ? theme.labelHighlightedAttrs : theme.labelAttrs
          ("\(col + 1)" as NSString).draw(
            at: NSPoint(x: cell.frame.minX + 1, y: row.minY + labelYOffset),
            withAttributes: labelAttrs
          )
        }
        var textAttrs = isHighlighted ? theme.highlightedAttrs : theme.attrs
        textAttrs[.paragraphStyle] = paragraph
        let drawRect = NSRect(
          x: cell.frame.minX + Self.labelGutter,
          y: row.minY + textYOffset,
          width: cell.textWidth + 2,
          height: textLineHeight + 2
        )
        (cell.text as NSString).draw(
          in: drawRect,
          withAttributes: textAttrs
        )
      }
    }
  }
}

final class SquirrelView: NSView {
  let textView: NSTextView

  private let squirrelLayoutDelegate: SquirrelLayoutDelegate
  var candidateRanges: [NSRange] = []
  var hilightedIndex = 0
  var preeditRange: NSRange = .empty
  var canPageUp: Bool = false
  var canPageDown: Bool = false
  var isExpanded = false
  var highlightedPreeditRange: NSRange = .empty
  var separatorWidth: CGFloat = 0
  var shape = CAShapeLayer()
  private var downPath: CGPath?
  private var upPath: CGPath?

  var lightTheme = SquirrelTheme()
  var darkTheme = SquirrelTheme()
  var currentTheme: SquirrelTheme {
    if isDark && darkTheme.available { darkTheme } else { lightTheme }
  }
  var textLayoutManager: NSTextLayoutManager {
    textView.textLayoutManager!
  }
  var textContentStorage: NSTextContentStorage {
    textView.textContentStorage!
  }
  var textContainer: NSTextContainer {
    textLayoutManager.textContainer!
  }

  override init(frame frameRect: NSRect) {
    squirrelLayoutDelegate = SquirrelLayoutDelegate()
    textView = NSTextView(frame: frameRect)
    textView.drawsBackground = false
    textView.isEditable = false
    textView.isSelectable = false
    textView.textLayoutManager?.delegate = squirrelLayoutDelegate
    super.init(frame: frameRect)
    textContainer.lineFragmentPadding = 0
    self.wantsLayer = true
    self.layer?.masksToBounds = true
  }
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var isFlipped: Bool {
    true
  }
  var isDark: Bool {
    NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
  }

  func convert(range: NSRange) -> NSTextRange? {
    guard range != .empty else { return nil }
    guard let startLocation = textLayoutManager.location(textLayoutManager.documentRange.location, offsetBy: range.location) else { return nil }
    guard let endLocation = textLayoutManager.location(startLocation, offsetBy: range.length) else { return nil }
    return NSTextRange(location: startLocation, end: endLocation)
  }

  var contentRect: NSRect {
    var ranges = candidateRanges
    if preeditRange.length > 0 {
      ranges.append(preeditRange)
    }
    // swiftlint:disable:next identifier_name
    var x0 = CGFloat.infinity, x1 = -CGFloat.infinity, y0 = CGFloat.infinity, y1 = -CGFloat.infinity
    for range in ranges {
      if let textRange = convert(range: range) {
        let rect = contentRect(range: textRange)
        x0 = min(rect.minX, x0)
        x1 = max(rect.maxX, x1)
        y0 = min(rect.minY, y0)
        y1 = max(rect.maxY, y1)
      }
    }
    if x1 == -CGFloat.infinity { return .zero }
    return NSRect(x: min(0, x0), y: min(0, y0), width: x1 - min(0, x0), height: y1 - min(0, y0))
  }

  func contentRect(range: NSTextRange) -> NSRect {
    // swiftlint:disable:next identifier_name
    var x0 = CGFloat.infinity, x1 = -CGFloat.infinity, y0 = CGFloat.infinity, y1 = -CGFloat.infinity
    textLayoutManager.enumerateTextSegments(in: range, type: .selection, options: [.rangeNotRequired]) { _, rect, _, _ in
      x0 = min(rect.minX, x0)
      x1 = max(rect.maxX, x1)
      y0 = min(rect.minY, y0)
      y1 = max(rect.maxY, y1)
      return true
    }
    return NSRect(x: x0, y: y0, width: x1-x0, height: y1-y0)
  }

  // swiftlint:disable:next function_parameter_count
  func drawView(candidateRanges: [NSRange], hilightedIndex: Int, preeditRange: NSRange, highlightedPreeditRange: NSRange, canPageUp: Bool, canPageDown: Bool) {
    self.candidateRanges = candidateRanges
    self.hilightedIndex = hilightedIndex
    self.preeditRange = preeditRange
    self.highlightedPreeditRange = highlightedPreeditRange
    self.canPageUp = canPageUp
    self.canPageDown = canPageDown
    self.needsDisplay = true
  }

  // swiftlint:disable:next cyclomatic_complexity
  override func draw(_ dirtyRect: NSRect) {
    var backgroundPath: CGPath?
    var preeditPath: CGPath?
    var candidatePaths: CGMutablePath?
    var highlightedPath: CGMutablePath?
    var highlightedPreeditPath: CGMutablePath?
    let theme = currentTheme
    if theme.isSingleLineLinear && isExpanded {
      drawExpandedBackground(theme: theme)
      return
    }

    var containingRect = self.bounds
    containingRect.size.width -= theme.pagingOffset
    let backgroundRect = theme.isSingleLineLinear ? bounds : containingRect

    var preeditRect = NSRect.zero
    if preeditRange.length > 0, let preeditTextRange = convert(range: preeditRange) {
      preeditRect = contentRect(range: preeditTextRange)
      preeditRect.size.width = backgroundRect.size.width
      preeditRect.size.height += theme.edgeInset.height + theme.preeditLinespace / 2 + theme.hilitedCornerRadius / 2
      preeditRect.origin = backgroundRect.origin
      if candidateRanges.count == 0 {
        preeditRect.size.height += theme.edgeInset.height - theme.preeditLinespace / 2 - theme.hilitedCornerRadius / 2
      }
      containingRect.size.height -= preeditRect.size.height
      containingRect.origin.y += preeditRect.size.height
      if theme.preeditBackgroundColor != nil {
        preeditPath = drawSmoothLines(rectVertex(of: preeditRect), straightCorner: Set(), alpha: 0, beta: 0)
      }
    }

    containingRect = carveInset(rect: containingRect)
    for i in 0..<candidateRanges.count {
      let candidate = candidateRanges[i]
      if i == hilightedIndex {
        if candidate.length > 0 && theme.highlightedBackColor != nil {
          highlightedPath = drawPath(highlightedRange: candidate, backgroundRect: backgroundRect, preeditRect: preeditRect, containingRect: containingRect, extraExpansion: 0)?.mutableCopy()
        }
      } else {
        if candidate.length > 0 && theme.candidateBackColor != nil {
          let candidatePath = drawPath(highlightedRange: candidate, backgroundRect: backgroundRect, preeditRect: preeditRect,
                                       containingRect: containingRect, extraExpansion: theme.surroundingExtraExpansion)
          if candidatePaths == nil {
            candidatePaths = CGMutablePath()
          }
          if let candidatePath = candidatePath {
            candidatePaths?.addPath(candidatePath)
          }
        }
      }
    }

    if (highlightedPreeditRange.length > 0) && (theme.highlightedPreeditColor != nil), let highlightedPreeditTextRange = convert(range: highlightedPreeditRange) {
      var innerBox = preeditRect
      innerBox.size.width -= (theme.edgeInset.width + 1) * 2
      innerBox.origin.x += theme.edgeInset.width + 1
      innerBox.origin.y += theme.edgeInset.height + 1
      if candidateRanges.count == 0 {
        innerBox.size.height -= (theme.edgeInset.height + 1) * 2
      } else {
        innerBox.size.height -= theme.edgeInset.height + theme.preeditLinespace / 2 + theme.hilitedCornerRadius / 2 + 2
      }
      var outerBox = preeditRect
      outerBox.size.height -= max(0, theme.hilitedCornerRadius + theme.borderLineWidth)
      outerBox.size.width -= max(0, theme.hilitedCornerRadius + theme.borderLineWidth)
      outerBox.origin.x += max(0, theme.hilitedCornerRadius + theme.borderLineWidth) / 2
      outerBox.origin.y += max(0, theme.hilitedCornerRadius + theme.borderLineWidth) / 2

      let (leadingRect, bodyRect, trailingRect) = multilineRects(forRange: highlightedPreeditTextRange, extraSurounding: 0, bounds: outerBox)
      var (highlightedPoints, highlightedPoints2, rightCorners, rightCorners2) = linearMultilineFor(body: bodyRect, leading: leadingRect, trailing: trailingRect)

      containingRect = carveInset(rect: preeditRect)
      highlightedPoints = expand(vertex: highlightedPoints, innerBorder: innerBox, outerBorder: outerBox)
      rightCorners = removeCorner(highlightedPoints: highlightedPoints, rightCorners: rightCorners, containingRect: containingRect)
      highlightedPreeditPath = drawSmoothLines(highlightedPoints, straightCorner: rightCorners, alpha: 0.3 * theme.hilitedCornerRadius, beta: 1.4 * theme.hilitedCornerRadius)?.mutableCopy()
      if highlightedPoints2.count > 0 {
        highlightedPoints2 = expand(vertex: highlightedPoints2, innerBorder: innerBox, outerBorder: outerBox)
        rightCorners2 = removeCorner(highlightedPoints: highlightedPoints2, rightCorners: rightCorners2, containingRect: containingRect)
        let highlightedPreeditPath2 = drawSmoothLines(highlightedPoints2, straightCorner: rightCorners2, alpha: 0.3 * theme.hilitedCornerRadius, beta: 1.4 * theme.hilitedCornerRadius)
        if let highlightedPreeditPath2 = highlightedPreeditPath2 {
          highlightedPreeditPath?.addPath(highlightedPreeditPath2)
        }
      }
    }

    NSBezierPath.defaultLineWidth = 0
    backgroundPath = drawSmoothLines(rectVertex(of: backgroundRect), straightCorner: Set(), alpha: 0.3 * theme.cornerRadius, beta: 1.4 * theme.cornerRadius)

    self.layer?.sublayers = nil
    let backPath = backgroundPath?.mutableCopy()
    if let path = preeditPath {
      backPath?.addPath(path)
    }
    if theme.mutualExclusive {
      if let path = highlightedPath {
        backPath?.addPath(path)
      }
      if let path = candidatePaths {
        backPath?.addPath(path)
      }
    }
    let panelLayer = shapeFromPath(path: backPath)
    panelLayer.fillColor = theme.backgroundColor.cgColor
    let panelLayerMask = shapeFromPath(path: backgroundPath)
    panelLayer.mask = panelLayerMask
    self.layer?.addSublayer(panelLayer)

    if let color = theme.preeditBackgroundColor, let path = preeditPath {
      let layer = shapeFromPath(path: path)
      layer.fillColor = color.cgColor
      let maskPath = backgroundPath?.mutableCopy()
      if theme.mutualExclusive, let hilitedPath = highlightedPreeditPath {
        maskPath?.addPath(hilitedPath)
      }
      let mask = shapeFromPath(path: maskPath)
      layer.mask = mask
      panelLayer.addSublayer(layer)
    }
    if theme.borderLineWidth > 0, let color = theme.borderColor {
      let borderLayer = shapeFromPath(path: backgroundPath)
      borderLayer.lineWidth = theme.borderLineWidth * 2
      borderLayer.strokeColor = color.cgColor
      borderLayer.fillColor = nil
      panelLayer.addSublayer(borderLayer)
    }
    if let color = theme.highlightedPreeditColor, let path = highlightedPreeditPath {
      let layer = shapeFromPath(path: path)
      layer.fillColor = color.cgColor
      panelLayer.addSublayer(layer)
    }
    if let color = theme.candidateBackColor, let path = candidatePaths {
      let layer = shapeFromPath(path: path)
      layer.fillColor = color.cgColor
      panelLayer.addSublayer(layer)
    }
    if let color = theme.highlightedBackColor, let path = highlightedPath {
      let layer = shapeFromPath(path: path)
      layer.fillColor = color.cgColor
      if theme.shadowSize > 0 {
        let shadowLayer = CAShapeLayer()
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOffset = NSSize(width: theme.shadowSize/2, height: (theme.vertical ? -1 : 1) * theme.shadowSize/2)
        shadowLayer.shadowPath = highlightedPath
        shadowLayer.shadowRadius = theme.shadowSize
        shadowLayer.shadowOpacity = 0.2
        let outerPath = backgroundPath?.mutableCopy()
        outerPath?.addPath(path)
        let shadowLayerMask = shapeFromPath(path: outerPath)
        shadowLayer.mask = shadowLayerMask
        layer.strokeColor = NSColor.black.withAlphaComponent(0.15).cgColor
        layer.lineWidth = 0.5
        layer.addSublayer(shadowLayer)
      }
      panelLayer.addSublayer(layer)
    }
    panelLayer.setAffineTransform(CGAffineTransform(translationX: theme.isSingleLineLinear ? 0 : theme.pagingOffset, y: 0))
    let panelPath = CGMutablePath()
    panelPath.addPath(backgroundPath!, transform: panelLayer.affineTransform().scaledBy(x: 1, y: -1).translatedBy(x: 0, y: -self.bounds.height))

    let (pagingLayer, downPath, upPath) = pagingLayer(theme: theme, preeditRect: preeditRect)
    if let sublayers = pagingLayer.sublayers, !sublayers.isEmpty {
      self.layer?.addSublayer(pagingLayer)
    }
    self.downPath = downPath?.copy()
    self.upPath = upPath?.copy()
    let flipTransform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -self.bounds.height)
    if let downPath {
      panelPath.addPath(downPath, transform: flipTransform)
    }
    if let upPath {
      panelPath.addPath(upPath, transform: flipTransform)
    }

    shape.path = panelPath
  }

  func click(at clickPoint: NSPoint) -> (Int?, Int?, Bool?) {
    var index = 0
    var candidateIndex: Int?
    var preeditIndex: Int?
    if let downPath = self.downPath, downPath.contains(clickPoint) {
      return (nil, nil, false)
    }
    if let upPath = self.upPath, upPath.contains(clickPoint) {
      return (nil, nil, true)
    }
    if let path = shape.path, path.contains(clickPoint) {
      let pagingInset = currentTheme.isSingleLineLinear ? 0 : currentTheme.pagingOffset
      var point = NSPoint(x: clickPoint.x - textView.textContainerInset.width - pagingInset,
                          y: clickPoint.y - textView.textContainerInset.height)
      let fragment = textLayoutManager.textLayoutFragment(for: point)
      if let fragment = fragment {
        point = NSPoint(x: point.x - fragment.layoutFragmentFrame.minX,
                        y: point.y - fragment.layoutFragmentFrame.minY)
        index = textLayoutManager.offset(from: textLayoutManager.documentRange.location, to: fragment.rangeInElement.location)
        for lineFragment in fragment.textLineFragments where lineFragment.typographicBounds.contains(point) {
          point = NSPoint(x: point.x - lineFragment.typographicBounds.minX,
                          y: point.y - lineFragment.typographicBounds.minY)
          index += lineFragment.characterIndex(for: point)
          if index >= preeditRange.location && index < preeditRange.upperBound {
            preeditIndex = index
          } else {
            for i in 0..<candidateRanges.count {
              let range = candidateRanges[i]
              if index >= range.location && index < range.upperBound {
                candidateIndex = i
                break
              }
            }
          }
          break
        }
      }
    }
    return (candidateIndex, preeditIndex, nil)
  }
}

private extension SquirrelView {
  func drawExpandedBackground(theme: SquirrelTheme) {
    layer?.sublayers = nil
    let outline = drawSmoothLines(rectVertex(of: bounds), straightCorner: [],
                                  alpha: 0.3 * theme.cornerRadius, beta: 1.4 * theme.cornerRadius)
    shape.path = outline
    let background = shapeFromPath(path: outline)
    background.fillColor = theme.backgroundColor.cgColor
    if let border = theme.borderColor, theme.borderLineWidth > 0 {
      background.strokeColor = border.cgColor
      background.lineWidth = theme.borderLineWidth * 2
    }
    layer?.addSublayer(background)
    let (button, downButton, upButton) = expansionLayer(theme: theme)
    layer?.addSublayer(button)
    downPath = downButton
    upPath = upButton
  }

  func expansionLayer(theme: SquirrelTheme) -> (CAShapeLayer, CGPath?, CGPath?) {
    let button = CAShapeLayer()
    guard theme.showPaging && (canPageUp || canPageDown) else { return (button, nil, nil) }
    let left = bounds.maxX - theme.pagingOffset
    let height = isExpanded ? min(28, bounds.height) : bounds.height
    let center = NSPoint(x: left + theme.pagingOffset / 2, y: height / 2)
    let direction: CGFloat = isExpanded ? -1 : 1
    let path = CGMutablePath()
    path.move(to: NSPoint(x: center.x - 3.5, y: center.y - 1.5 * direction))
    path.addLine(to: NSPoint(x: center.x, y: center.y + 2 * direction))
    path.addLine(to: NSPoint(x: center.x + 3.5, y: center.y - 1.5 * direction))
    button.path = path
    button.fillColor = nil
    button.strokeColor = (theme.labelAttrs[.foregroundColor] as? NSColor)?.cgColor
    button.lineWidth = 1.5
    button.lineCap = .round
    button.lineJoin = .round
    let hit = CGPath(rect: NSRect(x: left, y: 0, width: theme.pagingOffset, height: height), transform: nil)
    return isExpanded ? (button, nil, hit) : (button, hit, nil)
  }

  // Soften corner radius when adjacent points are very close.
  func sign(_ number: NSPoint) -> NSPoint {
    if number.length >= 2 {
      return number / number.length
    } else {
      return number / 2
    }
  }

  // Use cubic Bezier corners for continuous rounded paths.
  func drawSmoothLines(_ vertex: [NSPoint], straightCorner: Set<Int>, alpha: CGFloat, beta rawBeta: CGFloat) -> CGPath? {
    guard vertex.count >= 3 else {
      return nil
    }
    let beta = max(0.00001, rawBeta)
    let path = CGMutablePath()
    var previousPoint = vertex[vertex.count-1]
    var point = vertex[0]
    var nextPoint: NSPoint
    var control1: NSPoint
    var control2: NSPoint
    var target = previousPoint
    var diff = point - previousPoint
    if straightCorner.isEmpty || !straightCorner.contains(vertex.count-1) {
      target += sign(diff / beta) * beta
    }
    path.move(to: target)
    for i in 0..<vertex.count {
      previousPoint = vertex[(vertex.count+i-1)%vertex.count]
      point = vertex[i]
      nextPoint = vertex[(i+1)%vertex.count]
      target = point
      if straightCorner.contains(i) {
        path.addLine(to: target)
      } else {
        control1 = point
        diff = point - previousPoint

        target -= sign(diff / beta) * beta
        control1 -= sign(diff / beta) * alpha

        path.addLine(to: target)
        target = point
        control2 = point
        diff = nextPoint - point

        target += sign(diff / beta) * beta
        control2 += sign(diff / beta) * alpha

        path.addCurve(to: target, control1: control1, control2: control2)
      }
    }
    path.closeSubpath()
    return path
  }

  func rectVertex(of rect: NSRect) -> [NSPoint] {
    [rect.origin,
     NSPoint(x: rect.origin.x, y: rect.origin.y+rect.size.height),
     NSPoint(x: rect.origin.x+rect.size.width, y: rect.origin.y+rect.size.height),
     NSPoint(x: rect.origin.x+rect.size.width, y: rect.origin.y)]
  }

  func nearEmpty(_ rect: NSRect) -> Bool {
    return rect.size.height * rect.size.width < 1
  }

  // Split a multiline range into leading, complete-body, and trailing boxes.
  func multilineRects(forRange range: NSTextRange, extraSurounding: Double, bounds: NSRect) -> (NSRect, NSRect, NSRect) {
    let edgeInset = currentTheme.edgeInset
    var lineRects = [NSRect]()
    textLayoutManager.enumerateTextSegments(in: range, type: .selection, options: [.rangeNotRequired]) { _, rect, _, _ in
      var newRect = rect
      newRect.origin.x += edgeInset.width
      newRect.origin.y += edgeInset.height
      newRect.size.height += currentTheme.linespace
      newRect.origin.y -= currentTheme.linespace / 2
      lineRects.append(newRect)
      return true
    }

    var leadingRect = NSRect.zero
    var bodyRect = NSRect.zero
    var trailingRect = NSRect.zero
    if lineRects.count == 1 {
      bodyRect = lineRects[0]
    } else if lineRects.count == 2 {
      leadingRect = lineRects[0]
      trailingRect = lineRects[1]
    } else if lineRects.count > 2 {
      leadingRect = lineRects[0]
      trailingRect = lineRects[lineRects.count-1]
      // swiftlint:disable:next identifier_name
      var x0 = CGFloat.infinity, x1 = -CGFloat.infinity, y0 = CGFloat.infinity, y1 = -CGFloat.infinity
      for i in 1..<(lineRects.count-1) {
        let rect = lineRects[i]
        x0 = min(rect.minX, x0)
        x1 = max(rect.maxX, x1)
        y0 = min(rect.minY, y0)
        y1 = max(rect.maxY, y1)
      }
      y0 = min(leadingRect.maxY, y0)
      y1 = max(trailingRect.minY, y1)
      bodyRect = NSRect(x: x0, y: y0, width: x1-x0, height: y1-y0)
    }

    if extraSurounding > 0 {
      if nearEmpty(leadingRect) && nearEmpty(trailingRect) {
        bodyRect = expandHighlightWidth(rect: bodyRect, extraSurrounding: extraSurounding)
      } else {
        if !(nearEmpty(leadingRect)) {
          leadingRect = expandHighlightWidth(rect: leadingRect, extraSurrounding: extraSurounding)
        }
        if !(nearEmpty(trailingRect)) {
          trailingRect = expandHighlightWidth(rect: trailingRect, extraSurrounding: extraSurounding)
        }
      }
    }

    if !nearEmpty(leadingRect) && !nearEmpty(trailingRect) {
      leadingRect.size.width = bounds.maxX - leadingRect.origin.x
      trailingRect.size.width = trailingRect.maxX - bounds.minX
      trailingRect.origin.x = bounds.minX
      if !nearEmpty(bodyRect) {
        bodyRect.size.width = bounds.size.width
        bodyRect.origin.x = bounds.origin.x
      } else {
        let diff = trailingRect.minY - leadingRect.maxY
        leadingRect.size.height += diff / 2
        trailingRect.size.height += diff / 2
        trailingRect.origin.y -= diff / 2
      }
    }

    return (leadingRect, bodyRect, trailingRect)
  }

  // Build the highlight polygon from the multiline text boxes.
  func multilineVertex(leadingRect: NSRect, bodyRect: NSRect, trailingRect: NSRect) -> [NSPoint] {
    if nearEmpty(bodyRect) && !nearEmpty(leadingRect) && nearEmpty(trailingRect) {
      return rectVertex(of: leadingRect)
    } else if nearEmpty(bodyRect) && nearEmpty(leadingRect) && !nearEmpty(trailingRect) {
      return rectVertex(of: trailingRect)
    } else if nearEmpty(leadingRect) && nearEmpty(trailingRect) && !nearEmpty(bodyRect) {
      return rectVertex(of: bodyRect)
    } else if nearEmpty(trailingRect) && !nearEmpty(bodyRect) {
      let leadingVertex = rectVertex(of: leadingRect)
      let bodyVertex = rectVertex(of: bodyRect)
      return [bodyVertex[0], bodyVertex[1], bodyVertex[2], leadingVertex[3], leadingVertex[0], leadingVertex[1]]
    } else if nearEmpty(leadingRect) && !nearEmpty(bodyRect) {
      let trailingVertex = rectVertex(of: trailingRect)
      let bodyVertex = rectVertex(of: bodyRect)
      return [trailingVertex[1], trailingVertex[2], trailingVertex[3], bodyVertex[2], bodyVertex[3], bodyVertex[0]]
    } else if !nearEmpty(leadingRect) && !nearEmpty(trailingRect) && nearEmpty(bodyRect) && (leadingRect.maxX>trailingRect.minX) {
      let leadingVertex = rectVertex(of: leadingRect)
      let trailingVertex = rectVertex(of: trailingRect)
      return [trailingVertex[0], trailingVertex[1], trailingVertex[2], trailingVertex[3], leadingVertex[2], leadingVertex[3], leadingVertex[0], leadingVertex[1]]
    } else if !nearEmpty(leadingRect) && !nearEmpty(trailingRect) && !nearEmpty(bodyRect) {
      let leadingVertex = rectVertex(of: leadingRect)
      let bodyVertex = rectVertex(of: bodyRect)
      let trailingVertex = rectVertex(of: trailingRect)
      return [trailingVertex[1], trailingVertex[2], trailingVertex[3], bodyVertex[2], leadingVertex[3], leadingVertex[0], leadingVertex[1], bodyVertex[0]]
    } else {
      return [NSPoint]()
    }
  }

  // Clamp points outside the inner border to the outer border.
  func expand(vertex: [NSPoint], innerBorder: NSRect, outerBorder: NSRect) -> [NSPoint] {
    var newVertex = [NSPoint]()
    for i in 0..<vertex.count {
      var point = vertex[i]
      if point.x < innerBorder.origin.x {
        point.x = outerBorder.origin.x
      } else if point.x > innerBorder.origin.x+innerBorder.size.width {
        point.x = outerBorder.origin.x+outerBorder.size.width
      }
      if point.y < innerBorder.origin.y {
        point.y = outerBorder.origin.y
      } else if point.y > innerBorder.origin.y+innerBorder.size.height {
        point.y = outerBorder.origin.y+outerBorder.size.height
      }
      newVertex.append(point)
    }
    return newVertex
  }

  func direction(diff: CGPoint) -> CGPoint {
    if diff.y == 0 && diff.x > 0 {
      return NSPoint(x: 0, y: 1)
    } else if diff.y == 0 && diff.x < 0 {
      return NSPoint(x: 0, y: -1)
    } else if diff.x == 0 && diff.y > 0 {
      return NSPoint(x: -1, y: 0)
    } else if diff.x == 0 && diff.y < 0 {
      return NSPoint(x: 1, y: 0)
    } else {
      return NSPoint(x: 0, y: 0)
    }
  }

  func shapeFromPath(path: CGPath?) -> CAShapeLayer {
    let layer = CAShapeLayer()
    layer.path = path
    layer.fillRule = .evenOdd
    return layer
  }

  // Assumes clockwise iteration
  func enlarge(vertex: [NSPoint], by: Double) -> [NSPoint] {
    if by != 0 {
      var previousPoint: NSPoint
      var point: NSPoint
      var nextPoint: NSPoint
      var results = vertex
      var newPoint: NSPoint
      var displacement: NSPoint
      for i in 0..<vertex.count {
        previousPoint = vertex[(vertex.count+i-1) % vertex.count]
        point = vertex[i]
        nextPoint = vertex[(i+1) % vertex.count]
        newPoint = point
        displacement = direction(diff: point - previousPoint)
        newPoint.x += by * displacement.x
        newPoint.y += by * displacement.y
        displacement = direction(diff: nextPoint - point)
        newPoint.x += by * displacement.x
        newPoint.y += by * displacement.y
        results[i] = newPoint
      }
      return results
    } else {
      return vertex
    }
  }

  func expandHighlightWidth(rect: NSRect, extraSurrounding: CGFloat) -> NSRect {
    var newRect = rect
    if !nearEmpty(newRect) {
      newRect.size.width += extraSurrounding
      newRect.origin.x -= extraSurrounding / 2
    }
    return newRect
  }

  func removeCorner(highlightedPoints: [CGPoint], rightCorners: Set<Int>, containingRect: NSRect) -> Set<Int> {
    if !highlightedPoints.isEmpty && !rightCorners.isEmpty {
      var result = rightCorners
      for cornerIndex in rightCorners {
        let corner = highlightedPoints[cornerIndex]
        let dist = min(containingRect.maxY - corner.y, corner.y - containingRect.minY)
        if dist < 1e-2 {
          result.remove(cornerIndex)
        }
      }
      return result
    } else {
      return rightCorners
    }
  }

  // swiftlint:disable:next large_tuple
  func linearMultilineFor(body: NSRect, leading: NSRect, trailing: NSRect) -> (Array<NSPoint>, Array<NSPoint>, Set<Int>, Set<Int>) {
    let highlightedPoints, highlightedPoints2: [NSPoint]
    let rightCorners, rightCorners2: Set<Int>
    if nearEmpty(body) && !nearEmpty(leading) && !nearEmpty(trailing) && trailing.maxX < leading.minX {
      highlightedPoints = rectVertex(of: leading)
      highlightedPoints2 = rectVertex(of: trailing)
      rightCorners = [2, 3]
      rightCorners2 = [0, 1]
    } else {
      highlightedPoints = multilineVertex(leadingRect: leading, bodyRect: body, trailingRect: trailing)
      highlightedPoints2 = []
      rightCorners = []
      rightCorners2 = []
    }
    return (highlightedPoints, highlightedPoints2, rightCorners, rightCorners2)
  }

  func drawPath(highlightedRange: NSRange, backgroundRect: NSRect, preeditRect: NSRect, containingRect: NSRect, extraExpansion: Double) -> CGPath? {
    let theme = currentTheme
    let resultingPath: CGMutablePath?

    var currentContainingRect = containingRect
    currentContainingRect.size.width += extraExpansion * 2
    currentContainingRect.size.height += extraExpansion * 2
    currentContainingRect.origin.x -= extraExpansion
    currentContainingRect.origin.y -= extraExpansion

    let halfLinespace = theme.linespace / 2
    var innerBox = backgroundRect
    innerBox.size.width -= (theme.edgeInset.width + 1) * 2 - 2 * extraExpansion
    innerBox.origin.x += theme.edgeInset.width + 1 - extraExpansion
    innerBox.size.height += 2 * extraExpansion
    innerBox.origin.y -= extraExpansion
    if preeditRange.length == 0 {
      innerBox.origin.y += theme.edgeInset.height + 1
      innerBox.size.height -= (theme.edgeInset.height + 1) * 2
    } else {
      innerBox.origin.y += preeditRect.size.height + theme.preeditLinespace / 2 + theme.hilitedCornerRadius / 2 + 1
      innerBox.size.height -= theme.edgeInset.height + preeditRect.size.height + theme.preeditLinespace / 2 + theme.hilitedCornerRadius / 2 + 2
    }
    innerBox.size.height -= theme.linespace
    innerBox.origin.y += halfLinespace

    var outerBox = backgroundRect
    outerBox.size.height -= preeditRect.size.height + max(0, theme.hilitedCornerRadius + theme.borderLineWidth) - 2 * extraExpansion
    outerBox.size.width -= max(0, theme.hilitedCornerRadius + theme.borderLineWidth)  - 2 * extraExpansion
    outerBox.origin.x += max(0.0, theme.hilitedCornerRadius + theme.borderLineWidth) / 2.0 - extraExpansion
    outerBox.origin.y += preeditRect.size.height + max(0, theme.hilitedCornerRadius + theme.borderLineWidth) / 2 - extraExpansion

    let effectiveRadius = max(0, theme.hilitedCornerRadius + 2 * extraExpansion / theme.hilitedCornerRadius * max(0, theme.cornerRadius - theme.hilitedCornerRadius))

    if theme.linear, let highlightedTextRange = convert(range: highlightedRange) {
      let (leadingRect, bodyRect, trailingRect) = multilineRects(forRange: highlightedTextRange, extraSurounding: separatorWidth, bounds: outerBox)
      var (highlightedPoints, highlightedPoints2, rightCorners, rightCorners2) = linearMultilineFor(body: bodyRect, leading: leadingRect, trailing: trailingRect)

      highlightedPoints = enlarge(vertex: highlightedPoints, by: extraExpansion)
      highlightedPoints = expand(vertex: highlightedPoints, innerBorder: innerBox, outerBorder: outerBox)
      rightCorners = removeCorner(highlightedPoints: highlightedPoints, rightCorners: rightCorners, containingRect: currentContainingRect)
      resultingPath = drawSmoothLines(highlightedPoints, straightCorner: rightCorners, alpha: 0.3*effectiveRadius, beta: 1.4*effectiveRadius)?.mutableCopy()

      if highlightedPoints2.count > 0 {
        highlightedPoints2 = enlarge(vertex: highlightedPoints2, by: extraExpansion)
        highlightedPoints2 = expand(vertex: highlightedPoints2, innerBorder: innerBox, outerBorder: outerBox)
        rightCorners2 = removeCorner(highlightedPoints: highlightedPoints2, rightCorners: rightCorners2, containingRect: currentContainingRect)
        let highlightedPath2 = drawSmoothLines(highlightedPoints2, straightCorner: rightCorners2, alpha: 0.3*effectiveRadius, beta: 1.4*effectiveRadius)
        if let highlightedPath2 = highlightedPath2 {
          resultingPath?.addPath(highlightedPath2)
        }
      }
    } else if let highlightedTextRange = convert(range: highlightedRange) {
      var highlightedRect = self.contentRect(range: highlightedTextRange)
      if !nearEmpty(highlightedRect) {
        highlightedRect.size.width = backgroundRect.size.width
        highlightedRect.size.height += theme.linespace
        highlightedRect.origin = NSPoint(x: backgroundRect.origin.x, y: highlightedRect.origin.y + theme.edgeInset.height - halfLinespace)
        if highlightedRange.upperBound == (textView.string as NSString).length {
          highlightedRect.size.height += theme.edgeInset.height - halfLinespace
        }
        if highlightedRange.location - (preeditRange == .empty ? 0 : preeditRange.upperBound) <= 1 {
          if preeditRange.length == 0 {
            highlightedRect.size.height += theme.edgeInset.height - halfLinespace
            highlightedRect.origin.y -= theme.edgeInset.height - halfLinespace
          } else {
            highlightedRect.size.height += theme.hilitedCornerRadius / 2
            highlightedRect.origin.y -= theme.hilitedCornerRadius / 2
          }
        }

        var highlightedPoints = rectVertex(of: highlightedRect)
        highlightedPoints = enlarge(vertex: highlightedPoints, by: extraExpansion)
        highlightedPoints = expand(vertex: highlightedPoints, innerBorder: innerBox, outerBorder: outerBox)
        resultingPath = drawSmoothLines(highlightedPoints, straightCorner: Set(), alpha: effectiveRadius*0.3, beta: effectiveRadius*1.4)?.mutableCopy()
      } else {
        resultingPath = nil
      }
    } else {
      resultingPath = nil
    }
    return resultingPath
  }

  func carveInset(rect: NSRect) -> NSRect {
    var newRect = rect
    newRect.size.height -= (currentTheme.hilitedCornerRadius + currentTheme.borderWidth) * 2
    newRect.size.width -= (currentTheme.hilitedCornerRadius + currentTheme.borderWidth) * 2
    newRect.origin.x += currentTheme.hilitedCornerRadius + currentTheme.borderWidth
    newRect.origin.y += currentTheme.hilitedCornerRadius + currentTheme.borderWidth
    return newRect
  }

  func triangle(center: NSPoint, radius: CGFloat) -> [NSPoint] {
    [NSPoint(x: center.x, y: center.y + radius),
     NSPoint(x: center.x + 0.5 * sqrt(3) * radius, y: center.y - 0.5 * radius),
     NSPoint(x: center.x - 0.5 * sqrt(3) * radius, y: center.y - 0.5 * radius)]
  }

  func pagingLayer(theme: SquirrelTheme, preeditRect: CGRect) -> (CAShapeLayer, CGPath?, CGPath?) {
    let layer = CAShapeLayer()
    if theme.isSingleLineLinear {
      return expansionLayer(theme: theme)
    }
    guard theme.showPaging && (canPageUp || canPageDown) else { return (layer, nil, nil) }
    guard let firstCandidate = candidateRanges.first, let range = convert(range: firstCandidate) else { return (layer, nil, nil) }
    var height = contentRect(range: range).height
    let preeditHeight = max(0, preeditRect.height + theme.preeditLinespace / 2 + theme.hilitedCornerRadius / 2 - theme.edgeInset.height) + theme.edgeInset.height - theme.linespace / 2
    height += theme.linespace
    let radius = min(0.5 * theme.pagingOffset, 2 * height / 9)
    let effectiveRadius = min(theme.cornerRadius, 0.6 * radius)
    guard let trianglePath = drawSmoothLines(
      triangle(center: .zero, radius: radius),
      straightCorner: [], alpha: 0.3 * effectiveRadius, beta: 1.4 * effectiveRadius
    ) else {
      return (layer, nil, nil)
    }
    var downPath: CGPath?
    var upPath: CGPath?
    if canPageDown {
      var downTransform = CGAffineTransform(translationX: 0.5 * theme.pagingOffset, y: 2 * height / 3 + preeditHeight)
      let downLayer = shapeFromPath(path: trianglePath.copy(using: &downTransform))
      downLayer.fillColor = theme.backgroundColor.cgColor
      downPath = trianglePath.copy(using: &downTransform)
      layer.addSublayer(downLayer)
    }
    if canPageUp {
      var upTransform = CGAffineTransform(rotationAngle: .pi).translatedBy(x: -0.5 * theme.pagingOffset, y: -height / 3 - preeditHeight)
      let upLayer = shapeFromPath(path: trianglePath.copy(using: &upTransform))
      upLayer.fillColor = theme.backgroundColor.cgColor
      upPath = trianglePath.copy(using: &upTransform)
      layer.addSublayer(upLayer)
    }
    return (layer, downPath, upPath)
  }
}
