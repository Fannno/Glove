import SwiftUI

/// 專題研究限制與受試者知情同意告知視圖，說明原型限制、安全警語、用藥規範及法規宣告
struct ResearchNoticeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// 標記是否為設定頁面之查閱模式（為 true 時隱藏底部同意與拒絕按鈕）
    var isReviewMode: Bool = true
    var onAcknowledged: (() -> Void)? = nil
    var onDecline: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    noticeCard(
                        title: "1. 研究原型與用途",
                        content: "本版本為專題研究原型，研究內容包含手部動作紀錄及拉線控制。患者震顫辨識、配戴安全性及抑震效果尚未完成驗證，不能據此宣稱適合患者自行配戴或居家使用。提供的紀錄供觀察與溝通參考，不能替代醫師診斷、治療或專業評估。"
                    )

                    noticeCard(
                        title: "2. 不依 App 自行調整用藥",
                        content: "請勿僅依本系統的頻率、強度或圖表，自行停藥、增減劑量或變更服藥時間。服藥前後的圖表差異不能單獨證明藥物療效或病程變化。"
                    )

                    noticeCard(
                        title: "3. 判斷與資料限制",
                        content: "日常動作可能觸發裝置，也可能在出現震顫時未觸發。設計目標是減少漏觸發，但尚不能保證達成。作動標記不等於已確認的震顫事件或抑震成功；未顯示頻率、沒有作動或資料中斷，也不代表一定沒有震顫。"
                    )

                    noticeCard(
                        title: "4. 拉線風險與停止試用",
                        content: "拉線及固定結構可能造成壓迫、疼痛或活動受限。如出現疼痛、麻木、明顯勒痕、皮膚變色或持續拉扯，請立即停止試用，並通知現場負責人依事先確認的程序停機及協助解除。關閉 App、停止命令或切斷電源，不保證拉線會自動鬆開。若不適持續或有明顯受傷，請尋求醫療協助。"
                    )

                    noticeCard(
                        title: "5. 自行填寫的紀錄",
                        content: "活動、服藥時間及備註由使用者提供；未填寫代表資訊未知。圖表需連同實際活動、服藥情況及資料缺口解讀，不能以缺少紀錄推定沒有服藥或沒有症狀。"
                    )

                    noticeCard(
                        title: "6. 權益與資料告知",
                        content: "閱讀本告知不代表放棄任何法定權利（民法第 222 條規定故意或重大過失責任不得預先免除），也不等同同意參加人體研究或所有資料用途。人體研究的參與與退出、資料蒐集及使用範圍，須另有清楚的說明與適用的同意程序。"
                    )

                    HStack {
                        Spacer()
                        Text("適用版本：App v\(AppConfig.appVersion) ｜ 規格基準：2026-09-12 修訂版")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        Spacer()
                    }
                    .padding(.vertical, 2)

                    if !isReviewMode {
                        Button {
                            onAcknowledged?()
                            dismiss()
                        } label: {
                            Text("我已閱讀並了解用途、限制與風險")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppTheme.primary(for: colorScheme))
                                .cornerRadius(12)
                        }
                        .padding(.top, 4)

                        Button {
                            onDecline?()
                            dismiss()
                        } label: {
                            Text("暫不參與 / 離開")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("使用告知與研究限制")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// 建立單一規範與免責聲明卡片元件
    /// - Parameters:
    ///   - title: 條款標題文字
    ///   - content: 條款詳細說明內文
    /// - Returns: 排版完成之聲明卡片視圖
    private func noticeCard(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            Text(content)
                .font(.system(size: 12.5))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .lineSpacing(3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(10)
    }
}
