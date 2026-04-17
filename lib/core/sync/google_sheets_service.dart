import 'package:googleapis/sheets/v4.dart' as sheets;

import '../../features/diet/domain/entities/diet_record.dart' as diet;
import '../../features/exercise/domain/entities/exercise_record.dart';
import '../../features/settings/domain/entities/exercise_template.dart';
import '../../features/settings/domain/entities/food_template.dart';
import '../../features/weight/domain/entities/weight_record.dart' as weight;
import 'google_auth_service.dart';

class GoogleSheetsService {
  final GoogleAuthService _authService;
  final String spreadsheetId;
  sheets.SheetsApi? _sheetsApi;

  GoogleSheetsService(this._authService, this.spreadsheetId);

  Future<sheets.SheetsApi> get _api async {
    _sheetsApi ??= await _createSheetsApi();
    return _sheetsApi!;
  }

  Future<sheets.SheetsApi> _createSheetsApi() async {
    final client = await _authService.authClient;
    return sheets.SheetsApi(client);
  }

  // ==========================================================================
  // Initialize Sheets (Headers)
  // ==========================================================================

  /// 새 스프레드시트 생성 직후 모든 시트 헤더를 한 번에 초기화
  Future<void> setupSheetHeaders() async {
    await initializeExerciseSheet();
    await initializeDietSheet();
    await initializeTemplatesSheet();
    await initializeFoodTemplatesSheet();
    await initializeWeightSheet();
  }

  /// 동기화 전 필수 시트 3개가 모두 존재함을 보장 (멱등 연산).
  /// spreadsheets.get을 1회만 호출해 API 비용을 최소화합니다.
  Future<void> ensureAllRequiredSheets() async {
    final api = await _api;
    final spreadsheet = await api.spreadsheets.get(spreadsheetId);
    final existingTitles = spreadsheet.sheets
            ?.map((s) => s.properties?.title ?? '')
            .toSet() ??
        {};

    final required = [
      (
        title: 'exercise_records',
        headers: [
          'uuid',
          'timestamp',
          'updatedAt',
          'exerciseType',
          'exerciseName',
          'currentSet',
          'weight',
          'reps',
          'rpe'
        ],
        range: 'exercise_records!A1:I1',
      ),
      (
        title: 'diet_records',
        headers: [
          'uuid',
          'timestamp',
          'updatedAt',
          'mealType',
          'foodName',
          'totalCalories',
          'carbs',
          'protein',
          'fat',
          'satisfaction',
          'memo'
        ],
        range: 'diet_records!A1:K1',
      ),
      (
        title: 'exercise_templates',
        headers: ['uuid', 'name', 'exerciseType', 'updatedAt'],
        range: 'exercise_templates!A1:D1',
      ),
      (
        title: 'food_templates',
        headers: [
          'uuid',
          'name',
          'calories',
          'carbs',
          'protein',
          'fat',
          'updatedAt'
        ],
        range: 'food_templates!A1:G1',
      ),
      (
        title: 'weight_records',
        headers: ['uuid', 'timestamp', 'updatedAt', 'weight'],
        range: 'weight_records!A1:D1',
      ),
    ];

    for (final config in required) {
      if (!existingTitles.contains(config.title)) {
        // 시트 생성
        await api.spreadsheets.batchUpdate(
          sheets.BatchUpdateSpreadsheetRequest(requests: [
            sheets.Request(
              addSheet: sheets.AddSheetRequest(
                properties: sheets.SheetProperties(title: config.title),
              ),
            ),
          ]),
          spreadsheetId,
        );
        // 헤더 쓰기
        await api.spreadsheets.values.update(
          sheets.ValueRange(values: [config.headers]),
          spreadsheetId,
          config.range,
          valueInputOption: 'RAW',
        );
      }
    }
  }

  /// 운동 기록 시트 헤더 초기화 (최초 1회)
  Future<void> initializeExerciseSheet() async {
    final api = await _api;
    const range = 'exercise_records!A1:I1';
    final values = sheets.ValueRange(values: [
      [
        'uuid',
        'timestamp',
        'updatedAt',
        'exerciseType',
        'exerciseName',
        'currentSet',
        'weight',
        'reps',
        'rpe'
      ]
    ]);
    await api.spreadsheets.values.update(values, spreadsheetId, range,
        valueInputOption: 'RAW');
  }

