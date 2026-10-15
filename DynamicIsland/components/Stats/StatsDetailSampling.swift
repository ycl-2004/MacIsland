import SwiftUI

/// Each window contributes independently; closing one cannot disable another.
private struct StatsDetailSampling: ViewModifier {
    let kind: ProcessRankingType
    @State private var surfaceID = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { StatsManager.shared.setDetailSurface(surfaceID, kind: kind, visible: true) }
            .onDisappear { StatsManager.shared.setDetailSurface(surfaceID, kind: kind, visible: false) }
    }
}

extension View {
    func statsDetailSampling(_ kind: ProcessRankingType) -> some View {
        modifier(StatsDetailSampling(kind: kind))
    }
}
