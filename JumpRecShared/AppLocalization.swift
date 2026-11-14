//
//  AppLocalization.swift
//  JumpRecShared
//

import Foundation

/// Supported app languages for strings and locale behaviors managed outside String Catalogs.
public nonisolated enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case korean = "ko"

    /// Resolves the active app language from the bundle's localization first, then system preferences.
    public static var current: AppLanguage {
        for identifier in Bundle.main.preferredLocalizations {
            if let language = resolve(identifier: identifier) {
                return language
            }
        }
        for identifier in Locale.preferredLanguages {
            if let language = resolve(identifier: identifier) {
                return language
            }
        }
        return .english
    }

    /// Resolves an explicit `Locale` (such as a SwiftUI environment locale) to a supported language.
    public static func resolve(locale: Locale) -> AppLanguage {
        let languageCode = locale.language.languageCode?.identifier.lowercased()
        let scriptCode = locale.language.script?.identifier.lowercased()
        let regionCode = locale.language.region?.identifier.uppercased()

        switch languageCode {
        case "ja":
            return .japanese
        case "ko":
            return .korean
        case "zh":
            if scriptCode == "hant" || (scriptCode == nil && ["TW", "HK", "MO"].contains(regionCode ?? "")) {
                return .traditionalChinese
            }
            return .simplifiedChinese
        case "en":
            return .english
        default:
            return resolve(identifier: locale.identifier) ?? .english
        }
    }

    /// Parses a BCP-47 or legacy locale identifier when it matches a supported language.
    private static func resolve(identifier: String) -> AppLanguage? {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        if normalized == "ja" || normalized.hasPrefix("ja-") {
            return .japanese
        }
        if normalized == "ko" || normalized.hasPrefix("ko-") {
            return .korean
        }
        if normalized == "zh" || normalized.hasPrefix("zh-") {
            if normalized.contains("hant")
                || normalized.hasPrefix("zh-tw")
                || normalized.hasPrefix("zh-hk")
                || normalized.hasPrefix("zh-mo")
            {
                return .traditionalChinese
            }
            return .simplifiedChinese
        }
        if normalized == "en" || normalized.hasPrefix("en-") {
            return .english
        }
        return nil
    }
}

