import SwiftUI
import UIKit

/// 操作步驟資料模型
struct GuideStep: Identifiable {
    let id = UUID()
    let stepNumber: Int
    let title: String
    let description: String
    let imageAssetName: String?
    let placeholderPrompt: String
}

/// 指南單元項目
struct GuideTopic: Identifiable {
    let id = UUID()
    let title: String
    let summary: String
    let systemIcon: String
    let steps: [GuideStep]
}

/// 指南核心分類
enum GuideCategory: String, CaseIterable, Identifiable {
    case all = "全部指南"
    case account = "帳號與身分"
    case homeAndGlove = "手套連線與日常"
    case tremor = "震顫分析與紀錄"
    case DailyBoard = "家人心情便利貼"
    case medication = "用藥與貼片管理"
    case healthAndAssessment = "健康自評與體徵"
    case reminderAndReport = "提醒設定與就診報告"
    case familyShare = "家屬互相連結"
    case aiAssistant = "隨身健康小助手"

    var id: String { self.rawValue }

    var iconName: String {
        switch self {
        case .all: return "list.bullet.rectangle"
        case .account: return "person.crop.circle"
        case .homeAndGlove: return "hand.wave.fill"
        case .tremor: return "waveform.path.ecg"
        case .DailyBoard: return "note.text"
        case .medication: return "pills.fill"
        case .healthAndAssessment: return "heart.text.square.fill"
        case .reminderAndReport: return "doc.text.fill"
        case .familyShare: return "person.2.fill"
        case .aiAssistant: return "sparkles"
        }
    }
}

