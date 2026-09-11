// 운동 탭: daily_routine 계획 + 세트 CRUD + 인페이지 휴식 타이머.
import { api, asList, num, pick } from '../api.js';
import { state, isoForDateKey, commas, exerciseTemplates } from '../state.js';
import { $, h, render, emptyNote, toast, guard, MUSCLE_TYPES, SET_TYPE_LABELS } from '../dom.js';

let records = [];
let routineItems = [];
let restOverrides = new Map();
let editingUuid = null;

const normalize = (row) => ({
  uuid: pick(row, 'uuid', 'id'),
  recordedAt: pick(row, 'recorded_at', 'recordedAt'),
  type: pick(row, 'exercise_type', 'exerciseType') || '기타',
  name: pick(row, 'exercise_name', 'exerciseName') || '',
  key: pick(row, 'exercise_key', 'exerciseKey') || null,
  categoryKey: pick(row, 'category_key', 'categoryKey') || null,
  setNumber: num(pick(row, 'current_set', 'currentSet'), 0),
  weight: num(pick(row, 'weight'), 0),
  reps: num(pick(row, 'reps'), 0),
  rpe: num(pick(row, 'rpe'), 0),
  setType: pick(row, 'set_type', 'setType') || 'work',
});

const normalizeRoutine = (payload) => asList(pick(payload, 'items_json', 'items')).map((item) => ({
  type: pick(item, 'type', 'exercise_type', 'exerciseType') || '기타',
  name: pick(item, 'name', 'exercise_name', 'exerciseName') || '',
  exerciseKey: pick(item, 'exerciseKey', 'exercise_key') || undefined,
  categoryKey: pick(item, 'categoryKey', 'category_key') || undefined,
})).filter((item) => item.name);

const isVolumeSet = (set) => set.setType === 'work' || set.setType === 'drop';

export function init() {
  $('routineToggle').addEventListener('click', () => {
    const form = $('routineForm');
    form.hidden = !form.hidden;
    if (!form.hidden) $('routineName').focus();
  });
  $('routineCancel').addEventListener('click', () => { $('routineForm').hidden = true; });
  $('routineForm').addEventListener('submit', onRoutineSubmit);

  $('setFormToggle').addEventListener('click', () => {
    const card = $('setFormCard');
    card.hidden = false;
    $('setName').focus();
  });
  $('setCancel').addEventListener('click', () => { $('setFormCard').hidden = true; });
  $('setEditCancel').addEventListener('click', () => { resetSetForm(true); });
  $('setForm').addEventListener('submit', onSetSubmit);
  $('setName').addEventListener('change', () => applyExerciseMeta($('setName').value.trim()));

  $('restPreset').addEventListener('change', () => restReset());
  $('restStart').addEventListener('click', () => restStart());
  $('restPause').addEventListener('click', restPause);
  $('restReset').addEventListener('click', () => restReset());
  renderRest();
}

export async function refresh() {
  const date = state.dateKey;
  const [setsPayload, routinePayload, templates] = await Promise.all([
    api.get('/api/v1/exercise', { date }),
    api.get('/api/v1/daily-routine/' + date).catch(() => null),
    exerciseTemplates().catch(() => []),
  ]);
  records = asList(setsPayload).map(normalize).filter((row) => row.uuid);
  routineItems = normalizeRoutine(routinePayload);
  restOverrides = new Map(templates.filter((t) => t.name && t.restSeconds).map((t) => [t.name, t.restSeconds]));
  renderRoutine();
  renderGroups();
}

function renderRoutine() {
  const chip = $('routineChip');
  const types = [...new Set(routineItems.map((item) => item.type).filter((t) => t && t !== '기타'))];
  chip.textContent = types.length ? types.join(' · ') : (routineItems.length ? '기타' : '비어 있음');

  render($('routineList'), routineItems.length === 0
    ? [emptyNote('아직 계획된 운동이 없습니다. 세트를 기록하면 자동으로 추가됩니다.')]
    : routineItems.map((item, index) => h('span', { class: 'chip mint' },
        item.name,
        h('button', {
          class: 'icon-btn',
          type: 'button',
          title: '루틴에서 제거',
          onclick: () => removeRoutineItem(index),
        }, '×'),
      )));
}

