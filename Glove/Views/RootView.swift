import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var loginVM = LoginViewModel()
    @StateObject private var dataVM = DataViewModel.shared
    @StateObject private var medVM = MedicationViewModel()
    @ObservedObject private var bleVM = BluetoothViewModel.shared
    @StateObject private var symptomVM = SymptomViewModel()
    @StateObject private var vitalsVM = HealthVitalsViewModel()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    /// 版本更新提示彈窗控制、版本持久化鍵值與隱私防護遮罩顯示狀態
    @State private var showWhatsNewSheet: Bool = false
    private let lastSeenVersionKey = "last_seen_app_version"
    @State private var isPrivacyShieldActive: Bool = false

    /// 研究知情同意確認狀態與拒絕退出控制狀態
    @AppStorage("hasAcknowledgedResearchNotice") private var hasAcknowledgedNotice: Bool = false
    @State private var hasDeclinedNotice: Bool = false

    var body: some View {
        ZStack {
            Group {
                if !hasAcknowledgedNotice {
                    if hasDeclinedNotice {
                        declinedNoticeView
                    } else {
                        ResearchNoticeView(
                            isReviewMode: false,
                            onAcknowledged: {
                                hasAcknowledgedNotice = true
                                hasDeclinedNotice = false
                            },
                            onDecline: {
                                hasDeclinedNotice = true
                                showWhatsNewSheet = false
                                loginVM.logout()
                            }
                        )
                    }
                } else if loginVM.isRestoringSession {
                    VStack(spacing: 12) {
                        ProgressView()

                        Text("正在恢復登入狀態...")
                            .font(.subheadline)
                            .foregroundColor(
                                AppTheme.textSecondary(for: colorScheme)
                            )
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )

                } else if loginVM.isAuthenticated {
                    NavigationBarView(
                        loginVM: loginVM,
                        dataVM: dataVM,
                        medVM: medVM,
                        bleVM: bleVM,
                        symptomVM: symptomVM,
                        vitalsVM: vitalsVM
                    )
                } else {
                    LoginView(loginVM: loginVM)
                }
            }
            .id(loginVM.isAuthenticated)
            .animation(.easeInOut(duration: 0.3), value: loginVM.isAuthenticated)

            if isPrivacyShieldActive {
                PrivacyBlurOverlay()
                    .transition(.opacity)
                    .zIndex(999)
            }
        }
        .background(AppTheme.background(for: colorScheme).ignoresSafeArea())
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .inactive, .background:
                isPrivacyShieldActive = true
            case .active:
                withAnimation(.easeOut(duration: 0.2)) {
                    isPrivacyShieldActive = false
                }
            @unknown default:
                break
            }
        }
        .onAppear {
            if hasAcknowledgedNotice {
                prepareAcknowledgedSession()
            }
        }
        .task(id: hasAcknowledgedNotice) {
            guard hasAcknowledgedNotice else { return }

            await loginVM.restoreSession(
                modelContext: modelContext
            )
        }
        .onChange(of: hasAcknowledgedNotice) { _, acknowledged in
            if acknowledged {
                prepareAcknowledgedSession()
            } else {
                showWhatsNewSheet = false
            }
        }
        .sheet(isPresented: $showWhatsNewSheet) {
            WhatsNewSheet(
                version: AppConfig.appVersion,
                onDismiss: {
                    UserDefaults.standard.set(AppConfig.appVersion, forKey: lastSeenVersionKey)
                    showWhatsNewSheet = false
                }
            )
        }
    }

    /// 使用者拒絕知情同意時呈現之鎖定提示畫面
    private var declinedNoticeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "pause.circle")
                .font(.system(size: 52))
                .foregroundColor(AppTheme.primary(for: colorScheme))

            Text("已停止使用")
                .font(.title2.bold())
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text("您尚未確認使用告知，目前無法進入登入與主功能。您可以使用手機的主畫面手勢或主畫面按鈕離開 App，或重新閱讀告知後繼續。")
                .font(.body)
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)

            Button {
                hasDeclinedNotice = false
            } label: {
                Text("重新閱讀使用告知")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.primary(for: colorScheme))
                    .cornerRadius(12)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 使用者完成告知確認後啟動之權限請求與版本比對排程
    private func prepareAcknowledgedSession() {
        NotificationScheduler.shared.requestAuthorization()
        checkVersionUpdate()
    }

    /// 比對目前 App 版本與上次記錄版本，決定是否彈出新功能介紹工作表
    private func checkVersionUpdate() {
        let lastSeenVersion = UserDefaults.standard.string(forKey: lastSeenVersionKey)
        if lastSeenVersion != AppConfig.appVersion {
            showWhatsNewSheet = true
        }
    }
}

/// 當應用程式進入後台或未作用狀態時覆蓋於畫面上的隱私防護遮罩視圖
struct PrivacyBlurOverlay: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppTheme.background(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Image("SteadyHopeLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160)

                Text("SteadyHope")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(AppTheme.textPrimary(for: colorScheme))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        }
    }
}
