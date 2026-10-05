import Combine
import Foundation
import UIKit

@MainActor
final class DataViewModel: ObservableObject {
    static let shared = DataViewModel()
    let analyzer = TremorAnalyzer()
    private let repository: TremorRepositoryProtocol
    private var isPipelineBound = false

    /// 採樣參數、上傳批次限制、時區與日曆設定
    private let rawSampleInterval: TimeInterval = 0.01
    private let uploadBatchThreshold = 400
    private let trendUploadBatchSize = 20
    private let analysisRecordSaveInterval: TimeInterval = 3.0
    private let taipeiTimeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
    private let calendar: Calendar = {
        var c = Calendar.current
        c.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        return c
    }()
    let activityOptions = ["休息", "吃飯", "喝水", "寫字", "走路", "服藥後"]

    /// 量測會話識別碼、事件對應表、資料暫存緩衝區與冷卻計時器
    var currentSessionId: String = UUID().uuidString {
        didSet {
            if oldValue != currentSessionId {
                if !rawUploadBuffer.isEmpty {
                    flushRawUploadBuffer(forSession: oldValue)
                }
                if !trendUploadBuffer.isEmpty {
                    flushTrendUploadBuffer()
                }
            }
        }
    }
    private var eventSessionMap: [UUID: String] = [:]
    private var rawUploadBuffer: [TremorDataPoint] = []
    private var trendUploadBuffer: [TremorTrendPointDTO] = []
    private var lastAnalysisRecordTime: Date?

    /// 歷史資料載入控制旗標、當前請求標記與分析歷史快取狀態
    @Published private(set) var isHistoryLoading: Bool = false
    private var loadedHistoryDay: Date?
    private var loadingHistoryDay: Date?
    private var activeHistoryRequestID: UUID?
    private var analysisHistoryCache: [TremorAnalysisRecordDTO]?
    private var analysisHistoryCacheFetchedAt: Date?
    private let analysisHistoryCacheTTL: TimeInterval = 60

    /// 儀表板即時數據、連線狀態提示與最後震顫時間文字
    @Published var dominantFrequencyText: String = "--"
    @Published var tremorStrengthText: String = "0.00"
    @Published var statusText: String = "資料正常"
    @Published var lastVibrationDate: String = "--"
    @Published var lastVibrationTime: String = "--:--"

    /// 震顫走勢數據、馬達運轉時段與使用者選定檢視點
    @Published var rmsTrendHistory: [RMSTrendPoint] = []
    @Published var motorActiveIntervals: [MotorActiveInterval] = []
    @Published var selectedPoint: RMSTrendPoint? {
        didSet {
            updateDashboard()
        }
    }

    /// 活動情境標籤、分析事件清單、展開檢視項目與歷史篩選日期
    @Published var selectedActivityTag: String = "未標記"
    @Published var tremorEvents: [TremorEvent] = []
    @Published var expandedEventID: UUID? = nil
    @Published var selectedFilterDate: Date = Date() {
        didSet {
            guard !calendar.isDate(oldValue, inSameDayAs: selectedFilterDate) else {
                return
            }
            let date = selectedFilterDate
            selectedPoint = nil
            expandedEventID = nil
            Task { [weak self] in
                await self?.loadTremorHistory(for: date)
            }
        }
    }

    /// 初始化震顫資料檢視模型並注入儲存庫實體
    /// - Parameter repository: 符合 TremorRepositoryProtocol 之儲存庫實體
    init(repository: TremorRepositoryProtocol? = nil) {
        if let repository {
            self.repository = repository
        } else {
            self.repository = TremorRepository(tokenProvider: {
                AuthManager.shared.getToken()
            })
        }
    }

    /// RMS 連續震顫強度走勢資料點模型
    struct RMSTrendPoint: Identifiable {
        /// 資料點唯一識別碼
        let id = UUID()
        /// 資料取樣時間戳記
        let timestamp: Date
        /// 格式化時間文字標籤
        let timeLabel: String
        /// 該時間點計算之震顫強度均方根值（RMS）
        let rmsValue: Double
        /// 該取樣視窗內抑震馬達是否處於運轉介入狀態
        let isMotorActive: Bool
        /// 用於計算此走勢點之原始感測訊號資料視窗
        let rawWindowData: [TremorDataPoint]
        /// 使用者自訂之情境活動標籤
        var userTag: String = ""
        /// 附加之現場觀察照片影像清單
        var selectedImages: [UIImage] = []
        /// 標記此資料點是否已持久化儲存至伺服器
        var isSaved: Bool = false
    }

    /// 由原始取樣資料重建的實際馬達啟動區間模型
    struct MotorActiveInterval: Identifiable {
        /// 區間唯一識別碼
        let id: UUID
        /// 馬達運轉起始時間戳記
        let start: Date
        /// 馬達運轉結束時間戳記
        let end: Date

