import SwiftUI

struct AdaptiveGlassContainer<Content: View>: View {
    let spacing: CGFloat?
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: self.spacing) {
                    self.content()
                }
            } else {
                self.content()
            }
        #else
            self.content()
        #endif
    }
}

extension View {
    @ViewBuilder
    func adaptiveGlass<S: InsettableShape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                let resolved: Glass = {
                    var base: Glass = .regular
                    if let tint {
                        base = base.tint(tint)
                    }
                    if interactive {
                        base = base.interactive()
                    }
                    return base
                }()
                self.glassEffect(resolved, in: shape)
            } else {
                self.legacyGlassFallback(in: shape, tint: tint)
            }
        #else
            self.legacyGlassFallback(in: shape, tint: tint)
        #endif
    }

    @ViewBuilder
    func adaptiveGlassPill(tint: Color? = nil, interactive: Bool = true) -> some View {
        self.adaptiveGlass(in: Capsule(), tint: tint, interactive: interactive)
    }

    @ViewBuilder
    private func legacyGlassFallback<S: InsettableShape>(in shape: S, tint: Color?) -> some View {
        if let tint {
            self.background(tint, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        }
    }
}
