import SwiftUI

/// The app logo drawn as vectors, so it stays crisp at any size (the .icns is
/// raster and looked jagged when scaled down inside the panel).
struct GaugeMark: View {
    var size: CGFloat = 30

    var body: some View {
        let lineWidth = size * 0.11
        let inset = size * 0.26
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.15, green: 0.15, blue: 0.18),
                                 Color(red: 0.08, green: 0.08, blue: 0.10)],
                        startPoint: .top, endPoint: .bottom)
                )

            // Faint 270° track, gap centered at the bottom.
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.12),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(inset)

            // Amber value arc (~68% filled).
            Circle()
                .trim(from: 0, to: 0.75 * 0.68)
                .stroke(Color(red: 1.0, green: 0.70, blue: 0.14),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(inset)
        }
        .frame(width: size, height: size)
    }
}