  /// 운동 템플릿 시트 헤더 초기화 (최초 1회, v5: exerciseType 추가)
  Future<void> initializeTemplatesSheet() async {
    final api = await _api;
    const range = 'exercise_templates!A1:D1';
    final values = sheets.ValueRange(values: [
      ['uuid', 'name', 'exerciseType', 'updatedAt']
    ]);
    await api.spreadsheets.values.update(values, spreadsheetId, range,
        valueInputOption: 'RAW');
  }

  /// 음식 템플릿 시트 헤더 초기화 (최초 1회)
  Future<void> initializeFoodTemplatesSheet() async {
    final api = await _api;
    const range = 'food_templates!A1:G1';
    final values = sheets.ValueRange(values: [
      ['uuid', 'name', 'calories', 'carbs', 'protein', 'fat', 'updatedAt']
    ]);
    await api.spreadsheets.values.update(values, spreadsheetId, range,
        valueInputOption: 'RAW');
  }

  /// 식단 기록 시트 헤더 초기화 (최초 1회)
  Future<void> initializeDietSheet() async {
    final api = await _api;
    const range = 'diet_records!A1:K1';
    final values = sheets.ValueRange(values: [
      [
        'uuid',
        'timestamp',
        'updatedAt',
        'mealType',
        'foodName',
        'totalCalories',
        'carbs',
        'protein',
        'fat',
        'satisfaction',
        'memo'
      ]
    ]);
    await api.spreadsheets.values.update(values, spreadsheetId, range,
        valueInputOption: 'RAW');
  }

  /// 체중 기록 시트 헤더 초기화 (최초 1회, v5 신규)
  Future<void> initializeWeightSheet() async {
    final api = await _api;
    const range = 'weight_records!A1:D1';
    final values = sheets.ValueRange(values: [
      ['uuid', 'timestamp', 'updatedAt', 'weight']
    ]);
    await api.spreadsheets.values.update(values, spreadsheetId, range,
        valueInputOption: 'RAW');
  }

  // ==========================================================================
  // Batch Push (Local → Sheet)
  // ==========================================================================

  /// 운동 기록 Batch Push (Upsert & Delete 최적화 적용)
  Future<void> batchPushExerciseRecords(List<ExerciseRecord> records) async {
    if (records.isEmpty) return;

    final api = await _api;
    // 1. A열 전체 가져오기 및 매핑 (최적화)
    final uuidResponse = await api.spreadsheets.values.get(spreadsheetId, 'exercise_records!A:A');
    final uuidRows = uuidResponse.values ?? [];
    final uuidToRow = <String, int>{};
    for (int i = 0; i < uuidRows.length; i++) {
      if (uuidRows[i].isNotEmpty) {
        uuidToRow[uuidRows[i][0].toString()] = i + 1; // 1-based index
      }
    }

    final updateData = <sheets.ValueRange>[];
    final appendValues = <List<dynamic>>[];
    final deleteRowIndices = <int>[];

    for (final record in records) {
      final rowNum = uuidToRow[record.uuid];
      
      if (record.syncStatus == SyncStatus.deleted) {
        // 로컬에서 삭제된 경우, 시트에서도 삭제 대상으로 분류
        if (rowNum != null) {
          deleteRowIndices.add(rowNum - 1); // 0-based index for DimensionRange
        }
      } else {
        final rowTemplate = _exerciseRecordToRow(record);
        if (rowNum != null) {
          // 존재하는 UUID는 해당 행만 부분 업데이트 (Update)
          updateData.add(sheets.ValueRange(
            range: 'exercise_records!A$rowNum:I$rowNum',
            values: [rowTemplate],
          ));
        } else {
          // 존재하지 않는 새로운 UUID는 맨 아래 추가 (Append)
          appendValues.add(rowTemplate);
        }
      }
    }

    // 2. 존재하는 기록 일괄 덮어쓰기 (Batch Update)
    if (updateData.isNotEmpty) {
      final batchUpdateRequest = sheets.BatchUpdateValuesRequest(
        data: updateData,
        valueInputOption: 'RAW',
      );
      await api.spreadsheets.values.batchUpdate(batchUpdateRequest, spreadsheetId);
    }

    // 3. 새로운 기록 일괄 추가 (Append)
    if (appendValues.isNotEmpty) {
      final appendBody = sheets.ValueRange(values: appendValues);
      await api.spreadsheets.values.append(
          appendBody, spreadsheetId, 'exercise_records!A1', 
          valueInputOption: 'RAW', insertDataOption: 'INSERT_ROWS');
    }

    // 4. 삭제된 기록 일괄 삭제 (Batch Delete Rows)
    if (deleteRowIndices.isNotEmpty) {
      final sheetId = await _getSheetId(api, 'exercise_records');
      
      // 반드시 내림차순 정렬 (아래에서부터 지워야 인덱스가 꼬이지 않음)
      deleteRowIndices.sort((a, b) => b.compareTo(a));

      final requests = deleteRowIndices.map((idx) => sheets.Request(
        deleteDimension: sheets.DeleteDimensionRequest(
          range: sheets.DimensionRange(
            sheetId: sheetId,
            dimension: 'ROWS',
            startIndex: idx,
            endIndex: idx + 1,
          ),
        ),
      )).toList();

      final batchUpdateRequest = sheets.BatchUpdateSpreadsheetRequest(requests: requests);
      await api.spreadsheets.batchUpdate(batchUpdateRequest, spreadsheetId);
    }
  }

