import Charts
import PhotosUI
import SwiftUI
import UIKit

struct DataView: View {
    @ObservedObject var loginVM: LoginViewModel
    @ObservedObject var dataVM: DataViewModel = DataViewModel.shared
    @ObservedObject var bleVM: BluetoothViewModel
    @Environment(\.colorScheme) private var colorScheme

    /// 介面模式偏好與各類彈窗控制狀態
    @AppStorage("isSimpleModeEnabled") private var isSimpleMode: Bool = false
    @State private var isChartCleared: Bool = false
    @State private var activeInfoSheet: InfoSheetType? = nil
    @State private var showResearchNoticeSheet: Bool = false

    /// 多媒體照片選擇器、預覽圖片與分頁狀態
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var previewImage: UIImage? = nil
    @State private var currentPageIndex: Int = 0

    /// 事件編輯、情境標籤暫存與輸入焦點狀態
    @State private var showPSDForEventID: UUID? = nil
    @State private var editingEventID: UUID? = nil
    @State private var tempUserTag: String = ""
    @State private var tempSelectedImages: [UIImage] = []
    @FocusState private var isFieldFocused: Bool

    /// 事件儲存流程狀態與錯誤警訊控制
    @State private var savingEventID: UUID? = nil
    @State private var showSaveErrorAlert: Bool = false
    @State private var saveErrorMessage: String = ""

    /// 歷史補填提醒防打擾設定、選單控制與圖表跳轉目標時間
    @AppStorage("tremorReminderSnoozedUntil") private var tremorReminderSnoozedUntil: Double = 0
    @AppStorage("tremorReminderIgnoredBefore") private var tremorReminderIgnoredBefore: Double = 0
    @State private var showReminderOptions: Bool = false
    @State private var chartJumpTargetDate: Date? = nil

    /// 判斷當前篩選日期是否為今天
    private var isViewingToday: Bool {
        Calendar.current.isDateInToday(dataVM.selectedFilterDate)
    }

    /// 判斷目前使用者是否具備照護者身分
    private var isCaregiver: Bool {
        loginVM.userData?.role == 1 || loginVM.boundPartner != nil
    }

    /// 頂部狀態列當前連線或角色狀態文字
    private var currentStatusText: String {
        if isCaregiver { return "Steadyer 家屬" }
        if !bleVM.isConnected { return "裝置未連線" }
        return dataVM.statusText
    }

    /// 標準模式儀表板頻率顯示文字
    private var standardFreqDisplayText: String {
        if isChartCleared { return "--" }
        if let point = dataVM.selectedPoint {
            if let event = dataVM.filteredEvents.first(where: { abs($0.timestamp.timeIntervalSince(point.timestamp)) <= 5.0 }) {
                return String(format: "%.1f Hz", event.dominantFrequency)
            }
            return "--"
        }
        if !isCaregiver && !bleVM.isConnected { return "--" }
        return dataVM.dominantFrequencyText
    }

