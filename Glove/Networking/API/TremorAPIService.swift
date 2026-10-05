import Foundation

protocol TremorAPIServiceProtocol {
    /// 上傳壓縮之原始震顫取樣數據
    func uploadRawData(_ payload: TremorRawUploadRequestDTO, token: String) async throws

    /// 上傳單筆震顫分析特徵紀錄
    func uploadAnalysisRecord(_ record: TremorAnalysisRecordDTO, token: String) async throws

    /// 更新既有震顫分析紀錄的情境標籤與備註
    func updateAnalysisRecord(id: UUID, payload: TremorAnalysisUpdateDTO, token: String) async throws

    /// 取得歷史原始震顫取樣二進位壓縮封包清單
    func fetchRawDataHistory(token: String) async throws -> [RawTremorDataDTO]

    /// 取得歷史震顫分析特徵紀錄清單
    func fetchAnalysisHistory(token: String) async throws -> [TremorAnalysisRecordDTO]

    /// 批次上傳即時 RMS 趨勢點
    func uploadTrendPoints(_ payload: TremorTrendBatchUploadRequestDTO, token: String) async throws

    /// 依日期區間取得已保存的 RMS 趨勢點
    func fetchTrendHistory(from: Date, to: Date, token: String) async throws -> [TremorTrendPointDTO]
}

/// 震顫後端 API 傳輸服務實作，負責 HTTP 請求組裝、驗證標頭設定、狀態碼檢查與 JSON 解析
final class TremorAPIService: TremorAPIServiceProtocol {

    /// 全域單例存取點
    static let shared = TremorAPIService()

    /// 震顫相關端點之基礎 URL 路徑
    private var baseURL: String {
        var base = APIConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return "\(base)/tremor"
    }

    /// 初始化實體
    init() {}

    /// 建立具備統一日期與鍵值解碼策略的 JSONDecoder 實體
    /// - Parameter useSnakeCase: 是否將蛇形命名轉換為駝峰命名，預設為 true
    /// - Returns: 設定完成的 JSONDecoder
    private func makeDecoder(useSnakeCase: Bool = true) -> JSONDecoder {
        let decoder = JSONDecoder()
        if useSnakeCase {
            decoder.keyDecodingStrategy = .convertFromSnakeCase
        }
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// 建立統一日期編碼策略的 JSONEncoder 實體
    private func makeEncoder() -> JSONEncoder { let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// 上傳壓縮之原始震顫取樣數據至伺服器
    /// - Parameters:
    ///   - payload: 封裝壓縮數據之請求 DTO
    ///   - token: 使用者驗證 Token
    func uploadRawData(_ payload: TremorRawUploadRequestDTO, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/raw") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try makeEncoder().encode(payload)
        } catch {
            throw NetworkError.encodingFailed
        }

        try await NetworkManager.shared.requestData(request)
    }

    /// 上傳單筆震顫特徵分析紀錄至伺服器
    /// - Parameters:
    ///   - record: 震顫分析特徵資料 DTO
    ///   - token: 使用者驗證 Token
    func uploadAnalysisRecord(_ record: TremorAnalysisRecordDTO, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/analysis") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try makeEncoder().encode(record)
        } catch {
            throw NetworkError.encodingFailed
        }

        try await NetworkManager.shared.requestData(request)
    }

    /// 更新既有震顫分析紀錄的情境標籤與備註
    /// - Parameters:
    ///   - id: 欲更新之分析紀錄識別碼
    ///   - payload: 更新後的情境標籤與備註
    ///   - token: 使用者驗證 Token
    func updateAnalysisRecord(id: UUID, payload: TremorAnalysisUpdateDTO, token: String) async throws {
        guard let url = URL(
            string: "\(baseURL)/analysis/\(id.uuidString)"
        ) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"

        request.setValue(
            "Bearer \(token)",
            forHTTPHeaderField: "Authorization"
        )

        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        do {
            request.httpBody =
                try makeEncoder().encode(payload)
        } catch {
            throw NetworkError.encodingFailed
        }

        try await NetworkManager.shared
            .requestData(request)
    }

    /// 向伺服器拉取所有歷史原始震顫數據封包
    /// - Parameter token: 身分驗證 Bearer 權杖
    /// - Returns: 歷史原始震顫數據 DTO 陣列
    func fetchRawDataHistory(token: String) async throws -> [RawTremorDataDTO] {
        guard let url = URL(string: "\(baseURL)/raw") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await NetworkManager.shared.request(request, decoder: makeDecoder())
    }

    /// 向伺服器拉取所有歷史震顫分析特徵紀錄
    /// - Parameter token: 身分驗證 Bearer 權杖
    /// - Returns: 歷史震顫分析紀錄 DTO 陣列
    func fetchAnalysisHistory(token: String) async throws -> [TremorAnalysisRecordDTO] {
        guard let url = URL(string: "\(baseURL)/history") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await NetworkManager.shared.request(request, decoder: makeDecoder())
    }

    /// 批次上傳即時 RMS 趨勢點
    /// - Parameters:
    ///   - payload: 包含批次趨勢點之請求 DTO
    ///   - token: 使用者驗證 Token
    func uploadTrendPoints(_ payload: TremorTrendBatchUploadRequestDTO, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/trend/batch") else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try makeEncoder().encode(payload)
        } catch {
            throw NetworkError.encodingFailed
        }

        try await NetworkManager.shared.requestData(request)
    }

    /// 依指定日期區間取得 RMS 趨勢點
    /// - Parameters:
    ///   - from: 查詢起始日期
    ///   - to: 查詢結束日期
    ///   - token: 使用者驗證 Token
    /// - Returns: 符合時段之 RMS 趨勢點 DTO 陣列
    func fetchTrendHistory(
        from: Date,
        to: Date,
        token: String
    ) async throws -> [TremorTrendPointDTO] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        guard var components = URLComponents(string: "\(baseURL)/trend") else {
            throw NetworkError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "from", value: formatter.string(from: from)),
            URLQueryItem(name: "to", value: formatter.string(from: to))
        ]

        guard let url = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await NetworkManager.shared.request(
            request,
            decoder: makeDecoder()
        )
    }

}