  /// 식단 기록 Batch Push (Upsert & Delete 최적화 적용)
  Future<void> batchPushDietRecords(List<diet.DietRecord> records) async {
    if (records.isEmpty) return;

    final api = await _api;
    // 1. A열 전체 가져오기 및 매핑 (최적화)
    final uuidResponse = await api.spreadsheets.values.get(spreadsheetId, 'diet_records!A:A');
    final uuidRows = uuidResponse.values ?? [];
    final uuidToRow = <String, int>{};
    for (int i = 0; i < uuidRows.length; i++) {
      if (uuidRows[i].isNotEmpty) {
        uuidToRow[uuidRows[i][0].toString()] = i + 1; // 1-based index
      }
    }

    final updateData = <sheets.ValueRange>[];
    final appendValues = <List<dynamic>>[];
    final deleteRowIndices = <int>[];

    for (final record in records) {
      final rowNum = uuidToRow[record.uuid];
      
      if (record.syncStatus == diet.SyncStatus.deleted) {
        // 로컬에서 삭제된 경우, 시트에서도 삭제 대상으로 분류
        if (rowNum != null) {
          deleteRowIndices.add(rowNum - 1); // 0-based index for DimensionRange
        }
      } else {
        final rowTemplate = _dietRecordToRow(record);
        if (rowNum != null) {
          // 존재하는 UUID는 해당 행만 부분 업데이트 (Update)
          updateData.add(sheets.ValueRange(
            range: 'diet_records!A$rowNum:K$rowNum',
            values: [rowTemplate],
          ));
        } else {
          // 존재하지 않는 새로운 UUID는 맨 아래 추가 (Append)
          appendValues.add(rowTemplate);
        }
      }
    }

    // 2. 존재하는 기록 일괄 덮어쓰기 (Batch Update)
    if (updateData.isNotEmpty) {
      final batchUpdateRequest = sheets.BatchUpdateValuesRequest(
        data: updateData,
        valueInputOption: 'RAW',
      );
      await api.spreadsheets.values.batchUpdate(batchUpdateRequest, spreadsheetId);
    }

    // 3. 새로운 기록 일괄 추가 (Append)
    if (appendValues.isNotEmpty) {
      final appendBody = sheets.ValueRange(values: appendValues);
      await api.spreadsheets.values.append(
          appendBody, spreadsheetId, 'diet_records!A1', 
          valueInputOption: 'RAW', insertDataOption: 'INSERT_ROWS');
    }

    // 4. 삭제된 기록 일괄 삭제 (Batch Delete Rows)
    if (deleteRowIndices.isNotEmpty) {
      final sheetId = await _getSheetId(api, 'diet_records');
      
      // 반드시 내림차순 정렬 (아래에서부터 지워야 인덱스가 꼬이지 않음)
      deleteRowIndices.sort((a, b) => b.compareTo(a));

      final requests = deleteRowIndices.map((idx) => sheets.Request(
        deleteDimension: sheets.DeleteDimensionRequest(
          range: sheets.DimensionRange(
            sheetId: sheetId,
            dimension: 'ROWS',
            startIndex: idx,
            endIndex: idx + 1,
          ),
        ),
      )).toList();

      final batchUpdateRequest = sheets.BatchUpdateSpreadsheetRequest(requests: requests);
      await api.spreadsheets.batchUpdate(batchUpdateRequest, spreadsheetId);
    }
  }

