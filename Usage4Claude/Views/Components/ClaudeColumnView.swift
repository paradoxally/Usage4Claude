//
//  ClaudeColumnView.swift
//  Usage4Claude
//
//  Created by Claude Code on 2026-05-30.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// Claude 用量列视图（"全部账户"模式下每个账户一列）
/// 复刻 UsageDetailView.claudeMainContent 的圆环与限制行绘制，按账户数据独立渲染。
/// 与 CodexColumnView 保持一致的提取风格：接收显式数据 + 绑定 + 回调，不依赖父视图私有状态。
struct ClaudeColumnView: View {
    let usageData: UsageData?
    let errorMessage: String?
    @Binding var showRemainingMode: Bool
    let refreshState: RefreshState
    @Binding var animationType: UsageDetailView.LoadingAnimationType
    @Binding var rotationAngle: Double
    let remainingModeAnimationTrigger: Int
    var onRefresh: (() -> Void)?
    var onAnimationHint: ((String) -> Void)?
    var onToggleRemainingMode: (() -> Void)?
    var onOpenAuthSettings: (() -> Void)?

    private var activeDisplayTypes: [LimitType] {
        guard let data = usageData else { return [] }
        return UserSettings.shared.getActiveDisplayTypes(usageData: data)
            .filter { $0.provider == .claude }
    }

    private var isClaudeRefreshing: Bool {
        refreshState.isRefreshingProvider(.claude)
    }

    // MARK: - Body

    var body: some View {
        if let error = errorMessage {
            errorView(error)
        } else if let data = usageData {
            dataView(data)
        } else {
            loadingView
        }
    }

    // MARK: - Data State

    private func dataView(_ data: UsageData) -> some View {
        VStack(spacing: 15) {
            ringSection(data)
            limitRows(data)
        }
    }

    private func ringSection(_ data: UsageData) -> some View {
        ZStack {
            let primaryLimitData = getPrimaryLimitData(data: data, activeTypes: activeDisplayTypes)

            if let primary = primaryLimitData {
                let primaryRingColor = colorForPrimaryByActiveTypes(data: data, activeTypes: activeDisplayTypes)
                let primaryRingRange = UsageRingDisplay.displayedTrimRange(
                    usedPercentage: primary.percentage,
                    showRemainingMode: showRemainingMode
                )

                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 10)
                    .frame(width: 100, height: 100)

                if isClaudeRefreshing {
                    loadingAnimation()
                } else {
                    Circle()
                        .trim(from: primaryRingRange.from, to: primaryRingRange.to)
                        .stroke(primaryRingColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0.05), value: primaryRingRange)
                }

                if activeDisplayTypes.contains(.fiveHour) && activeDisplayTypes.contains(.sevenDay) {
                    let sevenDayPercentage = data.sevenDay?.percentage ?? (UserSettings.shared.displayMode == .custom ? 0 : nil)

                    if let percentage = sevenDayPercentage {
                        let outerRingRange = UsageRingDisplay.displayedTrimRange(
                            usedPercentage: percentage,
                            showRemainingMode: showRemainingMode
                        )

                        Circle()
                            .stroke(Color.gray.opacity(0.15), lineWidth: 3)
                            .frame(width: 114, height: 114)

                        if isClaudeRefreshing {
                            outerLoadingAnimation()
                        } else {
                            Circle()
                                .trim(from: outerRingRange.from, to: outerRingRange.to)
                                .stroke(colorForSevenDay(percentage), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 114, height: 114)
                                .rotationEffect(.degrees(-90))
                                .animation(.spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0.05), value: outerRingRange)
                        }
                    }
                }

                if !isClaudeRefreshing {
                    DetailUsageRingSweep(
                        trigger: remainingModeAnimationTrigger,
                        diameter: 122,
                        lineWidth: 3,
                        color: primaryRingColor
                    )
                }

