package com.nacfson.nacfson_health

import android.app.Activity
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

class PrivacyPolicyActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val title = TextView(this).apply {
            text = "Nacfson Health 개인정보 처리방침"
            textSize = 20f
            setPadding(0, 0, 0, 24)
        }
        val body = TextView(this).apply {
            text = """
                Nacfson Health 는 사용자의 활동 데이터(걸음 수, 심박수, 활동/기초대사 칼로리)를
                Health Connect 로부터 읽어 와 다음 목적에 한해 사용합니다.

                1. 개인 맞춤형 운동·식단 조언 생성 (Gemini AI)
                2. 일일 소모 칼로리 시각화

                수집된 활동 데이터는 사용자의 기기 안에서만 사용되며, 외부 서버로 전송되거나
                저장되지 않습니다. (단, AI 조언 생성 시 비식별 요약 수치만 Gemini API 로 전송됩니다.)

                권한은 언제든 Health Connect 앱 설정에서 회수할 수 있습니다.
            """.trimIndent()
            textSize = 14f
            setLineSpacing(6f, 1.2f)
        }

        val container = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 64, 48, 64)
            gravity = Gravity.TOP
            addView(title)
            addView(body)
        }
        val scroll = ScrollView(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            addView(container)
        }
        setContentView(scroll)
    }
}
