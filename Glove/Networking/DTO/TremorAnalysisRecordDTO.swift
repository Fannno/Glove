import Foundation

/// 震顫分析紀錄資料傳輸物件 (DTO)
public struct TremorAnalysisRecordDTO: Codable, Identifiable, Sendable {
    public let id: UUID
    public let sessionId: String
    public let recordedAt: Date
    public let dominantFrequencyHz: Double?
    public let tremorStrengthRmsDps: Double?
    public let motorOnFraction: Double
    public let dataValid: Bool
    public let frequencyReliable: Bool
    public let activityTag: String
    public let note: String?

    public init(
        id: UUID = UUID(),
        sessionId: String,
        recordedAt: Date,
        dominantFrequencyHz: Double?,
        tremorStrengthRmsDps: Double?,
        motorOnFraction: Double,
        dataValid: Bool,
        frequencyReliable: Bool,
        activityTag: String,
        note: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.recordedAt = recordedAt
        self.dominantFrequencyHz = dominantFrequencyHz
        self.tremorStrengthRmsDps = tremorStrengthRmsDps
        self.motorOnFraction = motorOnFraction
        self.dataValid = dataValid
        self.frequencyReliable = frequencyReliable
        self.activityTag = activityTag
        self.note = note
    }
}

/// 更新震顫分析紀錄時傳送至後端的資料
struct TremorAnalysisUpdateDTO: Codable {

    /// 更新後的生活情境標籤
    let activityTag: String

    /// 分析紀錄備註
    let note: String?
}

/// 震顫即時走勢點資料傳輸物件（DTO），用於直接記錄畫面當下使用的 RMS 與主頻率數據以供歷史圖表呈現
public struct TremorTrendPointDTO: Codable, Identifiable, Sendable {
    public let id: UUID
    public let sessionId: String
    public let recordedAt: Date
    public let rmsValue: Double
    public let dominantFrequencyHz: Double?
    public let motorOnFraction: Double
    public let dataValid: Bool
    public let frequencyReliable: Bool

    public init(
        id: UUID = UUID(),
        sessionId: String,
        recordedAt: Date,
        rmsValue: Double,
        dominantFrequencyHz: Double?,
        motorOnFraction: Double,
        dataValid: Bool,
        frequencyReliable: Bool
    ) {
        self.id = id
        self.sessionId = sessionId
        self.recordedAt = recordedAt
        self.rmsValue = rmsValue
        self.dominantFrequencyHz = dominantFrequencyHz
        self.motorOnFraction = motorOnFraction
        self.dataValid = dataValid
        self.frequencyReliable = frequencyReliable
    }
}

/// 震顫走勢點批次上傳請求資料傳輸物件（DTO），用於打包多筆連續走勢點以降低網路傳輸負擔
struct TremorTrendBatchUploadRequestDTO: Codable, Sendable {
    let points: [TremorTrendPointDTO]
}

