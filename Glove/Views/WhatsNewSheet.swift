import SwiftUI

struct WhatsNewSheet: View {
    let version: String
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("SteadyHope 更新完成")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(
                        AppTheme.textPrimary(for: colorScheme)
                    )

                Text("版本 \(version) 全新功能上線")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(
                        AppTheme.primary(for: colorScheme)
                    )
            }
            .padding(.top, 28)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    WhatsNewFeatureRow(
                        icon: "lock.shield.fill",
                        iconColor: AppTheme.primary(for: colorScheme),
                        title: "隱私與研究使用告知",
                        description: "首次使用會說明研究原型的用途與限制；App 切換至背景時也會自動以隱私畫面遮蔽健康資訊。"
                    )

                    WhatsNewFeatureRow(
                        icon: "circle.lefthalf.filled",
                        iconColor: AppTheme.accent(for: colorScheme),
                        title: "全新深淺色介面",
                        description: "重新整理全系統主題配色，改善淺色與深色模式下的閱讀與操作體驗。"
                    )

                    WhatsNewFeatureRow(
                        icon: "person.crop.circle.badge.plus",
                        iconColor: Color(hex: "805ad5"),
                        title: "自訂頭貼與帳號功能",
                        description: "現在可以設定自己的個人頭貼，並新增 Email 驗證碼忘記密碼與重設流程。"
                    )

                    WhatsNewFeatureRow(
                        icon: "hand.wave.fill",
                        iconColor: Color(hex: "319795"),
                        title: "手套初始化與控制改善",
                        description: "新增配戴初始化與基準線長設定，並改善 AUTO／MANUAL 模式切換及操作鎖定流程。"
                    )

                    WhatsNewFeatureRow(
                        icon: "chart.xyaxis.line",
                        iconColor: Color(hex: "38a169"),
                        title: "震顫與用藥趨勢對照",
                        description: "改善震顫趨勢資料處理與圖表操作，支援縮放、平移與時間選取，並可對照用藥時間。"
                    )

                    WhatsNewFeatureRow(
                        icon: "checklist",
                        iconColor: Color(hex: "0bc5ea"),
                        title: "評估紀錄管理",
                        description: "每日評估歷史現在可以刪除指定紀錄，並同步更新畫面上的歷史資料。"
                    )

                    WhatsNewFeatureRow(
                        icon: "book.fill",
                        iconColor: AppTheme.accent(for: colorScheme),
                        title: "系統操作指南更新",
                        description: "重新整理操作說明內容，並優先加入帳號與家人心情留言板的實際操作圖片。"
                    )

                    WhatsNewFeatureRow(
                        icon: "wrench.and.screwdriver.fill",
                        iconColor: AppTheme.primary(for: colorScheme),
                        title: "穩定性與效能改善",
                        description: "修正用藥提醒與資料權限問題，並改善震顫分析管線、趨勢同步及資料快取效率。"
                    )
                }
                .padding(.horizontal, 24)
            }

            Spacer(minLength: 10)

            Button(action: onDismiss) {
                Text("開始使用")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.primary(for: colorScheme))
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(AppTheme.cardBackground(for: colorScheme))
    }
}

// 單一功能特色展示列
struct WhatsNewFeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Text(description)
                    .font(.system(size: 12.5))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .lineSpacing(2)
            }
        }
    }
}