/// 使用者指南資料儲存庫，維護全系統靜態操作指引內容
struct GuideRepository {
    /// 依分類整理之指南單元對照字典
    static let topics: [GuideCategory: [GuideTopic]] = [
        .account: [
            GuideTopic(
                title: "如何登入與註冊帳號",
                summary: "依照 Hoper（佩戴者）或 Steadyer（照護者）身分建立帳號，保障個人資料與健康紀錄安全。",
                systemIcon: "person.badge.shield.checkmark",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "登入個人帳號與防護",
                        description: "打開 App，輸入註冊信箱與密碼後按「登入」。若登入狀態失效或帳號於其他裝置登入而收到登出提示，請重新登入。",
                        imageAssetName: "guide_login_screen",
                        placeholderPrompt: "預留畫面：登入畫面，包含信箱、密碼輸入框與安全提示"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "選擇適合的身分註冊",
                        description: "初次使用請點選註冊，並選擇「Hoper（佩戴者）」或「Steadyer（照護者）」身分。若您是 Hoper，表單會多出一欄「疾病階段」供您填寫，幫助系統更精確掌握您的病況進程。",
                        imageAssetName: "guide_register_role",
                        placeholderPrompt: "預留畫面：註冊頁面切換 Hoper 與 Steadyer 身分"
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "填寫基本資料與密碼設定",
                        description: "依表單填入姓名、信箱、生日、性別與密碼。註冊密碼至少 8 個字元，需同時包含大寫與小寫英文字母，並再次輸入相同密碼。可自行加入數字或符號提高密碼強度。",
                        imageAssetName: "guide_register_fields",
                        placeholderPrompt: "預留畫面：基本資料填寫表單與密碼檢核提示"
                    )
                ]
            ),
            GuideTopic(
                title: "忘記密碼與重設流程",
                summary: "若忘記登入密碼，可由登入頁發送 6 位數安全驗證碼至註冊信箱，快速驗證身分並設定新密碼。",
                systemIcon: "key.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "點選登入頁「忘記密碼？」",
                        description: "在登入畫面中，點擊「登入」按鈕下方的「忘記密碼？」文字連結，開啟密碼重設流程彈窗。",
                        imageAssetName: "guide_forgot_password_step1",
                        placeholderPrompt: "預留畫面：登入頁「忘記密碼？」文字連結按鈕"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "輸入註冊信箱並發送驗證碼",
                        description: "在第一頁「輸入信箱」頁面中填入您註冊時使用的電子信箱，點擊「發送驗證碼」，系統將寄送一組 6 位數重設代碼至您的信箱。",
                        imageAssetName: "guide_forgot_password_step2",
                        placeholderPrompt: "預留畫面：輸入信箱與發送驗證碼介面"
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "輸入驗證碼並設定新密碼",
                        description: "前往信箱查收 6 位數代碼後返回 App，於第二頁「驗證並重設」頁面填入驗證碼、新密碼與確認新密碼（密碼需至少 8 碼且包含大小寫英文字母），點擊「確認重設密碼」即可完成並重新登入。",
                        imageAssetName: "guide_forgot_password_step3",
                        placeholderPrompt: "預留畫面：輸入驗證碼、新密碼與確認重設密碼表單"
                    )
                ]
            ),
            GuideTopic(
                title: "修改個人資料、頭貼與密碼",
                summary: "隨時更換個人專屬頭貼、更新疾病階段與基本資料，或重設安全密碼。",
                systemIcon: "person.crop.circle.badge.checkmark",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "由側邊選單進入個人設定",
                        description: "點開左上方側邊選單，點擊最頂部的「個人帳號卡片（顯示姓名、身分與右箭頭處）」，即可進入個人資料編輯頁面。",
                        imageAssetName: "guide_profile_entry",
                        placeholderPrompt: "預留畫面：側邊選單頂部點擊個人帳號卡片之進入點"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "更換頭貼與修改基本資料",
                        description: "點擊頭貼右下角的相機圖示可從相簿上傳新照片。在「基本資料」區可修改姓名，點選性別按鈕（男／女／其他），選取疾病進程分期（未知／初期／中期／後期），並設定出生日期。",
                        imageAssetName: "guide_profile_edit",
                        placeholderPrompt: "預留畫面：頭貼相機圖示與姓名、性別、疾病階段填寫表單"
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "變更安全密碼與儲存修改",
                        description: "若要更換密碼，請於「修改密碼」區依序填入目前舊密碼、至少 6 位字元之新密碼與確認新密碼（若不變更請保持留空）；若忘記目前舊密碼，亦可點擊該區塊下方的「忘記密碼？」透過信箱驗證碼直接重設。確認無誤後點擊底部「儲存修改」按鈕完成更新。",
                        imageAssetName: "guide_profile_password",
                        placeholderPrompt: "預留畫面：修改密碼輸入欄位、「忘記密碼？」連結與底部「儲存修改」按鈕"
                    )
                ]
            )
        ],
        .homeAndGlove: [
            GuideTopic(
                title: "認識首頁資訊與今日用藥紀錄",
                summary: "查看已儲存的看病前準備、手套狀態、上次抖動時間與今日服藥紀錄。",
                systemIcon: "house.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "看病前準備與狀態卡片",
                        description: "首頁提供「看病前準備」，顯示已儲存的就診準備內容。中間卡片顯示手套電量與上次抖動時間；點擊電量前往手套設定，點擊時間前往震顫分析頁。就診準備需在匯出流程按「預覽 PDF 報告內容」後才完成儲存與同步。",
                        imageAssetName: "guide_home_header",
                        placeholderPrompt: "預留畫面：首頁頂部看病準備卡片與中間電量、發作時間看板"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "Steadyer（照護者）專屬視角",
                        description: "如果您是 Steadyer，首頁中間卡片會自動切換為顯示「當前所關心的 Hoper 姓名」，讓家庭照護者隨時確認正在瀏覽哪一位長輩的日常健康狀況。",
                        imageAssetName: "guide_home_caregiver",
                        placeholderPrompt: "預留畫面：Steadyer 視角首頁，顯示被照護者姓名卡片"
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "查看今天已登記的服藥紀錄",
                        description: "首頁「今日用藥資料」顯示今天已登記的服藥紀錄，包含時間、藥名及劑量；沒有紀錄時顯示「目前尚無資料」。點擊整張卡片可前往健康與用藥管理，再切換所需分頁。這張卡片不是今日尚待服用的排程清單。",
                        imageAssetName: "guide_home_med_today",
                        placeholderPrompt: "預留畫面：首頁下方今日用藥清單快捷區塊"
                    )
                ]
            ),
            GuideTopic(
                title: "手套連線與收線長度微調",
                summary: "連線後查看電量與馬達狀態，使用滑桿或手動輸入調整相對線長。",
                systemIcon: "hand.wave.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "建立低功耗藍牙連線",
                        description: "先開啟手套電源與手機藍牙，並將手機靠近手套。在手套設定頁依畫面按鈕開始搜尋及連線，確認顯示「手套已連線」。若未成功，確認電源、距離與藍牙授權後再試；已連線時可按「中斷連線」。",
                        imageAssetName: "guide_glove_connect",
                        placeholderPrompt: "預留畫面：手套搜尋動畫與系統藍牙開啟引導提示"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "查看手套狀態與微調線長",
                        description: "連線後可查看電量與馬達狀態。「收線長度微調」調整的是相對基準的線長，不是直接設定抑震力道。向左拉緊、向右放鬆，範圍 −50～＋50 mm，以 5 mm 為單位；也可手動輸入目標值並按「確定」。馬達作用中會暫停微調，請等待待命狀態。",
                        imageAssetName: "guide_glove_slider",
                        placeholderPrompt: "預留畫面：手套連線資訊、電量與收線長度微調"
                    )
                ]
            ),
            GuideTopic(
                title: "自動抑震與配戴初始化",
                summary: "戴妥手套後調整初始收緊量，確認舒適再啟用自動抑震。",
                systemIcon: "gearshape.arrow.triangle.2.circlepath",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "切換自動抑制模式",
                        description: "在「抑震控制模式」查看目前為 AUTO 或 MANUAL。按「暫停自動抑震並進入微調」可暫停自動控制；需要恢復時按「啟用自動抑震」。模式與馬達命令狀態用於了解裝置運作，不代表已確認抑震效果。",
                        imageAssetName: "guide_glove_auto_mode",
                        placeholderPrompt: "預留畫面：手套設定面板中的自動抑制切換開關"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "配戴後調整初始收緊量",
                        description: "點選「初始化手套配戴長度」。進入後會先暫停自動抑震；請戴妥手套並讓手指自然放鬆，再調整 0～14 cm 的初始收緊量。放開滑桿後會送出長度調整。確認舒適後按「完成並啟用自動抑震」；若按「取消」，會維持手動模式，不會自動恢復抑震。",
                        imageAssetName: "guide_glove_calibrate",
                        placeholderPrompt: "預留畫面：初始收緊量滑桿與完成並啟用自動抑震按鈕"
                    )
                ]
            )
        ],
        .tremor: [
            GuideTopic(
                title: "看懂震動強度圖表與分析紀錄",
                summary: "查看指定頻帶的強度走勢，使用縮放、時間定位與紀錄連動。",
                systemIcon: "waveform.path.ecg",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "查看震動頻率與均方根強度",
                        description: "上方顯示主要震動頻率（Hz）與震動強度 RMS（deg/s）。RMS 是 4–6 Hz 頻帶內的角速度訊號強度；主要頻率則在 3–7 Hz 搜尋，並需通過可信度條件。點擊問號可查看說明，數值不能直接當作疾病嚴重度。",
                        imageAssetName: "guide_tremor_metrics",
                        placeholderPrompt: "預留畫面：上方震動頻率與 RMS 強度卡片及說明彈窗"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "動作分析紀錄與圖表連動",
                        description: "圖上的橘點是可選取的動作分析紀錄，選取後以紅點標示，並連動下方對應卡片。馬達命令作用區間與分析紀錄是不同資訊；這些標記不等於已完成佩戴者發作起迄判定，也不能單獨用來判定抑震成功。",
                        imageAssetName: "guide_tremor_dots",
                        placeholderPrompt: "預留畫面：折線圖中橘點轉為紅點及連動卡片高亮"
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "手勢平移與雙指縮放",
                        description: "您可以透過單指左右滑動檢視不同時間段，或是透過雙指放大縮小時間軸，細緻觀察單次發作的起伏特徵。",
                        imageAssetName: "guide_tremor_gesture",
                        placeholderPrompt: "預留畫面：圖表雙指縮放與時間軸水平拖曳示意圖"
                    )
                ]
            ),
            GuideTopic(
                title: "補填動作情境與查看頻譜",
                summary: "為分析紀錄補充生活情境及影像，切換 RMS 走勢與 PSD 頻率分佈。",
                systemIcon: "tag.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "選擇活動標籤與附加影音",
                        description: "展開事件卡片後，可勾選發作當下進行的動作（如吃飯、喝水、寫字、走路等）或輸入備註，並支援附加本機相片或影片供回診重現情境。",
                        imageAssetName: "guide_event_edit",
                        placeholderPrompt: "預留畫面：展開事件卡片填寫情境活動與附加影像"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "唯讀鎖定與修改取消機制",
                        description: "儲存成功後，卡片會顯示已存的情境與影像；點擊影像可放大。需補充或修改時，按「補充生活情境與照片」，修改後按「儲存標籤紀錄」。按「取消」放棄本次未儲存修改；儲存失敗時請依畫面提示重試。",
                        imageAssetName: "guide_event_save",
                        placeholderPrompt: "預留畫面：事件卡片唯讀輪播、編輯與取消修改按鈕"
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "檢視功率譜密度 (PSD) 頻譜",
                        description: "展開紀錄卡片，可切換「強度走勢 (RMS)」與「頻率分佈 (PSD)」。RMS 頁顯示該筆紀錄前後 3 秒的強度變化；PSD 頁顯示頻率功率分佈。主要頻率搜尋範圍為 3–7 Hz，強度計算頻帶為 4–6 Hz，供日常觀察與回診溝通參考。",
                        imageAssetName: "guide_event_freq_chart",
                        placeholderPrompt: "預留畫面：卡片下方 PSD 功率譜密度頻率圖表"
                    )
                ]
            ),
            GuideTopic(
                title: "未標記事件提醒與時間快轉",
                summary: "快速補齊過往發作情境，並利用時間選取器精確定位波形時刻。",
                systemIcon: "clock.arrow.circlepath",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "過往未標記事件警示橫幅",
                        description: "若有過往動作紀錄尚未補填情境，畫面會顯示「歷史紀錄待補填提醒」。按「前往補填」可切換日期並定位紀錄。關閉時可選「三天內不提醒」或「不再提醒這批紀錄」；後者只忽略目前這批舊紀錄，之後的新紀錄仍會提醒。",
                        imageAssetName: "guide_tremor_unlabeled_banner",
                        placeholderPrompt: "預留畫面：圖表上方橘色未標記提醒橫幅與暫緩彈窗"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "指定時間點精確跳轉",
                        description: "欲檢視特定時間（如昨日 14:30）的連續波形時，點選時間選取器指定時分，圖表軸線便會立即滾動至該時刻，不需費力來回滑動尋找。",
                        imageAssetName: "guide_tremor_time_picker",
                        placeholderPrompt: "預留畫面：圖表時間選取器彈窗與波形快速跳轉"
                    )
                ]
            ),
            GuideTopic(
                title: "長輩友善：簡易模式",
                summary: "以較大的指標與狀態文字閱讀重點，並保留分析紀錄供補填情境。",
                systemIcon: "eyeglasses",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "一鍵切換簡易檢視",
                        description: "在日期附近的模式開關切換「簡易模式」或「標準模式」。簡易模式用較大的指標與文字呈現狀態，隱藏主走勢圖，但仍保留下方動作分析紀錄，方便補填情境。",
                        imageAssetName: "guide_simple_mode_view",
                        placeholderPrompt: "預留畫面：大字體、純文字指標的簡易模式主介面"
                    )
                ]
            ),
            GuideTopic(
                title: "有 RMS，但主要頻率顯示「--」",
                summary: "區分訊號強度、主要頻率與資料不足。",
                systemIcon: "questionmark.circle",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "了解「--」的意思",
                        description: "主要頻率顯示「--」，可能是資料不足、訊號中斷，或未通過頻率可信度條件，不代表一定沒有抖動。即使 RMS 仍有數值，也可能沒有可可靠回報的主要頻率。",
                        imageAssetName: nil,
                        placeholderPrompt: ""
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "先確認日期與連線",
                        description: "確認目前選取的日期、時間與紀錄。檢視即時資料時請確認手套已連線；歷史圖表沒有資料時，可改選有紀錄的日期。不要將無資料直接當作強度為零。",
                        imageAssetName: nil,
                        placeholderPrompt: ""
                    )
                ]
            )
        ],
        .DailyBoard: [
            GuideTopic(
                title: "瀏覽家人溫暖留言",
                summary: "透過日期篩選歷史留言，檢視家人與佩戴者之間的溫馨互動與私密備忘隔離。",
                systemIcon: "note.text",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "挑選日期與手動刷新",
                        description: "頂部日期選擇器可指定瀏覽特定日期的留言；點擊右上角重新整理按鈕，可即時載入最新同步的家庭便利貼。在「今天心情」區塊中，會以橫向卡片列出當天記錄的多筆心情（如開心、平靜、疲憊、不舒服等）與對應時間，方便快速回顧一日狀態。",
                        imageAssetName: "guide_mood_date_refresh",
                        placeholderPrompt: "預留畫面：頂部日期切換選單與手動整理按鈕"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "【佩戴者視角】瀏覽溫馨便利貼",
                        description: "如果您是 Hoper（佩戴者），看板上會顯示家人與自己所留下的溫馨留言。若發布時有選擇心情圖示，卡片上就會清晰標示該心情與發布時間。",
                        imageAssetName: "guide_mood_cards_hoper",
                        placeholderPrompt: "預留畫面：Hoper 端一般公開彩色便利貼看板"
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "【照護者視角】識別帶有鎖頭的私密備忘",
                        description: "如果您是 Steadyer（照護者），在「全部留言」分頁中能同時查看所有公開留言與私密便利貼。私密卡片右上角會標註「鎖頭 家屬」，在 Hoper 端則會全面隱藏以保留照護隱私。",
                        imageAssetName: "guide_mood_cards_steadyer",
                        placeholderPrompt: "預留畫面：Steadyer 端全部留言看板與鎖頭標示"
                    ),
                    GuideStep(
                        stepNumber: 4,
                        title: "【照護者視角】一鍵篩選僅限家屬查看",
                        description: "點擊頂部的「僅限家屬查看」分頁，系統會立即過濾並隱藏所有公開留言，僅單獨列出帶有鎖頭的私密備忘，方便照護者快速掌握重要的隱私交接與照護重點。",
                        imageAssetName: "guide_mood_cards_family_only",
                        placeholderPrompt: "預留畫面：僅限家屬查看分頁，僅呈現鎖頭私密卡片之過濾介面"
                    )
                ]
            ),
            GuideTopic(
                title: "寫一張心情便利貼",
                summary: "支援打字與語音輸入，依據身分選擇心情圖示、底色或設定私密備忘。",
                systemIcon: "square.and.pencil",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "文字與語音輔助輸入",
                        description: "便利貼內容以 100 字為限。若長輩手指不便打字，可點擊語音輸入提示，透過鍵盤內建語音功能直接說話轉成文字。",
                        imageAssetName: "guide_write_note_voice",
                        placeholderPrompt: "預留畫面：100 字輸入框與鍵盤語音轉文字指引"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "【佩戴者視角】選擇心情與底色",
                        description: "如果您是 Hoper（佩戴者），可依當下狀態自由選取心情圖示（若有勾選，發布後卡片上便會對應標示該心情），並從下方調色盤挑選喜歡的便利貼底色，完成後即可直接發送。",
                        imageAssetName: "guide_write_note_color_hoper",
                        placeholderPrompt: "預留畫面：Hoper 端心情選擇盤與底色調色盤介面"
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "【照護者視角】設定私密備忘與底色",
                        description: "如果您是 Steadyer（照護者），除了輸入文字與挑選便利貼底色外，可額外勾選「僅照護者查看」開關，確保該則留言僅在照護者端顯示，提供專屬的私密照護備忘空間。",
                        imageAssetName: "guide_write_note_color_steadyer",
                        placeholderPrompt: "預留畫面：Steadyer 端「僅照護者查看」開關與底色面板"
                    )
                ]
            ),
            GuideTopic(
                title: "放大閱讀、修改與刪除便利貼",
                summary: "在便利貼詳細畫面管理既有內容與查看完整訊息。",
                systemIcon: "pencil.circle",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "點開便利貼放大檢視",
                        description: "點擊留言看板上的任意便利貼，即可開啟詳細彈窗放大閱讀完整文字內容、留言時間與發布者姓名。",
                        imageAssetName: "guide_mood_detail_view",
                        placeholderPrompt: "預留畫面：點開便利貼後的放大詳細內容視窗"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "修改留言或刪除項目",
                        description: "若該則留言是由自己發布，彈窗內會顯示「編輯」與「刪除」按鈕。點選編輯可修改文字、心情或底色並儲存；點選刪除並再次確認即可安全移除該卡片。",
                        imageAssetName: "guide_mood_edit_delete",
                        placeholderPrompt: "預留畫面：便利貼編輯與刪除操作按鈕介面"
                    )
                ]
            )
        ],
        .medication: [
            GuideTopic(
                title: "建立處方用藥清單",
                summary: "自訂一日多次時段與週期排程，貼片部位自動提醒，支援家屬代填標記。",
                systemIcon: "list.clipboard.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "新增與管理處方排程",
                        description: "在用藥清單點選「管理清單」即可新增藥物。單一藥品支援早、中、晚等多個提醒時段，並可自訂每週或間隔天數；由家人代填之處方會清楚顯示「家屬代填」徽章。",
                        imageAssetName: "guide_med_plan_create",
                        placeholderPrompt: "預留畫面：新增藥品表單、多時段設定與家屬代填徽章"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "穿皮貼片用藥提醒",
                        description: "若配置穿皮貼片，系統會在清單中提醒 14 天內曾使用的部位，但不預設黏貼位置，由長輩在換藥時依當日膚況彈性決定。",
                        imageAssetName: "guide_patch_reminder",
                        placeholderPrompt: "預留畫面：貼片處方提醒卡片與部位防呆提示"
                    )
                ]
            ),
            GuideTopic(
                title: "貼片登記與 30 秒按壓指引",
                summary: "選擇劑量、確認撕除舊貼片與本次部位，完成按壓後儲存紀錄。",
                systemIcon: "bandage.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "確認撕除舊貼片與選擇部位",
                        description: "從「每日貼片用藥」開啟貼片流程，依處方選擇劑量規格，確認已撕除舊貼片，再選本次黏貼部位、填寫皮膚狀況，並可從相簿附加局部照片。若部位在 14 天內用過，會出現輪替提醒，可重新選擇或依畫面再次確認。",
                        imageAssetName: "guide_patch_step1",
                        placeholderPrompt: "預留畫面：撕除確認方塊、部位選擇圖與膚況拍照區"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "開始按壓倒數並完成儲存",
                        description: "按「確認部位並開始 30 秒按壓」進入按壓畫面，再按「開始 30 秒倒數」，依提示以手掌均勻按壓，使貼片黏貼牢固。倒數結束，或倒數中按「已按壓牢固，直接完成紀錄」，才會執行儲存。直接關閉倒數畫面不會完成這筆紀錄。",
                        imageAssetName: "guide_patch_timer",
                        placeholderPrompt: "預留畫面：開始倒數與直接完成紀錄按鈕"
                    )
                ]
            ),
            GuideTopic(
                title: "服藥打卡與生活紀錄管理",
                summary: "每日勾選服藥、臨時用藥補登，記錄生理數據並在藥效波動圖觀察變化。",
                systemIcon: "square.and.pencil.circle.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "今日清單打卡與臨時用藥",
                        description: "吃完藥後點擊清單旁的勾選鈕即可快速歸檔；若有醫師臨時加開的口服藥，亦可在服藥紀錄上方手動補登「單次服藥」。",
                        imageAssetName: "guide_med_check_done",
                        placeholderPrompt: "預留畫面：用藥勾選完成狀態與手動補登輸入框"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "服藥紀錄編輯與刪除",
                        description: "在「服藥紀錄」左滑該筆紀錄，選擇「編輯」或「刪除」。一般紀錄編輯時會跳到上方並展開表單，修改後按「儲存修改」，放棄則按「取消編輯」；貼片會開啟貼片專屬流程。照護者的新增與修改操作受佩戴者授權限制。",
                        imageAssetName: "guide_med_swipe_edit",
                        placeholderPrompt: "預留畫面：紀錄向左滑動顯示編輯與刪除按鈕，標註家屬代填"
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "觀察服藥前後藥效波動",
                        description: "切換至「藥效波動」分頁，圖表中會清楚標記每一次服藥的時間點，方便直觀對照服藥前後震顫強度是否有明顯減緩。",
                        imageAssetName: "guide_med_effect_chart",
                        placeholderPrompt: "預留畫面：時間軸上標記服藥時間點的震顫波動對照圖"
                    )
                ]
            ),
            GuideTopic(
                title: "查詢一段期間的服藥紀錄",
                summary: "查閱跨日紀錄，並返回今天的資料。",
                systemIcon: "calendar.badge.clock",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "設定查詢區間",
                        description: "切換至「服藥紀錄」，展開「區間查詢」，選擇開始及結束日期，再按「查詢這段期間」。查詢結果會顯示每筆紀錄的完整日期與時間。",
                        imageAssetName: nil,
                        placeholderPrompt: ""
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "回到今天與修改結果",
                        description: "按「回到今天」離開區間查詢並查看今天紀錄。查詢結果中的紀錄也可在有權限時左滑編輯；一般紀錄會帶入上方表單，貼片則開啟貼片流程。",
                        imageAssetName: nil,
                        placeholderPrompt: ""
                    )
                ]
            ),
            GuideTopic(
                title: "修改或刪除貼片紀錄",
                summary: "修正已登記的貼片劑量、部位與皮膚狀況。",
                systemIcon: "bandage",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "編輯既有貼片",
                        description: "在每日貼片卡片按「編輯貼片紀錄與部位流程」，或由服藥紀錄左滑編輯貼片。調整劑量、部位或膚況後按「儲存修改貼片紀錄」；編輯既有紀錄不會重新進入倒數。",
                        imageAssetName: nil,
                        placeholderPrompt: ""
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "刪除誤填貼片",
                        description: "使用貼片卡片的刪除操作並確認。刪除會清除該筆貼片打卡、黏貼部位及膚況紀錄，操作前請確認內容。",
                        imageAssetName: nil,
                        placeholderPrompt: ""
                    )
                ]
            )
        ],
        .healthAndAssessment: [
            GuideTopic(
                title: "每日自我健康評估",
                summary: "依需求選擇快篩、主題或完整量表，查看得分與歷史紀錄。",
                systemIcon: "checklist",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "依當下時間挑選評估模式",
                        description: "由左側選單進入「症狀評估量表」。Hoper 可選擇 5 題的「今日狀態 1 分鐘快篩」、主題分類評估，或完整 25 題量表。Steadyer 進入此功能時會顯示評估歷史紀錄。不同模式題數不同，比較分數時請先確認模式一致。",
                        imageAssetName: "guide_assessment_types",
                        placeholderPrompt: "預留畫面：三種評估深度模式選擇介面"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "送出評估並確認儲存成功",
                        description: "完成題目並送出，系統計算總分與各向度得分並儲存。請確認提交成功提示；失敗時依提示重試。完成當日評估後，系統會更新當日未填量表提醒狀態。",
                        imageAssetName: "guide_assessment_score",
                        placeholderPrompt: "預留畫面：測驗完成得分結算卡片與推播提醒註銷指示"
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "瀏覽歷史紀錄與獨立刪除",
                        description: "您可以在自評歷史清單中檢視過去填寫的每一次日期與向度得分；若填寫有誤，點擊該筆紀錄旁的「獨立刪除按鈕」即可安全移除，不需使用滑動手勢。",
                        imageAssetName: "guide_assessment_history_delete",
                        placeholderPrompt: "預留畫面：自評歷史清單畫面，每筆卡片附帶獨立刪除按鈕"
                    )
                ]
            ),
            GuideTopic(
                title: "生理體徵與突發表徵影音",
                summary: "登記血壓、血糖等 6 項常規體徵，並為突發動作異常拍照或錄影存查。",
                systemIcon: "heart.text.square.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "常規生理指標量測登記",
                        description: "在「生理健康」頁面中，可隨時記錄收縮壓、舒張壓、血糖、體溫、體重、睡眠時數與飲食份量，並提供日期歷史回溯與各項修改。",
                        imageAssetName: "guide_vitals_form",
                        placeholderPrompt: "預留畫面：生理數值 6 大項目登記表單與儲存按鈕"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "突發異動與僵硬表徵存查",
                        description: "若出現突發性斷電（Off 狀態）、異動症或步態凍結，可於「表徵記錄」輸入文字描述，並拍攝相片（最多 5 張）或錄製短影片上傳至影音牆，方便門診時重現給醫師看。",
                        imageAssetName: "guide_symptoms_media",
                        placeholderPrompt: "預留畫面：症狀描述文字框、多圖挑選與影音縮圖預覽"
                    )
                ]
            ),
            GuideTopic(
                title: "修改表徵紀錄與影音",
                summary: "在影音牆修正文字或附件。",
                systemIcon: "photo.on.rectangle",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "開啟紀錄詳情",
                        description: "切換至「表徵紀錄」，點開需要檢視的紀錄，查看文字、相片或影片。",
                        imageAssetName: nil,
                        placeholderPrompt: ""
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "編輯與刪除",
                        description: "有顯示編輯操作時，選「編輯紀錄」調整文字與影音，按「儲存」完成；「取消」放棄修改。要移除誤填項目時選「刪除紀錄」。",
                        imageAssetName: nil,
                        placeholderPrompt: ""
                    )
                ]
            )
        ],
        .reminderAndReport: [
            GuideTopic(
                title: "設定生活推播提醒",
                summary: "設定用藥、回診、領藥、每日量表與未標記事件五類提醒。",
                systemIcon: "bell.badge.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "自訂需要的提醒項目與時間",
                        description: "由左側選單開啟「提醒設定」。可設定日常服藥、回診、領藥、量表未填寫與未標記事件，共五類提醒。調整後務必按底部「儲存設定」，並確認手機允許 App 傳送通知。",
                        imageAssetName: "guide_reminders_overview",
                        placeholderPrompt: "預留畫面：五類提醒開關、時間選項與儲存設定"
                    )
                ]
            ),
            GuideTopic(
                title: "匯出門診就醫資料（產生 PDF 報告）",
                summary: "選擇日期區間，可使用 AI 整理並修改摘要，再預覽、儲存及分享就診參考報告。",
                systemIcon: "doc.text.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "選擇統計區間與匯出項目",
                        description: "由左側選單進入「匯出最近資料」，選擇起訖日期與希望由 AI 整理的報告項目，必要時新增自訂項目。「看病前準備」只作為首頁看診提示，不會放入 PDF。若不需 AI，可直接按「無需 AI 彙整預覽 PDF 報告內容」。",
                        imageAssetName: "guide_export_step1_view",
                        placeholderPrompt: "預留畫面：匯出日期區間選擇與報告勾選清單"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "AI 智慧彙整問診溝通重點",
                        description: "按「下一步：勾選觀察項目」，選取健康主題，並決定是否「引用心情留言板」。按「產生看診溝通摘要」後，可逐項閱讀及修改內容。確認後仍需按「預覽 PDF 報告內容」，才會完成內容儲存與首頁同步。",
                        imageAssetName: "guide_export_step2_ai",
                        placeholderPrompt: "預留畫面：AI 摘要生成進度與手動編輯文字框"
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "預覽並分享就診參考 PDF",
                        description: "按「預覽 PDF 報告內容」後檢視報告日期、個人資料、圖表與紀錄，再透過分享功能儲存檔案或列印。這是整理健康紀錄的就診參考報告，不是診斷證明。若產生失敗，請依畫面提示重試。",
                        imageAssetName: "guide_pdf_preview_screen",
                        placeholderPrompt: "預留畫面：完整就診 PDF 報告預覽介面與分享動作面板"
                    )
                ]
            ),
            GuideTopic(
                title: "自訂報告欄位與研究規範",
                summary: "補充自訂報告項目，並了解數據用途與研究限制。",
                systemIcon: "text.badge.plus",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "新增專屬自訂報告欄位",
                        description: "在匯出設定步驟中，點選「新增欄位」即可自由自訂標題與內容（例如復健治療進度、外院檢查結果），這些補充欄位會直接編排進入最終 PDF 報表。",
                        imageAssetName: "guide_report_custom_fields",
                        placeholderPrompt: "預留畫面：自訂報告欄位編輯清單與刪除按鈕"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "查閱研究規範與名詞定義",
                        description: "圖表數據旁的問號可查看頻率、RMS、圖例與分析規格；亦可由左側選單進入「使用告知與研究限制」。數據用於日常觀察及回診溝通，不應把分析紀錄或馬達命令狀態直接解讀為診斷或治療效果。",
                        imageAssetName: "guide_report_info_sheets",
                        placeholderPrompt: "預留畫面：名詞說明彈窗與研究規範面板"
                    )
                ]
            ),
            GuideTopic(
                title: "各類提醒的時間與儲存方式",
                summary: "了解固定提醒時間、量表提醒及事件提醒。",
                systemIcon: "clock.badge.checkmark",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "服藥、回診與領藥",
                        description: "服藥提醒配合每日用藥清單的時段。回診設定包含看診日期時間與提前小時選項，並於看診前一天晚上 8 點提醒；領藥提醒於預計領藥日當日上午 8 點發送。",
                        imageAssetName: nil,
                        placeholderPrompt: ""
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "每日量表與未標記事件",
                        description: "開啟「啟用量表未填寫提醒」並設定時間，當天尚未完成量表時提醒。另可開啟「啟用未標記事件每日提醒」，設定補填情境的提醒時間。",
                        imageAssetName: nil,
                        placeholderPrompt: ""
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "儲存設定與檢查通知",
                        description: "調整完成後按「儲存設定」。若沒收到提醒，先確認對應開關及時間，再到手機設定檢查 App 通知權限與專注模式。",
                        imageAssetName: nil,
                        placeholderPrompt: ""
                    )
                ]
            )
        ],
        .familyShare: [
            GuideTopic(
                title: "家人帳號配對與權限控管",
                summary: "Hoper 生成 6 位數號碼與家人連動，隨時管理 Steadyer 的代填權限。",
                systemIcon: "person.2.fill",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "Hoper 產生配對碼，家人輸入綁定",
                        description: "Hoper 於「家屬設定」點擊生成 6 位數安全配對碼（有效期限 10 分鐘）；Steadyer 於自身手機輸入 Hoper 的信箱與配對碼即可完成連動。",
                        imageAssetName: "guide_family_code_gen",
                        placeholderPrompt: "預留畫面：Hoper 產生配對碼視窗與 Steadyer 輸入驗證畫面"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "設定家人協助用藥的權限",
                        description: "Hoper 點擊已綁定的家人卡片，可進入詳細設定頁面，分別開啟或關閉「允許協助建立或修改用藥清單」與「允許協助新增或修改用藥紀錄」，嚴格把關個人用藥主導權。",
                        imageAssetName: "guide_family_permissions",
                        placeholderPrompt: "預留畫面：照護者詳細設定頁面，展示兩組用藥授權開關"
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "名單資訊透明與隨時解除綁定",
                        description: "連動後成員間能公開查看彼此姓名與信箱。Steadyer 僅能綁定單一 Hoper（更換需先解綁）；Hoper 則可綁定多位家屬，並可隨時手動解除特定家屬的連動關係。",
                        imageAssetName: "guide_family_members_list",
                        placeholderPrompt: "預留畫面：已連線家人清單與解除綁定按鈕確認彈窗"
                    )
                ]
            )
        ],
        .aiAssistant: [
            GuideTopic(
                title: "與小安健康助手聊聊天",
                summary: "隨身諮詢生活照護疑難，支援文字與日期搜尋，閱讀排版清晰無壓力。",
                systemIcon: "sparkles",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "發問衛教問題與即時中止",
                        description: "在對話框內提出照護疑問（如忘記吃藥處置、貼片過敏照護），小安會結合知識庫以清晰的 Markdown 條列回答；若回答過長，隨時可按下「中止」按鈕停止生成。",
                        imageAssetName: "guide_ai_chat_talk",
                        placeholderPrompt: "預留畫面：AI 衛教聊天視窗、條列回覆與即時中止按鈕"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "文字關鍵字與日期快速搜尋",
                        description: "利用聊天室頂部的搜尋欄輸入關鍵字，或使用日曆篩選器指定日期，便能即時跳轉至歷史對話紀錄，方便隨時複習衛教建議。",
                        imageAssetName: "guide_ai_chat_search",
                        placeholderPrompt: "預留畫面：聊天室頂端關鍵字搜尋與日曆篩選工具列"
                    )
                ]
            ),
            GuideTopic(
                title: "讓小安透過對話協助記錄與查詢",
                summary: "透過自然對話自動幫您完成用藥打卡、新增症狀、建立處方或查詢一週健康總結。",
                systemIcon: "wand.and.stars",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "自然語言智慧記錄（用藥與症狀）",
                        description: "可告訴小安「幫我記錄今天 08:00 吃了某藥半顆」，或「記錄今天下午手部僵硬」。登記用藥請提供實際藥名、劑量與時間；資料不足時小安會追問。收到成功回覆後，可到對應紀錄頁核對內容，若有誤再修改。",
                        imageAssetName: "guide_ai_action_log",
                        placeholderPrompt: "預留畫面：對話中自動執行記錄動作與結果回報的介面"
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "一鍵查詢一週健康與用藥總結",
                        description: "可問「我這週吃藥狀況怎樣？」或「幫我看這週健康摘要」。小安會依已儲存資料整理近七天震顫、生理指標、用藥、自評與症狀等資訊。尚未登記的服藥可能被視為疑似漏服，請先確認紀錄是否完整。",
                        imageAssetName: "guide_ai_weekly_summary",
                        placeholderPrompt: "預留畫面：小安回傳一週綜合健康總結的對話視窗"
                    )
                ]
            ),
            GuideTopic(
                title: "請小安新增便利貼與建立用藥排程",
                summary: "透過對話補充生活紀錄與既有處方排程。",
                systemIcon: "text.bubble",
                steps: [
                    GuideStep(
                        stepNumber: 1,
                        title: "新增心情便利貼",
                        description: "可說「幫我留言：今天散步很開心，心情是開心」。小安回覆成功後，到心情留言板核對內容。",
                        imageAssetName: nil,
                        placeholderPrompt: ""
                    ),
                    GuideStep(
                        stepNumber: 2,
                        title: "建立用藥排程",
                        description: "依現有處方提供藥名、劑量及提醒時段，請小安建立排程。收到成功回覆後，進入「管理用藥清單」核對；對話建立排程不代表取得新的處方建議。",
                        imageAssetName: nil,
                        placeholderPrompt: ""
                    ),
                    GuideStep(
                        stepNumber: 3,
                        title: "查詢用藥歷史",
                        description: "可問「幫我查最近的用藥紀錄」。若要精確查閱特定起訖日期，使用「服藥紀錄」的區間查詢功能。",
                        imageAssetName: nil,
                        placeholderPrompt: ""
                    )
                ]
            )
        ]
    ]
}

