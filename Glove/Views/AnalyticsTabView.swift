import Charts
import SwiftUI

/// 藥效波動與震動數據圖表分析
struct AnalyticsTabView: View {
    @ObservedObject var medVM: MedicationViewModel
    @ObservedObject var dataVM: DataViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedDate: Date

    /// 圖表可視範圍時段長度、縮放平移手勢與捲動位置狀態
    @State private var visibleDuration: TimeInterval = 4 * 3600
    @State private var zoomBaseDuration: TimeInterval = 4 * 3600
    @State private var chartScrollPosition: Date = Date()
    @State private var hasInitializedScrollPosition: Bool = false
    @State private var zoomAnchorDate: Date = Date()
    @State private var isPinching: Bool = false
    @State private var dragStartScrollPosition: Date? = nil

    /// 時間選取彈窗顯示、目標時間與手動選定標記狀態
    @State private var showTimePicker: Bool = false
    @State private var selectedChartTime: Date = Date()
    @State private var hasSelectedSpecificTime: Bool = false

    /// 原地單擊選取之資料點時間、強度數值與自動追隨節流時間戳記
    @State private var selectedPointDate: Date? = nil
    @State private var selectedPointRMS: Double? = nil
    @State private var lastAutoFollowUpdate: Date = .distantPast

    /// 圖表可視時長極限與圖表元件高度常數
    private let minimumVisibleDuration: TimeInterval = 5 * 60
    private let maximumVisibleDuration: TimeInterval = 24 * 60 * 60
    private let chartHeight: CGFloat = 285

