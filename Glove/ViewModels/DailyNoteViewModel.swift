import Combine
import SwiftData
import SwiftUI

@MainActor
final class DailyNoteViewModel: ObservableObject {
    let loginVM: LoginViewModel

    /// 每日留言資料存取 Repository 層實例
    private let dailyRepo = DailyNoteRepository()

    /// 使用者資訊與身分判斷
    var currentUserRole: String {
        loginVM.userData?.userName ?? "用戶"
    }
    var isPatient: Bool {
        loginVM.userData?.role == 0
    }

    /// 支援的心情標籤選項清單
    let moods = ["開心", "平靜", "疲憊", "不舒服"]

    /// 留言清單、載入狀態、選定篩選日期、心情篩選識別碼與選定詳情便利貼
    @Published var notes: [DailyNote] = []
    @Published var isLoadingData = false
    @Published var selectedDate = Date()
    @Published var selectedMood: UUID? = nil
    @Published var selectedDetailNote: DailyNote? = nil

    /// 新增便利貼表單之彈出狀態、輸入內容、心情標籤、照護者限定開關與卡片代表色
    @Published var showAddNoteSheet = false
    @Published var newNoteText = ""
    @Published var sheetSelectedMoodName: String? = nil
    @Published var isCaregiverOnly: Bool = false
    @Published var noteColor: Color = Color(red: 1.0, green: 0.94, blue: 0.8)

    /// 編輯便利貼之目標實體、編輯文字、選定心情、照護者限定開關與卡片代表色
    @Published var editingNote: DailyNote? = nil
    @Published var editNoteText: String = ""
    @Published var editSelectedMoodName: String? = nil
    @Published var editIsCaregiverOnly: Bool = false
    @Published var editNoteColor: Color = Color(red: 1.0, green: 0.94, blue: 0.8)

    /// 初始化檢視模型並注入登入狀態管理器
    /// - Parameter loginVM: 登入狀態與使用者資料的 ViewModel
    init(loginVM: LoginViewModel) {
        self.loginVM = loginVM
    }

    /// 判斷特定便利貼是否由當前登入使用者所發布
    /// - Parameter note: 欲比對之便利貼實體
    /// - Returns: 若為當前使用者發布則回傳 true，否則回傳 false
    func isMyNote(_ note: DailyNote) -> Bool {
        if let currentUserID = loginVM.userData?.userID, currentUserID != 0, note.userID != 0 {
            return note.userID == currentUserID
        }
        // 舊資料若尚未記錄 userID，則採用名稱作為備援比對
        print("[發送前檢查] 登入者ID: \(loginVM.userData?.userID ?? 0), 名字: \(loginVM.userData?.userName ?? "nil"), currentUserRole: \(currentUserRole)")
        return note.sender == currentUserRole
    }

    /// 取得便利貼介面應顯示的發布者姓名
    /// - Parameter note: 目標便利貼實體
    /// - Returns: 若為自身發布則回傳最新使用者姓名，否則回傳原紀錄姓名
    func senderDisplayName(for note: DailyNote) -> String {
        if isMyNote(note) {
            return loginVM.userData?.userName ?? note.sender
        }
        return note.sender
    }

    /// 驗證新增便利貼表單內容是否符合發送資格
    var canSendNote: Bool {
        let trimmed = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        return isPatient ? (!trimmed.isEmpty || sheetSelectedMoodName != nil) : !trimmed.isEmpty
    }

    /// 驗證編輯便利貼表單內容是否符合儲存資格
    var canSaveEditedNote: Bool {
        let trimmed = editNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        return isPatient ? (!trimmed.isEmpty || editSelectedMoodName != nil) : !trimmed.isEmpty
    }

    /// 取得今天所有具備心情標籤的便利貼紀錄，並按建立時間由舊至新排序
    var todaysDailiesWithMood: [DailyNote] {
        let calendar = Calendar.current
        return notes.filter {
            calendar.isDateInToday($0.date) && $0.moodName != nil
        }.sorted(by: { $0.date < $1.date })
    }

    /// 處理手動輸入新增留言時的字數與換行限制
    /// - Parameter newValue: 新輸入的文字內容
    func handleNoteTextChange(_ newValue: String) {
        let cleaned = cleanExcessiveNewlines(newValue)
        let limited = limitLinesAndLength(text: cleaned, maxCharacters: 100, maxLines: 5)
        if limited != newValue {
            newNoteText = limited
        }
    }

    /// 處理手動編輯既有留言時的字數與換行限制
    /// - Parameter newValue: 新輸入的文字內容
    func handleEditTextChange(_ newValue: String) {
        let cleaned = cleanExcessiveNewlines(newValue)
        let limited = limitLinesAndLength(text: cleaned, maxCharacters: 100, maxLines: 5)
        if limited != newValue {
            editNoteText = limited
        }
    }

