import SwiftUI

struct VersionSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [String]
}

struct VersionItem: Identifiable {
    let id = UUID()
    let version: String
    let releaseDate: String
    let isLatest: Bool
    let sections: [VersionSection]
}

struct VersionHistoryView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let history: [VersionItem] = [
        VersionItem(
            version: "1.0.1",
            releaseDate: "2026 年 10 月",
            isLatest: true,
            sections: [
                VersionSection(
                    title: "介面、帳號與隱私",
                    items: [
                        "新增全域 AppTheme，統一淺色與深色模式的介面配色",
                        "新增自訂使用者頭貼上傳與個人資料圖片呈現",
                        "新增忘記密碼功能，可透過 Email 六位數驗證碼重新設定密碼",
                        "新增專題研究用途、系統限制與使用風險告知流程",
                        "新增背景隱私遮罩，App 進入背景或切換畫面時自動隱藏健康資訊",
                        "統一佩戴者與照護者系統稱謂為 Hoper 與 Steadyer"
                    ]
                ),
                VersionSection(
                    title: "智慧手套與震顫分析",
                    items: [
                        "新增手套配戴初始化校準與基準線長設定流程",
                        "改善 AUTO／MANUAL 模式切換等待狀態與校準操作鎖定機制",
                        "依最新版分析規格調整震顫分析時序、特徵計算與資料格式",
                        "改善震顫趨勢資料同步，加入資料切片與快取機制以提升圖表處理效率",
                        "優化分析管線綁定與資料更新流程，避免重複處理"
                    ]
                ),
                VersionSection(
                    title: "用藥、評估與看診報告",
                    items: [
                        "新增每日評估紀錄刪除功能，刪除後同步更新歷史資料",
                        "改善用藥與震顫趨勢對照圖，支援縮放、平移與時間軸選取",
                        "PDF 報告的 RMS 趨勢加入用藥時間標記，協助查看服藥時間與震顫資料的時間關係",
                        "新增看診前準備備忘同步與遠端儲存功能",
                        "修復已刪除或變更之用藥排程仍可能觸發通知的問題"
                    ]
                ),
                VersionSection(
                    title: "家庭照護與操作體驗",
                    items: [
                        "改善心情留言板發布者識別與操作權限判斷",
                        "調整便利貼資料狀態管理與同步流程",
                        "更新關於我們頁面的系統主題配色與研究原型說明",
                        "擴充系統操作指南，目前已加入帳號與家人心情留言板的實際操作圖片",
                        "其他操作指南圖片保留預留區塊，後續將持續補充"
                    ]
                )
            ]
        ),
        VersionItem(
            version: "1.0.0",
            releaseDate: "2026 年 9 月",
            isLatest: false,
            sections: [
                VersionSection(
                    title: "智慧硬體與震顫分析",
                    items: [
                        "支援低功耗藍牙手套連線、電量偵測與馬達抑震狀態監控",
                        "即時運算 RMS 震動強度與 PSD 頻率特徵圖表",
                        "手套機械長度微調控制（-5cm 至 +5cm）",
                        "震顫分析紀錄與生活情境標籤管理"
                    ]
                ),
                VersionSection(
                    title: "處方排程與日常健康",
                    items: [
                        "常規處方多時段排程與服藥紀錄提醒",
                        "貼片用藥部位、膚況記錄與按壓引導",
                        "日常表徵影音紀錄",
                        "記錄血壓、血糖、體溫、體重、睡眠與飲食等生理資訊"
                    ]
                ),
                VersionSection(
                    title: "自我量表與家庭照護",
                    items: [
                        "動作障礙自我評估與歷史紀錄",
                        "Hoper 與 Steadyer 六位數配對碼連動與權限管理",
                        "家人心情留言板與照護者專屬留言"
                    ]
                ),
                VersionSection(
                    title: "AI 與看診報告",
                    items: [
                        "AI 健康與照護對話功能",
                        "支援文字與日期搜尋歷史對話",
                        "看診前準備與資料摘要",
                        "PDF 報告匯出，包含震顫、用藥、健康與評估資料"
                    ]
                )
            ]
        )
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 16) {
                ForEach(history) { item in
                    versionCard(item)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(AppTheme.background(for: colorScheme))
        .navigationTitle("版本紀錄")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func versionCard(_ item: VersionItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 8) {
                Text("Version \(item.version)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                if item.isLatest {
                    Text("最新")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AppTheme.primary(for: colorScheme).opacity(0.1))
                        .clipShape(Capsule())
                }

                Spacer()

                Text(item.releaseDate)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(item.sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                        ForEach(section.items, id: \.self) { change in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(AppTheme.textSecondary(for: colorScheme).opacity(0.45))
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 7)

                                Text(change)
                                    .font(.system(size: 13.5))
                                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                    .lineSpacing(3)
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(14)
    }
}