function renderGroups() {
  const container = $('exerciseGroups');
  if (records.length === 0) {
    render(container, h('div', { class: 'card' }, emptyNote('선택일에 기록된 세트가 없습니다')));
    return;
  }

  const groups = new Map();
  for (const set of [...records].sort((a, b) => String(a.recordedAt).localeCompare(String(b.recordedAt)))) {
    if (!groups.has(set.name)) groups.set(set.name, []);
    groups.get(set.name).push(set);
  }

  render(container, [...groups.entries()].map(([name, sets]) => {
    const volume = sets.filter(isVolumeSet).reduce((sum, set) => sum + set.weight * set.reps, 0);
    const rest = restOverrides.get(name);
    const meta = `${sets.length}세트 · ${commas(volume)}kg${rest ? ` · 휴식 ${rest}초` : ''}`;
    return h('div', { class: 'card' },
      h('div', { class: 'ex-head' },
        h('span', { class: 'name', text: name }),
        h('span', { class: 'meta', text: meta })),
      h('table', { class: 'set-table' },
        h('thead', {}, h('tr', {},
          h('th', { text: '세트' }), h('th', { text: '중량' }), h('th', { text: '횟수' }),
          h('th', { text: 'RPE' }), h('th', { text: '' }))),
        h('tbody', {}, sets.map((set) => setRow(set)))),
    );
  }));
}

function setRow(set) {
  const tagClass = set.setType === 'warmup' ? 'tag w' : set.setType === 'drop' ? 'tag d' : set.setType === 'failure' ? 'tag f' : 'tag';
  const label = set.setType === 'warmup' ? 'W' : String(set.setNumber || '·');
  return h('tr', {
    class: 'set-row',
    title: '탭하여 수정',
    onclick: () => editSet(set),
  },
    h('td', {}, h('span', { class: tagClass, title: SET_TYPE_LABELS[set.setType] || set.setType, text: label })),
    h('td', { text: `${set.weight}kg` }),
    h('td', { text: String(set.reps) }),
    h('td', { text: set.rpe ? set.rpe.toFixed(1) : '–' }),
    h('td', {}, h('button', {
      class: 'icon-btn',
      type: 'button',
      title: '삭제',
      onclick: (event) => { event.stopPropagation(); deleteSet(set); },
    }, '🗑')));
}

function applyExerciseMeta(name) {
  const master = state.master.exercises.find((exercise) => exercise.name === name);
  const routineItem = routineItems.find((item) => item.name === name);
  const category = master && state.master.categories.find((c) => c.key === master.categoryKey);
  const type = (routineItem && routineItem.type) || (category && category.name) || '기타';
  if (MUSCLE_TYPES.includes(type)) $('setExerciseType').value = type;
}

function masterFor(name) {
  return state.master.exercises.find((exercise) => exercise.name === name);
}

function nextSetNumber(name) {
  const same = records.filter((set) => set.name === name);
  return same.reduce((max, set) => Math.max(max, set.setNumber), 0) + 1;
}

function editSet(set) {
  editingUuid = set.uuid;
  $('setFormCard').hidden = false;
  $('setEditChip').hidden = false;
  $('setEditCancel').hidden = false;
  $('setSubmit').textContent = '수정 저장';
  $('setName').value = set.name;
  $('setExerciseType').value = MUSCLE_TYPES.includes(set.type) ? set.type : '기타';
  $('setType').value = set.setType;
  $('setWeight').value = String(set.weight);
  $('setReps').value = String(set.reps);
  $('setRpe').value = String(set.rpe);
  $('setFormCard').scrollIntoView({ block: 'nearest' });
}

function resetSetForm(keepValues) {
  editingUuid = null;
  $('setEditChip').hidden = true;
  $('setEditCancel').hidden = true;
  $('setSubmit').textContent = '저장';
  if (!keepValues) {
    $('setForm').reset();
    $('setRpe').value = '7.5';
  }
}

