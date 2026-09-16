import Combine
import Foundation
import UIKit

@MainActor
final class DataViewModel: ObservableObject {
    static let shared = DataViewModel()
    let analyzer = TremorAnalyzer()
    private let repository: TremorRepositoryProtocol
    private var isPipelineBound = false

    /// 採樣參數、時區與日曆設定
    private let rawSampleInterval: TimeInterval = 0.01
    private let uploadBatchThreshold = 400
    private let taipeiTimeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
    private let calendar: Calendar = {
        var c = Calendar.current
        c.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        return c
    }()
    let activityOptions = ["休息", "吃飯", "喝水", "寫字", "走路", "服藥後"]

    /// 量測會話識別碼、事件對應關聯、上傳緩衝區與快照冷卻時間
    var currentSessionId: String = UUID().uuidString {
        didSet {
            if oldValue != currentSessionId && !rawUploadBuffer.isEmpty {
                flushRawUploadBuffer(forSession: oldValue)
            }
        }
    }
    private var eventSessionMap: [UUID: String] = [:]
    private var rawUploadBuffer: [TremorDataPoint] = []
    private var lastAnalysisRecordTime: Date?

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
            let date = selectedFilterDate
            Task { [weak self] in
                guard let self else { return }
                self.selectedPoint = nil
                self.expandedEventID = nil
                await self.loadTremorHistory(for: date)
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
        /// 用於計算此走勢點之 400 筆原始感測訊號資料視窗
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
        tremorEvents.filter { calendar.isDate($0.timestamp, inSameDayAs: selectedFilterDate) }
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

    /// 產生 RMS 圖表共用的完整折線資料，包含背景連續走勢與獨立事件點之合併
    /// - Returns: 經過時間排序與去重後的完整走勢點陣列
    func mergedRMSChartHistory() -> [RMSTrendPoint] {
        var combined = rmsTrendHistory.filter {
            $0.rmsValue.isFinite && !$0.rmsValue.isNaN
        }
        for event in filteredEvents where event.rmsValue.isFinite && !event.rmsValue.isNaN {
            let alreadyIncluded = combined.contains {
                abs($0.timestamp.timeIntervalSince(event.timestamp)) <= 0.6
            }
            if !alreadyIncluded {
                combined.append(
                    RMSTrendPoint(
                        timestamp: event.timestamp,
                        timeLabel: event.timeLabel,
                        rmsValue: event.rmsValue,
                        isMotorActive: event.isMotorActive,
                        rawWindowData: event.rawWindowData,
                        userTag: event.userTag,
                        selectedImages: event.selectedImages,
                        isSaved: event.isSaved
                    )
                )
            }
        }
        return deduplicateChartPoints(combined)
    }

    /// 取得事件卡片繪製局部波形所需的 RMS 折線資料，並向外延伸保留邊界點
    /// - Parameters:
    ///   - targetDate: 目標事件時間基準
    ///   - seconds: 向前與向後擷取之秒數範圍
    /// - Returns: 局部走勢資料點陣列
    func rmsChartHistory(
        surrounding targetDate: Date,
        seconds: TimeInterval = 3
    ) -> [RMSTrendPoint] {
        let completeHistory = mergedRMSChartHistory()
        guard !completeHistory.isEmpty else { return [] }

        let startDate = targetDate.addingTimeInterval(-seconds)
        let endDate = targetDate.addingTimeInterval(seconds)

        let pointsInsideRange = completeHistory.filter {
            $0.timestamp >= startDate && $0.timestamp <= endDate
        }
        let pointBeforeRange = completeHistory.last { $0.timestamp < startDate }
        let pointAfterRange = completeHistory.first { $0.timestamp > endDate }

        var result: [RMSTrendPoint] = []
        if let pointBeforeRange { result.append(pointBeforeRange) }
        result.append(contentsOf: pointsInsideRange)
        if let pointAfterRange { result.append(pointAfterRange) }

        if result.count < 2,
           let nearestIndex = completeHistory.indices.min(by: {
               abs(completeHistory[$0].timestamp.timeIntervalSince(targetDate)) <
               abs(completeHistory[$1].timestamp.timeIntervalSince(targetDate))
           }) {
            let lowerIndex = max(completeHistory.startIndex, nearestIndex - 1)
            let upperIndex = min(completeHistory.index(before: completeHistory.endIndex), nearestIndex + 1)
            result = Array(completeHistory[lowerIndex...upperIndex])
        }

        return deduplicateChartPoints(result)
    }

    /// 依照半秒時間桶排除過度密集之重複圖表折線節點
    /// - Parameter points: 待處理之走勢點陣列
    /// - Returns: 去除重複節點後之走勢點陣列
    private func deduplicateChartPoints(_ points: [RMSTrendPoint]) -> [RMSTrendPoint] {
        var result: [RMSTrendPoint] = []
        var seenBuckets = Set<Int64>()

        for point in points.sorted(by: { $0.timestamp < $1.timestamp }) {
            let bucket = Int64((point.timestamp.timeIntervalSince1970 * 2).rounded(.toNearestOrAwayFromZero))
            if seenBuckets.insert(bucket).inserted {
                result.append(point)
            }
        }
        return result
    }

    /// 擷取特定時間範圍周邊之馬達啟動區間清單
    /// - Parameters:
    ///   - targetDate: 目標基準時間戳記
    ///   - seconds: 欲比對之時間範圍秒數
    /// - Returns: 涵蓋於該時段內之馬達區間陣列
    func motorIntervals(
        surrounding targetDate: Date,
        seconds: TimeInterval = 3
    ) -> [MotorActiveInterval] {
        let start = targetDate.addingTimeInterval(-seconds)
        let end = targetDate.addingTimeInterval(seconds)
        return motorActiveIntervals.filter { $0.end >= start && $0.start <= end }
    }

    /// 將連續原始取樣數據合併解析為連續的馬達啟動區間
    /// - Parameter points: 帶有時間戳記之原始感測資料點陣列
    /// - Returns: 解析完成之馬達運轉時段區間陣列
    private func buildMotorActiveIntervals(from points: [TremorTimedRawPoint]) -> [MotorActiveInterval] {
        let sortedPoints = points.sorted { $0.timestamp < $1.timestamp }
        guard !sortedPoints.isEmpty else { return [] }

        let sampleDuration: TimeInterval = rawSampleInterval
        let maximumContinuousGap: TimeInterval = max(rawSampleInterval * 5, 0.05)

        var intervals: [MotorActiveInterval] = []
        var activeStart: Date?
        var lastActiveDate: Date?

        func finishCurrentInterval() {
            guard let start = activeStart, let last = lastActiveDate else {
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
            if let previous = lastActiveDate, item.timestamp.timeIntervalSince(previous) > maximumContinuousGap {
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

    /// 針對缺乏原始感測細節之歷史事件，依據分析紀錄回補 0.5 秒馬達介入提示區間
    /// - Parameter existingRawIntervals: 既有之原始馬達區間陣列
    /// - Returns: 由事件推算建立之馬達啟動區間陣列
    private func buildFallbackMotorIntervalsFromAnalysisEvents(
        existingRawIntervals: [MotorActiveInterval]
    ) -> [MotorActiveInterval] {
        _ = existingRawIntervals
        let analysisWindowDuration: TimeInterval = 0.5

        let fallbackIntervals = filteredEvents.compactMap { event -> MotorActiveInterval? in
            guard event.isMotorActive else { return nil }
            let end = event.timestamp
            let start = end.addingTimeInterval(-analysisWindowDuration)
            return MotorActiveInterval(start: start, end: end)
        }
        return mergeMotorIntervals(fallbackIntervals)
    }

    /// 將即時接收之藍牙感測點馬達狀態加入當前日期之馬達時間軸中
    /// - Parameter points: 即時接收之 TremorDataPoint 陣列
    private func appendLiveMotorIntervals(from points: [TremorDataPoint]) {
        guard calendar.isDateInToday(selectedFilterDate) else { return }
        guard !points.isEmpty else { return }

        let fallbackEndDate = Date()
        let timedPoints: [TremorTimedRawPoint] = points.enumerated().map { index, point in
            let fallbackOffset = Double(points.count - 1 - index) * rawSampleInterval
            let timestamp = point.recordedAt ?? fallbackEndDate.addingTimeInterval(-fallbackOffset)
            return TremorTimedRawPoint(timestamp: timestamp, point: point)
        }
        let newIntervals = buildMotorActiveIntervals(from: timedPoints)
        guard !newIntervals.isEmpty else { return }

        motorActiveIntervals = mergeMotorIntervals(motorActiveIntervals + newIntervals)
    }

    /// 合併相鄰或重疊之馬達運轉區間，消除圖表繪製時之斷裂接縫
    /// - Parameter intervals: 待合併之馬達區間陣列
    /// - Returns: 合併整理後之連續馬達區間陣列
    private func mergeMotorIntervals(_ intervals: [MotorActiveInterval]) -> [MotorActiveInterval] {
        guard !intervals.isEmpty else { return [] }

        let mergeTolerance: TimeInterval = max(rawSampleInterval * 5, 0.05)
        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [MotorActiveInterval] = []

        for interval in sorted {
            guard interval.end > interval.start else { continue }
            if let last = merged.last, interval.start.timeIntervalSince(last.end) <= mergeTolerance {
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

    /// 載入當前選定篩選日期之完整震顫歷史紀錄與走勢資料
    func loadTremorHistory() async {
        await loadTremorHistory(for: selectedFilterDate)
    }

    /// 依指定日期依序載入分析事件、建立馬達時序並計算連續走勢
    /// - Parameter date: 查詢目標日期實體
    private func loadTremorHistory(for date: Date) async {
        selectedPoint = nil
        rmsTrendHistory = []
        motorActiveIntervals = []
        await loadAnalysisEvents(matchedHistory: [])

        motorActiveIntervals = buildFallbackMotorIntervalsFromAnalysisEvents(existingRawIntervals: [])
        guard calendar.isDate(date, inSameDayAs: selectedFilterDate) else { return }
        await loadRawDataTrend()
    }

    /// 從遠端伺服器載入歷史震顫分析紀錄並結合鄰近原始訊號視窗
    /// - Parameter matchedHistory: 可供比對之本機 RMS 走勢快取陣列
    func loadAnalysisEvents(matchedHistory: [RMSTrendPoint] = []) async {
        do {
            let records = try await repository.fetchAnalysisHistory()
            var seenIDs = Set<UUID>()
            var analysisRecords: [TremorEvent] = []

            for record in records.sorted(by: { $0.recordedAt > $1.recordedAt }) {
                guard seenIDs.insert(record.id).inserted else { continue }
                eventSessionMap[record.id] = record.sessionId

                let date = record.recordedAt
                let rawTag = record.activityTag.trimmingCharacters(in: .whitespacesAndNewlines)
                let tag = rawTag.isEmpty ? "未標記" : rawTag
                let maxMatchToleranceSeconds: TimeInterval = 5.0

                let matchedRaw = matchedHistory.min {
                    abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
                }.flatMap { matched -> [TremorDataPoint]? in
                    guard calendar.isDate(matched.timestamp, inSameDayAs: date),
                          abs(matched.timestamp.timeIntervalSince(date)) <= maxMatchToleranceSeconds else { return nil }
                    return matched.rawWindowData
                } ?? []

                guard record.dataValid else { continue }

                analysisRecords.append(
                    TremorEvent(
                        id: record.id,
                        timestamp: date,
                        timeLabel: date.toString(format: "yyyy-MM-dd HH:mm:ss"),
                        rmsValue: record.tremorStrengthRmsDps ?? 0.0,
                        dominantFrequency: record.frequencyReliable ? (record.dominantFrequencyHz ?? 0.0) : 0.0,
                        rawWindowData: matchedRaw,
                        isMotorActive: (record.motorOnFraction > 0.0),
                        motorOnFraction: record.motorOnFraction,
                        userTag: tag,
                        isSaved: true
                    )
                )
            }

            tremorEvents = analysisRecords

            if let latest = analysisRecords.first(where: { $0.dominantFrequency > 0 }) {
                lastVibrationDate = latest.timestamp.toString(format: "MM/dd")
                lastVibrationTime = latest.timestamp.toString(format: "HH:mm")
            } else {
                lastVibrationDate = "--"
                lastVibrationTime = "--:--"
            }
        } catch {
            AppLog.error("載入分析紀錄失敗: \(error.localizedDescription)")
            tremorEvents = []
            lastVibrationDate = "--"
            lastVibrationTime = "--:--"
        }
    }

    /// 從遠端伺服器載入指定日期的原始感測時序訊號並重建全天連續 RMS 走勢線與馬達區間
    func loadRawDataTrend() async {
        do {
            let timedRawPoints = try await repository.fetchTimedRawDataHistory()
            let sorted = timedRawPoints.sorted { $0.timestamp < $1.timestamp }

            let startOfDay = calendar.startOfDay(for: selectedFilterDate)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
                ?? startOfDay.addingTimeInterval(24 * 60 * 60)

            let dayPoints = sorted.filter {
                $0.timestamp >= startOfDay && $0.timestamp < endOfDay
            }

            let rawMotorIntervals = buildMotorActiveIntervals(from: dayPoints)
            let analysisFallbackIntervals = buildFallbackMotorIntervalsFromAnalysisEvents(
                existingRawIntervals: rawMotorIntervals
            )
            let historicalMotorIntervals = mergeMotorIntervals(
                rawMotorIntervals + analysisFallbackIntervals
            )

            if calendar.isDateInToday(selectedFilterDate) {
                let latestHistoricalTime = dayPoints.last?.timestamp ?? startOfDay
                let liveIntervals = motorActiveIntervals.filter { $0.end > latestHistoricalTime }
                motorActiveIntervals = mergeMotorIntervals(historicalMotorIntervals + liveIntervals)
            } else {
                motorActiveIntervals = historicalMotorIntervals
            }

            var computedHistory = buildHistoricalTrend(from: dayPoints)
            if computedHistory.isEmpty {
                computedHistory = buildFallbackTrendFromEvents()
            }

            if calendar.isDateInToday(selectedFilterDate),
               let latest = computedHistory.last?.timestamp {
                let livePoints = rmsTrendHistory.filter { $0.timestamp > latest }
                computedHistory.append(contentsOf: livePoints)
            }

            rmsTrendHistory = deduplicateTrendPoints(computedHistory).sorted { $0.timestamp < $1.timestamp }
            await backfillEventRawWindowData()
            selectedPoint = nil
            updateDashboard()
        } catch {
            AppLog.error("載入原始走勢失敗: \(error.localizedDescription)")
            motorActiveIntervals = buildFallbackMotorIntervalsFromAnalysisEvents(existingRawIntervals: [])
            if rmsTrendHistory.isEmpty {
                rmsTrendHistory = buildFallbackTrendFromEvents()
            }
        }
    }

    /// 根據連續原始資料點陣列以滑動視窗計算歷史 RMS 走勢點，並過濾時間不連續之訊號片段
    /// - Parameter points: 帶有時間戳記之原始感測資料陣列
    /// - Returns: 計算產生之 RMS 走勢點陣列
    private func buildHistoricalTrend(from points: [TremorTimedRawPoint]) -> [RMSTrendPoint] {
        let windowSize = 400
        let strideSize = 50
        guard points.count >= windowSize else { return [] }

        var result: [RMSTrendPoint] = []
        result.reserveCapacity(max(points.count / strideSize, 1))

        var startIndex = 0
        while startIndex + windowSize <= points.count {
            let endIndex = startIndex + windowSize
            let window = Array(points[startIndex..<endIndex])

            guard let firstTime = window.first?.timestamp, let lastTime = window.last?.timestamp else {
                startIndex += strideSize
                continue
            }

            if lastTime.timeIntervalSince(firstTime) > 5.5 {
                if let breakIndex = (1..<window.count).first(where: {
                    window[$0].timestamp.timeIntervalSince(window[$0 - 1].timestamp) > 0.5
                }) {
                    startIndex += breakIndex
                } else {
                    startIndex += strideSize
                }
                continue
            }

            let rawWindow = window.map(\.point)
            let resultValue = analyzer.analyze(data: rawWindow)
            let timestamp = lastTime

            guard resultValue.dataValid,
                  resultValue.tremorStrengthRmsDps.isFinite,
                  !resultValue.tremorStrengthRmsDps.isNaN else {
                startIndex += strideSize
                continue
            }

            let latest50 = rawWindow.suffix(50)
            let motorActive = latest50.contains { $0.motorEnabled == 1 }

            result.append(
                RMSTrendPoint(
                    timestamp: timestamp,
                    timeLabel: timestamp.toString(format: "HH:mm:ss"),
                    rmsValue: resultValue.tremorStrengthRmsDps,
                    isMotorActive: motorActive,
                    rawWindowData: rawWindow
                )
            )
            startIndex += strideSize
        }

        let tailStart = points.count - windowSize
        if tailStart >= 0 {
            let tailWindow = Array(points[tailStart..<points.count])
            if let firstTime = tailWindow.first?.timestamp,
               let tailTimestamp = tailWindow.last?.timestamp,
               tailTimestamp.timeIntervalSince(firstTime) <= 5.5 {
                let alreadyExists = result.contains { $0.timestamp == tailTimestamp }
                if !alreadyExists {
                    let rawWindow = tailWindow.map(\.point)
                    let resultValue = analyzer.analyze(data: rawWindow)

                    if resultValue.dataValid,
                       resultValue.tremorStrengthRmsDps.isFinite,
                       !resultValue.tremorStrengthRmsDps.isNaN {
                        let latest50 = rawWindow.suffix(50)
                        let motorActive = latest50.contains { $0.motorEnabled == 1 }

                        result.append(
                            RMSTrendPoint(
                                timestamp: tailTimestamp,
                                timeLabel: tailTimestamp.toString(format: "HH:mm:ss"),
                                rmsValue: resultValue.tremorStrengthRmsDps,
                                isMotorActive: motorActive,
                                rawWindowData: rawWindow
                            )
                        )
                    }
                }
            }
        }
        return result.sorted { $0.timestamp < $1.timestamp }
    }

    /// 當缺乏密集原始訊號時，從事件快照資料建構備援之走勢點陣列
    /// - Returns: 備援之 RMS 走勢點陣列
    private func buildFallbackTrendFromEvents() -> [RMSTrendPoint] {
        filteredEvents.map {
            RMSTrendPoint(
                timestamp: $0.timestamp,
                timeLabel: $0.timestamp.toString(format: "HH:mm:ss"),
                rmsValue: $0.rmsValue,
                isMotorActive: $0.isMotorActive,
                rawWindowData: $0.rawWindowData,
                userTag: $0.userTag,
                selectedImages: $0.selectedImages,
                isSaved: $0.isSaved
            )
        }
        .sorted { $0.timestamp < $1.timestamp }
    }

    /// 對走勢點進行半秒時間桶去重處理，避免重複繪製過度密集節點
    /// - Parameter points: 待處理之走勢點陣列
    /// - Returns: 去重後之走勢點陣列
    private func deduplicateTrendPoints(_ points: [RMSTrendPoint]) -> [RMSTrendPoint] {
        var result: [RMSTrendPoint] = []
        var seenBuckets = Set<Int64>()

        for point in points.sorted(by: { $0.timestamp < $1.timestamp }) {
            let bucket = Int64((point.timestamp.timeIntervalSince1970 * 2.0).rounded(.toNearestOrAwayFromZero))
            if seenBuckets.insert(bucket).inserted {
                result.append(point)
            }
        }
        return result
    }

    /// 從連續走勢快取中回補事件紀錄缺失之原始視窗訊號
    private func backfillEventRawWindowData() async {
        guard !tremorEvents.isEmpty, !rmsTrendHistory.isEmpty else { return }
        let maxTolerance: TimeInterval = 5.0

        tremorEvents = tremorEvents.map { event in
            guard event.rawWindowData.isEmpty else { return event }

            let matched = rmsTrendHistory.min {
                abs($0.timestamp.timeIntervalSince(event.timestamp)) < abs($1.timestamp.timeIntervalSince(event.timestamp))
            }
            let isValidMatch = matched != nil
                && calendar.isDate(matched!.timestamp, inSameDayAs: event.timestamp)
                && abs(matched!.timestamp.timeIntervalSince(event.timestamp)) <= maxTolerance

            let resolvedRaw = isValidMatch ? matched!.rawWindowData : []

            return TremorEvent(
                id: event.id,
                timestamp: event.timestamp,
                timeLabel: event.timeLabel,
                rmsValue: event.rmsValue,
                dominantFrequency: event.dominantFrequency,
                rawWindowData: resolvedRaw,
                isMotorActive: event.isMotorActive,
                motorOnFraction: event.motorOnFraction,
                userTag: event.userTag,
                selectedImages: event.selectedImages,
                isSaved: event.isSaved
            )
        }
    }

    /// 綁定藍牙數據流管線，接管即時資料更新、批次上傳、馬達區間推算與即時分析排程
    /// - Parameter pipeline: 藍牙端傳入之 TremorPipeline 實體
    func bindPipeline(_ pipeline: TremorPipeline) {
        guard !isPipelineBound else { return }
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
                || now.timeIntervalSince(self.lastAnalysisRecordTime!) >= 3.0

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

    /// 更新並儲存特定震顫事件的情境活動標籤與照片
    /// - Parameter event: 包含最新標籤資訊之 TremorEvent 實體
    /// - Returns: 更新成功回傳 true，失敗回傳 false
    func saveTremorEvent(_ event: TremorEvent) async -> Bool {
        guard let index = tremorEvents.firstIndex(where: { $0.id == event.id }) else {
            return false
        }

        var eventToSave = event
        let trimmedTag = event.userTag.trimmingCharacters(in: .whitespacesAndNewlines)
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
            return true
        } catch {
            AppLog.error("分析紀錄標記失敗：\(error.localizedDescription)")
            return false
        }
    }

    /// 依據當前選定點或最新資料更新儀表板顯示之數值與頻率文字
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

    /// 計算特定 400 筆感測視窗之功率譜密度（PSD）頻率能量分佈點陣列
    /// - Parameter windowData: 包含 400 筆三軸角速度之原始數據陣列
    /// - Returns: 0 至 15 Hz 區間之離散頻譜能量點陣列
    func calculatePSDData(from windowData: [TremorDataPoint]) -> [PSDPoint] {
        guard windowData.count == 400 else { return [] }

        let gyroX = windowData.map { $0.gyroXDps }
        let gyroY = windowData.map { $0.gyroYDps }
        let gyroZ = windowData.map { $0.gyroZDps }

        let psdX = analyzer.calculatePSD(signal: gyroX)
        let psdY = analyzer.calculatePSD(signal: gyroY)
        let psdZ = analyzer.calculatePSD(signal: gyroZ)

        guard psdX.count >= 61, psdY.count >= 61, psdZ.count >= 61 else { return [] }

        var points: [PSDPoint] = []
        let df = 0.25

        for k in 0...60 {
            let totalPower = psdX[k] + psdY[k] + psdZ[k]
            guard totalPower.isFinite, !totalPower.isNaN else { continue }
            points.append(PSDPoint(frequencyHz: Double(k) * df, power: totalPower))
        }

        return points
    }

    /// 將特定工作階段緩衝區內剩餘之原始資料立即壓縮並發送至後端
    /// - Parameter sessionId: 欲結算資料之工作階段識別碼
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

    /// 清空原始數據暫存緩衝區，並可指定是否強制結算上傳剩餘資料
    /// - Parameter flushRemaining: 若為 true 則先上傳剩餘資料再清空，若為 false 則直接丟棄
    func resetRawUploadBuffer(flushRemaining: Bool = false) {
        if flushRemaining && !rawUploadBuffer.isEmpty {
            flushRawUploadBuffer(forSession: currentSessionId)
        } else {
            rawUploadBuffer.removeAll()
        }
    }

    /// 更新儀表板顯示之上次震顫日期與時間文字
    /// - Parameter date: 發生顯著震顫之日期時間戳記
    public func updateLastVibrationTime(from date: Date) {
        lastVibrationDate = date.toString(format: "MM/dd")
        lastVibrationTime = date.toString(format: "HH:mm")
    }
}
