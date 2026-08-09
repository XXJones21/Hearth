//
//  HearthIcons.swift
//  Hearth
//
//  The house shelf's icons, drawn to match the desktop client rather than
//  approximated with SF Symbols. Ported from
//  `hearth-client/src/components/shell/icons.tsx`: a 24-unit viewBox, 2-unit
//  stroke, round caps and joins, no fill.
//
//  Why not SF Symbols. `book.closed`, `square.grid.2x2` and `gearshape` are
//  each close enough alone, but side by side in one column they read as three
//  different icon sets -- SF Symbols vary their stroke weight and corner
//  radius per glyph, and the shelf shows all four stacked where that
//  inconsistency is exactly what the eye picks up. These are the same drawings
//  the desktop uses, at the same weight, so the two clients agree.
//
//  The corner arcs are quadratic curves rather than true arcs. At a 20pt icon
//  a 2.5-unit radius corner is under two points across; the curve is
//  indistinguishable and avoids porting SVG's endpoint-parameterised arcs.
//

import SwiftUI

/// Scales the 24-unit design grid onto whatever rect the shape is given.
private struct Grid {
    public let rect: CGRect
    public var scale: CGFloat { min(rect.width, rect.height) / 24 }
    public func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
    }
    public func v(_ n: CGFloat) -> CGFloat { n * scale }
}

/// Journal. Desktop's IconBook: a cover, and the spine's inner rule.
public struct BookIcon: Shape {
    /// Explicit: a public struct's memberwise init is internal.
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let g = Grid(rect: rect)
        var path = Path()

        // The inner rule the pages sit on.
        path.move(to: g.p(4, 19.5))
        path.addQuadCurve(to: g.p(6.5, 17), control: g.p(4, 17))
        path.addLine(to: g.p(20, 17))

        // The cover.
        path.move(to: g.p(6.5, 2))
        path.addLine(to: g.p(20, 2))
        path.addLine(to: g.p(20, 22))
        path.addLine(to: g.p(6.5, 22))
        path.addQuadCurve(to: g.p(4, 19.5), control: g.p(4, 22))
        path.addLine(to: g.p(4, 4.5))
        path.addQuadCurve(to: g.p(6.5, 2), control: g.p(4, 2))
        return path
    }
}

/// Persona. Desktop's IconPerson: head, and shoulders as a half circle.
public struct PersonIcon: Shape {
    /// Explicit: a public struct's memberwise init is internal.
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let g = Grid(rect: rect)
        var path = Path()
        path.addEllipse(in: CGRect(x: g.p(12, 8).x - g.v(3.6),
                                   y: g.p(12, 8).y - g.v(3.6),
                                   width: g.v(7.2), height: g.v(7.2)))
        // Upper half of a circle centred under the head.
        path.move(to: g.p(4.5, 20.5))
        path.addArc(center: g.p(12, 20.5), radius: g.v(7.5),
                    startAngle: .degrees(180), endAngle: .degrees(360),
                    clockwise: false)
        return path
    }
}

/// Apps. Desktop's IconGrid: four rounded squares.
public struct GridIcon: Shape {
    /// Explicit: a public struct's memberwise init is internal.
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let g = Grid(rect: rect)
        var path = Path()
        for (x, y) in [(3.0, 3.0), (14.0, 3.0), (3.0, 14.0), (14.0, 14.0)] {
            path.addRoundedRect(
                in: CGRect(origin: g.p(x, y), size: CGSize(width: g.v(7), height: g.v(7))),
                cornerSize: CGSize(width: g.v(1.5), height: g.v(1.5))
            )
        }
        return path
    }
}

/// Settings. The one drawing that is CONSTRUCTED rather than ported: the
/// desktop's gear is a single path of relative arcs, and reproducing it by
/// hand invites the kind of error nobody notices until it ships. Eight teeth
/// around a hub reads identically at shelf size and is exact by construction.
public struct GearIcon: Shape {
    /// Explicit: a public struct's memberwise init is internal.
    public init() {}

    private let teeth = 8

    public func path(in rect: CGRect) -> Path {
        let g = Grid(rect: rect)
        let center = g.p(12, 12)
        var path = Path()

        path.addEllipse(in: CGRect(x: center.x - g.v(3), y: center.y - g.v(3),
                                   width: g.v(6), height: g.v(6)))

        // The body, a ring the teeth stand on.
        path.addEllipse(in: CGRect(x: center.x - g.v(7), y: center.y - g.v(7),
                                   width: g.v(14), height: g.v(14)))

        for index in 0..<teeth {
            let angle = (Double(index) / Double(teeth)) * 2 * .pi
            let inner = CGPoint(x: center.x + cos(angle) * g.v(7),
                                y: center.y + sin(angle) * g.v(7))
            let outer = CGPoint(x: center.x + cos(angle) * g.v(9.4),
                                y: center.y + sin(angle) * g.v(9.4))
            path.move(to: inner)
            path.addLine(to: outer)
        }
        return path
    }
}

/// One shelf icon at the desktop's weight. `size` is the box; the stroke
/// scales with it so a larger icon does not read as a thinner one.
public struct HearthIcon<S: Shape>: View {
    public let shape: S
    public var size: CGFloat = 19

    /// Explicit: a public struct's memberwise init is internal.
    public init(shape: S, size: CGFloat = 19) {
        self.shape = shape
        self.size = size
    }

    public var body: some View {
        shape
            .stroke(style: StrokeStyle(lineWidth: size * (2.0 / 24.0),
                                       lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}
