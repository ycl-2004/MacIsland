/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import Defaults

// Graph data protocol for unified interface
protocol GraphData {
    var title: String { get }
    var color: Color { get }
    var icon: String { get }
    var type: GraphType { get }
    var rankingType: ProcessRankingType? { get }
}

enum GraphType {
    case single
    case dual
}

// Single value graph data
struct SingleGraphData: GraphData {
    let title: String
    let value: String
    let data: [Double]
    let color: Color
    let icon: String
    let type: GraphType = .single
    let rankingType: ProcessRankingType?
}

// Dual value graph data (for network/disk)
struct DualGraphData: GraphData {
    let title: String
    let positiveValue: String
    let negativeValue: String
    let positiveData: [Double]
    let negativeData: [Double]
    let positiveColor: Color
    let negativeColor: Color
    let color: Color // Primary color for the component
    let icon: String
    let type: GraphType = .dual
    let rankingType: ProcessRankingType?
}

struct NotchStatsView: View {
    @ObservedObject var statsManager = StatsManager.shared
    @Default(.enableStatsFeature) var enableStatsFeature
    @Default(.showCpuGraph) var showCpuGraph
    @Default(.showMemoryGraph) var showMemoryGraph
    @Default(.showGpuGraph) var showGpuGraph
    @Default(.showNetworkGraph) var showNetworkGraph
    @Default(.showDiskGraph) var showDiskGraph
    @State private var showingCPUPopover = false
    @State private var showingMemoryPopover = false
    @State private var showingGPUPopover = false
    @State private var showingNetworkPopover = false
    @State private var showingDiskPopover = false
    @State private var isHoveringCPUPopover = false
    @State private var isHoveringMemoryPopover = false
    @State private var isHoveringGPUPopover = false
    @State private var isHoveringNetworkPopover = false
    @State private var isHoveringDiskPopover = false
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared

    var availableGraphs: [GraphData] {
        var graphs: [GraphData] = []

        if showCpuGraph {
            graphs.append(SingleGraphData(
                title: String(localized: "CPU"),
                value: statsManager.cpuUsageString,
                data: statsManager.cpuHistory,
                color: .statsCPU,
                icon: "cpu",
                rankingType: .cpu
            ))
        }

        if showMemoryGraph {
            graphs.append(SingleGraphData(
                title: String(localized: "Memory"),
                value: statsManager.memoryUsageString,
                data: statsManager.memoryHistory,
                color: .statsMemory,
                icon: "memorychip",
                rankingType: .memory
            ))
        }

        if showGpuGraph {
            graphs.append(SingleGraphData(
                title: String(localized: "GPU"),
                value: statsManager.gpuUsageString,
                data: statsManager.gpuHistory,
                color: .statsGPU,
                icon: "display",
                rankingType: .gpu
            ))
        }

        if showNetworkGraph {
            graphs.append(DualGraphData(
                title: String(localized: "Network"),
                positiveValue: "↓" + statsManager.networkDownloadString,
                negativeValue: "↑" + statsManager.networkUploadString,
                positiveData: statsManager.networkDownloadHistory,
                negativeData: statsManager.networkUploadHistory,
                positiveColor: .statsNetworkDown,
                negativeColor: .statsNetworkUp,
                color: .statsNetworkDown,
                icon: "network",
                rankingType: .network
            ))
        }

        if showDiskGraph {
            graphs.append(DualGraphData(
                title: String(localized: "Disk"),
                positiveValue: String(localized: "R ") + statsManager.diskReadString,
                negativeValue: String(localized: "W ") + statsManager.diskWriteString,
                positiveData: statsManager.diskReadHistory,
                negativeData: statsManager.diskWriteHistory,
                positiveColor: .statsDiskRead,
                negativeColor: .statsDiskWrite,
                color: .statsDiskRead,
                icon: "internaldrive",
                rankingType: .disk
            ))
        }

        return graphs
    }