  // ==========================================================================
  // Batch Push Templates (Local → Sheet)
  // ==========================================================================

  /// 운동 템플릿 Batch Push (생성/삭제만 지원 — 수정 없음)
  Future<void> batchPushTemplates(List<ExerciseTemplate> templates) async {
    if (templates.isEmpty) return;

    final api = await _api;
    // 1. A열 uuid 목록 읽기 및 매핑
    final uuidResponse = await api.spreadsheets.values
        .get(spreadsheetId, 'exercise_templates!A:A');
    final uuidRows = uuidResponse.values ?? [];
    final uuidToRow = <String, int>{};
    for (int i = 0; i < uuidRows.length; i++) {
      if (uuidRows[i].isNotEmpty) {
        uuidToRow[uuidRows[i][0].toString()] = i + 1; // 1-based
      }
    }

    final appendValues = <List<dynamic>>[];
    final deleteRowIndices = <int>[];

    for (final t in templates) {
      final rowNum = uuidToRow[t.uuid];
      if (t.syncStatus == TemplateSyncStatus.deleted) {
        // 시트에서 해당 행 삭제
        if (rowNum != null) deleteRowIndices.add(rowNum - 1); // 0-based
      } else {
        // created — 시트에 없는 경우에만 추가 (수정 없음)
        if (rowNum == null) {
          appendValues.add([
            t.uuid,
            t.name,
            t.exerciseType, // v5: exerciseType 추가
            t.updatedAt.millisecondsSinceEpoch,
          ]);
        }
      }
    }

    // 2. 신규 템플릿 일괄 추가 (Append)
    if (appendValues.isNotEmpty) {
      final appendBody = sheets.ValueRange(values: appendValues);
      await api.spreadsheets.values.append(
        appendBody, spreadsheetId, 'exercise_templates!A1',
        valueInputOption: 'RAW', insertDataOption: 'INSERT_ROWS',
      );
    }

    // 3. 삭제된 템플릿 일괄 행 삭제 (내림차순 정렬로 인덱스 꼬임 방지)
    if (deleteRowIndices.isNotEmpty) {
      final sheetId = await _getSheetId(api, 'exercise_templates');
      deleteRowIndices.sort((a, b) => b.compareTo(a));
      final requests = deleteRowIndices
          .map((idx) => sheets.Request(
                deleteDimension: sheets.DeleteDimensionRequest(
                  range: sheets.DimensionRange(
                    sheetId: sheetId,
                    dimension: 'ROWS',
                    startIndex: idx,
                    endIndex: idx + 1,
                  ),
                ),
              ))
          .toList();
      await api.spreadsheets.batchUpdate(
        sheets.BatchUpdateSpreadsheetRequest(requests: requests),
        spreadsheetId,
      );
    }
  }

