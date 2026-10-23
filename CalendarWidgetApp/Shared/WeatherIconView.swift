import SwiftUI

/// Draws one of the custom thin-line weather icons from WeatherIconData (48 x 48 grid).
struct WeatherIconView: View {
    let name: String
    var color: Color = .white
    var size: CGFloat = 40

    var body: some View {
        PolylineShape(d: WeatherIconData.paths[name] ?? "")
            .stroke(color, style: StrokeStyle(lineWidth: size / 48 * 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

/// Reads a tiny path format: "M x y L x y L x y Z M ..." on a 48 x 48 grid.
struct PolylineShape: Shape {
    let d: String

    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 48
        func point(_ x: Substring, _ y: Substring) -> CGPoint {
            CGPoint(x: rect.minX + (Double(x) ?? 0) * k, y: rect.minY + (Double(y) ?? 0) * k)
        }

        var path = Path()
        let t = d.split(separator: " ")
        var i = 0
        while i < t.count {
            switch t[i] {
            case "M" where i + 2 < t.count:
                path.move(to: point(t[i + 1], t[i + 2])); i += 3
            case "L" where i + 2 < t.count:
                path.addLine(to: point(t[i + 1], t[i + 2])); i += 3
            case "Z":
                path.closeSubpath(); i += 1
            default:
                i += 1
            }
        }
        return path
    }
}
