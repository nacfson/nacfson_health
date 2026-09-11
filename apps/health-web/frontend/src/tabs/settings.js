// 설정 탭: 프로필/영양 목표, 운동 템플릿, 루틴 프리셋, 로그아웃.
import { api, asList, num, pick } from '../api.js';
import { state, exerciseTemplates, addDays, todayKey } from '../state.js';
import { $, h, render, emptyNote, toast, guard, MUSCLE_TYPES, fillSelect } from '../dom.js';

const GOAL_LABELS = { diet: '다이어트', lean_cut: '린매스(감량)', lean_gain: '린매스(증량)', bulk_up: '벌크업' };

let templates = [];
let routines = [];
let editingTemplate = null;

export function init() {
  $('profileForm').addEventListener('submit', onProfileSubmit);
  $('recalcTargets').addEventListener('click', onRecalculate);

  $('etToggle').addEventListener('click', () => {
    const form = $('exerciseTemplateForm');
    form.hidden = !form.hidden;
    if (!form.hidden) $('etName').focus();
  });
  $('etCancel').addEventListener('click', () => resetTemplateForm());
  $('exerciseTemplateForm').addEventListener('submit', onTemplateSubmit);
  $('routinePresetForm').addEventListener('submit', onPresetSubmit);
}

export async function refresh() {
  const [profile, templateList, routinePayload] = await Promise.all([
    api.get('/api/v1/profile').catch(() => null),
    exerciseTemplates(),
    api.get('/api/v1/workout-routines').catch(() => []),
  ]);
  fillProfile(profile);
  templates = templateList;
  routines = asList(routinePayload).map((row) => ({
    uuid: pick(row, 'uuid', 'id'),
    name: pick(row, 'name') || '',
    items: asList(pick(row, 'items_json', 'items')),
  })).filter((row) => row.uuid);
  renderTemplates();
  renderRoutines();
}

// ---- 프로필 ----
function fillProfile(profile) {
  if (!profile) {
    $('profileGoalChip').textContent = '미설정';
    return;
  }
  const goal = pick(profile, 'goal') || 'lean_cut';
  $('profileGoalChip').textContent = GOAL_LABELS[goal] || goal;
  $('pfGender').value = pick(profile, 'gender') || 'male';
  $('pfAge').value = String(num(pick(profile, 'age'), 30));
  $('pfHeight').value = String(num(pick(profile, 'height_m', 'heightM'), 1.75));
  $('pfGoal').value = goal;
  $('pfActivity').value = pick(profile, 'activity_level', 'activityLevel') || 'moderate';
  $('pfIntensity').value = pick(profile, 'training_intensity', 'trainingIntensity') || 'moderate';
  setValue('pfTargetCalories', pick(profile, 'target_calories', 'targetCalories'));
  setValue('pfTargetCarbs', pick(profile, 'target_carbs', 'targetCarbs'));
  setValue('pfTargetProtein', pick(profile, 'target_protein', 'targetProtein'));
  setValue('pfTargetFat', pick(profile, 'target_fat', 'targetFat'));
  state.profile = profile;
}

function setValue(id, value) {
  $(id).value = value === undefined || value === null || num(value, 0) === 0 ? '' : String(value);
}

function profilePayload() {
  return {
    gender: $('pfGender').value,
    age: Math.round(num($('pfAge').value, 30)),
    height_m: num($('pfHeight').value, 1.75),
    goal: $('pfGoal').value,
    activity_level: $('pfActivity').value,
    training_intensity: $('pfIntensity').value,
    target_calories: num($('pfTargetCalories').value, 0),
    target_carbs: num($('pfTargetCarbs').value, 0),
    target_protein: num($('pfTargetProtein').value, 0),
    target_fat: num($('pfTargetFat').value, 0),
  };
}

async function onProfileSubmit(event) {
  event.preventDefault();
  const button = event.submitter || $('profileForm').querySelector('button[type="submit"]');
  guard(button, true);
  try {
    const saved = await api.put('/api/v1/profile', profilePayload());
    if (saved && typeof saved === 'object') fillProfile(saved);
    toast('프로필 저장됨');
  } catch (err) {
    toast('저장 실패: ' + err.message, true);
  } finally {
    guard(button, false);
  }
}

async function onRecalculate() {
  const button = $('recalcTargets');
  guard(button, true);
  try {
    const weight = await latestWeight();
    const profile = await api.post('/api/v1/profile/recalculate-targets', weight ? { weight } : {});
    if (profile && typeof profile === 'object') fillProfile(profile);
    toast(weight ? `목표 재계산됨 (체중 ${weight}kg 기준)` : '목표 재계산됨');
  } catch (err) {
    toast('재계산 실패: ' + err.message, true);
  } finally {
    guard(button, false);
  }
}

async function latestWeight() {
  try {
    const to = todayKey();
    const payload = await api.get('/api/v1/weight', { from: addDays(to, -29), to });
    const rows = asList(payload);
    if (rows.length === 0) return 0;
    const newest = rows
      .map((row) => ({ at: String(pick(row, 'recorded_at', 'recordedAt') || ''), weight: num(pick(row, 'weight', 'weight_kg'), 0) }))
      .sort((a, b) => a.at.localeCompare(b.at))
      .pop();
    return newest.weight;
  } catch {
    return 0;
  }
}

