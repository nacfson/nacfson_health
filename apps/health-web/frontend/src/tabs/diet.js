// 식단 탭: 끼니별 기록 CRUD + 음식 템플릿 (칼로리는 서버 Atwater 계산).
import { api, asList, num, pick } from '../api.js';
import { state, isoForDateKey, commas, pct, round1 } from '../state.js';
import { $, h, render, emptyNote, toast, guard, MEALS } from '../dom.js';

let records = [];
let templates = [];
let editingUuid = null;

const normalize = (row) => ({
  uuid: pick(row, 'uuid', 'id'),
  recordedAt: pick(row, 'recorded_at', 'recordedAt'),
  meal: pick(row, 'meal_type', 'mealType') || '간식',
  name: pick(row, 'food_name', 'foodName') || '',
  carbs: num(pick(row, 'carbs'), 0),
  protein: num(pick(row, 'protein'), 0),
  fat: num(pick(row, 'fat'), 0),
  calories: num(pick(row, 'total_calories', 'totalCalories', 'calories'), 0),
  satisfaction: pick(row, 'satisfaction'),
  memo: pick(row, 'memo') || '',
});

export const atwater = (carbs, protein, fat) => Math.round(num(carbs, 0) * 4 + num(protein, 0) * 4 + num(fat, 0) * 9);

export function init() {
  $('foodForm').addEventListener('submit', onFoodSubmit);
  $('foodEditCancel').addEventListener('click', () => resetFoodForm());
  for (const id of ['foodCarbs', 'foodProtein', 'foodFat']) {
    $(id).addEventListener('input', updateKcalPreview);
  }
  $('ftToggle').addEventListener('click', () => {
    const form = $('foodTemplateForm');
    form.hidden = !form.hidden;
    if (!form.hidden) $('ftName').focus();
  });
  $('ftCancel').addEventListener('click', () => { $('foodTemplateForm').hidden = true; });
  $('foodTemplateForm').addEventListener('submit', onTemplateSubmit);
  updateKcalPreview();
}

export async function refresh() {
  const [dietPayload, templatePayload, profile] = await Promise.all([
    api.get('/api/v1/diet', { date: state.dateKey }),
    api.get('/api/v1/food-templates').catch(() => []),
    ensureProfile(),
  ]);
  records = asList(dietPayload).map(normalize).filter((row) => row.uuid);
  templates = asList(templatePayload).map((row) => ({
    uuid: pick(row, 'uuid', 'id'),
    name: pick(row, 'name') || '',
    carbs: num(pick(row, 'carbs'), 0),
    protein: num(pick(row, 'protein'), 0),
    fat: num(pick(row, 'fat'), 0),
    calories: num(pick(row, 'calories'), 0),
  })).filter((row) => row.uuid);
  renderTotals(profile);
  renderGroups();
  renderTemplates();
}

let profilePromise = null;

async function ensureProfile() {
  if (state.profile) return state.profile;
  if (!profilePromise) {
    profilePromise = api.get('/api/v1/profile')
      .then((profile) => { state.profile = profile; return profile; })
      .catch(() => null)
      .finally(() => { profilePromise = null; });
  }
  return profilePromise;
}

const targetOf = (profile, ...keys) => num(pick(profile || {}, ...keys), 0);

function renderTotals(profile) {
  const consumed = records.reduce((sum, row) => sum + row.calories, 0);
  const carbs = records.reduce((sum, row) => sum + row.carbs, 0);
  const protein = records.reduce((sum, row) => sum + row.protein, 0);
  const fat = records.reduce((sum, row) => sum + row.fat, 0);

  const kcalTarget = targetOf(profile, 'target_calories', 'targetCalories');
  const carbTarget = targetOf(profile, 'target_carbs', 'targetCarbs');
  const proteinTarget = targetOf(profile, 'target_protein', 'targetProtein');
  const fatTarget = targetOf(profile, 'target_fat', 'targetFat');

  $('dietKcalLabel').textContent = `${commas(consumed)} / ${kcalTarget ? commas(kcalTarget) : '–'}`;
  $('dietKcalBar').style.width = pct(consumed, kcalTarget) + '%';
  setMacro('dietCarbs', 'dietCarbsBar', carbs, carbTarget);
  setMacro('dietProtein', 'dietProteinBar', protein, proteinTarget);
  setMacro('dietFat', 'dietFatBar', fat, fatTarget);
}

