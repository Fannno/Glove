import Charts
import PhotosUI
import SwiftUI
import UIKit

/// 震顫事件卡片視圖，支援展開檢視時序 RMS 走勢、PSD 頻譜圖、補充情境標籤與照片管理
struct TremorEventCardView: View {
    @Binding var event: TremorEvent
    @ObservedObject var dataVM: DataViewModel
    @ObservedObject var loginVM: LoginViewModel
    @Environment(\.colorScheme) private var colorScheme
    let isSimpleMode: Bool

    /// 編輯情境標籤與照片選擇暫存綁定狀態
    @Binding var editingEventID: UUID?
    @Binding var tempUserTag: String
    @Binding var tempSelectedImages: [UIImage]
    @Binding var selectedMediaItems: [PhotosPickerItem]
    @Binding var currentPageIndex: Int
    @Binding var previewImage: UIImage?

    /// 儲存進度、提示警告與彈窗工作表綁定狀態
    @Binding var savingEventID: UUID?
    @Binding var activeInfoSheet: InfoSheetType?
    @Binding var showSaveErrorAlert: Bool
    @Binding var saveErrorMessage: String

    /// 文字輸入框焦點狀態與圖表切換分頁索引
    @FocusState.Binding var isFieldFocused: Bool
    @State private var selectedChartTab: Int = 0

    /// 身分與卡片展示狀態判斷計算屬性
    private var isCaregiver: Bool {
        if let role = loginVM.userData?.role {
            return role == 1
        }
        if loginVM.boundPartner != nil {
            return true
        }
        return false
    }

    private var isExpanded: Bool {
        dataVM.expandedEventID == event.id
    }

    private var isTagged: Bool {
        !event.userTag.isEmpty && event.userTag != "未標記"
    }