    // 日期與時間軸邊界計算
    private var taipeiCalendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        return calendar
    }

    /// 判斷目前選取之日期是否為今日
    private var isViewingToday: Bool {
        taipeiCalendar.isDateInToday(selectedDate)
    }

    /// 選定日之起始時間（00:00:00）
    private var dayStart: Date {
        taipeiCalendar.startOfDay(for: selectedDate)
    }

    /// 選定日之結束時間（若為今日則取當前時間，非今日則取隔日零時）
    private var dayEnd: Date {
        let tomorrow = taipeiCalendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(24 * 60 * 60)
        return isViewingToday ? min(tomorrow, Date()) : tomorrow
    }

    /// 當日最後一個有效秒數時間點
    private var dayLastSecond: Date {
        isViewingToday ? Date() : dayEnd.addingTimeInterval(-1)
    }

    /// 限制在最大與最小允許範圍內的可視時長
    private var clampedVisibleDuration: TimeInterval {
        min(max(visibleDuration, minimumVisibleDuration), maximumVisibleDuration)
    }

    /// 圖表捲動位置允許之最大左邊界起始時間
    private var maxLeadingDate: Date {
        max(dayStart, dayEnd.addingTimeInterval(-clampedVisibleDuration))
    }

    /// 經過邊界限制過濾後之圖表捲動位置
    private var clampedChartScrollPosition: Date {
        min(max(chartScrollPosition, dayStart), maxLeadingDate)
    }

    /// 圖表可視範圍的結束時間點
    private var visibleEndDate: Date {
        min(clampedChartScrollPosition.addingTimeInterval(clampedVisibleDuration), dayEnd)
    }

    /// 包含前後緩衝之資料擷取時間區間
    private var bufferedRange: (start: Date, end: Date) {
        let buffer = min(max(clampedVisibleDuration * 0.05, 60), 5 * 60)
        return (
            clampedChartScrollPosition.addingTimeInterval(-buffer),
            visibleEndDate.addingTimeInterval(buffer)
        )
    }

    /// 利用二分搜尋快速切片指定時段範圍之走勢點陣列
    /// - Parameters:
    ///   - points: 依時間遞增排序之走勢資料陣列
    ///   - start: 擷取起始時間
    ///   - end: 擷取結束時間
    /// - Returns: 切片後的資料點陣列
    private func trendSlice(
        _ points: [DataViewModel.RMSTrendPoint],
        start: Date,
        end: Date
    ) -> [DataViewModel.RMSTrendPoint] {
        guard !points.isEmpty else { return [] }

        var low = 0
        var high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].timestamp < start {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let lower = low

        low = lower
        high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].timestamp <= end {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let upper = low

        guard lower < upper else { return [] }
        return Array(points[lower..<upper])
    }

    /// 經緩衝範圍過濾且排除非數值之震顫走勢資料點
    private var bufferedTremorPoints: [DataViewModel.RMSTrendPoint] {
        let range = bufferedRange
        return trendSlice(
            dataVM.rmsTrendHistory,
            start: range.start,
            end: range.end
        ).filter {
            $0.rmsValue.isFinite && !$0.rmsValue.isNaN
        }
    }

    /// 對走勢資料點進行桶狀極值降採樣以減輕繪圖負載
    /// - Parameters:
    ///   - points: 原始資料點陣列
    ///   - maxCount: 目標最大取樣點數
    /// - Returns: 降採樣後之資料點陣列
    private func downsampleTrend(
        _ points: [DataViewModel.RMSTrendPoint],
        maxCount: Int
    ) -> [DataViewModel.RMSTrendPoint] {
        guard points.count > maxCount, maxCount >= 4 else {
            return points
        }

        let bucketCount = max(1, maxCount / 2)
        let bucketSize = Int(ceil(Double(points.count) / Double(bucketCount)))
        var result: [DataViewModel.RMSTrendPoint] = []
        result.reserveCapacity(maxCount)

        var startIndex = 0
        while startIndex < points.count {
            let endIndex = min(startIndex + bucketSize, points.count)
            let bucket = points[startIndex..<endIndex]

            guard let minPoint = bucket.min(by: { $0.rmsValue < $1.rmsValue }),
                  let maxPoint = bucket.max(by: { $0.rmsValue < $1.rmsValue })
            else {
                startIndex = endIndex
                continue
            }

            if minPoint.timestamp <= maxPoint.timestamp {
                result.append(minPoint)
                if minPoint.id != maxPoint.id {
                    result.append(maxPoint)
                }
            } else {
                result.append(maxPoint)
                if minPoint.id != maxPoint.id {
                    result.append(minPoint)
                }
            }
            startIndex = endIndex
        }
        return result
    }

    /// 選定日當日之全部服藥紀錄清單
    private var todayMedications: [MedicationRecord] {
        medVM.medicationList.filter {
            $0.date >= dayStart && $0.date <= dayEnd
        }
    }

    /// 經可視緩衝範圍過濾後之服藥紀錄清單
    private var bufferedMedications: [MedicationRecord] {
        let buffer = max(clampedVisibleDuration * 0.5, 60)
        let start = clampedChartScrollPosition.addingTimeInterval(-buffer)
        let end = visibleEndDate.addingTimeInterval(buffer)
        return todayMedications.filter {
            $0.date >= start && $0.date <= end
        }
    }

    /// 計算給定走勢資料之 Y 軸安全最大刻度值
    /// - Parameter points: 待分析之走勢資料陣列
    /// - Returns: 圖表適用的 Y 軸上限值
    private func maxY(for points: [DataViewModel.RMSTrendPoint]) -> Double {
        let values = points.map(\.rmsValue).filter { $0.isFinite && !$0.isNaN }
        guard let maximum = values.max(), maximum > 0 else {
            return 0.5
        }
        return max(0.5, maximum * 1.25)
    }

    /// 根據當前可視長度動態調整 X 軸刻度間距秒數
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

    /// 當前可視時段內所有 X 軸標籤時間刻度陣列
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

    /// 格式化指定時間在 X 軸上之文字呈現
    /// - Parameter date: 刻度日期時間
    /// - Returns: 時間字串
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

    /// 圖表可視範圍中央對應之時間點
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
            if !taipeiCalendar.isDate(dataVM.selectedFilterDate, inSameDayAs: selectedDate) {
                dataVM.selectedFilterDate = selectedDate
            } else if dataVM.rmsTrendHistory.isEmpty && !dataVM.isHistoryLoading {
                Task {
                    await dataVM.loadTremorHistory()
                }
            }
            initializeScrollPositionIfNeeded()
        }
        .onChange(of: selectedDate) { _, newDate in
            if !taipeiCalendar.isDate(dataVM.selectedFilterDate, inSameDayAs: newDate) {
                dataVM.selectedFilterDate = newDate
            }
            hasInitializedScrollPosition = false
            hasSelectedSpecificTime = false
            selectedPointDate = nil
            selectedPointRMS = nil
            initializeScrollPositionIfNeeded()
        }
        .onChange(of: dataVM.rmsTrendHistory.last?.timestamp) { _, _ in
            guard isViewingToday, !hasSelectedSpecificTime else { return }
            let now = Date()
            guard now.timeIntervalSince(lastAutoFollowUpdate) >= 2.0 else { return }
            lastAutoFollowUpdate = now
            moveToDate(now, animated: false)
        }
    }

    /// 圖表上方操作與狀態指示標頭，包含時段標示、選擇時間按鈕與縮放切換
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

    /// 快捷縮放時段按鈕元件
    /// - Parameters:
    ///   - title: 按鈕顯示名稱
    ///   - duration: 目標可視時段秒數
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

    /// 彈出式日期與時間滾輪跳轉導覽頁面
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

    /// 核心手勢圖表本體，支援滑動檢視、雙指縮放、拖曳平移與單擊選取
    private var interactiveChartView: some View {
        let chartPoints = downsampleTrend(bufferedTremorPoints, maxCount: 900)
        let currentMaxY = maxY(for: chartPoints)

        return GeometryReader { geometry in
            Chart {
                ForEach(chartPoints) { point in
                    LineMark(
                        x: .value("時間", point.timestamp),
                        y: .value("強度", max(0, point.rmsValue))
                    )
                    .foregroundStyle(AppTheme.primary(for: colorScheme))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.linear)
                }

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
            .chartYScale(domain: 0.0...currentMaxY)
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

    /// 原地單擊選取後顯示之詳細資訊卡片
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

    /// 圖表閱讀指引與臨床觀察摘要卡片
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

    /// 無震顫與服藥紀錄時顯示之空狀態提示視圖
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

    /// 圖表底部操作提示與單位標籤
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

    /// 處理使用者於圖表上的單擊手勢，尋找最接近之有效資料點
    /// - Parameter tappedDate: 點擊處對應之時間
    private func handleChartTap(at tappedDate: Date) {
        let tolerance = max(clampedVisibleDuration * 0.05, 30)

        if let closest = dataVM.nearestTrendPoint(to: tappedDate, tolerance: tolerance) {
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

    /// 計算給定時間距離前一次服藥的時間間隔文字描述
    /// - Parameter date: 目標比對時間
    /// - Returns: 格式化後的時間間隔描述字串
    private func relativeMedicationTimeText(for date: Date) -> String {
        let pastMeds = todayMedications.filter { $0.date <= date }.sorted { $0.date > $1.date }
        guard let lastMed = pastMeds.first else { return "服藥前量測" }

        let diffMinutes = Int(date.timeIntervalSince(lastMed.date) / 60)
        let hours = diffMinutes / 60
        let minutes = diffMinutes % 60
        let timeStr = hours > 0 ? "\(hours)小時\(minutes)分" : "\(minutes)分鐘"
        return "服藥（\(lastMed.name)）後 \(timeStr)"
    }

    /// 視圖初次載入時初始化圖表捲動位置
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

    /// 平移圖表視野至指定時間點
    /// - Parameters:
    ///   - target: 目標時間點
    ///   - animated: 是否包含動畫效果
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

    /// 限制圖表捲動位置不超出當日有效邊界
    private func keepScrollPositionInsideDay() {
        let maxLeading = max(dayStart, dayEnd.addingTimeInterval(-clampedVisibleDuration))
        chartScrollPosition = min(max(chartScrollPosition, dayStart), maxLeading)
    }

    /// 建立圖表圖例標記元件
    /// - Parameters:
    ///   - color: 圖例圓點色彩
    ///   - title: 圖例說明文字
    private func legendBadge(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption).foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
    }
}