    // Smart grid layout system for different graph counts
    @ViewBuilder
    var statsGridLayout: some View {
        let graphCount = availableGraphs.count

        if graphCount <= 3 {
            // 1-3 graphs: Single row with equal spacing
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: graphCount),
                spacing: 12
            ) {
                ForEach(0..<graphCount, id: \.self) { index in
                    graphViewForIndex(index)
                }
            }
        } else if graphCount == 4 {
            // 4 graphs: two rows (2x2) without a collapsible expansion
            VStack(spacing: statsGridSpacingHeight) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                    spacing: 12
                ) {
                    ForEach(0..<2, id: \.self) { index in
                        graphViewForIndex(index)
                    }
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                    spacing: 12
                ) {
                    ForEach(2..<graphCount, id: \.self) { index in
                        graphViewForIndex(index)
                    }
                }
            }
        } else {
            // 5 graphs: First row 3 graphs, second row 2 graphs (half-width each)
            VStack(spacing: statsGridSpacingHeight) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 8
                ) {
                    ForEach(0..<3, id: \.self) { index in
                        graphViewForIndex(index)
                    }
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                    spacing: 8
                ) {
                    ForEach(3..<graphCount, id: \.self) { index in
                        graphViewForIndex(index)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func graphViewForIndex(_ index: Int) -> some View {
        let graphData = availableGraphs[index]

        if let rankingType = rankingTypeForGraph(graphData) {
            Button(action: {
                handleGraphClick(for: graphData)
            }) {
                UnifiedStatsCard(graphData: graphData)
            }
            .buttonStyle(PlainButtonStyle())
            .popover(isPresented: bindingForGraph(graphData)) {
                RankedProcessPopover(
                    rankingType: rankingType,
                    onHoverChange: { hovering in
                        switch rankingType {
                        case .cpu:
                            isHoveringCPUPopover = hovering
                        case .memory:
                            isHoveringMemoryPopover = hovering
                        case .gpu:
                            isHoveringGPUPopover = hovering
                        case .network:
                            isHoveringNetworkPopover = hovering
                        case .disk:
                            isHoveringDiskPopover = hovering
                        }
                    }
                )
                .onDisappear {
                    switch rankingType {
                    case .cpu:
                        isHoveringCPUPopover = false
                    case .memory:
                        isHoveringMemoryPopover = false
                    case .gpu:
                        isHoveringGPUPopover = false
                    case .network:
                        isHoveringNetworkPopover = false
                    case .disk:
                        isHoveringDiskPopover = false
                    }
                    DispatchQueue.main.async {
                        updateStatsPopoverState()
                    }
                }
            }
            .transition(.asymmetric(
                insertion: .scale.combined(with: .opacity).animation(.notchRelaxed),
                removal: .scale.combined(with: .opacity).animation(.notchRelaxed)
            ))
        } else {
            UnifiedStatsCard(graphData: graphData)
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity).animation(.notchRelaxed),
                    removal: .scale.combined(with: .opacity).animation(.notchRelaxed)
                ))
        }
    }

    private func handleGraphClick(for graphData: GraphData) {
        switch graphData.rankingType {
        case .cpu:
            showingCPUPopover = true
        case .memory:
            showingMemoryPopover = true
        case .gpu:
            showingGPUPopover = true
        case .network:
            showingNetworkPopover = true
        case .disk:
            showingDiskPopover = true
        case nil:
            break
        }
    }

    private func bindingForGraph(_ graphData: GraphData) -> Binding<Bool> {
        switch graphData.rankingType {
        case .cpu:
            return $showingCPUPopover
        case .memory:
            return $showingMemoryPopover
        case .gpu:
            return $showingGPUPopover
        case .network:
            return $showingNetworkPopover
        case .disk:
            return $showingDiskPopover
        case nil:
            return .constant(false)
        }
    }

    private func rankingTypeForGraph(_ graphData: GraphData) -> ProcessRankingType? {
        graphData.rankingType
    }
    
    // Helper function to create graph views using unified component
    @ViewBuilder
    func graphView(for graphData: GraphData) -> some View {
        UnifiedStatsCard(graphData: graphData)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !enableStatsFeature {
                // Disabled state
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("Stats Disabled")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Enable stats monitoring in Settings to view system performance data.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if availableGraphs.isEmpty {
                // No graphs enabled state
                VStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    
                    Text("No Graphs Enabled")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Enable graph visibility in Settings → Stats to view performance data.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                VStack(spacing: 8) {
                    statsGridLayout
                }
                .padding(12)
                .animation(.notchRelaxed, value: availableGraphs.count)
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity).animation(.notchRelaxed),
                    removal: .scale.combined(with: .opacity).animation(.notchRelaxed)
                ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Note: Smart monitoring will handle starting/stopping based on notch state and current view
        }
        .onDisappear {
            // Keep monitoring running when tab is not visible
            updateStatsPopoverState()
        }
        .animation(.notchRelaxed, value: enableStatsFeature)
        .animation(.notchRelaxed, value: availableGraphs.count)
        .onChange(of: showingCPUPopover) { _, newValue in
            updateStatsPopoverState()
        }
        .onChange(of: showingMemoryPopover) { _, newValue in
            updateStatsPopoverState()
        }
        .onChange(of: showingGPUPopover) { _, newValue in
            updateStatsPopoverState()
        }
        .onChange(of: showingNetworkPopover) { _, newValue in
            updateStatsPopoverState()
        }
        .onChange(of: showingDiskPopover) { _, newValue in
            updateStatsPopoverState()
        }
        .onChange(of: isHoveringCPUPopover) { _, _ in
            updateStatsPopoverState()
        }
        .onChange(of: isHoveringMemoryPopover) { _, _ in
            updateStatsPopoverState()
        }
        .onChange(of: isHoveringGPUPopover) { _, _ in
            updateStatsPopoverState()
        }
        .onChange(of: isHoveringNetworkPopover) { _, _ in
            updateStatsPopoverState()
        }
        .onChange(of: isHoveringDiskPopover) { _, _ in
            updateStatsPopoverState()
        }
    }
    private func updateStatsPopoverState() {
        let anyPopoverOpen = showingCPUPopover || showingMemoryPopover || showingGPUPopover || showingNetworkPopover || showingDiskPopover
        let newState = anyPopoverOpen
        if vm.isStatsPopoverActive != newState {
            vm.isStatsPopoverActive = newState
            debugLog(
                "📊 Stats popover state updated: \(newState) (CPU=\(showingCPUPopover), Memory=\(showingMemoryPopover), "
                    + "GPU=\(showingGPUPopover), Network=\(showingNetworkPopover), Disk=\(showingDiskPopover))"
            )
        }
    }
}