/// 指南圖片預留元件，依據素材存在與否顯示原圖或虛線佔位框
struct GuideImagePlaceholder: View {
    /// 圖檔名稱
    let assetName: String?
    /// 預留畫面提示字串
    let prompt: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let name = assetName, let uiImage = UIImage(named: name) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            AppTheme.textSecondary(for: colorScheme).opacity(colorScheme == .dark ? 0.25 : 0.12),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.05),
                    radius: 4,
                    x: 0,
                    y: 2
                )
                .padding(.vertical, 4)
                .accessibilityLabel(prompt.replacingOccurrences(of: "預留畫面：", with: ""))
        } else if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 20))
                    .foregroundColor(AppTheme.primary(for: colorScheme).opacity(0.6))

                Text(prompt)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 80)
            .background(AppTheme.cardBackground(for: colorScheme).opacity(0.5))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
                    .foregroundColor(AppTheme.primary(for: colorScheme).opacity(0.3))
            )
            .padding(.vertical, 4)
        }
    }
}

/// 系統操作說明主視圖，提供分類橫向滾動過濾、全域關鍵字搜尋與指南卡片列表
struct UserGuideView: View {
    /// 當前選定之分類標籤
    @State private var selectedCategory: GuideCategory = .all
    /// 搜尋欄位輸入字串
    @State private var searchText: String = ""
    @Environment(\.colorScheme) private var colorScheme

