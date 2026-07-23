import SwiftUI

struct DeskSwitcher: View {
    @Environment(DenStore.self) private var store

    @Binding var scrollPosition: ScrollPosition
    let shouldReduceMotion: Bool
    let item: (DeskState, CGSize) -> AnyView
    let onFramesChange: ([UUID: CGRect]) -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(store.state.desks) { desk in
                            item(desk, geometry.size)
                        }
                    }
                    .scrollTargetLayout()
                }
                .padding(.horizontal, 12)
                .animation(DenMotion.spatial(reduceMotion: shouldReduceMotion), value: store.state.desks.map(\.id))
            }
            .scrollPosition($scrollPosition, anchor: .center)
            .coordinateSpace(name: "desk-switcher")
            .scrollIndicators(.hidden)
            .onChange(of: store.state.focusedDeskID) { _, deskID in
                withAnimation(DenMotion.spatial(reduceMotion: shouldReduceMotion)) {
                    scrollPosition.scrollTo(id: deskID, anchor: .center)
                }
            }
            .onPreferenceChange(DeskFramePreferenceKey.self, perform: onFramesChange)
        }
        .frame(height: 36)
    }
}