    /// 標準模式儀表板強度顯示文字
    private var standardRMSDisplayText: String {
        if let selected = dataVM.selectedPoint {
            return String(format: "%.1f", max(0, selected.rmsValue))
        }
        if isChartCleared { return "0.0" }
        if !isCaregiver && !bleVM.isConnected { return "--" }
        let value = dataVM.currentRMS
        guard value.isFinite, !value.isNaN else { return "0.0" }
        return String(format: "%.1f", max(0, value))
    }

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()
                .onTapGesture {
                    isFieldFocused = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        headerView
                        if reminderCandidateCount > 0 { pastUnlabeledAlertBanner }
                        filterAndModeControlBar

                        if isSimpleMode {
                            simpleDashboardCardsView
                            tremorEventsSectionView
                        } else {
                            dashboardCardsView
                            rmsTrendChartView(parentProxy: proxy)
                            tremorEventsSectionView
                        }
                    }
                    .padding(.bottom, 80)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .confirmationDialog("歷史紀錄提醒", isPresented: $showReminderOptions, titleVisibility: .visible) {
            Button("三天內不提醒") {
                tremorReminderSnoozedUntil = Date().addingTimeInterval(3 * 24 * 60 * 60).timeIntervalSince1970
            }
            Button("不再提醒這批紀錄") {
                tremorReminderIgnoredBefore = Date().timeIntervalSince1970
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("你可以暫時關閉提醒，或讓目前已存在的舊紀錄不再重複提醒。之後新產生的未標記事件仍會正常提醒。")
        }
        .alert("儲存失敗", isPresented: $showSaveErrorAlert) {
            Button("確定", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
        .onChange(of: dataVM.selectedFilterDate) { _, _ in
            isChartCleared = false
            dataVM.selectedPoint = nil
            dataVM.expandedEventID = nil
        }
        .onAppear {
            dataVM.bindPipeline(bleVM.pipeline)
            Task { await dataVM.loadTremorHistory() }
        }
        .onDisappear {
            isFieldFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .fullScreenCover(
            item: Binding(
                get: { previewImage.map { ImagePreviewItem(image: $0) } },
                set: { previewImage = $0?.image }
            )
        ) { item in
            imagePreview(image: item.image) { previewImage = nil }.background(BackgroundClearView())
        }
        .fullScreenCover(item: $activeInfoSheet) { sheetType in
            DataInfoOverlayView(type: sheetType, activeInfoSheet: $activeInfoSheet).background(BackgroundClearView())
        }
        .sheet(isPresented: $showResearchNoticeSheet) {
            ResearchNoticeView()
        }
    }

    /// 頂部標題與連線狀態指示列
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text(titleText)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeInfoSheet = .dataAndRules
                        }
                    } label: {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 20))
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 5)

                HStack(spacing: 6) {
                    Circle().fill(statusColor(currentStatusText)).frame(width: 8, height: 8)
                    Text("狀態：\(currentStatusText)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }

            Spacer()

            Button {
                showResearchNoticeSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.shield")
                    Text("使用須知")
                }
                .font(.caption2.weight(.bold))
                .foregroundColor(AppTheme.primary(for: colorScheme))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(AppTheme.primary(for: colorScheme).opacity(0.12))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    /// 根據使用者身分動態產生畫面主標題
    private var titleText: String {
        if isCaregiver { return "\(loginVM.partnerName) 的動作數據" }
        return "即時動作數據"
    }

    /// 計算待補填情境標籤的歷史候選事件數量
    private var reminderCandidateCount: Int {
        let ignoredBefore = Date(timeIntervalSince1970: tremorReminderIgnoredBefore)
        let snoozed = Date().timeIntervalSince1970 < tremorReminderSnoozedUntil
        if snoozed { return 0 }

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current

        return dataVM.tremorEvents.filter { event in
            !calendar.isDateInToday(event.timestamp) && event.timestamp > ignoredBefore && (event.userTag.isEmpty || event.userTag == "未標記")
        }.count
    }

    /// 歷史事件未標記提醒橫幅
    private var pastUnlabeledAlertBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppTheme.accent(for: colorScheme))
                .font(.system(size: 18))

            VStack(alignment: .leading, spacing: 3) {
                Text("歷史紀錄待補填提醒")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                Text("尚有 \(reminderCandidateCount) 筆動作紀錄未填寫情境。補齊後可協助醫師掌握發作規律。")
                    .font(.caption2)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button {
                let ignoredBefore = Date(timeIntervalSince1970: tremorReminderIgnoredBefore)
                var calendar = Calendar.current
                calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current

                let candidates = dataVM.tremorEvents.filter { event in
                    !calendar.isDateInToday(event.timestamp) && event.timestamp > ignoredBefore && (event.userTag.isEmpty || event.userTag == "未標記")
                }

                guard let earliestUnlabeled = candidates.min(by: { $0.timestamp < $1.timestamp }) else { return }

                withAnimation(.easeInOut) {
                    dataVM.selectedFilterDate = earliestUnlabeled.timestamp
                    chartJumpTargetDate = earliestUnlabeled.timestamp
                    dataVM.expandedEventID = earliestUnlabeled.id
                }
            } label: {
                Text("前往補填")
                    .font(.caption2.bold())
                    .foregroundColor(AppTheme.background(for: colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.accent(for: colorScheme))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Button {
                showReminderOptions = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(AppTheme.accent(for: colorScheme).opacity(0.12))
        .cornerRadius(12)
        .padding(.horizontal, 20)
    }

    /// 日期選擇器與簡易/標準模式切換列
    private var filterAndModeControlBar: some View {
        HStack {
            HStack(spacing: 6) {
                DatePicker("", selection: $dataVM.selectedFilterDate, displayedComponents: .date)
                    .labelsHidden()
                    .transformEffect(.init(scaleX: 0.9, y: 0.9))

                if !isViewingToday {
                    Button {
                        withAnimation {
                            dataVM.selectedFilterDate = Date()
                            chartJumpTargetDate = Date()
                        }
                        dataVM.selectedPoint = nil
                        dataVM.expandedEventID = nil
                        isChartCleared = false
                    } label: {
                        Text("回到今天")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(AppTheme.primary(for: colorScheme))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.primary(for: colorScheme).opacity(0.1))
                            .cornerRadius(6)
                    }
                }
            }

            Spacer()

            Toggle(isOn: $isSimpleMode.animation(.spring())) {
                HStack(spacing: 4) {
                    Image(systemName: isSimpleMode ? "eyeglasses" : "chart.xyaxis.line").font(.caption)
                    Text(isSimpleMode ? "簡易模式" : "標準模式").font(.caption).fontWeight(.bold)
                }
                .foregroundColor(isSimpleMode ? .green : AppTheme.textSecondary(for: colorScheme))
            }
            .toggleStyle(SwitchToggleStyle(tint: .green))
            .fixedSize()
        }
        .padding(.horizontal, 20)
    }

    /// 標準模式數據看板卡片（震動頻率與震動強度）
    private var dashboardCardsView: some View {
        HStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("主要震動頻率").font(.caption).foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    Spacer()
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        withAnimation(.easeInOut(duration: 0.2)) { activeInfoSheet = .frequency }
                    } label: {
                        Image(systemName: "questionmark.circle").font(.caption).foregroundColor(AppTheme.primary(for: colorScheme))
                    }
                }
                Text(standardFreqDisplayText)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.primary(for: colorScheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(15)
            .softCardShadow()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("震動強度 (RMS)").font(.caption).foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    Spacer()
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        withAnimation(.easeInOut(duration: 0.2)) { activeInfoSheet = .rms }
                    } label: {
                        Image(systemName: "questionmark.circle").font(.caption).foregroundColor(AppTheme.primary(for: colorScheme))
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(standardRMSDisplayText)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor((!isCaregiver && !bleVM.isConnected) ? AppTheme.textSecondary(for: colorScheme) : AppTheme.textPrimary(for: colorScheme))
                    Text("deg/s").font(.caption).foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(15)
            .softCardShadow()
        }
        .padding(.horizontal, 20)
    }

    /// 簡易模式數據看板卡片（震顫節奏、抖動幅度與狀態摘要）
    private var simpleDashboardCardsView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Text("震顫節奏").font(.system(size: 15, weight: .semibold)).foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        Button {
                            activeInfoSheet = .frequency
                        } label: {
                            Image(systemName: "questionmark.circle.fill").font(.system(size: 17)).foregroundColor(AppTheme.primary(for: colorScheme))
                        }
                        .buttonStyle(.plain)
                    }
                    Text(!isCaregiver && !bleVM.isConnected ? "--" : dataVM.dominantFrequencyText)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.75)
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 112)
                .padding(.horizontal, 8)
                .background(AppTheme.cardBackground(for: colorScheme))
                .cornerRadius(16)
                .softCardShadow()

                VStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Text("抖動幅度").font(.system(size: 15, weight: .semibold)).foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        Button {
                            activeInfoSheet = .rms
                        } label: {
                            Image(systemName: "questionmark.circle.fill").font(.system(size: 17)).foregroundColor(AppTheme.primary(for: colorScheme))
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(!isCaregiver && !bleVM.isConnected ? "--" : String(format: "%.1f", max(0, dataVM.currentRMS)))
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .minimumScaleFactor(0.75)
                            .foregroundColor((!isCaregiver && !bleVM.isConnected) ? AppTheme.textSecondary(for: colorScheme) : (dataVM.currentRMS >= 0.20 ? .orange : AppTheme.textPrimary(for: colorScheme)))
                            .lineLimit(1)
                        Text("deg/s").font(.caption2).foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 112)
                .padding(.horizontal, 8)
                .background(AppTheme.cardBackground(for: colorScheme))
                .cornerRadius(16)
                .softCardShadow()
            }

            HStack(spacing: 10) {
                Circle().fill(simpleStatusColor).frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(simpleStatusTitle).font(.system(size: 16, weight: .bold)).foregroundColor(simpleStatusColor)
                    Text(simpleStatusDescription).font(.caption).foregroundColor(AppTheme.textSecondary(for: colorScheme)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(14)
            .softCardShadow()
        }
        .padding(.horizontal, 20)
    }

    /// 簡易模式狀態摘要標題文字
    private var simpleStatusTitle: String {
        if !isCaregiver && !bleVM.isConnected { return "目前沒有連線" }
        if dataVM.currentRMS >= 0.20 { return "有明顯震顫" }
        return "手部很穩定"
    }

    /// 簡易模式狀態說明文字
    private var simpleStatusDescription: String {
        if !isCaregiver && !bleVM.isConnected { return "連接裝置後，才會繼續顯示即時震動。" }
        if dataVM.currentRMS >= 0.20 { return "系統目前偵測到比較明顯的手部震動。" }
        return "目前沒有偵測到明顯的手部震動。"
    }

    /// 簡易模式狀態指示色彩
    private var simpleStatusColor: Color {
        if !isCaregiver && !bleVM.isConnected { return AppTheme.textSecondary(for: colorScheme) }
        return dataVM.currentRMS >= 0.20 ? .orange : .green
    }

    /// 建構 RMS 走勢圖表容器視圖
    /// - Parameter parentProxy: 外層捲動視圖代理
    /// - Returns: 圖表容器元件
    private func rmsTrendChartView(parentProxy: ScrollViewProxy) -> some View {
        RMSTrendChartViewContainer(
            history: dataVM.rmsTrendHistory,
            lineHistory: dataVM.rmsTrendHistory,
            motorIntervals: dataVM.motorActiveIntervals,
            events: dataVM.filteredEvents,
            selectedDate: dataVM.selectedFilterDate,
            parentProxy: parentProxy,
            isViewingToday: isViewingToday,
            activeInfoSheet: $activeInfoSheet,
            selectedPoint: dataVM.selectedPoint,
            isChartCleared: $isChartCleared,
            jumpTargetDate: $chartJumpTargetDate,
            onEventSelected: { event in
                handleChartEventSelection(event, parentProxy: parentProxy)
            },
            onChartSelectionCleared: {
                dataVM.selectedPoint = nil
                dataVM.expandedEventID = nil
                isChartCleared = true
            },
            onReturnToNow: {
                withAnimation(.easeInOut) {
                    dataVM.selectedFilterDate = Date()
                    chartJumpTargetDate = Date()
                }
                dataVM.selectedPoint = nil
                dataVM.expandedEventID = nil
                isChartCleared = false
            }
        )
    }

    /// 處理圖表中點選事件點後的聯動選擇與卡片捲動跳轉
    /// - Parameters:
    ///   - event: 選取之震顫事件實體
    ///   - parentProxy: 外層捲動視圖代理
    private func handleChartEventSelection(_ event: TremorEvent, parentProxy: ScrollViewProxy) {
        if let trendPoint = dataVM.nearestTrendPoint(to: event.timestamp, tolerance: 1.0) {
            dataVM.selectedPoint = trendPoint
        } else {
            dataVM.selectedPoint = DataViewModel.RMSTrendPoint(
                timestamp: event.timestamp,
                timeLabel: event.timeLabel,
                rmsValue: event.rmsValue,
                isMotorActive: event.isMotorActive,
                rawWindowData: event.rawWindowData
            )
        }

        isChartCleared = false
        dataVM.expandedEventID = event.id

        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.20)) {
                parentProxy.scrollTo(event.id, anchor: .center)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                withAnimation(.easeOut(duration: 0.20)) {
                    parentProxy.scrollTo(event.id, anchor: .top)
                }
            }
        }
    }

    /// 動作分析紀錄分區清單視圖
    private var tremorEventsSectionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.rectangle.portrait.fill").foregroundColor(AppTheme.primary(for: colorScheme))
                let targetPrefix = isCaregiver ? "\(loginVM.partnerName) 的" : ""
                let dateStr = isViewingToday ? "今日" : dataVM.selectedFilterDate.toString(format: "yyyy/MM/dd")
                Text("\(targetPrefix)\(dateStr)動作分析紀錄 (\(dataVM.filteredEvents.count) 筆)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                Spacer()
            }
            .padding(.horizontal, 20)

            if dataVM.filteredEvents.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.green.opacity(0.6))
                    Text(isViewingToday ? "今日尚無分析紀錄" : "該日無動作分析紀錄")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(AppTheme.cardBackground(for: colorScheme))
                .cornerRadius(20)
                .softCardShadow()
                .padding(.horizontal, 20)
            } else {
                eventListView
            }
        }
    }

    /// 依小時分組之震顫事件卡片清單
    private var eventListView: some View {
        let filtered = dataVM.filteredEvents
        let groupedEvents = Dictionary(grouping: filtered) { $0.timestamp.toString(format: "HH:00") }
        let sortedHours = groupedEvents.keys.sorted { $0 > $1 }
        let indexByID = Dictionary(uniqueKeysWithValues: dataVM.tremorEvents.indices.map { (dataVM.tremorEvents[$0].id, $0) })

        return LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(sortedHours, id: \.self) { hourHeader in
                VStack(alignment: .leading, spacing: 8) {
                    Text(hourHeader)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                    ForEach(groupedEvents[hourHeader] ?? []) { event in
                        if let index = indexByID[event.id] {
                            TremorEventCardView(
                                event: $dataVM.tremorEvents[index],
                                dataVM: dataVM,
                                loginVM: loginVM,
                                isSimpleMode: isSimpleMode,
                                editingEventID: $editingEventID,
                                tempUserTag: $tempUserTag,
                                tempSelectedImages: $tempSelectedImages,
                                selectedMediaItems: $selectedMediaItems,
                                currentPageIndex: $currentPageIndex,
                                previewImage: $previewImage,
                                savingEventID: $savingEventID,
                                activeInfoSheet: $activeInfoSheet,
                                showSaveErrorAlert: $showSaveErrorAlert,
                                saveErrorMessage: $saveErrorMessage,
                                isFieldFocused: $isFieldFocused
                            )
                            .id(event.id)
                        }
                    }
                }
            }
        }
    }

    /// 建立照片全螢幕預覽視圖
    /// - Parameters:
    ///   - image: 欲展示之圖片實體
    ///   - onClose: 關閉預覽回呼閉包
    /// - Returns: 照片預覽元件
    private func imagePreview(image: UIImage, onClose: @escaping () -> Void) -> some View {
        ImagePreview(image: image, onClose: onClose)
    }

    /// 依據連線狀態文字判斷指示燈之對應色彩
    /// - Parameter status: 狀態說明文字
    /// - Returns: 對應的 Color 色彩
    private func statusColor(_ status: String) -> Color {
        switch status {
        case "Steadyer 家屬": return AppTheme.primary(for: colorScheme)
        case "資料正常": return .green
        case "資料累積中": return .orange
        case "裝置未連線", "未連線": return AppTheme.textSecondary(for: colorScheme)
        default: return .red
        }
    }
}

