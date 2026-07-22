import SwiftUI

struct DeskSwitcher: View {
    @Environment(DenStore.self) private var store

    let shouldReduceMotion: Bool
    let item: (DeskState, CGSize, ScrollViewProxy) -> AnyView
    let onFramesChange: ([UUID: CGRect]) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(store.state.desks) { desk in
                                item(desk, geometry.size, proxy)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: store.state.desks.map(\.id))
                }
                .coordinateSpace(name: "desk-switcher")
                .scrollIndicators(.hidden)
                .onChange(of: store.state.focusedDeskID) { _, deskID in
                    withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) {
                        proxy.scrollTo(deskID, anchor: .center)
                    }
                }
                .onPreferenceChange(DeskFramePreferenceKey.self, perform: onFramesChange)
            }
            .frame(height: 36)
        }
    }
}