    /// 根據分類與搜尋關鍵字動態計算出之主題項目集合
    var filteredTopics: [(category: GuideCategory, topic: GuideTopic)] {
        var results: [(category: GuideCategory, topic: GuideTopic)] = []

        let categoriesToSearch: [GuideCategory] =
            (selectedCategory == .all)
            ? GuideCategory.allCases.filter { $0 != .all }
            : [selectedCategory]

        for category in categoriesToSearch {
            if let topics = GuideRepository.topics[category] {
                for topic in topics {
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        results.append((category, topic))
                    } else {
                        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        let matchTitle = topic.title.lowercased().contains(query)
                        let matchSummary = topic.summary.lowercased().contains(query)
                        let matchSteps = topic.steps.contains {
                            $0.title.lowercased().contains(query) || $0.description.lowercased().contains(query)
                        }

                        if matchTitle || matchSummary || matchSteps {
                            results.append((category, topic))
                        }
                    }
                }
            }
        }
        return results
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryFilterBar

                ScrollView {
                    LazyVStack(spacing: 12) {
                        if filteredTopics.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(filteredTopics, id: \.topic.id) { pair in
                                NavigationLink(
                                    destination: GuideDetailView(topic: pair.topic)
                                ) {
                                    GuideTopicCard(
                                        topic: pair.topic,
                                        category: pair.category
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
            }
            .background(AppTheme.background(for: colorScheme))
            .navigationTitle("系統操作說明")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜尋使用方法（如：忘記密碼、貼片、配對）")
        }
    }

    /// 分類水平滾動篩選工具列
    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GuideCategory.allCases) { category in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = category
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: category.iconName)
                                .font(.system(size: 11))
                            Text(category.rawValue)
                                .font(
                                    .system(
                                        size: 13,
                                        weight: selectedCategory == category ? .bold : .medium
                                    )
                                )
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            selectedCategory == category
                                ? AppTheme.primary(for: colorScheme)
                                : AppTheme.cardBackground(for: colorScheme)
                        )
                        .foregroundColor(
                            selectedCategory == category
                                ? .white
                                : AppTheme.textSecondary(for: colorScheme)
                        )
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(
                                    selectedCategory == category
                                        ? Color.clear
                                        : AppTheme.textSecondary(for: colorScheme).opacity(0.2),
                                    lineWidth: 1
                                )
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(AppTheme.cardBackground(for: colorScheme))
        .overlay(Divider(), alignment: .bottom)
    }

    /// 無符合搜尋條件時呈現之空狀態視圖
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 38))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .padding(.top, 40)

            Text("找不到符合的說明主題")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

            Text("請嘗試輸入其他生活關鍵字，或切換上方分類檢視。")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }
}