        /// 初始化馬達啟動時段區間
        /// - Parameters:
        ///   - id: 區間唯一識別碼，預設為全新 UUID
        ///   - start: 區間開始時間
        ///   - end: 區間結束時間
        init(id: UUID = UUID(), start: Date, end: Date) {
            self.id = id
            self.start = start
            self.end = end
        }
    }

    /// 功率譜密度（PSD）頻譜能量資料點模型
    struct PSDPoint: Identifiable {
        /// 頻率點唯一識別碼
        let id = UUID()
        /// 頻率數值（單位：Hz）
        let frequencyHz: Double
        /// 該頻率下三軸疊加之能量強度
        let power: Double
    }

    /// 當前有效之即時或使用者選定點之 RMS 震顫強度數值
    var currentRMS: Double {
        if let selectedPoint {
            return selectedPoint.rmsValue
        }
        return rmsTrendHistory.last?.rmsValue ?? (Double(tremorStrengthText) ?? 0.0)
    }

    /// 篩選出符合目前選定日期之震顫事件紀錄清單
    var filteredEvents: [TremorEvent] {
        let start = calendar.startOfDay(for: selectedFilterDate)
        let end = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(24 * 60 * 60)
        return tremorEvents.filter {
            $0.timestamp >= start && $0.timestamp < end
        }
    }

    /// 統計非今日且未完成情境標籤標記之歷史事件數量
    var pastUnlabeledCount: Int {
        tremorEvents.filter { event in
            !calendar.isDateInToday(event.timestamp) &&
            (event.userTag.isEmpty || event.userTag == "未標記")
        }.count
    }

    /// 依據走勢資料動態計算圖表 Y 軸適當之最大安全刻度值
    /// - Parameter history: 欲分析之 RMS 資料點陣列
    /// - Returns: 圖表 Y 軸適當之最大顯示範圍數值
    func calculateSafeMaxY(from history: [RMSTrendPoint]) -> Double {
        let values = history.map(\.rmsValue).filter { $0.isFinite && !$0.isNaN }
        return max(0.5, (values.max() ?? 0.5) * 1.2)
    }

    /// 取得圖表繪製使用之有效 RMS 走勢資料
    /// - Returns: 數值合法之走勢點陣列
    func mergedRMSChartHistory() -> [RMSTrendPoint] {
        rmsTrendHistory.filter {
            $0.rmsValue.isFinite && !$0.rmsValue.isNaN
        }
    }

    /// 以二分搜尋取得事件前後指定秒數範圍之 RMS 走勢區間
    /// - Parameters:
    ///   - targetDate: 目標事件時間基準
    ///   - seconds: 前後擴展之秒數
    /// - Returns: 截取後之走勢資料點陣列
    func rmsChartHistory(
        surrounding targetDate: Date,
        seconds: TimeInterval = 3
    ) -> [RMSTrendPoint] {
        guard !rmsTrendHistory.isEmpty else { return [] }

        let startDate = targetDate.addingTimeInterval(-seconds)
        let endDate = targetDate.addingTimeInterval(seconds)

        var lower = lowerBoundTrendIndex(for: startDate)
        var upper = upperBoundTrendIndex(for: endDate)

        if lower > 0 {
            lower -= 1
        }
        if upper < rmsTrendHistory.count {
            upper += 1
        }

        guard lower < upper else {
            if let nearest = nearestTrendPoint(to: targetDate, tolerance: seconds + 1) {
                return [nearest]
            }
            return []
        }

        return Array(rmsTrendHistory[lower..<upper]).filter {
            $0.rmsValue.isFinite && !$0.rmsValue.isNaN
        }
    }

    /// 取得指定時間在容許誤差範圍內最接近的走勢點
    /// - Parameters:
    ///   - targetDate: 目標比對時間
    ///   - tolerance: 容許之最大時間誤差秒數
    /// - Returns: 符合條件的最接近走勢點，若超出容許範圍則回傳 nil
    func nearestTrendPoint(
        to targetDate: Date,
        tolerance: TimeInterval = 1.0
    ) -> RMSTrendPoint? {
        guard !rmsTrendHistory.isEmpty else { return nil }

        let index = lowerBoundTrendIndex(for: targetDate)
        var candidates: [RMSTrendPoint] = []

        if index < rmsTrendHistory.count {
            candidates.append(rmsTrendHistory[index])
        }
        if index > 0 {
            candidates.append(rmsTrendHistory[index - 1])
        }

        guard let nearest = candidates.min(by: {
            abs($0.timestamp.timeIntervalSince(targetDate)) <
            abs($1.timestamp.timeIntervalSince(targetDate))
        }) else {
            return nil
        }

        return abs(nearest.timestamp.timeIntervalSince(targetDate)) <= tolerance ? nearest : nil
    }