    /// 從遠端伺服器拉取最新便利貼資料
    /// - Parameters:
    ///   - modelContext: 資料操作內容物件（選填）
    ///   - isSilent: 是否靜默載入，為 true 時不顯示載入指示器
    @MainActor
    func loadAllNotes(modelContext: ModelContext? = nil, isSilent: Bool = false) async {
        if !isSilent {
            self.isLoadingData = true
        }

        defer {
            if !isSilent {
                Task { @MainActor in
                    self.isLoadingData = false
                }
            }
        }

        do {
            let remoteNotes = try await dailyRepo.fetchAllDailies()
            self.notes = remoteNotes
        } catch {
            let errorMsg = error.localizedDescription
            AppLog.error("載入便利貼失敗: \(errorMsg)")

            if errorMsg.contains("401") || errorMsg.contains("已在其他裝置登入") || errorMsg.contains("登入已失效") {
                self.notes = []
            }
        }
        isLoadingData = false
    }

    /// 發送新建立之便利貼，並非同步上傳至伺服器
    /// - Parameter modelContext: 資料操作內容物件（選填）
    @MainActor
    func sendNote(modelContext: ModelContext? = nil) async {
        guard canSendNote else { return }

        let trimmedContent = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let newDaily = DailyNote(
            userID: loginVM.userData?.userID ?? 0,
            content: trimmedContent,
            date: Date(),
            colorHex: noteColor.toHex() ?? "#FFF0CC",
            sender: currentUserRole,
            moodName: sheetSelectedMoodName,
            isCaregiverOnly: isCaregiverOnly
        )

        if !trimmedContent.isEmpty {
            self.notes.insert(newDaily, at: 0)
        } else {
            self.notes.append(newDaily)
        }

        let recordID = newDaily.id
        resetSheetState()

        do {
            try await dailyRepo.syncDailyRecord(
                id: recordID,
                content: newDaily.content,
                date: newDaily.date,
                colorHex: newDaily.colorHex,
                sender: newDaily.sender,
                moodName: newDaily.moodName,
                isCaregiverOnly: newDaily.isCaregiverOnly
            )
        } catch {
            AppLog.error("同步紀錄至伺服器失敗: \(error.localizedDescription)")
        }
    }

    /// 編輯便利貼：載入目標資料至表單
    /// - Parameter note: 欲修改的 DailyNote 實體
    func startEditing(_ note: DailyNote) {
        self.editingNote = note
        self.editNoteText = note.content
        self.editNoteColor = Color(hex: note.colorHex)
        self.editSelectedMoodName = note.moodName
        self.editIsCaregiverOnly = note.isCaregiverOnly ?? false
    }

    /// 儲存編輯內容，並同步至遠端伺服器
    /// - Parameter modelContext: 資料操作內容物件（選填）
    @MainActor
    func saveEditedNote(modelContext: ModelContext? = nil) async {
        guard let note = editingNote, canSaveEditedNote else { return }

        let trimmedContent = editNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        note.content = trimmedContent
        note.colorHex = editNoteColor.toHex() ?? "#FFF0CC"
        note.moodName = editSelectedMoodName
        note.isCaregiverOnly = editIsCaregiverOnly

        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        }

        let recordID = note.id
        self.editingNote = nil
        self.selectedDetailNote = nil

