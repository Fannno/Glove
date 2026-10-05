import Foundation
import SwiftUI

struct AboutUsView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                headerSection
                versionCard
                introCard
                featuresCard
                disclaimerCard
                contactCard
                footerSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(AppTheme.background(for: colorScheme))
        .navigationTitle("關於我們")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image("SteadyHopeLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            
            VStack(spacing: 4) {
                Text("SteadyHope")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.primary(for: colorScheme))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var versionCard: some View {
        NavigationLink(destination: VersionHistoryView()) {
            HStack {
                Text("版本紀錄")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                Spacer()

                Text("v\(AppConfig.appVersion)")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme).opacity(0.6))

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme).opacity(0.35))
            }
        }
        .buttonStyle(.plain)
        .modifier(CardModifier())
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("系統簡介")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppTheme.primary(for: colorScheme))

            Text(
                """
                SteadyHope 是專題研究原型，結合穿戴式手套與行動端應用程式，記錄手部動作訊號與日常健康資料，協助使用者及照護者進行居家觀察與回診溝通。

                系統整合低功耗藍牙傳輸、馬達控制狀態、連續震顫強度（RMS）與頻譜（PSD）特徵分析、用藥紀錄、突發表徵紀錄，以及自我評估量表。

                系統亦提供 AI 回診前摘要與 A4 格式報告匯出，將不同來源的紀錄整理成較容易閱讀的時間範圍資料，供日常觀察與醫病溝通參考。

                本系統目前仍屬研究原型，患者震顫辨識、配戴安全性及抑震效果尚未完成完整驗證。
                """
            )
            .font(.system(size: 13.5))
            .foregroundColor(AppTheme.textPrimary(for: colorScheme).opacity(0.75))
            .lineSpacing(5)
        }
        .modifier(CardModifier())
    }

    private var featuresCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("主要特色")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppTheme.primary(for: colorScheme))

            VStack(spacing: 12) {
                featureRow(
                    title: "智慧手套與即時震顫特徵分析",
                    desc: "透過低功耗藍牙取得角速度資料，支援馬達控制狀態記錄，並分析 4–6 Hz RMS 強度與 3–7 Hz 頻率特徵。"
                )

                Divider()

                featureRow(
                    title: "彈性處方排程與穿皮貼片追蹤",
                    desc: "支援多時段用藥排程與紀錄，以及穿皮貼片輪替提醒、部位紀錄與使用流程引導。"
                )

                Divider()

                featureRow(
                    title: "日常表徵影音牆與生理徵象監控",
                    desc: "支援文字、相片及影片相關表徵紀錄，同時整理血壓、血糖、體溫、體重等生理數值。"
                )

                Divider()

                featureRow(
                    title: "動作障礙自我評估量表",
                    desc: "提供不同形式的自我評估紀錄，整理情緒、日常生活與動作相關項目的填寫結果，方便進行時間趨勢比較。"
                )

                Divider()

                featureRow(
                    title: "家庭雙向照護連動與心情便利貼",
                    desc: "支援配對碼連動、照護者權限控管與心情留言板，並提供私密備忘功能。"
                )

                Divider()

                featureRow(
                    title: "AI 回診前摘要 PDF 報告",
                    desc: "支援關鍵字與日期範圍整理，並匯出包含 RMS 趨勢、PSD 頻率分布及日常紀錄的 A4 格式報告。"
                )
            }
        }
        .modifier(CardModifier())
    }

    private func featureRow(title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text(desc)
                .font(.system(size: 12.5))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme).opacity(0.75))
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var disclaimerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("資料來源與免責聲明")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppTheme.primary(for: colorScheme))

            VStack(spacing: 12) {
                disclaimerSection(
                    title: "用藥清單與衛教資訊來源",
                    content: "本系統內建之用藥清單、藥品資料庫及相關衛教內容，主要源自「巴金森寶典」應用程式。該資料庫由臺大醫院巴金森症暨動作障礙中心，以及台灣巴金森之友協會共同合作開發，相關內容經醫療專業團隊審定與維護。"
                )

                Divider()

                disclaimerSection(
                    title: "症狀評估量表架構",
                    content: "本系統使用之日常症狀評估量表，其原始架構與評分標準參考自「台灣動作障礙學會」所發布之學術衛教資料，並融合「國際巴金森與動作障礙學會（MDS）」之臨床評估指標。資料經結構化與數位化整理，旨在協助使用者與照護者進行居家日常狀態之客觀紀錄與趨勢比對。"
                )

                Divider()

                disclaimerSection(
                    title: "研究原型限制",
                    content: "本系統目前為專題研究原型。患者震顫辨識、裝置配戴安全性、控制反應及抑震效果尚未完成完整驗證。日常動作可能造成額外裝置作動，也可能在出現震顫時未觸發。"
                )

                Divider()

                disclaimerSection(
                    title: "資料與醫療使用限制",
                    content: "本系統所提供之震顫特徵、生理數值、量表結果及 AI 摘要，僅供日常健康管理與門診溝通參考，不可作為醫療診斷、疾病嚴重度判定或自行調整藥物的依據。服藥前後的圖表差異亦不能單獨證明藥物療效或病程變化。"
                )
            }
        }
        .modifier(CardModifier())
    }

    private func disclaimerSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text(content)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme).opacity(0.75))
                .lineSpacing(4)
        }
    }

    private var contactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("聯絡我們")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppTheme.primary(for: colorScheme))

            Text("淡江大學資訊管理學系")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text("電話：02-2621-5656")
                .font(.system(size: 13.5))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme).opacity(0.75))
                .textSelection(.enabled)

            Text("電子信箱：tkumisassistant@gmail.com")
                .font(.system(size: 13.5))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme).opacity(0.75))
                .textSelection(.enabled)

            (
                Text("地址：新北市淡水區英專路151號")
                + Text("商管大樓11樓 (B1111)").bold()
            )
                .font(.system(size: 13.5))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme).opacity(0.75))
                .textSelection(.enabled)
        }
        .modifier(CardModifier())
    }

    private var footerSection: some View {
        VStack(spacing: 4) {
            Text("SteadyHope")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme).opacity(0.6))

            Text("All Rights Reserved © 2026")
                .font(.system(size: 10))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme).opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct CardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground(for: colorScheme))
            .cornerRadius(12)
            .softCardShadow()
    }
}