    /// 二分搜尋大於或等於指定目標時間的第一個走勢點索引
    /// - Parameter targetDate: 搜尋目標時間
    /// - Returns: 走勢點陣列之索引值
    private func lowerBoundTrendIndex(for targetDate: Date) -> Int {
        var low = 0
        var high = rmsTrendHistory.count
        while low < high {
            let mid = (low + high) / 2
            if rmsTrendHistory[mid].timestamp < targetDate {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    /// 二分搜尋大於指定目標時間的第一個走勢點索引
    /// - Parameter targetDate: 搜尋目標時間
    /// - Returns: 走勢點陣列之索引值
    private func upperBoundTrendIndex(for targetDate: Date) -> Int {
        var low = 0
        var high = rmsTrendHistory.count
        while low < high {
            let mid = (low + high) / 2
            if rmsTrendHistory[mid].timestamp <= targetDate {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    /// 依照半秒時間桶排除過度密集之重複圖表折線節點
    /// - Parameter points: 待處理之走勢點陣列
    /// - Returns: 去除重複節點後之走勢點陣列
    private func deduplicateChartPoints(
        _ points: [RMSTrendPoint]
    ) -> [RMSTrendPoint] {
        var result: [RMSTrendPoint] = []
        result.reserveCapacity(points.count)

        var seenBuckets = Set<Int64>()
        seenBuckets.reserveCapacity(points.count)

        for point in points {
            let bucket = Int64(
                (point.timestamp.timeIntervalSince1970 * 2).rounded(.toNearestOrAwayFromZero)
            )
            if seenBuckets.insert(bucket).inserted {
                result.append(point)
            }
        }
        return result
    }

    /// 從遠端伺服器載入歷史震顫分析紀錄並整合畫面狀態
    /// - Parameter matchedHistory: 可供比對之本機 RMS 走勢快取陣列（預設為空）
    func loadAnalysisEvents(matchedHistory _: [RMSTrendPoint] = []) async {
        do {
            let records = try await repository.fetchAnalysisHistory()
            applyAnalysisRecords(records)
        } catch {
            AppLog.error("載入分析紀錄失敗: \(error.localizedDescription)")
            tremorEvents = []
            lastVibrationDate = "--"
            lastVibrationTime = "--:--"
        }
    }

    /// 將伺服器端取得之分析紀錄轉換為本地事件模型並保留未同步之即時事件
    /// - Parameter records: 伺服器傳回之分析紀錄 DTO 陣列
    private func applyAnalysisRecords(_ records: [TremorAnalysisRecordDTO]) {
        let existingEventByID = Dictionary(
            uniqueKeysWithValues: tremorEvents.map { ($0.id, $0) }
        )

        var seenIDs = Set<UUID>()
        var analysisRecords: [TremorEvent] = []
        analysisRecords.reserveCapacity(records.count)

        for record in records.sorted(by: { $0.recordedAt > $1.recordedAt }) {
            guard record.dataValid else { continue }
            guard seenIDs.insert(record.id).inserted else { continue }

            eventSessionMap[record.id] = record.sessionId

            let date = record.recordedAt
            let rawTag = record.activityTag.trimmingCharacters(in: .whitespacesAndNewlines)
            let tag = rawTag.isEmpty ? "未標記" : rawTag
            let existingEvent = existingEventByID[record.id]

            analysisRecords.append(
                TremorEvent(
                    id: record.id,
                    timestamp: date,
                    timeLabel: date.toString(format: "yyyy-MM-dd HH:mm:ss"),
                    rmsValue: record.tremorStrengthRmsDps ?? 0.0,
                    dominantFrequency: record.frequencyReliable
                        ? (record.dominantFrequencyHz ?? 0.0)
                        : 0.0,
                    rawWindowData: existingEvent?.rawWindowData ?? [],
                    isMotorActive: record.motorOnFraction > 0.0,
                    motorOnFraction: record.motorOnFraction,
                    userTag: tag,
                    selectedImages: existingEvent?.selectedImages ?? [],
                    isSaved: true
                )
            )
        }

        let serverIDs = Set(analysisRecords.map(\.id))
        let pendingLiveEvents = tremorEvents.filter {
            !serverIDs.contains($0.id) && calendar.isDateInToday($0.timestamp)
        }

        tremorEvents = (pendingLiveEvents + analysisRecords).sorted { $0.timestamp > $1.timestamp }

        if let latest = tremorEvents.first(where: { $0.dominantFrequency > 0 }) {
            lastVibrationDate = latest.timestamp.toString(format: "MM/dd")
            lastVibrationTime = latest.timestamp.toString(format: "HH:mm")
        } else {
            lastVibrationDate = "--"
            lastVibrationTime = "--:--"
        }
    }

    /// 安全取得分析紀錄快取或向伺服器拉取最新資料
    /// - Parameter force: 是否強制略過快取重新自網路讀取
    /// - Returns: 分析紀錄 DTO 陣列，失敗則回傳現存快取
    private func fetchAnalysisRecordsSafely(
        force: Bool = false
    ) async -> [TremorAnalysisRecordDTO]? {
        if !force,
           let cache = analysisHistoryCache,
           let fetchedAt = analysisHistoryCacheFetchedAt,
           Date().timeIntervalSince(fetchedAt) < analysisHistoryCacheTTL {
            return cache
        }

        do {
            let records = try await repository.fetchAnalysisHistory()
            analysisHistoryCache = records
            analysisHistoryCacheFetchedAt = Date()
            return records
        } catch {
            AppLog.error("載入分析紀錄失敗: \(error.localizedDescription)")
            return analysisHistoryCache
        }
    }

    /// 取得指定日期的伺服器端 RMS 走勢歷史紀錄
    /// - Parameter date: 查詢目標日期
    /// - Returns: 走勢點 DTO 陣列，失敗時回傳 nil
    private func fetchSavedTrendHistory(
        for date: Date
    ) async -> [TremorTrendPointDTO]? {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
            ?? startOfDay.addingTimeInterval(24 * 60 * 60)

        do {
            return try await repository.fetchTrendHistory(
                from: startOfDay,
                to: endOfDay
            )
        } catch {
            AppLog.error("載入 RMS Trend 失敗: \(error.localizedDescription)")
            return nil
        }
    }

    /// 將伺服器端走勢點資料與馬達啟動時段套用至畫面模型中
    /// - Parameters:
    ///   - serverPoints: 伺服器傳回之走勢點 DTO 陣列
    ///   - date: 目標日期
    private func applyTrendPoints(
        _ serverPoints: [TremorTrendPointDTO],
        for date: Date
    ) {
        let sortedServerPoints = serverPoints.filter {
            $0.dataValid &&
            $0.rmsValue.isFinite &&
            !$0.rmsValue.isNaN
        }

        let mappedServerPoints = sortedServerPoints.map { point in
            RMSTrendPoint(
                timestamp: point.recordedAt,
                timeLabel: point.recordedAt.toString(format: "HH:mm:ss"),
                rmsValue: point.rmsValue,
                isMotorActive: point.motorOnFraction > 0,
                rawWindowData: []
            )
        }

        let latestServerTime = mappedServerPoints.last?.timestamp ?? .distantPast

        let pendingLivePoints: [RMSTrendPoint]
        if calendar.isDateInToday(date) {
            pendingLivePoints = rmsTrendHistory.filter {
                calendar.isDate($0.timestamp, inSameDayAs: date) &&
                $0.timestamp > latestServerTime
            }
        } else {
            pendingLivePoints = []
        }

        rmsTrendHistory = mappedServerPoints + pendingLivePoints

        var intervals: [MotorActiveInterval] = []
        intervals.reserveCapacity(sortedServerPoints.count / 4)

        var activeStart: Date?
        var activeEnd: Date?

        func finishInterval() {
            guard let start = activeStart, let end = activeEnd else {
                activeStart = nil
                activeEnd = nil
                return
            }
            intervals.append(
                MotorActiveInterval(start: start, end: end)
            )
            activeStart = nil
            activeEnd = nil
        }

        for point in sortedServerPoints {
            guard point.motorOnFraction > 0 else {
                finishInterval()
                continue
            }

            let start = point.recordedAt.addingTimeInterval(-0.5)
            let end = point.recordedAt

            if let currentEnd = activeEnd,
               start.timeIntervalSince(currentEnd) <= 0.05 {
                activeEnd = max(currentEnd, end)
            } else {
                finishInterval()
                activeStart = start
                activeEnd = end
            }
        }
        finishInterval()

        if calendar.isDateInToday(date) {
            let pendingMotorIntervals = pendingLivePoints.compactMap { point -> MotorActiveInterval? in
                guard point.isMotorActive else { return nil }
                return MotorActiveInterval(
                    start: point.timestamp.addingTimeInterval(-0.5),
                    end: point.timestamp
                )
            }
            motorActiveIntervals = mergeMotorIntervals(
                intervals + pendingMotorIntervals
            )
        } else {
            motorActiveIntervals = intervals
        }

        selectedPoint = nil
        updateDashboard()
    }

    /// 從遠端伺服器載入指定篩選日期的 RMS 走勢紀錄並更新畫面
    func loadRawDataTrend() async {
        let date = selectedFilterDate

        guard let points = await fetchSavedTrendHistory(for: date) else {
            return
        }

        guard calendar.isDate(
            date,
            inSameDayAs: selectedFilterDate
        ) else {
            return
        }

        applyTrendPoints(points, for: date)
    }

    /// 將歷史原始採樣點合併為連續的馬達運轉作用區間
    /// - Parameter points: 帶有時間戳記之原始感測資料點陣列
    /// - Returns: 合併解析後之馬達運轉時段區間陣列
    private func buildMotorActiveIntervals(
        from points: [TremorTimedRawPoint]
    ) -> [MotorActiveInterval] {
        let sortedPoints = points.sorted { $0.timestamp < $1.timestamp }
        guard !sortedPoints.isEmpty else { return [] }

        let sampleDuration: TimeInterval = rawSampleInterval
        let maximumContinuousGap: TimeInterval = max(rawSampleInterval * 5, 0.05)

        var intervals: [MotorActiveInterval] = []
        var activeStart: Date?
        var lastActiveDate: Date?

        func finishCurrentInterval() {
            guard let start = activeStart,
                  let last = lastActiveDate else {
                activeStart = nil
                lastActiveDate = nil
                return
            }

            intervals.append(
                MotorActiveInterval(
                    start: start,
                    end: last.addingTimeInterval(sampleDuration)
                )
            )
            activeStart = nil
            lastActiveDate = nil
        }

        for item in sortedPoints {
            guard item.point.motorEnabled == 1 else {
                finishCurrentInterval()
                continue
            }

            if let previous = lastActiveDate,
               item.timestamp.timeIntervalSince(previous) > maximumContinuousGap {
                finishCurrentInterval()
            }

            if activeStart == nil {
                activeStart = item.timestamp
            }
            lastActiveDate = item.timestamp
        }

        finishCurrentInterval()
        return mergeMotorIntervals(intervals)
    }

    /// 將即時藍牙感測點之馬達啟用狀態追加至今日時間軸中
    /// - Parameter points: 即時接收之 TremorDataPoint 感測訊號陣列
    private func appendLiveMotorIntervals(from points: [TremorDataPoint]) {
        guard calendar.isDateInToday(selectedFilterDate) else { return }
        guard !points.isEmpty else { return }

        let fallbackEndDate = Date()

        let timedPoints: [TremorTimedRawPoint] = points.enumerated().map { index, point in
            let fallbackOffset = Double(points.count - 1 - index) * rawSampleInterval
            let timestamp = point.recordedAt
                ?? fallbackEndDate.addingTimeInterval(-fallbackOffset)

            return TremorTimedRawPoint(
                timestamp: timestamp,
                point: point
            )
        }
        let newIntervals = buildMotorActiveIntervals(from: timedPoints)
        guard !newIntervals.isEmpty else { return }

        motorActiveIntervals = mergeMotorIntervals(
            motorActiveIntervals + newIntervals
        )
    }

    /// 合併相鄰或重疊之馬達運轉時段，避免圖表繪製時產生斷裂接縫
    /// - Parameter intervals: 待合併處理之馬達區間陣列
    /// - Returns: 合併整理後之連續馬達時段陣列
    private func mergeMotorIntervals(
        _ intervals: [MotorActiveInterval]
    ) -> [MotorActiveInterval] {
        guard !intervals.isEmpty else { return [] }

        let mergeTolerance: TimeInterval = max(rawSampleInterval * 5, 0.05)
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [MotorActiveInterval] = []

        for interval in sorted {
            guard interval.end > interval.start else { continue }

            if let last = merged.last,
               interval.start.timeIntervalSince(last.end) <= mergeTolerance {
                merged.removeLast()
                merged.append(
                    MotorActiveInterval(
                        id: last.id,
                        start: last.start,
                        end: max(last.end, interval.end)
                    )
                )
            } else {
                merged.append(interval)
            }
        }

        return merged
    }

    /// 取得指定事件時間前後涵蓋之馬達運轉時段清單
    /// - Parameters:
    ///   - targetDate: 目標比對基準時間戳記
    ///   - seconds: 前後涵蓋秒數範圍
    /// - Returns: 位於該時間範圍內之馬達區間陣列
    func motorIntervals(
        surrounding targetDate: Date,
        seconds: TimeInterval = 3
    ) -> [MotorActiveInterval] {
        let start = targetDate.addingTimeInterval(-seconds)
        let end = targetDate.addingTimeInterval(seconds)

        return motorActiveIntervals.filter {
            $0.end >= start && $0.start <= end
        }
    }

    /// 載入當前篩選日期之震顫歷史走勢與分析事件
    /// - Parameter force: 是否強制重新發送網路請求
    func loadTremorHistory(force: Bool = false) async {
        await loadTremorHistory(
            for: selectedFilterDate,
            force: force
        )
    }

    /// 依指定日期非同步平行載入分析事件紀錄與 RMS 走勢線
    /// - Parameters:
    ///   - date: 查詢目標日期實體
    ///   - force: 是否強制重新發送網路請求
    private func loadTremorHistory(
        for date: Date,
        force: Bool = false
    ) async {
        let targetDay = calendar.startOfDay(for: date)

        if !force,
           let loadingHistoryDay,
           calendar.isDate(
               loadingHistoryDay,
               inSameDayAs: targetDay
           ) {
            return
        }

        if !force,
           let loadedHistoryDay,
           calendar.isDate(
               loadedHistoryDay,
               inSameDayAs: targetDay
           ) {
            return
        }

        let requestID = UUID()
        activeHistoryRequestID = requestID
        loadingHistoryDay = targetDay
        isHistoryLoading = true

        defer {
            if activeHistoryRequestID == requestID {
                activeHistoryRequestID = nil
                loadingHistoryDay = nil
                isHistoryLoading = false
            }
        }

        let isSwitchingDay: Bool
        if let loadedHistoryDay {
            isSwitchingDay = !calendar.isDate(
                loadedHistoryDay,
                inSameDayAs: targetDay
            )
        } else {
            isSwitchingDay = false
        }

        if isSwitchingDay {
            selectedPoint = nil
            expandedEventID = nil
            rmsTrendHistory = []
            motorActiveIntervals = []
            updateDashboard()
        }

        async let analysisRecordsTask = fetchAnalysisRecordsSafely()
        let trendPoints = await fetchSavedTrendHistory(for: date)

        guard activeHistoryRequestID == requestID,
              calendar.isDate(
                  date,
                  inSameDayAs: selectedFilterDate
              ) else {
            _ = await analysisRecordsTask
            return
        }

        if let trendPoints {
            applyTrendPoints(trendPoints, for: date)
        } else if !calendar.isDateInToday(date) {
            rmsTrendHistory = []
            motorActiveIntervals = []
            updateDashboard()
        }

        let analysisRecords = await analysisRecordsTask

        guard activeHistoryRequestID == requestID,
              calendar.isDate(
                  date,
                  inSameDayAs: selectedFilterDate
              ) else {
            return
        }

        if let analysisRecords {
            applyAnalysisRecords(analysisRecords)
        }

        if trendPoints != nil {
            loadedHistoryDay = targetDay
        }
        updateDashboard()
    }

    /// 綁定藍牙數據處理管線之即時回呼事件
    /// - Parameter pipeline: 即時感測器管線實體
    func bindPipeline(_ pipeline: TremorPipeline) {
        guard !isPipelineBound else {
            return
        }

        isPipelineBound = true

        pipeline.onStatusChanged = { [weak self] status in
            Task { @MainActor [weak self] in
                self?.statusText = status
            }
        }

        pipeline.onNewRawBatchAppended = { [weak self] newPoints in
            Task { @MainActor [weak self] in
                guard let self, !newPoints.isEmpty else { return }

                self.appendLiveMotorIntervals(from: newPoints)
                self.rawUploadBuffer.append(contentsOf: newPoints)

                while self.rawUploadBuffer.count >= self.uploadBatchThreshold {
                    let batch = Array(self.rawUploadBuffer.prefix(self.uploadBatchThreshold))
                    self.rawUploadBuffer.removeFirst(self.uploadBatchThreshold)

                    let sessionId = self.currentSessionId
                    let baseDate = batch.first?.recordedAt ?? Date()
                    let repository = self.repository

                    Task {
                        do {
                            try await repository.syncRawData(
                                sessionId: sessionId,
                                rawPoints: batch,
                                baseDate: baseDate
                            )
                        } catch {
                            AppLog.error("原始震顫數據批次上傳失敗: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }

        pipeline.onAnalysisUpdated = { [weak self] result, window400Data in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !window400Data.isEmpty else { return }

                let sampleTime = window400Data.last?.recordedAt ?? Date()
                let timeStr = sampleTime.toString(format: "HH:mm:ss")

                let latest50 = Array(window400Data.suffix(50))
                let motorFraction: Double?
                let isMotorActive: Bool

                if latest50.count == 50,
                   latest50.allSatisfy({ $0.motorEnabled == 0 || $0.motorEnabled == 1 }) {
                    let activeCount = latest50.filter { $0.motorEnabled == 1 }.count
                    motorFraction = Double(activeCount) / 50.0
                    isMotorActive = activeCount > 0
                } else {
                    motorFraction = nil
                    isMotorActive = false
                }

                if result.dataValid,
                   result.tremorStrengthRmsDps.isFinite,
                   !result.tremorStrengthRmsDps.isNaN {
                    let trendPoint = TremorTrendPointDTO(
                        sessionId: self.currentSessionId,
                        recordedAt: sampleTime,
                        rmsValue: result.tremorStrengthRmsDps,
                        dominantFrequencyHz: result.dominantFrequencyHz,
                        motorOnFraction: motorFraction ?? 0.0,
                        dataValid: true,
                        frequencyReliable: result.frequencyReliable
                    )

                    self.trendUploadBuffer.append(trendPoint)

                    while self.trendUploadBuffer.count >= self.trendUploadBatchSize {
                        let batch = Array(
                            self.trendUploadBuffer.prefix(self.trendUploadBatchSize)
                        )
                        self.trendUploadBuffer.removeFirst(self.trendUploadBatchSize)

                        let repository = self.repository
                        Task {
                            do {
                                try await repository.syncTrendPoints(batch)
                            } catch {
                                AppLog.error(
                                    "RMS Trend 批次上傳失敗: \(error.localizedDescription)"
                                )
                            }
                        }
                    }
                }

                if self.selectedPoint == nil {
                    if result.dataValid {
                        self.tremorStrengthText = String(format: "%.2f", result.tremorStrengthRmsDps)

                        if result.frequencyReliable,
                           let frequency = result.dominantFrequencyHz,
                           frequency.isFinite {
                            self.dominantFrequencyText = String(format: "%.2f Hz", frequency)
                        } else {
                            self.dominantFrequencyText = "--"
                        }
                    } else {
                        self.tremorStrengthText = "資料不足"
                        self.dominantFrequencyText = "--"
                    }
                }

                if result.dataValid {
                    var liveCalendar = Calendar.current
                    liveCalendar.timeZone = self.taipeiTimeZone

                    if liveCalendar.isDateInToday(self.selectedFilterDate) {
                        let newPoint = RMSTrendPoint(
                            timestamp: sampleTime,
                            timeLabel: timeStr,
                            rmsValue: result.tremorStrengthRmsDps,
                            isMotorActive: isMotorActive,
                            rawWindowData: window400Data
                        )

                        if let lastTime = self.rmsTrendHistory.last?.timestamp {
                            if sampleTime.timeIntervalSince(lastTime) > 0 {
                                self.rmsTrendHistory.append(newPoint)
                            }
                        } else {
                            self.rmsTrendHistory.append(newPoint)
                        }

                        let maxLivePoints = 24 * 60 * 60 * 2
                        if self.rmsTrendHistory.count > maxLivePoints {
                            self.rmsTrendHistory.removeFirst(self.rmsTrendHistory.count - maxLivePoints)
                        }
                    }
                }

                guard result.dataValid else { return }

                let isSignificantTremor = result.tremorStrengthRmsDps >= 0.20 && result.frequencyReliable
                guard isSignificantTremor else { return }

                let now = Date()
                let shouldSave = self.lastAnalysisRecordTime == nil
                || now.timeIntervalSince(self.lastAnalysisRecordTime!) >= self.analysisRecordSaveInterval

                guard shouldSave else { return }
                self.lastAnalysisRecordTime = now

                let sessionId = self.currentSessionId
                let analysisRecord = TremorAnalysisRecordDTO(
                    id: UUID(),
                    sessionId: sessionId,
                    recordedAt: sampleTime,
                    dominantFrequencyHz: result.dominantFrequencyHz,
                    tremorStrengthRmsDps: result.tremorStrengthRmsDps,
                    motorOnFraction: motorFraction ?? 0.0,
                    dataValid: true,
                    frequencyReliable: result.frequencyReliable,
                    activityTag: self.selectedActivityTag,
                    note: nil
                )

                self.eventSessionMap[analysisRecord.id] = sessionId

                if self.analysisHistoryCache != nil {
                    self.analysisHistoryCache?.insert(analysisRecord, at: 0)
                    self.analysisHistoryCacheFetchedAt = Date()
                }

                let liveEvent = TremorEvent(
                    id: analysisRecord.id,
                    timestamp: sampleTime,
                    timeLabel: timeStr,
                    rmsValue: result.tremorStrengthRmsDps,
                    dominantFrequency: result.dominantFrequencyHz ?? 0.0,
                    rawWindowData: window400Data,
                    isMotorActive: isMotorActive,
                    motorOnFraction: motorFraction,
                    userTag: self.selectedActivityTag,
                    isSaved: true
                )
                self.tremorEvents.insert(liveEvent, at: 0)

                self.lastVibrationDate = sampleTime.toString(format: "MM/dd")
                self.lastVibrationTime = sampleTime.toString(format: "HH:mm")

                let repository = self.repository
                Task {
                    do {
                        try await repository.syncAnalysisResult(record: analysisRecord)
                    } catch {
                        AppLog.error("分析紀錄上傳失敗: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// 儲存更新特定震顫事件之情境活動標籤與照片
    /// - Parameter event: 待更新儲存之震顫事件實體
    /// - Returns: 儲存成功回傳 true，否則回傳 false
    func saveTremorEvent(
        _ event: TremorEvent
    ) async -> Bool {
        guard let index = tremorEvents.firstIndex(
            where: { $0.id == event.id }
        ) else {
            return false
        }

        var eventToSave = event
        let trimmedTag = event.userTag
            .trimmingCharacters(in: .whitespacesAndNewlines)

        eventToSave.userTag = trimmedTag.isEmpty ? "未標記" : trimmedTag

        do {
            try await repository.updateAnalysisRecord(
                id: eventToSave.id,
                activityTag: eventToSave.userTag,
                note: nil
            )

            tremorEvents[index].isSaved = true
            tremorEvents[index].userTag = eventToSave.userTag
            tremorEvents[index].selectedImages = eventToSave.selectedImages

            analysisHistoryCache = nil
            analysisHistoryCacheFetchedAt = nil

            return true
        } catch {
            AppLog.error(
                "分析紀錄標記失敗：\(error.localizedDescription)"
            )
            return false
        }
    }

    /// 更新儀表板顯示之即時數值與主頻率文字
    private func updateDashboard() {
        guard let targetPoint = selectedPoint ?? rmsTrendHistory.last else {
            dominantFrequencyText = "--"
            tremorStrengthText = "0.00"
            return
        }

        guard targetPoint.rmsValue.isFinite, !targetPoint.rmsValue.isNaN else {
            dominantFrequencyText = "--"
            tremorStrengthText = "資料不足"
            return
        }

        tremorStrengthText = String(format: "%.2f", targetPoint.rmsValue)

        if !targetPoint.rawWindowData.isEmpty {
            let result = analyzer.analyze(data: targetPoint.rawWindowData)
            if result.frequencyReliable, let frequency = result.dominantFrequencyHz {
                dominantFrequencyText = String(format: "%.2f Hz", frequency)
            } else {
                dominantFrequencyText = "--"
            }
        } else {
            dominantFrequencyText = "--"
        }
    }

    /// 依據 400 筆角速度視窗資料計算三軸疊加之功率譜密度（PSD）分佈點
    /// - Parameter windowData: 400 筆原始感測數據點
    /// - Returns: 頻率與功率強度資料點陣列
    func calculatePSDData(from windowData: [TremorDataPoint]) -> [PSDPoint] {
        guard windowData.count == 400 else {
            return []
        }

        let gyroX = windowData.map { $0.gyroXDps }
        let gyroY = windowData.map { $0.gyroYDps }
        let gyroZ = windowData.map { $0.gyroZDps }

        let psdX = analyzer.calculatePSD(signal: gyroX)
        let psdY = analyzer.calculatePSD(signal: gyroY)
        let psdZ = analyzer.calculatePSD(signal: gyroZ)

        guard psdX.count >= 61, psdY.count >= 61, psdZ.count >= 61 else {
            return []
        }

        var points: [PSDPoint] = []
        let df = 0.25

        for k in 0...60 {
            let totalPower = psdX[k] + psdY[k] + psdZ[k]
            guard totalPower.isFinite, !totalPower.isNaN else {
                continue
            }
            points.append(
                PSDPoint(
                    frequencyHz: Double(k) * df,
                    power: totalPower
                )
            )
        }

        return points
    }

    /// 立即上傳指定會話殘留之原始感測資料緩衝區
    /// - Parameter sessionId: 目標量測會話識別碼
    private func flushRawUploadBuffer(forSession sessionId: String) {
        guard !rawUploadBuffer.isEmpty else { return }
        let batch = rawUploadBuffer
        rawUploadBuffer.removeAll()
        let baseDate = batch.first?.recordedAt ?? Date()
        let repo = self.repository

        Task {
            do {
                try await repo.syncRawData(
                    sessionId: sessionId,
                    rawPoints: batch,
                    baseDate: baseDate
                )
            } catch {
                AppLog.error("結清原始震顫數據失敗: \(error.localizedDescription)")
            }
        }
    }

    /// 立即將暫存之 RMS 走勢點批次上傳至伺服器
    private func flushTrendUploadBuffer() {
        guard !trendUploadBuffer.isEmpty else { return }

        let batch = trendUploadBuffer
        trendUploadBuffer.removeAll()

        let repo = self.repository
        Task {
            do {
                try await repo.syncTrendPoints(batch)
            } catch {
                AppLog.error("結清 RMS Trend 失敗: \(error.localizedDescription)")
            }
        }
    }

    /// 重設原始數據與走勢點暫存緩衝區
    /// - Parameter flushRemaining: 是否在清空前將殘留資料強制上傳
    func resetRawUploadBuffer(flushRemaining: Bool = false) {
        if flushRemaining {
            if !rawUploadBuffer.isEmpty {
                flushRawUploadBuffer(forSession: currentSessionId)
            }
            if !trendUploadBuffer.isEmpty {
                flushTrendUploadBuffer()
            }
        } else {
            rawUploadBuffer.removeAll()
            trendUploadBuffer.removeAll()
        }
    }

    /// 更新儀表板最後震顫時間標記文字
    /// - Parameter date: 發生顯著震顫之日期時間
    public func updateLastVibrationTime(from date: Date) {
        lastVibrationDate = date.toString(format: "MM/dd")
        lastVibrationTime = date.toString(format: "HH:mm")
    }
}