        do {
            try await dailyRepo.syncDailyRecord(
                id: recordID,
                content: note.content,
                date: note.date,
                colorHex: note.colorHex,
                sender: note.sender,
                moodName: note.moodName,
                isCaregiverOnly: note.isCaregiverOnly
            )
        } catch {
            AppLog.error("更新紀錄至伺服器失敗: \(error.localizedDescription)")
        }
    }

    /// 刪除便利貼：自記憶體清單中移除並發送伺服器刪除請求
    /// - Parameters:
    ///   - note: 欲刪除的 DailyNote 實體
    ///   - modelContext: 資料操作內容物件（選填）
    @MainActor
    func deleteNote(note: DailyNote, modelContext: ModelContext? = nil) async {
        let noteID = note.id
        notes.removeAll { $0.id == noteID }

        do {
            try await dailyRepo.removeDailyRecord(recordID: noteID)
        } catch {
            AppLog.error("從伺服器刪除便利貼失敗: \(error.localizedDescription)")
        }
    }

    /// 重設新增表單狀態並關閉表單
    func cancelAddingNote() {
        resetSheetState()
    }

    /// 清空新增便利貼表單的所有輸入暫存欄位
    private func resetSheetState() {
        newNoteText = ""
        sheetSelectedMoodName = nil
        showAddNoteSheet = false
    }

    /// 字串格式限制處理（限制最大字數與最大行數）
    /// - Parameters:
    ///   - text: 原始輸入字串
    ///   - maxCharacters: 允許輸入的最大字元數
    ///   - maxLines: 允許輸入的最大行數
    /// - Returns: 符合規範的安全裁剪字串
    private func limitLinesAndLength(text: String, maxCharacters: Int, maxLines: Int) -> String {
        let lines = text.components(separatedBy: "\n")
        if lines.count > maxLines {
            let allowedLines = lines.prefix(maxLines)
            let combinedText = allowedLines.joined(separator: "\n")
            return String(combinedText.prefix(maxCharacters))
        }
        return String(text.prefix(maxCharacters))
    }

    /// 移除過多連續換行符號（將 3 個以上換行壓縮為 2 個）
    /// - Parameter text: 原始輸入字串
    /// - Returns: 整理後的排版字串
    private func cleanExcessiveNewlines(_ text: String) -> String {
        return text.replacingOccurrences(
            of: "(\\n\\s*){3,}",
            with: "\n\n",
            options: .regularExpression
        )
    }

    /// 根據心情中文名稱取得對應的 SF Symbol 圖示名稱
    /// - Parameter name: 心情名稱（開心、平靜、疲憊、不舒服）
    /// - Returns: 對應的 SF Symbol 圖示識別碼字串
    func getMoodIcon(for name: String) -> String {
        switch name {
        case "開心": return "face.smiling"
        case "平靜": return "face.dashed"
        case "疲憊": return "zzz"
        case "不舒服": return "thermometer"
        default: return ""
        }
    }

    /// 依據心情名稱與外觀模式取得對應之色彩
    /// - Parameters:
    ///   - name: 心情中文名稱
    ///   - colorScheme: 系統目前的外觀色彩模式
    /// - Returns: 對應之 Color 實體
    func getMoodColor(for name: String, colorScheme: ColorScheme = .light) -> Color {
        if colorScheme == .dark {
            switch name {
            case "開心": return Color(hex: "E2B08B")
            case "平靜": return Color(hex: "98BFA3")
            case "疲憊": return Color(hex: "93B4CB")
            case "不舒服": return Color(hex: "BEA8C2")
            default: return Color(hex: "94A3B8")
            }
        } else {
            switch name {
            case "開心": return .orange
            case "平靜": return .green
            case "疲憊": return .blue
            case "不舒服": return .purple
            default: return .gray
            }
        }
    }

    /// 根據便利貼之 Hex 色碼與外觀色彩模式計算卡片背景色
    /// - Parameters:
    ///   - hex: 儲存之十六進位色彩字串
    ///   - colorScheme: 系統目前的外觀色彩模式
    /// - Returns: 對應的卡片背景 Color 實體
    func getNoteCardColor(for hex: String, colorScheme: ColorScheme) -> Color {
        let cleanedHex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()

        if colorScheme == .dark {
            switch cleanedHex {
            case "FFF0CC", "FFEEC2", "FFF4D6", "725B3E":
                return Color(hex: "725B3E")
            case "E6F5FF", "E5F5FF", "DDF0FF", "3D566E":
                return Color(hex: "3D566E")
            case "EBFBEB", "E8FAE8", "E2FBE5", "3D5A46":
                return Color(hex: "3D5A46")
            case "FAEBFA", "F9EBF9", "FBE7F2", "69485B":
                return Color(hex: "69485B")
            default:
                return Color(hex: "424A54")
            }
        } else {
            switch cleanedHex {
            case "FFF0CC", "FFEEC2", "FFF4D6", "725B3E":
                return Color(red: 1.0, green: 0.94, blue: 0.8)
            case "E6F5FF", "E5F5FF", "DDF0FF", "3D566E":
                return Color(red: 0.9, green: 0.96, blue: 1.0)
            case "EBFBEB", "E8FAE8", "E2FBE5", "3D5A46":
                return Color(red: 0.92, green: 0.98, blue: 0.93)
            case "FAEBFA", "F9EBF9", "FBE7F2", "69485B":
                return Color(red: 0.98, green: 0.92, blue: 0.95)
            default:
                return Color(hex: hex)
            }
        }
    }

    /// 依據外觀色彩模式提供便利貼表單選色器之色彩陣列
    /// - Parameter colorScheme: 系統目前的外觀色彩模式
    /// - Returns: 供選色之 Color 陣列
    func notePalette(for colorScheme: ColorScheme) -> [Color] {
        if colorScheme == .dark {
            return [
                Color(hex: "725B3E"),
                Color(hex: "3D566E"),
                Color(hex: "3D5A46"),
                Color(hex: "69485B")
            ]
        } else {
            return [
                Color(red: 1.0, green: 0.94, blue: 0.8),
                Color(red: 0.9, green: 0.96, blue: 1.0),
                Color(red: 0.92, green: 0.98, blue: 0.93),
                Color(red: 0.98, green: 0.92, blue: 0.95)
            ]
        }
    }
}