// ---- 운동 템플릿 ----
function renderTemplates() {
  const container = $('exerciseTemplates');
  if (templates.length === 0) {
    render(container, emptyNote('저장된 운동 템플릿이 없습니다'));
    return;
  }
  render(container, templates.map((template) => h('div', { class: 'food' },
    h('div', {
      title: '탭하여 수정',
      style: { cursor: 'pointer' },
      onclick: () => editTemplate(template),
    },
      template.name,
      h('small', { text: `${template.type}${template.restSeconds ? ` · 휴식 ${template.restSeconds}초` : ''}` })),
    h('div', { class: 'val' },
      h('button', {
        class: 'icon-btn',
        type: 'button',
        title: '삭제',
        onclick: () => deleteTemplate(template),
      }, '🗑')))));
}

function editTemplate(template) {
  editingTemplate = template.uuid;
  $('exerciseTemplateForm').hidden = false;
  $('etName').value = template.name;
  if (MUSCLE_TYPES.includes(template.type)) $('etType').value = template.type;
  $('etRest').value = template.restSeconds ? String(template.restSeconds) : '';
}

function resetTemplateForm() {
  editingTemplate = null;
  $('exerciseTemplateForm').reset();
  $('exerciseTemplateForm').hidden = true;
  fillSelect($('etType'), MUSCLE_TYPES.map((type) => ({ value: type, label: type })), '가슴');
}

async function onTemplateSubmit(event) {
  event.preventDefault();
  const name = $('etName').value.trim();
  if (!name) return;
  const rest = num($('etRest').value, 0);
  const master = state.master.exercises.find((exercise) => exercise.name === name);
  const payload = {
    name,
    exercise_type: $('etType').value,
    rest_seconds_override: rest > 0 ? rest : undefined,
  };
  if (master) {
    payload.exercise_key = master.key;
    payload.category_key = master.categoryKey;
  }
  try {
    if (editingTemplate) {
      await api.patch('/api/v1/exercise-templates/' + editingTemplate, payload);
      toast('템플릿 수정됨');
    } else {
      await api.post('/api/v1/exercise-templates', payload);
      toast('템플릿 저장됨');
    }
    state.templates = null;
    resetTemplateForm();
    await refresh();
  } catch (err) {
    toast('템플릿 저장 실패: ' + err.message, true);
  }
}

async function deleteTemplate(template) {
  if (!window.confirm(`템플릿 "${template.name}"을(를) 삭제할까요?`)) return;
  try {
    await api.del('/api/v1/exercise-templates/' + template.uuid);
    toast('템플릿 삭제됨');
    state.templates = null;
    await refresh();
  } catch (err) {
    toast('삭제 실패: ' + err.message, true);
  }
}

// ---- 루틴 프리셋 ----
function renderRoutines() {
  const container = $('workoutRoutines');
  if (routines.length === 0) {
    render(container, emptyNote('저장된 루틴 프리셋이 없습니다'));
    return;
  }
  render(container, routines.map((routine) => h('div', { class: 'food' },
    h('div', {},
      routine.name,
      h('small', { text: routine.items.map((item) => pick(item, 'name', 'exercise_name') || '').filter(Boolean).join(' · ') || '항목 없음' })),
    h('div', { class: 'val' },
      h('button', {
        class: 'btn mini soft',
        type: 'button',
        onclick: () => applyRoutine(routine),
      }, '적용'),
      h('button', {
        class: 'icon-btn',
        type: 'button',
        title: '삭제',
        onclick: () => deleteRoutine(routine),
      }, '🗑')))));
}

async function currentRoutineItems() {
  const payload = await api.get('/api/v1/daily-routine/' + state.dateKey);
  return asList(pick(payload, 'items_json', 'items'));
}

async function onPresetSubmit(event) {
  event.preventDefault();
  const name = $('rpName').value.trim();
  if (!name) return;
  try {
    const items = await currentRoutineItems();
    if (items.length === 0) {
      toast('선택일 루틴이 비어 있습니다', true);
      return;
    }
    await api.post('/api/v1/workout-routines', { name, items_json: items });
    toast('프리셋 저장됨');
    $('routinePresetForm').reset();
    await refresh();
  } catch (err) {
    toast('프리셋 저장 실패: ' + err.message, true);
  }
}

async function applyRoutine(routine) {
  try {
    await api.put('/api/v1/daily-routine/' + state.dateKey, { items_json: routine.items });
    toast(`"${routine.name}" 루틴 적용됨`);
  } catch (err) {
    toast('적용 실패: ' + err.message, true);
  }
}

async function deleteRoutine(routine) {
  if (!window.confirm(`프리셋 "${routine.name}"을(를) 삭제할까요?`)) return;
  try {
    await api.del('/api/v1/workout-routines/' + routine.uuid);
    toast('프리셋 삭제됨');
    await refresh();
  } catch (err) {
    toast('삭제 실패: ' + err.message, true);
  }
}