// Unified Stats Card Component - handles both single and dual data types, matches boring.notch sizing
struct UnifiedStatsCard: View {
    let graphData: GraphData
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 3) { // Match boring.notch spacing
            // Header - consistent across all card types
            HStack(spacing: 4) {
                Image(systemName: graphData.icon)
                    .foregroundStyle(graphData.color)
                    .font(.caption) // Match boring.notch font size
                
                Text(graphData.title)
                    .font(.caption) // Match boring.notch font size
                    .fontWeight(.medium)
                    .foregroundStyle(.inkSecondary)
                
                Spacer()
            }
            
            // Values section - same height for every card so the grid boxes match.
            // Tabular digits, so a reading that ticks over every second keeps
            // its width instead of jostling the text beside it.
            Group {
                if let singleData = graphData as? SingleGraphData {
                    Text(singleData.value)
                        .font(.caption.monospacedDigit()) // Match boring.notch font size
                        .fontWeight(.bold)
                        .foregroundStyle(.inkPrimary)
                        .frame(maxWidth: .infinity)
                } else if let dualData = graphData as? DualGraphData {
                    HStack(spacing: 6) {
                        Text(dualData.positiveValue)
                            .font(.caption.monospacedDigit())
                            .fontWeight(.semibold)
                            .foregroundColor(dualData.positiveColor)
                        
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.inkQuaternary)
                        
                        Text(dualData.negativeValue)
                            .font(.caption.monospacedDigit())
                            .fontWeight(.semibold)
                            .foregroundColor(dualData.negativeColor)
                    }
                }
            }
            .frame(height: 18) // Fixed height for the values section
            
            // Graph section - adapts based on graph type
            Group {
                if let singleData = graphData as? SingleGraphData {
                    MiniGraph(data: singleData.data, color: singleData.color)
                } else if let dualData = graphData as? DualGraphData {
                    DualQuadrantGraph(
                        positiveData: dualData.positiveData,
                        negativeData: dualData.negativeData,
                        positiveColor: dualData.positiveColor,
                        negativeColor: dualData.negativeColor
                    )
                }
            }
            .frame(height: 36) // Match boring.notch exactly - reduced from 50
            
            // Click hint - shown for graphs that open popovers
            if graphData.rankingType != nil {
                Text("Click for details")
                    .font(.caption2)
                    .foregroundStyle(.inkSecondary)
                    .opacity(isHovered ? 1.0 : 0.0)
            }
        }
        .padding(8) // Match boring.notch padding - reduced from 10
        // Hover lifts the surface rather than scaling the card: scaling
        // re-rasterises the text and graph and leaves them soft mid-animation.
        .background(
            RoundedRectangle(cornerRadius: NotchRadius.card, style: .continuous)
                .fill(isHovered ? Color.fillCardHover : .fillCard)
                .overlay(
                    RoundedRectangle(cornerRadius: NotchRadius.card, style: .continuous)
                        .strokeBorder(isHovered ? Color.strokeRegular : .strokeHairline, lineWidth: 1)
                )
        )
        .animation(.notchQuick, value: isHovered)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// How a metric's line and fill are drawn, shared by both graph kinds: a
/// rounded line over an area that fades out towards the baseline.
private enum GraphInk {
    static let line = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)

    static func fill(_ color: Color, from start: UnitPoint, to end: UnitPoint) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.28), color.opacity(0)], startPoint: start, endPoint: end)
    }
}

struct MiniGraph: View {
    let data: [Double]
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            let maxValue = data.max() ?? 1.0
            let normalizedData = maxValue > 0 ? data.map { $0 / maxValue } : data
            