/// RMS 震動走勢圖表容器元件，負責手勢縮放、水平捲動平移、事件點顯示與馬達作用區間渲染
private struct RMSTrendChartViewContainer: View {
    /// 走勢歷史、事件清單、馬達時段與選定日期
    let history: [DataViewModel.RMSTrendPoint]
    let lineHistory: [DataViewModel.RMSTrendPoint]
    let motorIntervals: [DataViewModel.MotorActiveInterval]
    let events: [TremorEvent]
    let selectedDate: Date

    /// 外層視圖代理、狀態綁定與事件回呼閉包
    let parentProxy: ScrollViewProxy
    let isViewingToday: Bool
    let activeInfoSheet: Binding<InfoSheetType?>
    let selectedPoint: DataViewModel.RMSTrendPoint?
    @Binding var isChartCleared: Bool
    let jumpTargetDate: Binding<Date?>
    let onEventSelected: (TremorEvent) -> Void
    let onChartSelectionCleared: () -> Void
    let onReturnToNow: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    /// 縮放時長、圖表水平捲動位置與手勢拖曳狀態
    @State private var visibleDuration: TimeInterval = 60
    @State private var zoomBaseDuration: TimeInterval = 60
    @State private var chartScrollPosition: Date = Date()
    @State private var hasInitializedScrollPosition: Bool = false
    @State private var zoomAnchorDate: Date = Date()
    @State private var isPinching: Bool = false
    @State private var dragStartScrollPosition: Date? = nil

