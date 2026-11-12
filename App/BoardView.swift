import ChessCore
import SwiftUI

private enum BoardColors {
    static let light = Color(red: 0.94, green: 0.85, blue: 0.71)
    static let dark = Color(red: 0.71, green: 0.53, blue: 0.39)
    static let lastMove = Color(red: 0.80, green: 0.82, blue: 0.20).opacity(0.55)
    static let selected = Color(red: 0.08, green: 0.47, blue: 0.11).opacity(0.50)
    static let target = Color(red: 0.08, green: 0.33, blue: 0.11).opacity(0.45)
    static let check = Color(red: 0.90, green: 0.10, blue: 0.10)
    static let hint = Color(red: 0.15, green: 0.45, blue: 0.95).opacity(0.55)
}

/// What the board needs from the game or puzzle it shows.
@MainActor
protocol BoardModel: AnyObject {
    var position: Position { get }
    var lastMove: Move? { get }
    var selectedSquare: Square? { get }
    var targetSquares: [Square] { get }
    var checkedKingSquare: Square? { get }
    /// Squares marked as a hint.
    var hintSquares: [Square] { get }
    /// `true` when black is at the bottom.
    var isFlipped: Bool { get }

    func canSelect(_ square: Square) -> Bool
    func select(_ square: Square)
    func deselect()
    func tap(_ square: Square)
    func move(from: Square, to: Square)
}

/// The board. Pieces can be moved by click-click or by dragging.
struct BoardView<Model: BoardModel>: View {
    let model: Model

    /// A piece currently held with the mouse.
    private struct Drag: Equatable {
        let from: Square
        /// Whether the piece was already selected before the press. If so, a click clears the selection.
        let wasSelected: Bool
        var location: CGPoint
        var hasMoved = false
    }

    @State private var drag: Drag?
    /// Whether the current press has already been evaluated (even if no piece was picked up).
    @State private var pressHandled = false

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height) / 8
            ZStack(alignment: .topLeading) {
                squares(side: side)
                pieces(side: side)
                if let drag, drag.hasMoved, let piece = model.position[drag.from] {
                    PieceImage(piece: piece)
                        .frame(width: side * 1.2, height: side * 1.2)
                        .position(drag.location)
                        .shadow(radius: 3, y: 2)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: side * 8, height: side * 8, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(boardGesture(side: side))
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Drawing

    private func squares(side: CGFloat) -> some View {
        let lastMove = model.lastMove
        let targets = Set(model.targetSquares)
        let checked = model.checkedKingSquare
        let hints = model.hintSquares

        return ForEach(Square.all, id: \.self) { square in
            ZStack {
                (square.isLight ? BoardColors.light : BoardColors.dark)
                if square == lastMove?.from || square == lastMove?.to {
                    BoardColors.lastMove
                }
                if square == model.selectedSquare {
                    BoardColors.selected
                }
                if hints.contains(square) {
                    BoardColors.hint
                }
                if square == checked {
                    RadialGradient(
                        colors: [BoardColors.check, BoardColors.check.opacity(0)],
                        center: .center, startRadius: side * 0.1, endRadius: side * 0.6)
                }
                if targets.contains(square) {
                    targetMark(isCapture: model.position[square] != nil, side: side)
                }
                coordinateLabels(for: square, side: side)
            }
            .frame(width: side, height: side)
            .offset(origin(of: square, side: side))
        }
    }

    @ViewBuilder
    private func targetMark(isCapture: Bool, side: CGFloat) -> some View {
        if isCapture {
            Circle()
                .strokeBorder(BoardColors.target, lineWidth: side * 0.1)
                .padding(side * 0.04)
        } else {
            Circle()
                .fill(BoardColors.target)
                .frame(width: side * 0.3, height: side * 0.3)
        }
    }

    /// File letters along the bottom row, rank numbers along the left column of the visible board.
    @ViewBuilder
    private func coordinateLabels(for square: Square, side: CGFloat) -> some View {
        let color = square.isLight ? BoardColors.dark : BoardColors.light
        let font = Font.system(size: side * 0.21, weight: .semibold)
        if square.rank == (model.isFlipped ? 7 : 0) {
            Text(square.name.prefix(1))
                .font(font)
                .foregroundStyle(color)
                .padding(side * 0.04)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .accessibilityHidden(true)
        }
        if square.file == (model.isFlipped ? 7 : 0) {
            Text(square.name.suffix(1))
                .font(font)
                .foregroundStyle(color)
                .padding(side * 0.04)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityHidden(true)
        }
    }

    private func pieces(side: CGFloat) -> some View {
        ForEach(model.position.pieces, id: \.square) { square, piece in
            PieceImage(piece: piece)
                .frame(width: side, height: side)
                .opacity(drag?.hasMoved == true && drag?.from == square ? 0.3 : 1)
                .offset(origin(of: square, side: side))
                .allowsHitTesting(false)
        }
    }

    // MARK: - Geometry

    private func origin(of square: Square, side: CGFloat) -> CGSize {
        let column = model.isFlipped ? 7 - square.file : square.file
        let row = model.isFlipped ? square.rank : 7 - square.rank
        return CGSize(width: CGFloat(column) * side, height: CGFloat(row) * side)
    }

    private func square(at point: CGPoint, side: CGFloat) -> Square? {
        let column = Int((point.x / side).rounded(.down))
        let row = Int((point.y / side).rounded(.down))
        guard (0..<8).contains(column), (0..<8).contains(row) else { return nil }
        return model.isFlipped
            ? Square(file: 7 - column, rank: row)
            : Square(file: column, rank: 7 - row)
    }

    // MARK: - Input

    /// One gesture for both: releasing on the origin square is a click, anywhere else drops the piece.
    private func boardGesture(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if !pressHandled {
                    pressHandled = true
                    if let start = square(at: value.startLocation, side: side), model.canSelect(start) {
                        drag = Drag(
                            from: start,
                            wasSelected: model.selectedSquare == start,
                            location: value.location)
                        model.select(start)
                    }
                }
                guard drag != nil else { return }
                drag?.location = value.location
                if square(at: value.location, side: side) != drag?.from {
                    drag?.hasMoved = true
                }
            }
            .onEnded { value in
                defer {
                    drag = nil
                    pressHandled = false
                }
                let start = square(at: value.startLocation, side: side)
                let end = square(at: value.location, side: side)
                guard let drag else {
                    // No movable piece was picked up: a click on a target square or on nothing.
                    if let start, start == end { model.tap(start) }
                    return
                }
                if end == drag.from {
                    if drag.wasSelected && !drag.hasMoved { model.deselect() }
                } else if let end {
                    model.move(from: drag.from, to: end)
                }
            }
    }
}