            Path { path in
                guard !normalizedData.isEmpty else { return }
                
                let stepX = geometry.size.width / CGFloat(normalizedData.count - 1)
                
                for (index, value) in normalizedData.enumerated() {
                    let pointX = CGFloat(index) * stepX
                    let pointY = geometry.size.height * (1 - CGFloat(value))
                    
                    if index == 0 {
                        path.move(to: CGPoint(x: pointX, y: pointY))
                    } else {
                        path.addLine(to: CGPoint(x: pointX, y: pointY))
                    }
                }
            }
            .stroke(color, style: GraphInk.line)
            
            // Gradient fill
            Path { path in
                guard !normalizedData.isEmpty else { return }
                
                let stepX = geometry.size.width / CGFloat(normalizedData.count - 1)
                
                path.move(to: CGPoint(x: 0, y: geometry.size.height))
                
                for (index, value) in normalizedData.enumerated() {
                    let pointX = CGFloat(index) * stepX
                    let pointY = geometry.size.height * (1 - CGFloat(value))
                    path.addLine(to: CGPoint(x: pointX, y: pointY))
                }
                
                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                path.closeSubpath()
            }
            .fill(GraphInk.fill(color, from: .top, to: .bottom))
        }
    }
}



struct DualQuadrantGraph: View {
    let positiveData: [Double]
    let negativeData: [Double]
    let positiveColor: Color
    let negativeColor: Color
    
    var body: some View {
        GeometryReader { geometry in
            let maxPositive = positiveData.max() ?? 1.0
            let maxNegative = negativeData.max() ?? 1.0
            let maxValue = max(maxPositive, maxNegative)
            
            let normalizedPositive = maxValue > 0 ? positiveData.map { $0 / maxValue } : positiveData
            let normalizedNegative = maxValue > 0 ? negativeData.map { $0 / maxValue } : negativeData
            
            let centerY = geometry.size.height / 2
            
            ZStack {
                // Center dividing line
                Path { path in
                    path.move(to: CGPoint(x: 0, y: centerY))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: centerY))
                }
                .stroke(.strokeHairline, lineWidth: 1)
                
                // Positive quadrant (upper half)
                Path { path in
                    guard !normalizedPositive.isEmpty else { return }
                    
                    let stepX = geometry.size.width / CGFloat(normalizedPositive.count - 1)
                    
                    for (index, value) in normalizedPositive.enumerated() {
                        let pointX = CGFloat(index) * stepX
                        let pointY = centerY - (centerY * CGFloat(value)) // Above center
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: pointX, y: pointY))
                        } else {
                            path.addLine(to: CGPoint(x: pointX, y: pointY))
                        }
                    }
                }
                .stroke(positiveColor, style: GraphInk.line)
                
                // Positive fill
                Path { path in
                    guard !normalizedPositive.isEmpty else { return }
                    
                    let stepX = geometry.size.width / CGFloat(normalizedPositive.count - 1)
                    
                    path.move(to: CGPoint(x: 0, y: centerY))
                    
                    for (index, value) in normalizedPositive.enumerated() {
                        let pointX = CGFloat(index) * stepX
                        let pointY = centerY - (centerY * CGFloat(value))
                        path.addLine(to: CGPoint(x: pointX, y: pointY))
                    }
                    
                    path.addLine(to: CGPoint(x: geometry.size.width, y: centerY))
                    path.closeSubpath()
                }
                .fill(GraphInk.fill(positiveColor, from: .top, to: .center))
                
                // Negative quadrant (lower half)
                Path { path in
                    guard !normalizedNegative.isEmpty else { return }
                    
                    let stepX = geometry.size.width / CGFloat(normalizedNegative.count - 1)
                    
                    for (index, value) in normalizedNegative.enumerated() {
                        let pointX = CGFloat(index) * stepX
                        let pointY = centerY + (centerY * CGFloat(value)) // Below center
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: pointX, y: pointY))
                        } else {
                            path.addLine(to: CGPoint(x: pointX, y: pointY))
                        }
                    }
                }
                .stroke(negativeColor, style: GraphInk.line)
                
                // Negative fill
                Path { path in
                    guard !normalizedNegative.isEmpty else { return }
                    
                    let stepX = geometry.size.width / CGFloat(normalizedNegative.count - 1)
                    
                    path.move(to: CGPoint(x: 0, y: centerY))
                    
                    for (index, value) in normalizedNegative.enumerated() {
                        let pointX = CGFloat(index) * stepX
                        let pointY = centerY + (centerY * CGFloat(value))
                        path.addLine(to: CGPoint(x: pointX, y: pointY))
                    }
                    
                    path.addLine(to: CGPoint(x: geometry.size.width, y: centerY))
                    path.closeSubpath()
                }
                .fill(GraphInk.fill(negativeColor, from: .bottom, to: .center))
            }
        }
    }
}

#Preview {
    NotchStatsView()
        .frame(width: 400, height: 300)
        .background(Color.black)
}
