import SwiftUI

struct GloveInitializationSheet: View {
    @ObservedObject private var bleVM = BluetoothViewModel.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// 初始化收緊量（cm）
    @State private var calibrationTakeUpCm: Double = BluetoothViewModel.initialTakeUpDefaultCm
    @State private var isAdjusting: Bool = false
    @State private var isFinishingInitialization: Bool = false

    private var controlsLocked: Bool {
        isAdjusting || bleVM.isInitializationSequencePending
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "hand.raised.fill")
                                .foregroundColor(AppTheme.primary(for: colorScheme))
                            Text("手套初始配戴校準")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        }

                        Text("進入此畫面後會先暫停自動抑震。請戴妥手套並保持手指自然放鬆，再用下方滑桿調整初始收緊量，最多 14 cm。放開滑桿後，手套會自動微調至指定位置。")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .lineSpacing(4)
                    }
                    .padding(18)
                    .background(AppTheme.cardBackground(for: colorScheme))
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)

                    VStack(spacing: 20) {
                        HStack {
                            Text("初始收緊量")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            Spacer()

                            Text(String(format: "%.1f cm", calibrationTakeUpCm))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(AppTheme.primary(for: colorScheme))
                        }

                        Slider(
                            value: $calibrationTakeUpCm,
                            in: BluetoothViewModel.initialTakeUpMinCm...BluetoothViewModel.initialTakeUpMaxCm,
                            step: 0.5,
                            onEditingChanged: { editing in
                                isAdjusting = editing
                                if !editing {
                                    _ = bleVM.sendInitialTakeUpCm(calibrationTakeUpCm)
                                }
                            }
                        )
                        .accentColor(AppTheme.primary(for: colorScheme))
                        .disabled(bleVM.isInitializationSequencePending)

                        HStack {
                            Text("0 cm")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            Spacer()
                            Text("最多 14 cm")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))
                        }

                        Text("目前基準線長：\(Int(BluetoothViewModel.initialCableHomeMm - calibrationTakeUpCm * 10.0)) mm")
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    }
                    .padding(20)
                    .background(AppTheme.cardBackground(for: colorScheme))
                    .cornerRadius(18)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, y: 3)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(statusTitle)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(AppTheme.accent(for: colorScheme))

                        Text(statusDescription)
                            .font(.system(size: 11.5))
                            .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                            .lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(AppTheme.accent(for: colorScheme).opacity(0.08))
                    .cornerRadius(12)

                    Spacer()

                    Button(action: {
                        confirmComfortablePosition()
                    }) {
                        HStack(spacing: 8) {
                            if bleVM.isInitializationSequencePending {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                            }

                            Text(
                                bleVM.isInitializationSequencePending
                                    ? "正在套用設定並啟用 AUTO..."
                                    : "完成並啟用自動抑震"
                            )
                            .font(.system(size: 16, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppTheme.primary(for: colorScheme))
                        .foregroundColor(.white)
                        .cornerRadius(14)
                        .shadow(color: AppTheme.primary(for: colorScheme).opacity(0.3), radius: 8, y: 4)
                    }
                    .disabled(controlsLocked)
                    .opacity(controlsLocked ? 0.65 : 1.0)
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("手套配戴初始化")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        bleVM.cancelInitialCalibrationSequence()
                        bleVM.setAutomaticSuppression(false)
                        dismiss()
                    }
                    .disabled(bleVM.isInitializationSequencePending)
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                }
            }
            .onAppear {
                bleVM.resetInitializationSequenceFeedback()
                calibrationTakeUpCm = min(
                    max(bleVM.initialTakeUpCm, BluetoothViewModel.initialTakeUpMinCm),
                    BluetoothViewModel.initialTakeUpMaxCm
                )
                bleVM.setAutomaticSuppression(false)
            }
            .onChange(of: bleVM.initializationSequenceSucceeded) { _, succeeded in
                guard succeeded, isFinishingInitialization else { return }
                isFinishingInitialization = false
                dismiss()
            }
            .alert(
                "初始化未完成",
                isPresented: Binding(
                    get: { bleVM.initializationSequenceErrorMessage != nil },
                    set: { newValue in
                        if !newValue {
                            bleVM.clearInitializationSequenceError()
                        }
                    }
                )
            ) {
                Button("確定", role: .cancel) {
                    bleVM.clearInitializationSequenceError()
                    isFinishingInitialization = false
                }
            } message: {
                Text(bleVM.initializationSequenceErrorMessage ?? "未知錯誤")
            }
        }
    }

    private var statusTitle: String {
        if bleVM.isInitializationSequencePending {
            if bleVM.isInitialLengthCommandPending {
                return "正在確認手套鬆緊度"
            }
            if bleVM.isAutomaticModeCommandPending {
                return "正在切換至 AUTO 模式"
            }
            return "正在完成初始化"
        }

        if bleVM.isInitialLengthCommandPending {
            return "正在套用長度設定"
        }

        return "目前模式：MANUAL 微調"
    }

    private var statusDescription: String {
        if bleVM.isInitializationSequencePending {
            return "系統正在確認手套的初始位置設定，確認完成後將自動切換至 AUTO 模式，請稍候。"
        }

        if bleVM.isInitialLengthCommandPending {
            return "手套正在調整至指定鬆緊度，請保持放鬆稍候片刻。"
        }

        return "調整滑桿時維持 MANUAL 模式。調整至舒適位置後，點擊下方按鈕即可完成校準並切換至 AUTO 模式。"
    }

    private func confirmComfortablePosition() {
        isFinishingInitialization = true
        let started = bleVM.confirmInitialTakeUpAndEnableAuto(calibrationTakeUpCm)

        if !started {
            isFinishingInitialization = false
        }
    }
}