  /// 음식 템플릿 Batch Push (생성/삭제만 지원 — 수정 없음)
  Future<void> batchPushFoodTemplates(List<FoodTemplate> templates) async {
    if (templates.isEmpty) return;

    final api = await _api;
    // 1. A열 uuid 목록 읽기 및 매핑
    final uuidResponse = await api.spreadsheets.values
        .get(spreadsheetId, 'food_templates!A:A');
    final uuidRows = uuidResponse.values ?? [];
    final uuidToRow = <String, int>{};
    for (int i = 0; i < uuidRows.length; i++) {
      if (uuidRows[i].isNotEmpty) {
        uuidToRow[uuidRows[i][0].toString()] = i + 1; // 1-based
      }
    }

    final appendValues = <List<dynamic>>[];
    final deleteRowIndices = <int>[];

    for (final t in templates) {
      final rowNum = uuidToRow[t.uuid];
      if (t.syncStatus == FoodTemplateSyncStatus.deleted) {
        if (rowNum != null) deleteRowIndices.add(rowNum - 1); // 0-based
      } else {
        // created — 시트에 없는 경우에만 추가 (수정 없음)
        if (rowNum == null) {
          appendValues.add([
            t.uuid,
            t.name,
            t.calories,
            t.carbs,
            t.protein,
            t.fat,
            t.updatedAt.millisecondsSinceEpoch,
          ]);
        }
      }
    }

    // 2. 신규 템플릿 일괄 추가 (Append)
    if (appendValues.isNotEmpty) {
      final appendBody = sheets.ValueRange(values: appendValues);
      await api.spreadsheets.values.append(
        appendBody, spreadsheetId, 'food_templates!A1',
        valueInputOption: 'RAW', insertDataOption: 'INSERT_ROWS',
      );
    }

    // 3. 삭제된 템플릿 일괄 행 삭제 (내림차순 정렬로 인덱스 꼬임 방지)
    if (deleteRowIndices.isNotEmpty) {
      final sheetId = await _getSheetId(api, 'food_templates');
      deleteRowIndices.sort((a, b) => b.compareTo(a));
      final requests = deleteRowIndices
          .map((idx) => sheets.Request(
                deleteDimension: sheets.DeleteDimensionRequest(
                  range: sheets.DimensionRange(
                    sheetId: sheetId,
                    dimension: 'ROWS',
                    startIndex: idx,
                    endIndex: idx + 1,
                  ),
                ),
              ))
          .toList();
      await api.spreadsheets.batchUpdate(
        sheets.BatchUpdateSpreadsheetRequest(requests: requests),
        spreadsheetId,
      );
    }
  }

  /// 체중 기록 Batch Push (Upsert & Delete 최적화 적용, v5 신규)
  Future<void> batchPushWeightRecords(List<weight.WeightRecord> records) async {
    if (records.isEmpty) return;

    final api = await _api;
    // 1. A열 전체 가져오기 및 매핑 (최적화)
    final uuidResponse = await api.spreadsheets.values.get(spreadsheetId, 'weight_records!A:A');
    final uuidRows = uuidResponse.values ?? [];
    final uuidToRow = <String, int>{};
    for (int i = 0; i < uuidRows.length; i++) {
      if (uuidRows[i].isNotEmpty) {
        uuidToRow[uuidRows[i][0].toString()] = i + 1; // 1-based index
      }
    }

    final updateData = <sheets.ValueRange>[];
    final appendValues = <List<dynamic>>[];
    final deleteRowIndices = <int>[];

    for (final record in records) {
      final rowNum = uuidToRow[record.uuid];

      if (record.syncStatus == weight.SyncStatus.deleted) {
        // 로컬에서 삭제된 경우, 시트에서도 삭제 대상으로 분류
        if (rowNum != null) {
          deleteRowIndices.add(rowNum - 1); // 0-based index for DimensionRange
        }
      } else {
        final rowTemplate = _weightRecordToRow(record);
        if (rowNum != null) {
          // 존재하는 UUID는 해당 행만 부분 업데이트 (Update)
          updateData.add(sheets.ValueRange(
            range: 'weight_records!A$rowNum:D$rowNum',
            values: [rowTemplate],
          ));
        } else {
          // 존재하지 않는 새로운 UUID는 맨 아래 추가 (Append)
          appendValues.add(rowTemplate);
        }
      }
    }

    // 2. 존재하는 기록 일괄 덮어쓰기 (Batch Update)
    if (updateData.isNotEmpty) {
      final batchUpdateRequest = sheets.BatchUpdateValuesRequest(
        data: updateData,
        valueInputOption: 'RAW',
      );
      await api.spreadsheets.values.batchUpdate(batchUpdateRequest, spreadsheetId);
    }

    // 3. 새로운 기록 일괄 추가 (Append)
    if (appendValues.isNotEmpty) {
      final appendBody = sheets.ValueRange(values: appendValues);
      await api.spreadsheets.values.append(
        appendBody, spreadsheetId, 'weight_records!A1',
        valueInputOption: 'RAW', insertDataOption: 'INSERT_ROWS',
      );
    }

    // 4. 삭제된 기록 일괄 행 삭제 (내림차순 정렬로 인덱스 꼬임 방지)
    if (deleteRowIndices.isNotEmpty) {
      final sheetId = await _getSheetId(api, 'weight_records');
      deleteRowIndices.sort((a, b) => b.compareTo(a));
      final requests = deleteRowIndices
          .map((idx) => sheets.Request(
                deleteDimension: sheets.DeleteDimensionRequest(
                  range: sheets.DimensionRange(
                    sheetId: sheetId,
                    dimension: 'ROWS',
                    startIndex: idx,
                    endIndex: idx + 1,
                  ),
                ),
              ))
          .toList();
      await api.spreadsheets.batchUpdate(
        sheets.BatchUpdateSpreadsheetRequest(requests: requests),
        spreadsheetId,
      );
    }
  }

