import Charts
import SwiftUI

/// 藥效波動與震動數據圖表分析
struct AnalyticsTabView: View {
    @ObservedObject var medVM: MedicationViewModel
    @ObservedObject var dataVM: DataViewModel
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedDate: Date

    // 縮放、平移與視窗狀態
    @State private var visibleDuration: TimeInterval = 4 * 3600 // 預設 4 小時視窗
    @State private var zoomBaseDuration: TimeInterval = 4 * 3600
    @State private var chartScrollPosition: Date = Date()
    @State private var hasInitializedScrollPosition: Bool = false
    @State private var zoomAnchorDate: Date = Date()
    @State private var isPinching: Bool = false
    @State private var dragStartScrollPosition: Date? = nil

    // 日期與時間選取跳轉狀態
    @State private var showTimePicker: Bool = false
    @State private var selectedChartTime: Date = Date()
    @State private var hasSelectedSpecificTime: Bool = false

    // 原地選取狀態
    @State private var selectedPointDate: Date? = nil
    @State private var selectedPointRMS: Double? = nil

    private let minimumVisibleDuration: TimeInterval = 5 * 60
    private let maximumVisibleDuration: TimeInterval = 24 * 60 * 60
    private let chartHeight: CGFloat = 285

    // 日期與時間軸邊界計算
    private var taipeiCalendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        return calendar
    }

    private var isViewingToday: Bool {
        taipeiCalendar.isDateInToday(selectedDate)
    }

    private var dayStart: Date {
        taipeiCalendar.startOfDay(for: selectedDate)
    }

    private var dayEnd: Date {
        let tomorrow = taipeiCalendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(24 * 60 * 60)
        return isViewingToday ? min(tomorrow, Date()) : tomorrow
    }

    private var dayLastSecond: Date {
        isViewingToday ? Date() : dayEnd.addingTimeInterval(-1)
    }

    private var clampedVisibleDuration: TimeInterval {
        min(max(visibleDuration, minimumVisibleDuration), maximumVisibleDuration)
    }

    private var maxLeadingDate: Date {
        max(dayStart, dayEnd.addingTimeInterval(-clampedVisibleDuration))
    }

    private var clampedChartScrollPosition: Date {
        min(max(chartScrollPosition, dayStart), maxLeadingDate)
    }

    private var visibleEndDate: Date {
        min(clampedChartScrollPosition.addingTimeInterval(clampedVisibleDuration), dayEnd)
    }

    // 資料緩衝區過濾
    private var bufferedTremorPoints: [DataViewModel.RMSTrendPoint] {
        let buffer = max(clampedVisibleDuration * 0.5, 60)
        let start = clampedChartScrollPosition.addingTimeInterval(-buffer)
        let end = visibleEndDate.addingTimeInterval(buffer)

        return dataVM.rmsTrendHistory.filter {
            $0.timestamp >= start && $0.timestamp <= end
        }
    }

    private var todayMedications: [MedicationRecord] {
        medVM.medicationList.filter {
            $0.date >= dayStart && $0.date <= dayEnd
        }
    }

    private var bufferedMedications: [MedicationRecord] {
        let buffer = max(clampedVisibleDuration * 0.5, 60)
        let start = clampedChartScrollPosition.addingTimeInterval(-buffer)
        let end = visibleEndDate.addingTimeInterval(buffer)

        return todayMedications.filter {
            $0.date >= start && $0.date <= end
        }
    }

    private var dynamicMaxY: Double {
        let values = bufferedTremorPoints.map(\.rmsValue).filter { $0.isFinite && !$0.isNaN }
        guard let maximum = values.max(), maximum > 0 else { return 0.5 }
        return max(0.5, maximum * 1.25)
    }

    // 動態 X 軸刻度
    private var xAxisStride: TimeInterval {
        switch clampedVisibleDuration {
        case ...300: return 60
        case ...900: return 180
        case ...1800: return 300
        case ...3600: return 600
        case ...7200: return 1200
        case ...14400: return 1800
        case ...43200: return 7200
        default: return 14400
        }
    }

    private var visibleXAxisTicks: [Date] {
        let step = xAxisStride
        let startInterval = clampedChartScrollPosition.timeIntervalSince1970
        let endInterval = visibleEndDate.timeIntervalSince1970

        let bufferedStart = max(dayStart.timeIntervalSince1970, startInterval - step)
        let bufferedEnd = min(dayEnd.timeIntervalSince1970, endInterval + step)
        let alignedStart = floor(bufferedStart / step) * step

        var current = alignedStart
        var ticks: [Date] = []

        while current <= bufferedEnd {
            let date = Date(timeIntervalSince1970: current)
            if date >= dayStart && date <= dayEnd {
                ticks.append(date)
            }
            current += step
        }
        return ticks
    }

    private func xAxisLabel(for date: Date) -> String {
        switch clampedVisibleDuration {
        case ...1800:
            return date.toString(format: "HH:mm:ss")
        case ...14400:
            return date.toString(format: "HH:mm")
        default:
            return "\(taipeiCalendar.component(.hour, from: date))h"
        }
    }

    private var visibleHeaderTime: Date {
        let center = clampedChartScrollPosition.addingTimeInterval(clampedVisibleDuration * 0.5)
        return min(max(center, dayStart), dayLastSecond)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("用藥與震動時序對照")
                    .font(.title2.bold())
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                Text("將震動強度（RMS）與服藥時間放在同一時間軸，方便觀察服藥前後的震動變化，作為日常回顧與回診討論的參考。")
                    .font(.subheadline)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 12) {
                chartControlHeaderView
                    .padding(.horizontal, 4)

                if bufferedTremorPoints.isEmpty && bufferedMedications.isEmpty {
                    emptyStateView
                } else {
                    interactiveChartView
                    chartFooterView
                        .padding(.horizontal, 4)
                }

                inPlaceSelectionDetailCard
                    .padding(.horizontal, 4)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)

            summaryCardView
        }
        .sheet(isPresented: $showTimePicker) {
            timePickerNavigationStack
        }
        .onAppear {
            dataVM.selectedFilterDate = selectedDate
            Task {
                await dataVM.loadTremorHistory()
            }
            initializeScrollPositionIfNeeded()
        }
        .onChange(of: selectedDate) { _, newDate in
            dataVM.selectedFilterDate = newDate
            Task {
                await dataVM.loadTremorHistory()
            }
            hasInitializedScrollPosition = false
            hasSelectedSpecificTime = false
            selectedPointDate = nil
            selectedPointRMS = nil
            initializeScrollPositionIfNeeded()
        }
        .onChange(of: dataVM.rmsTrendHistory.last?.timestamp) { _, _ in
            guard isViewingToday, !hasSelectedSpecificTime else { return }
            moveToDate(Date(), animated: false)
        }
    }

    // 圖表頂部操作列
    private var chartControlHeaderView: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                    Text("\(selectedDate.toString(format: "MM/dd")) \(visibleHeaderTime.toString(format: "HH:mm")) 震動與服藥時序")
                        .font(.headline)
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                }
                Spacer()

                Button {
                    selectedChartTime = min(max(visibleHeaderTime, dayStart), dayLastSecond)
                    showTimePicker = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.clock")
                        Text("選擇時間")
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AppTheme.primary(for: colorScheme).opacity(0.10))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

            HStack {
                legendBadge(color: AppTheme.primary(for: colorScheme), title: "震動 RMS")
                legendBadge(color: AppTheme.accent(for: colorScheme), title: "服藥點")
                legendBadge(color: .red, title: "選取標記")
                Spacer()
                quickZoomButton(title: "1小時", duration: 3600)
                quickZoomButton(title: "4小時", duration: 4 * 3600)
                quickZoomButton(title: "全天", duration: 24 * 3600)
            }
        }
    }

    private func quickZoomButton(title: String, duration: TimeInterval) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                visibleDuration = duration
                zoomBaseDuration = duration
                let maxLeading = max(dayStart, dayEnd.addingTimeInterval(-duration))
                let center = visibleHeaderTime
                let newLeading = center.addingTimeInterval(-duration * 0.5)
                chartScrollPosition = min(max(newLeading, dayStart), maxLeading)
            }
        } label: {
            Text(title)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(AppTheme.primary(for: colorScheme).opacity(clampedVisibleDuration == duration ? 0.2 : 0.08))
                .foregroundColor(AppTheme.primary(for: colorScheme))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var timePickerNavigationStack: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("選擇查看日期與時間")
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                DatePicker(
                    "日期與時間",
                    selection: $selectedChartTime,
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal, 8)

                Text("目標時間：\(selectedChartTime.toString(format: "yyyy/MM/dd HH:mm"))")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                Button {
                    hasSelectedSpecificTime = false
                    let now = Date()
                    selectedChartTime = now
                    selectedDate = now
                    selectedPointDate = nil
                    selectedPointRMS = nil
                    showTimePicker = false
                    DispatchQueue.main.async {
                        moveToDate(now, animated: true)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                        Text("回到今天現在")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(AppTheme.primary(for: colorScheme).opacity(0.10))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)

                Spacer()
            }
            .padding()
            .background(AppTheme.background(for: colorScheme))
            .navigationTitle("選擇時間點")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showTimePicker = false }
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("前往") {
                        hasSelectedSpecificTime = true
                        selectedPointDate = nil
                        selectedPointRMS = nil

                        let targetTime = selectedChartTime
                        let targetDay = taipeiCalendar.startOfDay(for: targetTime)

                        if !taipeiCalendar.isDate(targetTime, inSameDayAs: selectedDate) {
                            selectedDate = targetDay
                        }

                        let targetDayEnd = taipeiCalendar.date(byAdding: .day, value: 1, to: targetDay) ?? targetDay
                        let limitEnd = taipeiCalendar.isDateInToday(targetDay) ? Date() : targetDayEnd.addingTimeInterval(-1)
                        let safeTime = min(max(targetTime, targetDay), limitEnd)

                        showTimePicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            moveToDate(safeTime, animated: true)
                        }
                    }
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.primary(for: colorScheme))
                }
            }
        }
        .presentationDetents([.large])
    }

    // 核心手勢圖表本體
    private var interactiveChartView: some View {
        GeometryReader { geometry in
            Chart {
                // 震動強度折線與漸層面積
                ForEach(bufferedTremorPoints) { point in
                    LineMark(
                        x: .value("時間", point.timestamp),
                        y: .value("強度", max(0, point.rmsValue))
                    )
                    .foregroundStyle(AppTheme.primary(for: colorScheme))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)

                    AreaMark(
                        x: .value("時間", point.timestamp),
                        y: .value("強度", max(0, point.rmsValue))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppTheme.primary(for: colorScheme).opacity(0.22), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.monotone)
                }

                // 服藥標記垂直線與註記
                ForEach(bufferedMedications) { med in
                    RuleMark(x: .value("服藥時間", med.date))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                        .foregroundStyle(AppTheme.accent(for: colorScheme))
                        .annotation(position: .top, alignment: .center) {
                            HStack(spacing: 3) {
                                Image(systemName: med.medType == .patch ? "figure.stand" : "pill.fill")
                                    .font(.system(size: 8))
                                Text(med.name)
                                    .font(.system(size: 8, weight: .bold))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AppTheme.cardBackground(for: colorScheme).opacity(0.92))
                            .foregroundColor(AppTheme.accent(for: colorScheme))
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(AppTheme.accent(for: colorScheme).opacity(0.6), lineWidth: 1)
                            )
                        }
                }

                // 原地單擊選取標記線
                if let selectedDate = selectedPointDate, let selectedRMS = selectedPointRMS {
                    RuleMark(x: .value("選取時間", selectedDate))
                        .foregroundStyle(Color.red.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))

                    PointMark(
                        x: .value("選取時間", selectedDate),
                        y: .value("選取強度", selectedRMS)
                    )
                    .foregroundStyle(Color.red)
                    .symbolSize(60)
                }
            }
            .chartXScale(domain: clampedChartScrollPosition...visibleEndDate)
            .chartYScale(domain: 0.0...dynamicMaxY)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(Color.gray.opacity(0.25))

                    if let doubleVal = value.as(Double.self) {
                        AxisValueLabel {
                            Text(String(format: "%.1f", doubleVal))
                                .font(.system(size: 10, design: .rounded))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom, values: visibleXAxisTicks) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(Color.gray.opacity(0.25))

                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(xAxisLabel(for: date))
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.textSecondary(for: colorScheme))
                                .padding(.top, 4)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .chartGesture { proxy in
                SpatialTapGesture()
                    .onEnded { tapValue in
                        let location = tapValue.location
                        guard let tappedDate = proxy.value(atX: location.x, as: Date.self) else { return }
                        handleChartTap(at: tappedDate)
                    }
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        if !isPinching {
                            isPinching = true
                            zoomAnchorDate = visibleHeaderTime
                        }
                        let magnification = max(value.magnification, 0.05)
                        let newDuration = min(max(zoomBaseDuration / magnification, minimumVisibleDuration), maximumVisibleDuration)
                        visibleDuration = newDuration
                        let maxLeading = max(dayStart, dayEnd.addingTimeInterval(-newDuration))
                        let newLeading = zoomAnchorDate.addingTimeInterval(-newDuration * 0.5)
                        chartScrollPosition = min(max(newLeading, dayStart), maxLeading)
                    }
                    .onEnded { _ in
                        zoomBaseDuration = clampedVisibleDuration
                        isPinching = false
                        keepScrollPositionInsideDay()
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        guard !isPinching else { return }
                        let width = max(geometry.size.width, 1)
                        let secondsPerPoint = clampedVisibleDuration / width
                        if dragStartScrollPosition == nil {
                            dragStartScrollPosition = chartScrollPosition
                        }
                        guard let startPosition = dragStartScrollPosition else { return }
                        let deltaSeconds = Double(value.translation.width) * secondsPerPoint
                        let proposedLeading = startPosition.addingTimeInterval(-deltaSeconds)
                        let maxLeading = max(dayStart, dayEnd.addingTimeInterval(-clampedVisibleDuration))
                        chartScrollPosition = min(max(proposedLeading, dayStart), maxLeading)
                    }
                    .onEnded { _ in
                        dragStartScrollPosition = nil
                    }
            )
        }
        .frame(height: chartHeight)
    }

    // 原地選取資訊卡片
    @ViewBuilder
    private var inPlaceSelectionDetailCard: some View {
        if let selectedDate = selectedPointDate, let rms = selectedPointRMS {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text(selectedDate.toString(format: "HH:mm:ss"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    }
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            self.selectedPointDate = nil
                            self.selectedPointRMS = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }

                Divider()

                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("震動強度 (RMS)")
                            .font(.caption2)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        Text(String(format: "%.2f deg/s", rms))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(rms >= 0.20 ? .orange : AppTheme.textPrimary(for: colorScheme))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("服藥時差")
                            .font(.caption2)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        Text(relativeMedicationTimeText(for: selectedDate))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                    }
                }
            }
            .padding(10)
            .background(AppTheme.background(for: colorScheme))
            .cornerRadius(10)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var summaryCardView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("圖表閱讀說明")
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(AppTheme.primary(for: colorScheme))
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("服藥前後的震動變化")
                        .font(.subheadline.bold())
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    Text("虛線標示服藥時間，曲線呈現震動強度（RMS）。可對照服藥前後的數值與時間變化；此圖不直接判定藥效或 OFF 時期。")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }
        }
        .padding()
        .background(AppTheme.primary(for: colorScheme).opacity(0.08))
        .cornerRadius(12)
    }
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 36))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.5))
            Text("目前尚無震動或服藥數據")
                .font(.subheadline)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .frame(maxWidth: .infinity, minHeight: chartHeight)
        .background(AppTheme.background(for: colorScheme))
        .cornerRadius(12)
    }

    private var chartFooterView: some View {
        HStack {
            Text("點擊圖表可標記時間點（紅點與紅虛線）檢視精確數值")
                .font(.caption2)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            Spacer()
            Text("單位：deg/s")
                .font(.caption2)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
    }

    // 互動與計算邏輯
    private func handleChartTap(at tappedDate: Date) {
        let tolerance = max(clampedVisibleDuration * 0.05, 30)
        let nearbyHistory = bufferedTremorPoints.filter {
            abs($0.timestamp.timeIntervalSince(tappedDate)) <= tolerance
        }

        if let closest = nearbyHistory.min(by: { abs($0.timestamp.timeIntervalSince(tappedDate)) < abs($1.timestamp.timeIntervalSince(tappedDate)) }) {
            withAnimation(.easeOut(duration: 0.2)) {
                selectedPointDate = closest.timestamp
                selectedPointRMS = closest.rmsValue
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                selectedPointDate = nil
                selectedPointRMS = nil
            }
        }
    }

    private func relativeMedicationTimeText(for date: Date) -> String {
        let pastMeds = todayMedications.filter { $0.date <= date }.sorted { $0.date > $1.date }
        guard let lastMed = pastMeds.first else { return "服藥前量測" }

        let diffMinutes = Int(date.timeIntervalSince(lastMed.date) / 60)
        let hours = diffMinutes / 60
        let minutes = diffMinutes % 60

        let timeStr = hours > 0 ? "\(hours)小時\(minutes)分" : "\(minutes)分鐘"
        return "服藥（\(lastMed.name)）後 \(timeStr)"
    }

    private func initializeScrollPositionIfNeeded() {
        guard !hasInitializedScrollPosition else { return }
        hasInitializedScrollPosition = true

        if isViewingToday {
            moveToDate(Date(), animated: false)
        } else if let firstMed = todayMedications.first {
            moveToDate(firstMed.date, animated: false)
        } else if let latest = dataVM.rmsTrendHistory.last?.timestamp {
            moveToDate(latest, animated: false)
        } else {
            moveToDate(dayStart, animated: false)
        }
    }

    private func moveToDate(_ target: Date, animated: Bool) {
        let safeTarget = min(max(target, dayStart), dayEnd)
        let maxLeading = max(dayStart, dayEnd.addingTimeInterval(-clampedVisibleDuration))

        let leading = safeTarget.addingTimeInterval(-clampedVisibleDuration * 0.5)
        let clampedLeading = min(max(leading, dayStart), maxLeading)

        if animated {
            withAnimation(.easeInOut(duration: 0.25)) { chartScrollPosition = clampedLeading }
        } else {
            chartScrollPosition = clampedLeading
        }
    }

    private func keepScrollPositionInsideDay() {
        let maxLeading = max(dayStart, dayEnd.addingTimeInterval(-clampedVisibleDuration))
        chartScrollPosition = min(max(chartScrollPosition, dayStart), maxLeading)
    }

    private func legendBadge(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption).foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
    }
}
