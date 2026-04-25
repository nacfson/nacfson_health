import WidgetKit
import SwiftUI

/// 홈스크린 위젯 묶음.
/// - `NutritionWidget`: 오늘 칼로리/탄단지 진행률
/// - `WorkoutHeatmapWidget`: 최근 13주 운동 볼륨 잔디밭
///
/// Live Activity(`RestActivityWidget`) 는 별도 타겟이므로 이 Bundle 에 포함하지 않는다.
@main
struct NacfsonHealthWidgetBundle: WidgetBundle {
    var body: some Widget {
        NutritionWidget()
        WorkoutHeatmapWidget()
    }
}