  // ==========================================================================
  // Delta Pull Templates (Sheet → Local)
  // ==========================================================================

  /// 운동 템플릿 Delta Pull (v5: exerciseType 포함)
  Future<List<ExerciseTemplate>> readTemplatesDelta({DateTime? since}) async {
    final api = await _api;
    const range = 'exercise_templates!A2:D';

    final response = await api.spreadsheets.values.get(spreadsheetId, range);
    final rows = response.values ?? [];

    return rows
        .where((row) => row.length >= 3)
        .map(_rowToTemplate)
        .where((t) => since == null || t.updatedAt.isAfter(since))
        .toList();
  }

  /// 음식 템플릿 Delta Pull
  Future<List<FoodTemplate>> readFoodTemplatesDelta({DateTime? since}) async {
    final api = await _api;
    const range = 'food_templates!A2:G';

    final response = await api.spreadsheets.values.get(spreadsheetId, range);
    final rows = response.values ?? [];

    return rows
        .where((row) => row.length >= 7)
        .map(_rowToFoodTemplate)
        .where((t) => since == null || t.updatedAt.isAfter(since))
        .toList();
  }

  /// 체중 기록 Delta Pull (v5 신규)
  Future<List<weight.WeightRecord>> readWeightRecordsDelta({DateTime? since}) async {
    final api = await _api;
    const range = 'weight_records!A2:D';

    final response = await api.spreadsheets.values.get(spreadsheetId, range);
    final rows = response.values ?? [];

    return rows
        .where((row) => row.length >= 4)
        .map(_rowToWeightRecord)
        .where((record) => since == null || record.updatedAt.isAfter(since))
        .toList();
  }

  // ==========================================================================
  // Helper: Get Sheet ID for DeleteDimensionRequest
  // ==========================================================================

  Future<int> _getSheetId(sheets.SheetsApi api, String title) async {
    final spreadsheet = await api.spreadsheets.get(spreadsheetId);
    final sheet = spreadsheet.sheets?.firstWhere(
      (s) => s.properties?.title == title,
      orElse: () => throw Exception('Sheet $title not found'),
    );
    return sheet?.properties?.sheetId ?? 0;
  }

  // ==========================================================================
  // Delta Pull (Sheet → Local)
  // ==========================================================================

  /// 운동 기록 Delta Pull
  Future<List<ExerciseRecord>> readExerciseRecordsDelta({
    DateTime? since,
  }) async {
    final api = await _api;
    const range = 'exercise_records!A2:I';

    final response =
        await api.spreadsheets.values.get(spreadsheetId, range);
    final rows = response.values ?? [];

    return rows
        .where((row) => row.length >= 9)
        .map(_rowToExerciseRecord)
        .where((record) =>
            since == null || record.updatedAt.isAfter(since))
        .toList();
  }

  /// 식단 기록 Delta Pull
  Future<List<diet.DietRecord>> readDietRecordsDelta({
    DateTime? since,
  }) async {
    final api = await _api;
    const range = 'diet_records!A2:K';

    final response =
        await api.spreadsheets.values.get(spreadsheetId, range);
    final rows = response.values ?? [];

    return rows
        .where((row) => row.length >= 10)
        .map(_rowToDietRecord)
        .where((record) =>
            since == null || record.updatedAt.isAfter(since))
        .toList();
  }