/// 指南主題外層卡片元件，展示圖示、標題、摘要、所屬分類與步驟總數
struct GuideTopicCard: View {
    /// 目標指南主題資料
    let topic: GuideTopic
    /// 所屬分類
    let category: GuideCategory
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.primary(for: colorScheme).opacity(0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: topic.systemIcon)
                    .font(.system(size: 18))
                    .foregroundColor(AppTheme.primary(for: colorScheme))
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(topic.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.4))
                }

                Text(topic.summary)
                    .font(.system(size: 12.5))
                    .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                    .lineLimit(2)
                    .lineSpacing(2)

                HStack(spacing: 8) {
                    Text(category.rawValue)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(AppTheme.primary(for: colorScheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AppTheme.primary(for: colorScheme).opacity(0.1))
                        .cornerRadius(4)

                    Text("共 \(topic.steps.count) 個步驟")
                        .font(.system(size: 10.5))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme).opacity(0.7))
                }
                .padding(.top, 3)
            }
        }
        .padding(14)
        .background(AppTheme.cardBackground(for: colorScheme))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppTheme.textSecondary(for: colorScheme).opacity(0.15), lineWidth: 1)
        )
    }
}

/// 指南詳細步驟內頁視圖，依序展示步驟編號、說明文字與排版指引圖檔
struct GuideDetailView: View {
    /// 顯示之目標指南主題
    let topic: GuideTopic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(topic.title)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundColor(AppTheme.primary(for: colorScheme))

                    Text(topic.summary)
                        .font(.system(size: 13.5))
                        .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                        .lineSpacing(3)
                }
                .padding(.bottom, 4)

                Divider()

                ForEach(topic.steps) { step in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.primary(for: colorScheme))
                                .frame(width: 24, height: 24)

                            Text("\(step.stepNumber)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(step.title)
                                .font(.system(size: 15.5, weight: .bold))
                                .foregroundColor(AppTheme.textPrimary(for: colorScheme))

                            Text(step.description)
                                .font(.system(size: 13.5))
                                .foregroundColor(AppTheme.textSecondary(for: colorScheme))
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)

                            GuideImagePlaceholder(
                                assetName: step.imageAssetName,
                                prompt: step.placeholderPrompt
                            )
                            .padding(.top, 2)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
            .padding(18)
        }
        .background(AppTheme.background(for: colorScheme))
        .navigationTitle("操作指引")
        .navigationBarTitleDisplayMode(.inline)
    }
}