/// Centralizes all user-facing and model-facing strings not managed in `.xcstrings` String Catalogs.
public nonisolated enum AppLocalization {
    // MARK: - Metric Formatting

    /// Formats a jump-rate value with the localized per-minute unit.
    public static func rateText(_ value: Int, language: AppLanguage = .current) -> String {
        switch language {
        case .english:
            "\(value)/min"
        case .japanese:
            "\(value)/分"
        case .simplifiedChinese:
            "\(value)/分钟"
        case .traditionalChinese:
            "\(value)/分鐘"
        case .korean:
            "\(value)/분"
        }
    }

    /// Formats a heart-rate value in beats per minute.
    public static func heartRateText(_ value: Int, language _: AppLanguage = .current) -> String {
        "\(value) bpm"
    }

    // MARK: - Speech Announcements

    /// Returns the BCP-47 voice language tag for speech synthesis.
    public static func speechLanguageCode(for language: AppLanguage = .current) -> String {
        switch language {
        case .english:
            "en-US"
        case .japanese:
            "ja-JP"
        case .simplifiedChinese:
            "zh-CN"
        case .traditionalChinese:
            "zh-TW"
        case .korean:
            "ko-KR"
        }
    }

    /// Returns the silent warmup utterance used to prime `AVSpeechSynthesizer`.
    public static func speechWarmupText(isCompact: Bool = false, language: AppLanguage = .current) -> String {
        switch language {
        case .english:
            isCompact ? "a" : "Hello"
        case .japanese:
            isCompact ? "あ" : "こんにちは"
        case .simplifiedChinese, .traditionalChinese:
            isCompact ? "啊" : "你好"
        case .korean:
            isCompact ? "아" : "안녕하세요"
        }
    }

    /// Returns the spoken phrase announced when a workout starts.
    public static func sessionStartedAnnouncement(for language: AppLanguage = .current) -> String {
        switch language {
        case .english:
            "Workout Started!"
        case .japanese:
            "ワークアウトを開始しました"
        case .simplifiedChinese:
            "训练已开始！"
        case .traditionalChinese:
            "運動已開始！"
        case .korean:
            "운동을 시작했습니다."
        }
    }

    /// Returns the spoken phrase announced when a workout ends.
    public static func sessionFinishedAnnouncement(for language: AppLanguage = .current) -> String {
        switch language {
        case .english:
            "Workout Finished!"
        case .japanese:
            "ワークアウトが終了しました"
        case .simplifiedChinese:
            "训练已结束！"
        case .traditionalChinese:
            "運動已結束！"
        case .korean:
            "운동을 마쳤습니다."
        }
    }

    /// Returns the spoken phrase announced for every 100-jump milestone.
    public static func jumpMilestoneAnnouncement(for jumpCount: Int, language: AppLanguage = .current) -> String {
        switch language {
        case .english:
            "\(jumpCount) Jumps"
        case .japanese:
            "\(jumpCount) 回"
        case .simplifiedChinese:
            "\(jumpCount) 次"
        case .traditionalChinese:
            "\(jumpCount) 下"
        case .korean:
            "\(jumpCount)회"
        }
    }

    // MARK: - Calendar & Settings

    /// Returns Sunday-first compact weekday headers matching the given locale.
    public static func calendarDayHeaders(for locale: Locale) -> [String] {
        switch AppLanguage.resolve(locale: locale) {
        case .english:
            ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
        case .japanese:
            ["日", "月", "火", "水", "木", "金", "土"]
        case .simplifiedChinese, .traditionalChinese:
            ["日", "一", "二", "三", "四", "五", "六"]
        case .korean:
            ["일", "월", "화", "수", "목", "금", "토"]
        }
    }

    /// Resolves the hosted privacy policy markdown filename for the given language.
    public static func privacyPolicyFilename(for language: AppLanguage = .current) -> String {
        switch language {
        case .japanese:
            "PRIVACY_POLICY_ja.md"
        case .english, .simplifiedChinese, .traditionalChinese, .korean:
            "PRIVACY_POLICY.md"
        }
    }

    // MARK: - AI Workout Recap

    /// Metric labels included in the on-device AI recap prompt.
    public enum AICommentMetric: Sendable {
        case duration
        case jumps
        case calories
        case averageRate
        case peakRate
        case longestStreak
        case shortBreaks
        case longBreaks
        case averageHeartRate
        case peakHeartRate

        func label(for language: AppLanguage) -> String {
            switch (self, language) {
            case (.duration, .english): "Duration"
            case (.duration, .japanese): "時間"
            case (.duration, .simplifiedChinese): "时长"
            case (.duration, .traditionalChinese): "時間"
            case (.duration, .korean): "시간"

            case (.jumps, .english): "Jumps"
            case (.jumps, .japanese): "ジャンプ回数"
            case (.jumps, .simplifiedChinese): "跳绳次数"
            case (.jumps, .traditionalChinese): "跳繩次數"
            case (.jumps, .korean): "점프 횟수"

            case (.calories, .english): "Calories"
            case (.calories, .japanese): "消費カロリー"
            case (.calories, .simplifiedChinese): "消耗卡路里"
            case (.calories, .traditionalChinese): "消耗卡路里"
            case (.calories, .korean): "소모 칼로리"

            case (.averageRate, .english): "Average rate"
            case (.averageRate, .japanese): "平均レート"
            case (.averageRate, .simplifiedChinese): "平均频率"
            case (.averageRate, .traditionalChinese): "平均頻率"
            case (.averageRate, .korean): "평균 페이스"

            case (.peakRate, .english): "Peak rate"
            case (.peakRate, .japanese): "最高レート"
            case (.peakRate, .simplifiedChinese): "最高频率"
            case (.peakRate, .traditionalChinese): "最高頻率"
            case (.peakRate, .korean): "최고 페이스"

            case (.longestStreak, .english): "Longest streak"
            case (.longestStreak, .japanese): "最長連続回数"
            case (.longestStreak, .simplifiedChinese): "最长连续次数"
            case (.longestStreak, .traditionalChinese): "最長連續次數"
            case (.longestStreak, .korean): "최장 연속 횟수"

            case (.shortBreaks, .english): "Short breaks"
            case (.shortBreaks, .japanese): "短い休憩"
            case (.shortBreaks, .simplifiedChinese): "短休息"
            case (.shortBreaks, .traditionalChinese): "短休息"
            case (.shortBreaks, .korean): "짧은 휴식"

            case (.longBreaks, .english): "Long breaks"
            case (.longBreaks, .japanese): "長い休憩"
            case (.longBreaks, .simplifiedChinese): "长休息"
            case (.longBreaks, .traditionalChinese): "長休息"
            case (.longBreaks, .korean): "긴 휴식"

            case (.averageHeartRate, .english): "Average heart rate"
            case (.averageHeartRate, .japanese): "平均心拍数"
            case (.averageHeartRate, .simplifiedChinese): "平均心率"
            case (.averageHeartRate, .traditionalChinese): "平均心率"
            case (.averageHeartRate, .korean): "평균 심박수"

            case (.peakHeartRate, .english): "Peak heart rate"
            case (.peakHeartRate, .japanese): "最高心拍数"
            case (.peakHeartRate, .simplifiedChinese): "最高心率"
            case (.peakHeartRate, .traditionalChinese): "最高心率"
            case (.peakHeartRate, .korean): "최고 심박수"
            }
        }
    }

    /// Returns system instructions for generating a gentle AI workout recap.
    public static func aiCommentInstructions(for language: AppLanguage) -> String {
        switch language {
        case .english:
            """
            Generate two short fields for a jump rope workout recap.
            Keep the tone casual, gentle, simple, and human.
            The highlight should be one short sentence about the workout's most notable point.
            The phrase should be either a gentle reflective question or a kind supportive phrase.
            Keep the combined output around 40 words total.
            Use at most one emoji across both fields, and only if it fits naturally.
            Do not guess or describe the user's emotions.
            Do not repeat raw stats back to the user.
            Do not overpraise or sound overly excited.
            Do not use markdown.
            Do not assume this is the best record.
            Write the response in English.
            """
        case .japanese:
            """
            縄跳びワークアウトの振り返りとして、短い highlight と phrase の2項目を生成してください。
            トーンはやさしく、自然で、シンプルにしてください。
            highlight はそのワークアウトの特徴を一文で短く伝えてください。
            phrase はやさしい振り返りの問いかけ、または思いやりのある一言にしてください。
            合計は40語相当以内の短さに収めてください。
            絵文字は両方合わせて最大1つまで、自然な場合のみ使ってください。
            ユーザーの感情を決めつけないでください。
            数字や統計をそのまま並べ直さないでください。
            大げさに褒めすぎたり、過度に興奮した口調にしないでください。
            Markdown は使わないでください。
            自己ベストだと決めつけないでください。
            出力は日本語で書いてください。
            """
        case .simplifiedChinese:
            """
            请为一次跳绳训练回顾生成简短的 highlight 和 phrase 两项内容。
            语气请保持轻松、温和、自然、简洁。
            highlight 请用一句话简短概括这次训练最突出的亮点。
            phrase 请写一句温和的回顾提问，或是一句贴心鼓励的话。
            两项合计长度请控制在约40字以内。
            两项合计最多只使用1个表情符号，且仅在自然合适时使用。
            不要揣测或描述用户的情绪。
            不要把原始统计数字直接罗列复述给用户。
            不要过度夸赞，也不要使用过于亢奋的语气。
            不要使用 Markdown。
            不要默认这就是最佳纪录。
            请使用简体中文回复。
            """
        case .traditionalChinese:
            """
            請為一次跳繩運動回顧產生簡短的 highlight 和 phrase 兩項內容。
            語氣請保持輕鬆、溫和、自然、簡潔。
            highlight 請用一句簡短的話說明這次運動最值得注意的亮點。
            phrase 請寫一句溫柔的回顧提問，或是一句貼心鼓勵的話。
            兩項合計長度請控制在約40字以內。
            兩項合計最多只使用1個表情符號，且僅在自然合適時使用。
            不要猜測或描述使用者的情緒。
            不要直接把原始數據重新列舉給使用者。
            不要過度稱讚，也不要使用過於亢奮的語氣。
            不要使用 Markdown。
            不要預設這就是最佳紀錄。
            請使用繁體中文回覆。
            """
        case .korean:
            """
            줄넘기 운동 요약으로 짧은 highlight와 phrase 두 항목을 생성해 주세요.
            어조는 편안하고 다정하며 자연스럽고 간결하게 유지해 주세요.
            highlight에는 이번 운동에서 가장 눈에 띄는 점을 한 문장으로 짧게 담아 주세요.
            phrase에는 부드럽게 돌아보는 질문이나 따뜻한 응원의 한마디를 적어 주세요.
            두 항목을 합쳐 40어절 안팎의 짧은 길이로 작성해 주세요.
            이모지는 두 항목을 합쳐 최대 1개까지만, 자연스러울 때만 사용해 주세요.
            사용자의 감정을 추측하거나 단정해 서술하지 마세요.
            원시 수치나 통계를 그대로 나열해 되풀이하지 마세요.
            과도하게 칭찬하거나 지나치게 들뜬 어조를 쓰지 마세요.
            Markdown은 사용하지 마세요.
            이번 기록을 개인 최고 기록이라고 단정하지 마세요.
            한국어로 작성해 주세요.
            """
        }
    }

    /// Builds the per-session AI recap prompt from formatted workout metrics.
    public static func aiCommentPrompt(metrics: [String], language: AppLanguage) -> String {
        let joinedMetrics = metrics.joined(separator: "\n")
        switch language {
        case .english:
            return """
            Create a short highlight and a short phrase for this jump rope workout.
            The phrase must be either a gentle reflective question or a kind supportive phrase.
            \(joinedMetrics)
            """
        case .japanese:
            return """
            この縄跳びワークアウトについて、短い highlight と短い phrase を作成してください。
            phrase は、やさしい振り返りの問いかけ、または思いやりのある一言にしてください。
            \(joinedMetrics)
            """
        case .simplifiedChinese:
            return """
            请为这次跳绳训练生成简短的 highlight 和 phrase。
            phrase 必须是一句温和的回顾提问，或是一句贴心鼓励的话。
            \(joinedMetrics)
            """
        case .traditionalChinese:
            return """
            請為這次跳繩運動產生簡短的 highlight 和 phrase。
            phrase 必須是一句溫柔的回顧提問，或是一句貼心鼓勵的話。
            \(joinedMetrics)
            """
        case .korean:
            return """
            이번 줄넘기 운동에 대해 짧은 highlight와 짧은 phrase를 작성해 주세요.
            phrase는 부드럽게 돌아보는 질문이거나 따뜻한 응원의 한마디여야 합니다.
            \(joinedMetrics)
            """
        }
    }

    /// Formats one metric line for the AI recap prompt.
    public static func aiCommentPromptLine(_ metric: AICommentMetric, value: String, language: AppLanguage) -> String {
        "\(metric.label(for: language)): \(value)"
    }
}