                DetailUsageRingCenterText(
                    usedPercentage: primary.percentage,
                    showRemainingMode: showRemainingMode
                )
            }
        }
        .frame(height: 114)
        .contentShape(Circle())
        .onTapGesture {
            if refreshState.canRefresh && !refreshState.isRefreshing {
                onRefresh?()
            }
        }
        .onLongPressGesture(minimumDuration: 3.0) {
            let allTypes = UsageDetailView.LoadingAnimationType.allCases
            let currentIndex = allTypes.firstIndex(of: animationType) ?? 0
            animationType = allTypes[(currentIndex + 1) % allTypes.count]
            onAnimationHint?(animationType.name)
        }
    }

    @ViewBuilder
    private func limitRows(_ data: UsageData) -> some View {
        VStack(spacing: 8) {
            let activeTypes = activeDisplayTypes

            if activeTypes.count >= 2 {
                VStack(spacing: 5) {
                    ForEach(activeTypes, id: \.self) { type in
                        UnifiedLimitRow(type: type, data: data, showRemainingMode: showRemainingMode)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { onToggleRemainingMode?() }
            } else if activeTypes.count == 1 {
                let singleType = activeTypes.first!

                if singleType == .fiveHour, let fiveHour = data.fiveHour {
                    VStack(spacing: 5) {
                        InfoRow(icon: "clock.fill", title: L.Usage.fiveHourLimit, value: fiveHour.formattedResetsInHours)
                        InfoRow(icon: "arrow.clockwise", title: L.Usage.resetTime, value: fiveHour.formattedResetTimeShort)
                    }
                } else if singleType == .sevenDay, let sevenDay = data.sevenDay {
                    VStack(spacing: 5) {
                        InfoRow(icon: "calendar", title: L.Usage.sevenDayLimit, value: sevenDay.formattedResetsInDays, tintColor: .purple)
                        InfoRow(icon: "calendar.badge.clock", title: L.Usage.resetDate, value: sevenDay.formattedResetDateLong, tintColor: .purple)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Error / Loading States

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text(error)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button(action: { onOpenAuthSettings?() }) {
                Label(L.Usage.goToSettings, systemImage: "key.fill")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text(L.Usage.loading)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(height: 100)
    }

    // MARK: - Helpers (replicated from UsageDetailView+Helpers)

    private func getPrimaryLimitData(data: UsageData, activeTypes: [LimitType]) -> UsageData.LimitData? {
        let showPlaceholder = UserSettings.shared.displayMode == .custom
        let placeholderData = UsageData.LimitData(percentage: 0, resetsAt: nil)

        if activeTypes.contains(.fiveHour) {
            if let fiveHour = data.fiveHour { return fiveHour }
            else if showPlaceholder { return placeholderData }
        } else if activeTypes.contains(.sevenDay) {
            if let sevenDay = data.sevenDay { return sevenDay }
            else if showPlaceholder { return placeholderData }
        }
        return nil
    }

    private func colorForPrimaryByActiveTypes(data: UsageData, activeTypes: [LimitType]) -> Color {
        if activeTypes.contains(.fiveHour) {
            if let fiveHour = data.fiveHour { return UsageColorScheme.fiveHourColorSwiftUI(fiveHour.percentage) }
            return .gray
        } else if activeTypes.contains(.sevenDay) {
            if let sevenDay = data.sevenDay { return UsageColorScheme.sevenDayColorSwiftUI(sevenDay.percentage) }
            return .gray
        }
        return .gray
    }

    private func colorForSevenDay(_ percentage: Double) -> Color {
        UsageColorScheme.sevenDayColorSwiftUI(percentage)
    }

    // MARK: - Loading Animations (replicated from UsageDetailView+Helpers)

    @ViewBuilder
    private func loadingAnimation() -> some View {
        switch animationType {
        case .rainbow:
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [.blue, .purple, .pink, .orange, .blue]), center: .center),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(rotationAngle))
        case .dashed:
            Circle()
                .trim(from: 0, to: 1)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round, dash: [10, 8]))
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(rotationAngle))
        case .pulse:
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.6)
                    .stroke(Color.blue.opacity(0.8), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 90, height: 90)
                    .rotationEffect(.degrees(rotationAngle))
                Circle()
                    .trim(from: 0, to: 0.4)
                    .stroke(Color.blue.opacity(0.4), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-rotationAngle * 0.7))
            }
        }
    }

    @ViewBuilder
    private func outerLoadingAnimation() -> some View {
        switch animationType {
        case .rainbow:
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    AngularGradient(gradient: Gradient(colors: [.blue, .purple, .pink, .orange, .blue]), center: .center),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 114, height: 114)
                .rotationEffect(.degrees(-rotationAngle))
        case .dashed:
            Circle()
                .trim(from: 0, to: 1)
                .stroke(Color.purple, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 6]))
                .frame(width: 114, height: 114)
                .rotationEffect(.degrees(-rotationAngle))
        case .pulse:
            Circle()
                .trim(from: 0, to: 0.4)
                .stroke(Color.purple.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 114, height: 114)
                .rotationEffect(.degrees(-rotationAngle * 0.7))
        }
    }
}