    private var isEditing: Bool {
        !isCaregiver && editingEventID == event.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerButton

            if isExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    if isEditing {
                        editablePanelView
                    } else {
                        readOnlyPanelView
                    }

                    if !isSimpleMode {
                        Divider().padding(.vertical, 4)
                        eventDetailChartsView
                    }
                }
                .padding()
                .background(AppTheme.background(for: colorScheme))
            }
        }
        .cornerRadius(16)
        .padding(.horizontal, 20)
        .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
    }

    /// 卡片頂部摘要列按鈕，點擊可展開或收合卡片細節
    private var headerButton: some View {
        Button(action: {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            withAnimation(.spring()) {
                if isExpanded {
                    dataVM.expandedEventID = nil
                    editingEventID = nil
                } else {
                    dataVM.expandedEventID = event.id
                    tempUserTag = (event.userTag == "未標記") ? "" : event.userTag
                    tempSelectedImages = event.selectedImages
                }
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(event.timestamp.toString(format: "HH:mm:ss"))
                            .font(.system(size: isSimpleMode ? 18 : 16, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                        if isTagged {
                            Text(event.userTag)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        } else {
                            Text("未標記")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.accent(for: colorScheme).opacity(0.12))
                                .foregroundColor(AppTheme.accent(for: colorScheme))
                                .cornerRadius(4)
                        }

                        if event.isMotorActive {
                            HStack(spacing: 2) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 9))
                                Text("抑震介入")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppTheme.primary(for: colorScheme).opacity(0.12))
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                            .cornerRadius(4)
                        }
                    }

                    Text(String(format: "強度: %.2f deg/s | 頻率: %.1f Hz", event.rmsValue, event.dominantFrequency))
                        .font(isSimpleMode ? .subheadline : .caption)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
            .padding(isSimpleMode ? 16 : 14)
            .background(AppTheme.cardBackground(for: colorScheme))
        }
        .buttonStyle(.plain)
    }

    /// 唯讀檢視面板，展示已記錄之情境標籤與照片預覽
    private var readOnlyPanelView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("情境標籤：")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                Text(event.userTag.isEmpty ? "未標記" : event.userTag)
                    .font(.system(size: 14))
                    .foregroundColor((event.userTag.isEmpty || event.userTag == "未標記") ? AppTheme.accent(for: colorScheme) : AppTheme.textPrimary(for: colorScheme))
            }

            if !event.selectedImages.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("紀錄影像 (點擊放大檢視)：")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    TabView {
                        ForEach(Array(event.selectedImages.enumerated()), id: \.offset) { _, img in
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 200)
                                .frame(maxWidth: .infinity)
                                .clipped()
                                .cornerRadius(10)
                                .onTapGesture {
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        previewImage = img
                                    }
                                }
                        }
                    }
                    .frame(height: 200)
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
                }
            }

            if !isCaregiver {
                Button(action: {
                    withAnimation {
                        tempUserTag = (event.userTag == "未標記") ? "" : event.userTag
                        tempSelectedImages = event.selectedImages
                        editingEventID = event.id
                    }
                }) {
                    HStack {
                        Image(systemName: "pencil")
                        Text("補充生活情境與照片")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(AppTheme.primary(for: colorScheme).opacity(0.1))
                    .foregroundColor(AppTheme.primary(for: colorScheme))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 編輯面板，提供標籤文字輸入、快捷活動選項與照片上傳功能
    private var editablePanelView: some View {
        let isCurrentlySaving = savingEventID == event.id

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("填寫發作當下活動：")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                TextField("自訂活動 (如: 拿筷子、看電視)", text: $tempUserTag)
                    .focused($isFieldFocused)
                    .textFieldStyle(.roundedBorder)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(dataVM.activityOptions, id: \.self) { tag in
                            Button(action: {
                                tempUserTag = tag
                            }) {
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(tempUserTag == tag ? AppTheme.primary(for: colorScheme) : AppTheme.textSecondary(for: colorScheme).opacity(0.15))
                                    .foregroundColor(tempUserTag == tag ? .white : AppTheme.textPrimary(for: colorScheme))
                                    .cornerRadius(12)
                            }
                        }
                    }
                }
            }

            MediaManagementView(
                tempSelectedImages: $tempSelectedImages,
                selectedMediaItems: $selectedMediaItems,
                currentPageIndex: $currentPageIndex,
                previewImage: $previewImage
            )

            HStack(spacing: 12) {
                Button(action: {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    withAnimation {
                        editingEventID = nil
                    }
                }) {
                    Text("取消")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(AppTheme.textSecondary(for: colorScheme).opacity(0.15))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .cornerRadius(10)
                }

                Button(action: {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    savingEventID = event.id

                    var eventToSave = event
                    let finalTag = tempUserTag.trimmingCharacters(in: .whitespacesAndNewlines)
                    eventToSave.userTag = finalTag.isEmpty ? "未標記" : finalTag
                    eventToSave.selectedImages = tempSelectedImages

                    Task {
                        let success = await dataVM.saveTremorEvent(eventToSave)

                        await MainActor.run {
                            savingEventID = nil
                            if success {
                                withAnimation {
                                    editingEventID = nil
                                }
                            } else {
                                UINotificationFeedbackGenerator().notificationOccurred(.error)
                                saveErrorMessage = "網路連線異常或伺服器未回應，請稍後再試。"
                                showSaveErrorAlert = true
                            }
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        if isCurrentlySaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                            Text("儲存中...")
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                            Text("儲存標籤紀錄")
                        }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isCurrentlySaving ? AppTheme.textSecondary(for: colorScheme).opacity(0.4) : AppTheme.primary(for: colorScheme))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isCurrentlySaving)
            }
        }
    }

    /// 事件細節圖表容器，支援強度走勢與頻率分佈切換
    private var eventDetailChartsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("圖表類型", selection: $selectedChartTab) {
                Text("強度走勢 (RMS)").tag(0)
                Text("頻率分佈 (PSD)").tag(1)
            }
            .pickerStyle(.segmented)

            if selectedChartTab == 0 {
                eventTrendChartView
            } else {
                psdDetailChartView
            }
        }
    }

    /// 產生圖表時間軸安全刻度陣列
    /// - Parameters:
    ///   - start: 區間起始時間
    ///   - end: 區間結束時間
    ///   - strideSeconds: 刻度步進間隔秒數
    /// - Returns: 計算後之日期刻度陣列
    private func generateSafeXAxisTicks(start: Date, end: Date, strideSeconds: TimeInterval) -> [Date] {
        var ticks: [Date] = []
        var current = start.timeIntervalSince1970
        let endInterval = end.timeIntervalSince1970

        while current <= endInterval {
            ticks.append(Date(timeIntervalSince1970: current))
            current += strideSeconds
        }
        return ticks
    }

    /// 事件前後 3 秒的連續 RMS 強度走勢圖表與馬達運轉時段標記
    private var eventTrendChartView: some View {
        let startDate = event.timestamp.addingTimeInterval(-3)
        let endDate = event.timestamp.addingTimeInterval(3)
        let chartHistory = dataVM.rmsChartHistory(surrounding: event.timestamp, seconds: 3)
        _ = chartHistory.filter { $0.timestamp >= startDate && $0.timestamp <= endDate }

        var visibleMotorIntervals = dataVM.motorIntervals(surrounding: event.timestamp, seconds: 3)

        if event.isMotorActive {
            let fallbackInterval = DataViewModel.MotorActiveInterval(
                start: event.timestamp.addingTimeInterval(-0.5),
                end: event.timestamp
            )

            let alreadyHasVisibleCoverage = visibleMotorIntervals.contains { interval in
                interval.start <= fallbackInterval.start && interval.end >= fallbackInterval.end
            }

            if !alreadyHasVisibleCoverage {
                visibleMotorIntervals.append(fallbackInterval)
            }
        }

        let validValues = chartHistory.map(\.rmsValue).filter { $0.isFinite && !$0.isNaN }
        let localMaxY = max(0.5, (validValues.max() ?? 0.5) * 1.15)
        let safeTicks = generateSafeXAxisTicks(start: startDate, end: endDate, strideSeconds: 1)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(AppTheme.primary(for: colorScheme))
                Text("\(event.timestamp.toString(format: "HH:mm:ss")) 前後 3 秒震動強度走勢")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeInfoSheet = .eventRMSTrend
                    }
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.primary(for: colorScheme).opacity(0.8))
                }
                .buttonStyle(.plain)

                Spacer()
            }

            if chartHistory.isEmpty {
                Text("無區間數據")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart {
                    ForEach(visibleMotorIntervals) { interval in
                        let visibleStart = max(interval.start, startDate)
                        let visibleEnd = min(interval.end, endDate)

                        if visibleEnd > visibleStart {
                            RectangleMark(
                                xStart: .value("馬達開始", visibleStart),
                                xEnd: .value("馬達結束", visibleEnd),
                                yStart: .value("底", 0),
                                yEnd: .value("頂", localMaxY)
                            )
                            .foregroundStyle(Color.orange.opacity(0.18))
                        }
                    }

                    ForEach(chartHistory) { point in
                        if point.rmsValue.isFinite && !point.rmsValue.isNaN {
                            LineMark(
                                x: .value("時間", point.timestamp),
                                y: .value("強度", max(0, point.rmsValue))
                            )
                            .foregroundStyle(AppTheme.primary(for: colorScheme))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.linear)
                        }
                    }

                    PointMark(
                        x: .value("目前事件時間", event.timestamp),
                        y: .value("目前事件強度", max(0, event.rmsValue))
                    )
                    .foregroundStyle(Color.orange)
                    .symbolSize(85)
                }
                .chartXScale(domain: startDate...endDate)
                .chartYScale(domain: 0...localMaxY)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(Color.gray.opacity(0.3))

                        if let number = value.as(Double.self) {
                            AxisValueLabel {
                                Text(String(format: "%.1f", number))
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom, values: safeTicks) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(Color.gray.opacity(0.3))

                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(date.toString(format: "ss") + "s")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.textSecondary(for: colorScheme))
                            }
                        }
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea.clipped()
                }
                .frame(height: 160)

                HStack(spacing: 14) {
                    HStack(spacing: 4) {
                        Capsule()
                            .fill(AppTheme.primary(for: colorScheme))
                            .frame(width: 15, height: 3)
                        Text("RMS 走勢")
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                        Text("目前事件")
                    }

                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.orange.opacity(0.3))
                            .frame(width: 9, height: 9)
                        Text("馬達介入區間")
                    }

                    Spacer()
                }
                .font(.caption2)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.top, 2)

                if chartHistory.count == 1 {
                    Text("目前只有一筆 RMS 資料，累積下一筆後才會形成折線。")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }
        }
        .padding()
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.03), radius: 4, y: 2)
    }

    /// 事件對應之功率譜密度（PSD）離散頻譜分佈圖表
    private var psdDetailChartView: some View {
        let eventWindow = event.rawWindowData
        let nearestHistoryWindow = dataVM.rmsTrendHistory
            .filter { $0.rawWindowData.count == 400 }
            .min { abs($0.timestamp.timeIntervalSince(event.timestamp)) < abs($1.timestamp.timeIntervalSince(event.timestamp)) }

        let nearestTimeDifference = nearestHistoryWindow.map { abs($0.timestamp.timeIntervalSince(event.timestamp)) } ?? .infinity
        let resolvedWindow: [TremorDataPoint]

        if eventWindow.count == 400 {
            resolvedWindow = eventWindow
        } else if let nearestHistoryWindow, nearestTimeDifference <= 5 {
            resolvedWindow = nearestHistoryWindow.rawWindowData
        } else {
            resolvedWindow = []
        }

        let psdData = dataVM.calculatePSDData(from: resolvedWindow)
        let isSignalReliable = event.rmsValue >= 0.20 && event.rmsValue.isFinite && !event.rmsValue.isNaN
        let validPowers = psdData.map(\.power).filter { $0.isFinite && !$0.isNaN && $0 >= 0 }
        let maxPowerValue = validPowers.max() ?? 0
        let maxPowerDomain = max(0.0001, maxPowerValue * 1.2)

        let maxPeak = isSignalReliable
            ? psdData.filter { $0.frequencyHz >= 3 && $0.frequencyHz <= 7 && $0.power.isFinite && !$0.power.isNaN }.max(by: { $0.power < $1.power })
            : nil

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.purple)
                Text("震動頻率分佈")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .lineLimit(1)

                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeInfoSheet = .eventPSD
                    }
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 15))
                        .foregroundColor(.purple.opacity(0.8))
                }
                .buttonStyle(.plain)

                Spacer()
            }

            HStack(spacing: 8) {
                Text(event.timestamp.toString(format: "HH:mm:ss"))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))

                Spacer()

                Text(String(format: "強度：%.2f deg/s", event.rmsValue.isFinite ? event.rmsValue : 0))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isSignalReliable ? .purple : AppTheme.textSecondary(for: colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(isSignalReliable ? Color.purple.opacity(0.10) : AppTheme.textSecondary(for: colorScheme).opacity(0.10))
                    .cornerRadius(7)
            }

            if psdData.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 28))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.6))
                    Text("此事件沒有完整的頻率分析資料")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    Text("需取得事件附近完整的 400 筆感測資料，才能繪製 PSD 柱狀圖。")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                .frame(maxWidth: .infinity, minHeight: 190)
            } else {
                HStack {
                    Spacer()
                    Text("PSD 能量 ((deg/s)²/Hz)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                Chart {
                    RectangleMark(
                        xStart: .value("區段開始", 3.0),
                        xEnd: .value("區段結束", 7.0),
                        yStart: .value("底", 0.0),
                        yEnd: .value("頂", maxPowerDomain)
                    )
                    .foregroundStyle(Color.purple.opacity(0.08))

                    ForEach(psdData) { point in
                        if point.frequencyHz.isFinite && point.power.isFinite && !point.power.isNaN {
                            BarMark(
                                x: .value("頻率", point.frequencyHz),
                                y: .value("PSD 能量", max(0, point.power)),
                                width: .fixed(5)
                            )
                            .foregroundStyle(
                                point.frequencyHz >= 3 && point.frequencyHz <= 7
                                ? Color.purple
                                : Color.purple.opacity(0.28)
                            )
                        }
                    }

                    if let peak = maxPeak, peak.power > 0 {
                        RuleMark(x: .value("主要頻率", peak.frequencyHz))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .foregroundStyle(Color.red)
                            .annotation(position: .top, alignment: .center) {
                                Text(String(format: "%.1f Hz", peak.frequencyHz))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.red)
                                    .cornerRadius(5)
                            }
                    }
                }
                .chartXScale(domain: 0...15)
                .chartYScale(domain: 0...maxPowerDomain)
                .chartXAxis {
                    AxisMarks(values: [0, 3, 5, 7, 10, 15]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                            .foregroundStyle(Color.gray.opacity(0.3))

                        AxisValueLabel {
                            if let frequency = value.as(Int.self) {
                                Text("\(frequency) Hz")
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.gray.opacity(0.25))

                        AxisValueLabel {
                            if let power = value.as(Double.self) {
                                Text(formattedPSDPower(power))
                                    .font(.system(size: 10, design: .rounded))
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            }
                        }
                    }
                }
                .frame(height: 190)

                HStack(spacing: 15) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.purple.opacity(0.3))
                            .frame(width: 12, height: 12)
                        Text("3–7 Hz 典型震顫區")
                    }

                    if maxPeak != nil {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("主要震動頻率")
                        }
                    }
                }
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }
        }
        .padding()
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
    }

    /// 格式化 PSD 能量數值字串
    /// - Parameter value: 能量強度數值
    /// - Returns: 格式化後之字串
    private func formattedPSDPower(_ value: Double) -> String {
        if value == 0 {
            return "0"
        }
        if abs(value) < 0.001 {
            return String(format: "%.1e", value)
        }
        if abs(value) < 0.1 {
            return String(format: "%.3f", value)
        }
        return String(format: "%.2f", value)
    }
}