    /// 時間跳轉滾輪彈窗狀態與選中時間
    @State private var showTimePicker: Bool = false
    @State private var selectedChartTime: Date = Date()
    @State private var hasSelectedSpecificTime: Bool = false

    /// 圖表中當前選取之事件識別碼與時間戳記
    @State private var chartSelectedEventID: UUID? = nil
    @State private var chartSelectedDate: Date? = nil

    /// 圖表可視時長極限與高度常數
    private let minimumVisibleDuration: TimeInterval = 3
    private let maximumVisibleDuration: TimeInterval = 24 * 60 * 60
    private let chartHeight: CGFloat = 285

    /// 台北時區日曆實體
    private var taipeiCalendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        return calendar
    }

    /// 當日零時起始時間
    private var dayStart: Date {
        taipeiCalendar.startOfDay(for: selectedDate)
    }

    /// 當日結束時間點（今日為當前時間，非今日為隔日零時）
    private var dayEnd: Date {
        let tomorrow = taipeiCalendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
        return isViewingToday ? min(tomorrow, Date()) : tomorrow
    }

    /// 當日最後一個有效秒數時間點
    private var dayLastSecond: Date {
        isViewingToday ? Date() : dayEnd.addingTimeInterval(-1)
    }

    /// 夾擠限制後之可視時長
    private var clampedVisibleDuration: TimeInterval {
        min(max(visibleDuration, minimumVisibleDuration), maximumVisibleDuration)
    }

    /// 圖表左側起點允許之最大時間
    private var maxLeadingDate: Date {
        max(dayStart, dayEnd.addingTimeInterval(-clampedVisibleDuration))
    }

    /// 限制在邊界內的圖表水平捲動起始位置
    private var clampedChartScrollPosition: Date {
        min(max(chartScrollPosition, dayStart), maxLeadingDate)
    }

    /// 圖表可視範圍的結束時間
    private var visibleEndDate: Date {
        let calculatedEnd = clampedChartScrollPosition.addingTimeInterval(clampedVisibleDuration)
        return min(calculatedEnd, dayEnd)
    }

    /// 涵蓋前後緩衝區之資料擷取時段區間
    private var bufferedRange: (start: Date, end: Date) {
        let buffer = max(clampedVisibleDuration * 1.5, 5)
        return (clampedChartScrollPosition.addingTimeInterval(-buffer), visibleEndDate.addingTimeInterval(buffer))
    }

    /// 依時間區間利用二分搜尋擷取走勢資料切片
    /// - Parameters:
    ///   - points: 原始資料點陣列
    ///   - start: 區間起始時間
    ///   - end: 區間結束時間
    /// - Returns: 切片後之資料點陣列
    private func trendSlice(_ points: [DataViewModel.RMSTrendPoint], start: Date, end: Date) -> [DataViewModel.RMSTrendPoint] {
        guard !points.isEmpty else { return [] }
        var low = 0, high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].timestamp < start { low = mid + 1 } else { high = mid }
        }
        let lower = low

        low = lower
        high = points.count
        while low < high {
            let mid = (low + high) / 2
            if points[mid].timestamp <= end { low = mid + 1 } else { high = mid }
        }
        let upper = low

        guard lower < upper else { return [] }
        return Array(points[lower..<upper])
    }

    /// 針對資料量過大的走勢資料進行極值降採樣
    /// - Parameters:
    ///   - points: 原始資料點陣列
    ///   - maxCount: 允許之最大取樣點數
    /// - Returns: 降採樣後之資料點陣列
    private func downsampleTrend(_ points: [DataViewModel.RMSTrendPoint], maxCount: Int = 1200) -> [DataViewModel.RMSTrendPoint] {
        guard points.count > maxCount, maxCount >= 4 else { return points }
        let bucketCount = max(1, maxCount / 2)
        let bucketSize = Int(ceil(Double(points.count) / Double(bucketCount)))
        var result: [DataViewModel.RMSTrendPoint] = []
        result.reserveCapacity(maxCount)

        var startIndex = 0
        while startIndex < points.count {
            let endIndex = min(startIndex + bucketSize, points.count)
            let bucket = points[startIndex..<endIndex]
            guard let minPoint = bucket.min(by: { $0.rmsValue < $1.rmsValue }),
                  let maxPoint = bucket.max(by: { $0.rmsValue < $1.rmsValue }) else {
                startIndex = endIndex
                continue
            }
            if minPoint.timestamp <= maxPoint.timestamp {
                result.append(minPoint)
                if minPoint.id != maxPoint.id { result.append(maxPoint) }
            } else {
                result.append(maxPoint)
                if minPoint.id != maxPoint.id { result.append(minPoint) }
            }
            startIndex = endIndex
        }
        return result
    }

    /// 經緩衝時段過濾之事件清單
    private var bufferedEvents: [TremorEvent] {
        let range = bufferedRange
        return events.filter { $0.timestamp >= range.start && $0.timestamp <= range.end }
    }

    /// 依數量上限過濾之代表性事件點陣列
    private var chartEvents: [TremorEvent] {
        let source = bufferedEvents
        let maxCount = 800
        guard source.count > maxCount else { return source }

        let bucketSize = Int(ceil(Double(source.count) / Double(maxCount)))
        var result: [TremorEvent] = []
        result.reserveCapacity(maxCount)

        var index = 0
        while index < source.count {
            let end = min(index + bucketSize, source.count)
            if let strongest = source[index..<end].max(by: { $0.rmsValue < $1.rmsValue }) {
                result.append(strongest)
            }
            index = end
        }
        return result
    }

    /// 經緩衝時段過濾之馬達啟動區間陣列
    private var bufferedMotorIntervals: [DataViewModel.MotorActiveInterval] {
        let range = bufferedRange
        return motorIntervals.filter { $0.end >= range.start && $0.start <= range.end }
    }

    /// 圖表折線繪製使用之降採樣資料點陣列
    private var chartLineHistory: [DataViewModel.RMSTrendPoint] {
        let range = bufferedRange
        let sliced = trendSlice(lineHistory, start: range.start, end: range.end)
        let valid = sliced.filter { $0.rmsValue.isFinite && !$0.rmsValue.isNaN }
        return downsampleTrend(valid)
    }

    /// 依據可視時長動態計算 X 軸刻度步進間隔秒數
    private var xAxisStride: TimeInterval {
        switch clampedVisibleDuration {
        case ...6: return 1
        case ...15: return 2
        case ...30: return 5
        case ...60: return 10
        case ...120: return 20
        case ...300: return 60
        case ...600: return 120
        case ...1800: return 300
        case ...3600: return 600
        case ...7200: return 1200
        case ...21600: return 3600
        case ...43200: return 7200
        default: return 14400
        }
    }

    /// 計算目前可視範圍內所有 X 軸時間刻度
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
            if date >= dayStart && date <= dayEnd { ticks.append(date) }
            current += step
        }
        return ticks
    }

    /// 格式化指定時間在 X 軸上之文字呈現
    /// - Parameter date: 刻度日期時間
    /// - Returns: 時間字串
    private func xAxisLabel(for date: Date) -> String {
        switch clampedVisibleDuration {
        case ...120: return "\(taipeiCalendar.component(.second, from: date))s"
        case ...3600: return "\(taipeiCalendar.component(.minute, from: date))m"
        default: return "\(taipeiCalendar.component(.hour, from: date))h"
        }
    }

    /// 圖表可視範圍中央對應的時間戳記
    private var visibleHeaderTime: Date {
        let center = clampedChartScrollPosition.addingTimeInterval(clampedVisibleDuration * 0.5)
        return min(max(center, dayStart), dayLastSecond)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            chartHeaderView

            if history.isEmpty && events.isEmpty {
                emptyChartView
            } else {
                HStack {
                    Spacer()
                    Text("deg/s")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .padding(.trailing, 2)
                }
                .padding(.bottom, -2)

                mainChartArea
                chartFooterLegendView
            }
        }
        .padding()
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(20)
        .padding(.horizontal, 20)
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)
        .sheet(isPresented: $showTimePicker) {
            timePickerNavigationStack
        }
        .onAppear {
            initializeScrollPositionIfNeeded()
        }
        .onChange(of: selectedDate) { _, _ in
            hasInitializedScrollPosition = false
            hasSelectedSpecificTime = false
            chartSelectedDate = nil
            clearChartSelection()
            initializeScrollPositionIfNeeded()
        }
        .onChange(of: history.last?.timestamp) { _, _ in
            guard isViewingToday, !hasSelectedSpecificTime else { return }
            moveToDate(Date(), animated: false)
        }
        .onChange(of: jumpTargetDate.wrappedValue) { _, newDate in
            guard let newDate else { return }
            clearChartSelection()
            moveToDate(newDate, animated: true)
            DispatchQueue.main.async { jumpTargetDate.wrappedValue = nil }
        }
    }

    /// 圖表時間選擇彈窗導覽頁面
    private var timePickerNavigationStack: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("選擇圖表時間")
                    .font(.headline)
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                DatePicker(
                    "時間",
                    selection: $selectedChartTime,
                    in: dayStart...dayLastSecond,
                    displayedComponents: [.hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()

                Text(selectedChartTime.toString(format: "yyyy/MM/dd HH:mm"))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                if isViewingToday {
                    Button {
                        hasSelectedSpecificTime = false
                        selectedChartTime = Date()
                        clearChartSelection()
                        isChartCleared = false
                        onReturnToNow()
                        showTimePicker = false
                        DispatchQueue.main.async { moveToDate(Date(), animated: false) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                            Text("回到現在")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(AppTheme.primary(for: colorScheme).opacity(0.10))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                }
                Spacer()
            }
            .padding()
            .background(AppTheme.background(for: colorScheme))
            .navigationTitle("查看時間")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showTimePicker = false }
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("前往") {
                        hasSelectedSpecificTime = true
                        clearChartSelection()
                        let safeTime = min(max(selectedChartTime, dayStart), dayLastSecond)
                        selectedChartTime = safeTime
                        moveToDate(safeTime, animated: true)
                        showTimePicker = false
                    }
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.primary(for: colorScheme))
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// 圖表核心繪圖畫布，繪製馬達區間、RMS 折線與事件點
    @ViewBuilder
    private var mainChartArea: some View {
        let linePoints = chartLineHistory
        let visibleEvents = chartEvents
        let hMaximum = linePoints.map(\.rmsValue).filter { $0.isFinite && !$0.isNaN }.max() ?? 0
        let eMaximum = visibleEvents.map(\.rmsValue).filter { $0.isFinite && !$0.isNaN }.max() ?? 0
        let currentMaxY = max(0.5, max(hMaximum, eMaximum) * 1.15)
        let safeXAxisTicks = self.visibleXAxisTicks

        GeometryReader { geometry in
            Chart {
                ForEach(bufferedMotorIntervals) { interval in
                    let visibleStart = max(interval.start, clampedChartScrollPosition)
                    let visibleEnd = min(interval.end, visibleEndDate)

                    if visibleEnd > visibleStart {
                        RectangleMark(
                            xStart: .value("馬達開始", visibleStart),
                            xEnd: .value("馬達結束", visibleEnd),
                            yStart: .value("底", 0.0),
                            yEnd: .value("頂", currentMaxY)
                        )
                        .foregroundStyle(Color.orange.opacity(0.18))
                    }
                }

                ForEach(linePoints) { point in
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

                ForEach(visibleEvents) { event in
                    let isSelected = (event.id == chartSelectedEventID)
                    PointMark(
                        x: .value("事件時間", event.timestamp),
                        y: .value("事件強度", max(0, event.rmsValue))
                    )
                    .foregroundStyle(isSelected ? Color.red : Color.orange)
                    .symbolSize(isSelected ? 90 : 38)
                }
            }
            .chartXScale(domain: clampedChartScrollPosition...visibleEndDate)
            .chartYScale(domain: 0.0...currentMaxY)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(Color.gray.opacity(0.3))

                    if let doubleVal = value.as(Double.self) {
                        AxisValueLabel {
                            Text(String(format: "%.1f", doubleVal))
                                .font(.system(size: 11, design: .rounded))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom, values: safeXAxisTicks) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(Color.gray.opacity(0.3))

                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(xAxisLabel(for: date))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
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
                        guard let date = proxy.value(atX: location.x, as: Date.self),
                              let value = proxy.value(atY: location.y, as: Double.self) else { return }
                        handleChartTap(at: date, yValue: value)
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

    /// 圖表上方標題與時間選擇按鈕列
    private var chartHeaderView: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(AppTheme.primary(for: colorScheme))

                Text("\(visibleHeaderTime.toString(format: "HH:mm")) 震動強度走勢")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Button {
                    activeInfoSheet.wrappedValue = .chart
                } label: {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(AppTheme.primary(for: colorScheme).opacity(0.8))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 4)

            Button {
                selectedChartTime = min(max(visibleHeaderTime, dayStart), dayLastSecond)
                showTimePicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
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
    }

    /// 無走勢資料時的空白佔位視圖
    private var emptyChartView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 30))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.6))

            Text("\(selectedDate.toString(format: "MM/dd")) 尚無走勢資料")
                .font(.subheadline)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))

            Text("選擇時間後，可查看該時段的震動資料")
                .font(.caption2)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
        }
        .frame(maxWidth: .infinity, minHeight: chartHeight)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(15)
    }

    /// 初次載入時初始化圖表捲動位置至適當時點
    private func initializeScrollPositionIfNeeded() {
        guard !hasInitializedScrollPosition else { return }
        hasInitializedScrollPosition = true

        if let jumpDate = jumpTargetDate.wrappedValue {
            moveToDate(jumpDate, animated: false)
            DispatchQueue.main.async { jumpTargetDate.wrappedValue = nil }
        } else if isViewingToday {
            moveToDate(Date(), animated: false)
        } else if let latest = history.last?.timestamp {
            moveToDate(latest, animated: false)
        } else {
            moveToDate(dayStart, animated: false)
        }
    }

    /// 平移圖表視野至指定目標時間點
    /// - Parameters:
    ///   - target: 目標時間
    ///   - animated: 是否包含平活動畫
    private func moveToDate(_ target: Date, animated: Bool) {
        let safeTarget = min(max(target, dayStart), dayEnd)
        let maxLeading = max(dayStart, dayEnd.addingTimeInterval(-clampedVisibleDuration))
        let isTargetNow = isViewingToday && safeTarget >= Date().addingTimeInterval(-10)
        let multiplier: TimeInterval = isTargetNow ? 1.0 : 0.5
        let leading = safeTarget.addingTimeInterval(-clampedVisibleDuration * multiplier)
        let clampedLeading = min(max(leading, dayStart), maxLeading)

        if animated {
            withAnimation(.easeInOut(duration: 0.25)) { chartScrollPosition = clampedLeading }
        } else {
            chartScrollPosition = clampedLeading
        }
    }

    /// 限制圖表水平捲動位置保持在當日合法時段之內
    private func keepScrollPositionInsideDay() {
        let maxLeading = max(dayStart, dayEnd.addingTimeInterval(-clampedVisibleDuration))
        chartScrollPosition = min(max(chartScrollPosition, dayStart), maxLeading)
    }

    /// 清除圖表中當前選取之事件點狀態
    private func clearChartSelection() {
        chartSelectedEventID = nil
        chartSelectedDate = nil
    }

    /// 處理使用者於圖表上的單擊點擊，判定是否選中鄰近事件點
    /// - Parameters:
    ///   - tappedDate: 點擊處 X 軸對應之時間
    ///   - yValue: 點擊處 Y 軸數值
    private func handleChartTap(at tappedDate: Date, yValue _: Double) {
        let xTolerance = dynamicHitTolerance

        guard let nearestEvent = chartEvents.min(by: {
            abs($0.timestamp.timeIntervalSince(tappedDate)) < abs($1.timestamp.timeIntervalSince(tappedDate))
        }),
        abs(nearestEvent.timestamp.timeIntervalSince(tappedDate)) <= xTolerance else {
            clearChartSelection()
            onChartSelectionCleared()
            return
        }

        chartSelectedEventID = nearestEvent.id
        chartSelectedDate = nearestEvent.timestamp
        onEventSelected(nearestEvent)
    }

    /// 依據當前縮放等級動態計算點擊容許的時間誤差範圍秒數
    private var dynamicHitTolerance: TimeInterval {
        switch clampedVisibleDuration {
        case ...10: return 1.5
        case ...30: return 4.0
        case ...60: return 7.0
        case ...120: return 12.0
        case ...300: return 18.0
        case ...600: return 30.0
        case ...1800: return 45.0
        case ...3600: return 90.0
        default: return 180.0
        }
    }

    /// 圖表底部圖例說明列
    private var chartFooterLegendView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle().fill(Color.orange).frame(width: 7, height: 7)
                    Text("動作分析紀錄(點擊跳轉)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.orange.opacity(0.3)).frame(width: 9, height: 9)
                    Text("馬達命令作用區間")
                        .font(.caption2)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }

                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                    Text("目前選取")
                        .font(.caption2)
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }
        }
    }
}
