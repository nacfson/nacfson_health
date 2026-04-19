import 'package:intl/intl.dart';
import '../../exercise/data/repositories/exercise_repository.dart';
import '../../diet/data/repositories/diet_repository.dart';
// import '../../settings/domain/entities/user_profile.dart'; // 향후 ProfileRepo 추가 시 사용

class HealthDataAggregationFacade {
  final ExerciseRepository _exerciseRepo;
  final DietRepository _dietRepo;
  // final UserProfileRepository _profileRepo;

  HealthDataAggregationFacade(
    this._exerciseRepo,
    this._dietRepo,
    // this._profileRepo,
  );

  Future<String> gatherDataAndBuildPrompt() async {
    final today = DateTime.now();
    
    // DB에서 오늘 데이터 조회
    final exercises = await _exerciseRepo.getByDate(today);
    final diets = await _dietRepo.getByDate(today);
    // final profile = await _profileRepo.getProfile();

    final buffer = StringBuffer();
    
    // 사용자 컨텍스트 (임시 하드코딩, 차후 profile 연동)
    buffer.writeln("이 사용자는 다이어트가 목표인 30대 남성입니다. 목표 칼로리는 2000kcal입니다.");
    buffer.writeln("[오늘의 데이터 - ${DateFormat('yyyy-MM-dd').format(today)}]");
    
    // 식단 데이터 집계
    int totalCals = 0;
    double totalCarbs = 0, totalProtein = 0, totalFat = 0;
    for (var d in diets) {
      totalCals += d.totalCalories;
      totalCarbs += d.carbs;
      totalProtein += d.protein;
      totalFat += d.fat;
    }
    buffer.writeln("• 식단: 총 ${totalCals}kcal 섭취 (단백질 ${totalProtein}g, 탄수화물 ${totalCarbs}g, 지방 ${totalFat}g)");

    // 운동 데이터 집계
    if (exercises.isEmpty) {
      buffer.writeln("• 운동: 오늘은 운동 기록이 없습니다.");
    } else {
      buffer.writeln("• 운동 기록:");
      for (var e in exercises) {
        buffer.writeln("  - ${e.exerciseName}: ${e.weight}kg x ${e.reps}회 x ${e.currentSet}세트");
      }
    }

    buffer.writeln("\n위 데이터를 바탕으로 오늘 하루에 대한 친근하고 짧은 한 줄 조언(격려 또는 팁)을 작성해줘.");

    return buffer.toString();
  }
}