function setMacro(valueId, barId, value, target) {
  $(valueId).textContent = `${Math.round(value)}g${target ? ' / ' + Math.round(target) + 'g' : ''}`;
  $(barId).style.width = pct(value, target) + '%';
}

function renderGroups() {
  const container = $('dietGroups');
  if (records.length === 0) {
    render(container, h('div', { class: 'card' }, emptyNote('선택일에 기록된 식사가 없습니다')));
    return;
  }

  const byMeal = new Map();
  for (const row of records) {
    if (!byMeal.has(row.meal)) byMeal.set(row.meal, []);
    byMeal.get(row.meal).push(row);
  }
  const order = [...MEALS.filter((meal) => byMeal.has(meal)), ...[...byMeal.keys()].filter((meal) => !MEALS.includes(meal))];

  render(container, order.map((meal) => {
    const items = byMeal.get(meal);
    const mealKcal = items.reduce((sum, row) => sum + row.calories, 0);
    return h('div', { class: 'card' },
      h('div', { class: 'row between' },
        h('h3', { text: meal }),
        h('span', { class: 'chip', text: `${commas(mealKcal)} kcal` })),
      ...items.map((row) => h('div', { class: 'food' },
        h('div', {
          title: '탭하여 수정',
          style: { cursor: 'pointer' },
          onclick: () => editFood(row),
        },
          row.name,
          h('small', { text: `탄 ${round1(row.carbs)} · 단 ${round1(row.protein)} · 지 ${round1(row.fat)}${row.satisfaction ? ' · 만족 ' + row.satisfaction : ''}${row.memo ? ' · ' + row.memo : ''}` })),
        h('div', { class: 'val' },
          h('strong', { text: commas(row.calories) }),
          h('button', {
            class: 'icon-btn',
            type: 'button',
            title: '삭제',
            onclick: () => deleteFood(row),
          }, '🗑')))));
  }));
}

function renderTemplates() {
  const container = $('foodTemplates');
  if (templates.length === 0) {
    render(container, emptyNote('저장된 음식 템플릿이 없습니다'));
    return;
  }
  render(container, templates.map((template) => h('div', { class: 'food' },
    h('div', {
      title: '입력 폼 채우기',
      style: { cursor: 'pointer' },
      onclick: () => fillFromTemplate(template),
    },
      template.name,
      h('small', { text: `탄 ${round1(template.carbs)} · 단 ${round1(template.protein)} · 지 ${round1(template.fat)} · ${commas(template.calories)} kcal` })),
    h('div', { class: 'val' },
      h('button', {
        class: 'btn mini soft',
        type: 'button',
        onclick: () => quickAdd(template),
      }, '+ 기록'),
      h('button', {
        class: 'icon-btn',
        type: 'button',
        title: '템플릿 삭제',
        onclick: () => deleteTemplate(template),
      }, '🗑')))));
}

function fillFromTemplate(template) {
  $('foodName').value = template.name;
  $('foodCarbs').value = String(template.carbs);
  $('foodProtein').value = String(template.protein);
  $('foodFat').value = String(template.fat);
  updateKcalPreview();
  $('foodName').focus();
}

async function quickAdd(template) {
  try {
    await api.post('/api/v1/diet', {
      meal_type: $('foodMeal').value,
      food_name: template.name,
      carbs: template.carbs,
      protein: template.protein,
      fat: template.fat,
      recorded_at: isoForDateKey(state.dateKey),
    });
    toast(template.name + ' 기록됨');
    await refresh();
  } catch (err) {
    toast('기록 실패: ' + err.message, true);
  }
}

