// 요약 탭: 서버 집계 DTO (소비 kcal/목표/볼륨/부위/추정 운동 kcal).
import { api, asList, num, pick } from '../api.js';
import { state, commas, pct, round1 } from '../state.js';
import { $, h, render, emptyNote, toast } from '../dom.js';

export function init() {
  $('summaryRefresh').addEventListener('click', () => {
    refresh().then(() => toast('요약 갱신됨')).catch((err) => toast('갱신 실패: ' + err.message, true));
  });
}

export async function refresh() {
  const [summary, routine] = await Promise.all([
    api.get('/api/v1/summary', { date: state.dateKey }),
    api.get('/api/v1/daily-routine/' + state.dateKey).catch(() => null),
  ]);

  const consumed = num(pick(summary, 'consumed_calories', 'consumedCalories'), 0);
  const target = num(pick(summary, 'target_calories', 'targetCalories'), 0);
  const carbs = num(pick(summary, 'carbs'), 0);
  const protein = num(pick(summary, 'protein'), 0);
  const fat = num(pick(summary, 'fat'), 0);

  $('summaryKcalLabel').textContent = `${commas(consumed)} / ${target ? commas(target) : '–'} kcal`;
  $('summaryKcalBar').style.width = pct(consumed, target) + '%';
  setMacro('summaryCarbs', 'summaryCarbsBar', carbs, num(pick(summary, 'target_carbs', 'targetCarbs'), 0));
  setMacro('summaryProtein', 'summaryProteinBar', protein, num(pick(summary, 'target_protein', 'targetProtein'), 0));
  setMacro('summaryFat', 'summaryFatBar', fat, num(pick(summary, 'target_fat', 'targetFat'), 0));

  const isWorkoutDay = Boolean(pick(summary, 'is_workout_day', 'isWorkoutDay'));
  const setCount = num(pick(summary, 'set_count', 'setCount'), 0);
  $('summaryDayChip').textContent = isWorkoutDay ? '운동일' : '휴식일';
  $('summaryDayChip').className = 'chip ' + (isWorkoutDay ? 'mint' : '');

  const muscles = asList(pick(summary, 'muscles')).map(String);
  render($('summaryMuscles'), muscles.length
    ? muscles.map((muscle) => h('span', { class: 'chip', text: muscle }))
    : [h('span', { class: 'muted', text: '기록된 부위 없음' })]);

  const volume = num(pick(summary, 'total_volume', 'totalVolume'), 0);
  const avgRpe = num(pick(summary, 'avg_rpe', 'avgRpe'), 0);
  const estimated = num(pick(summary, 'estimated_exercise_kcal', 'estimatedExerciseKcal'), 0);
  $('summaryVolume').textContent = `볼륨 ${commas(volume)}kg · ${setCount}세트 · 평균 RPE ${avgRpe ? round1(avgRpe).toFixed(1) : '–'} · 추정 운동 ${commas(estimated)} kcal`;

  const items = asList(pick(routine, 'items_json', 'items')).map((item) => pick(item, 'name', 'exercise_name') || '');
  render($('summaryRoutine'), items.length
    ? items.filter(Boolean).map((name) => h('span', { class: 'chip mint', text: name }))
    : [emptyNote('계획된 루틴이 없습니다')]);
}

function setMacro(valueId, barId, value, target) {
  $(valueId).textContent = `${Math.round(value)}g${target ? ' / ' + Math.round(target) + 'g' : ''}`;
  $(barId).style.width = pct(value, target) + '%';
}