  // ==========================================================================
  // Helper: Record → Row
  // ==========================================================================

  List<dynamic> _exerciseRecordToRow(ExerciseRecord r) => [
        r.uuid,
        r.timestamp.millisecondsSinceEpoch,
        r.updatedAt.millisecondsSinceEpoch,
        r.exerciseType,
        r.exerciseName,
        r.currentSet,
        r.weight,
        r.reps,
        r.rpe,
      ];

  List<dynamic> _dietRecordToRow(diet.DietRecord r) => [
        r.uuid,
        r.timestamp.millisecondsSinceEpoch,
        r.updatedAt.millisecondsSinceEpoch,
        r.mealType,
        r.foodName,
        r.totalCalories,
        r.carbs,
        r.protein,
        r.fat,
        r.satisfaction,
        r.memo ?? '',
      ];

  // ==========================================================================
  // Helper: Row → Record
  // ==========================================================================

  ExerciseRecord _rowToExerciseRecord(List<dynamic> row) {
    return ExerciseRecord(
      uuid: row[0].toString(),
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(int.parse(row[1].toString())),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(int.parse(row[2].toString())),
      syncStatus: SyncStatus.synced,
      exerciseType: row[3].toString(),
      exerciseName: row[4].toString(),
      currentSet: int.parse(row[5].toString()),
      weight: double.parse(row[6].toString()),
      reps: int.parse(row[7].toString()),
      rpe: double.parse(row[8].toString()),
    );
  }

  diet.DietRecord _rowToDietRecord(List<dynamic> row) {
    return diet.DietRecord(
      uuid: row[0].toString(),
      timestamp:
          DateTime.fromMillisecondsSinceEpoch(int.parse(row[1].toString())),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(int.parse(row[2].toString())),
      syncStatus: diet.SyncStatus.synced,
      mealType: row[3].toString(),
      foodName: row[4].toString(),
      totalCalories: int.parse(row[5].toString()),
      carbs: double.parse(row[6].toString()),
      protein: double.parse(row[7].toString()),
      fat: double.parse(row[8].toString()),
      satisfaction: int.parse(row[9].toString()),
      memo: row.length > 10 ? row[10].toString() : null,
    );
  }

  ExerciseTemplate _rowToTemplate(List<dynamic> row) {
    // v5 마이그레이션: exerciseType 컬럼 추가
    // v4 형식: [uuid, name, updatedAt] (3컬럼)
    // v5 형식: [uuid, name, exerciseType, updatedAt] (4컬럼)
    // 하위호환성: 두 형식 모두 지원
    final hasExerciseType = row.length >= 4;
    return ExerciseTemplate(
      uuid: row[0].toString(),
      name: row[1].toString(),
      exerciseType: hasExerciseType ? row[2].toString() : '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        int.parse(row[hasExerciseType ? 3 : 2].toString()),
      ),
      syncStatus: TemplateSyncStatus.synced,
    );
  }

  FoodTemplate _rowToFoodTemplate(List<dynamic> row) {
    return FoodTemplate(
      uuid: row[0].toString(),
      name: row[1].toString(),
      calories: int.parse(row[2].toString()),
      carbs: double.parse(row[3].toString()),
      protein: double.parse(row[4].toString()),
      fat: double.parse(row[5].toString()),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(int.parse(row[6].toString())),
      syncStatus: FoodTemplateSyncStatus.synced,
    );
  }

  List<dynamic> _weightRecordToRow(weight.WeightRecord r) => [
        r.uuid,
        r.timestamp.millisecondsSinceEpoch,
        r.updatedAt.millisecondsSinceEpoch,
        r.weight,
      ];

  weight.WeightRecord _rowToWeightRecord(List<dynamic> row) {
    return weight.WeightRecord(
      uuid: row[0].toString(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        int.parse(row[1].toString()),
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        int.parse(row[2].toString()),
      ),
      syncStatus: weight.SyncStatus.synced,
      weight: double.parse(row[3].toString()),
    );
  }
}