function updateKcalPreview() {
  const kcal = atwater($('foodCarbs').value, $('foodProtein').value, $('foodFat').value);
  $('foodKcalPreview').textContent = `예상 ${commas(kcal)} kcal (Atwater)`;
}

function editFood(row) {
  editingUuid = row.uuid;
  $('foodEditChip').hidden = false;
  $('foodEditCancel').hidden = false;
  $('foodSubmit').textContent = '수정 저장';
  $('foodMeal').value = MEALS.includes(row.meal) ? row.meal : '간식';
  $('foodName').value = row.name;
  $('foodCarbs').value = String(row.carbs);
  $('foodProtein').value = String(row.protein);
  $('foodFat').value = String(row.fat);
  $('foodSatisfaction').value = row.satisfaction === undefined || row.satisfaction === null ? '' : String(row.satisfaction);
  $('foodMemo').value = row.memo;
  updateKcalPreview();
  $('foodForm').scrollIntoView({ block: 'nearest' });
}

function resetFoodForm() {
  editingUuid = null;
  $('foodEditChip').hidden = true;
  $('foodEditCancel').hidden = true;
  $('foodSubmit').textContent = '기록';
  $('foodForm').reset();
  $('foodMeal').value = '점심';
  $('foodSatisfaction').value = '3';
  updateKcalPreview();
}

async function onFoodSubmit(event) {
  event.preventDefault();
  const name = $('foodName').value.trim();
  if (!name) return;
  const existing = editingUuid ? records.find((row) => row.uuid === editingUuid) : null;
  const satisfactionRaw = $('foodSatisfaction').value;
  const payload = {
    meal_type: $('foodMeal').value,
    food_name: name,
    carbs: num($('foodCarbs').value, 0),
    protein: num($('foodProtein').value, 0),
    fat: num($('foodFat').value, 0),
    satisfaction: satisfactionRaw === '' ? undefined : num(satisfactionRaw, 0),
    memo: $('foodMemo').value.trim() || undefined,
    recorded_at: existing ? existing.recordedAt : isoForDateKey(state.dateKey),
  };
  const submit = $('foodSubmit');
  const wasEditing = Boolean(editingUuid);
  guard(submit, true);
  try {
    if (wasEditing) {
      await api.patch('/api/v1/diet/' + editingUuid, payload);
      toast('식사 수정됨');
    } else {
      await api.post('/api/v1/diet', payload);
      toast('식사 기록됨');
    }
    resetFoodForm();
    await refresh();
  } catch (err) {
    toast('저장 실패: ' + err.message, true);
  } finally {
    guard(submit, false);
  }
}

async function deleteFood(row) {
  if (!window.confirm(`"${row.name}" 기록을 삭제할까요?`)) return;
  try {
    await api.del('/api/v1/diet/' + row.uuid);
    toast('삭제됨');
    await refresh();
  } catch (err) {
    toast('삭제 실패: ' + err.message, true);
  }
}

async function onTemplateSubmit(event) {
  event.preventDefault();
  const name = $('ftName').value.trim();
  if (!name) return;
  try {
    await api.post('/api/v1/food-templates', {
      name,
      carbs: num($('ftCarbs').value, 0),
      protein: num($('ftProtein').value, 0),
      fat: num($('ftFat').value, 0),
    });
    toast('템플릿 저장됨');
    $('foodTemplateForm').reset();
    $('foodTemplateForm').hidden = true;
    await refresh();
  } catch (err) {
    toast('템플릿 저장 실패: ' + err.message, true);
  }
}

async function deleteTemplate(template) {
  if (!window.confirm(`템플릿 "${template.name}"을(를) 삭제할까요?`)) return;
  try {
    await api.del('/api/v1/food-templates/' + template.uuid);
    toast('템플릿 삭제됨');
    await refresh();
  } catch (err) {
    toast('삭제 실패: ' + err.message, true);
  }
}