async function onSetSubmit(event) {
  event.preventDefault();
  const name = $('setName').value.trim();
  if (!name) return;
  const master = masterFor(name);
  const existing = editingUuid ? records.find((set) => set.uuid === editingUuid) : null;
  const payload = {
    exercise_name: name,
    exercise_type: $('setExerciseType').value || '기타',
    exercise_key: (master && master.key) || (existing && existing.key) || undefined,
    category_key: (master && master.categoryKey) || (existing && existing.categoryKey) || undefined,
    current_set: existing ? existing.setNumber : nextSetNumber(name),
    weight: num($('setWeight').value, 0),
    reps: Math.max(1, Math.round(num($('setReps').value, 1))),
    rpe: num($('setRpe').value, 0),
    set_type: $('setType').value,
    recorded_at: existing ? existing.recordedAt : isoForDateKey(state.dateKey),
  };
  const submit = $('setSubmit');
  const wasEditing = Boolean(editingUuid);
  guard(submit, true);
  try {
    if (wasEditing) {
      await api.patch('/api/v1/exercise/' + editingUuid, payload);
      toast('세트 수정됨');
    } else {
      await api.post('/api/v1/exercise', payload);
      toast('세트 저장됨');
    }
    const restSeconds = restOverrides.get(name);
    // keep name/weight/reps after a create so the next set is one tap
    resetSetForm(!wasEditing);
    await refresh().catch(() => {});
    restStart(restSeconds);
  } catch (err) {
    toast('저장 실패: ' + err.message, true);
  } finally {
    guard(submit, false);
  }
}

async function deleteSet(set) {
  if (!window.confirm(`"${set.name}" ${set.setNumber || ''}세트를 삭제할까요?`)) return;
  try {
    await api.del('/api/v1/exercise/' + set.uuid);
    toast('삭제됨');
    await refresh();
  } catch (err) {
    toast('삭제 실패: ' + err.message, true);
  }
}

async function onRoutineSubmit(event) {
  event.preventDefault();
  const name = $('routineName').value.trim();
  if (!name) return;
  if (routineItems.some((item) => item.name === name)) {
    toast('이미 루틴에 있습니다', true);
    return;
  }
  const masterKey = $('routineKey').value;
  const master = state.master.exercises.find((exercise) => exercise.key === masterKey);
  const item = {
    type: $('routineType').value,
    name,
    exerciseKey: masterKey || undefined,
    categoryKey: (master && master.categoryKey) || undefined,
  };
  await saveRoutine([...routineItems, item], '루틴에 추가됨');
  $('routineName').value = '';
  $('routineKey').value = '';
  $('routineForm').hidden = true;
}

async function removeRoutineItem(index) {
  const next = routineItems.filter((_, i) => i !== index);
  await saveRoutine(next, '루틴에서 제거됨');
}

async function saveRoutine(items, message) {
  try {
    await api.put('/api/v1/daily-routine/' + state.dateKey, { items_json: items });
    toast(message);
    await refresh();
  } catch (err) {
    toast('루틴 저장 실패: ' + err.message, true);
  }
}

// ---- 인페이지 휴식 타이머 ----
let restRemaining = 90;
let restTimerId = 0;

const mmss = (seconds) => `${Math.floor(seconds / 60)}:${String(Math.max(0, seconds) % 60).padStart(2, '0')}`;

function renderRest() {
  $('restTime').textContent = mmss(restRemaining);
}

function restStart(seconds) {
  if (seconds) {
    restRemaining = seconds;
    if ([...$('restPreset').options].some((option) => option.value === String(seconds))) {
      $('restPreset').value = String(seconds);
    }
  }
  if (!restRemaining) restRemaining = num($('restPreset').value, 90);
  restPause();
  renderRest();
  restTimerId = setInterval(() => {
    restRemaining -= 1;
    renderRest();
    if (restRemaining <= 0) {
      restPause();
      toast('휴식 종료 — 다음 세트');
      if (navigator.vibrate) navigator.vibrate(200);
    }
  }, 1000);
}

function restPause() {
  if (restTimerId) clearInterval(restTimerId);
  restTimerId = 0;
}

function restReset(seconds) {
  restPause();
  restRemaining = seconds || num($('restPreset').value, 90);
  renderRest();
}
