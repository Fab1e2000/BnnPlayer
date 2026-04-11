import SwiftUI

private struct HoverInteractiveModifier: ViewModifier {
    let enabled: Bool
    let brightness: Double
    let scale: CGFloat

    @State private var isHovering = false

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .brightness(enabled && isHovering ? brightness : 0)
            .scaleEffect(enabled && isHovering ? scale : 1)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
        #else
        content
        #endif
    }
}

extension View {
    func hoverInteractive(enabled: Bool = true, brightness: Double = 0.08, scale: CGFloat = 1.0) -> some View {
        modifier(HoverInteractiveModifier(enabled: enabled, brightness: brightness, scale: scale))
    }
}
