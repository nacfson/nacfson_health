// 체중 탭: 기록 CRUD + 30일 추세 차트.
import { api, asList, num, pick } from '../api.js';
import { state, isoForDateKey, isoDate, todayKey, addDays, round1 } from '../state.js';
import { $, h, render, emptyNote, toast, guard } from '../dom.js';

let records = [];
let editingUuid = null;

const normalize = (row) => ({
  uuid: pick(row, 'uuid', 'id'),
  recordedAt: pick(row, 'recorded_at', 'recordedAt'),
  dateKey: isoDate(pick(row, 'recorded_at', 'recordedAt')),
  weight: num(pick(row, 'weight', 'weight_kg', 'weightKg'), 0),
});

export function init() {
  $('weightForm').addEventListener('submit', onSubmit);
  $('weightEditCancel').addEventListener('click', () => resetForm());
}

export async function refresh() {
  const to = todayKey();
  const from = addDays(to, -29);
  const payload = await api.get('/api/v1/weight', { from, to });
  records = asList(payload).map(normalize).filter((row) => row.uuid);
  renderToday();
  renderChart();
  renderList();
}

const sorted = () => [...records].sort((a, b) => a.dateKey.localeCompare(b.dateKey));

function renderToday() {
  const selected = records.filter((row) => row.dateKey === state.dateKey);
  const latest = selected[selected.length - 1] || sorted().slice(-1)[0];
  $('weightLatest').textContent = latest ? `${round1(latest.weight)} kg` : '– kg';

  if (!latest) {
    $('weightDelta').textContent = '기록 없음';
    return;
  }
  const window = sorted().filter((row) => row.dateKey <= latest.dateKey).slice(-8, -1);
  if (window.length === 0) {
    $('weightDelta').textContent = `${latest.dateKey} 기준`;
    return;
  }
  const avg = window.reduce((sum, row) => sum + row.weight, 0) / window.length;
  const delta = round1(latest.weight - avg);
  const sign = delta > 0 ? '+' : '';
  $('weightDelta').textContent = `직전 ${window.length}회 평균 대비 ${sign}${delta} kg`;
}

function renderChart() {
  const container = $('weightChart');
  const points = sorted();
  if (points.length < 2) {
    render(container, h('p', { class: 'empty', style: { padding: '8px' }, text: '추세를 그리려면 2개 이상의 기록이 필요합니다' }));
    return;
  }
  const weights = points.map((row) => row.weight);
  const min = Math.min(...weights);
  const max = Math.max(...weights);
  const span = max - min || 1;
  const width = 640;
  const height = 200;
  const step = points.length > 1 ? (width - 24) / (points.length - 1) : 0;
  const coords = points.map((row, index) => {
    const x = 12 + index * step;
    const y = 180 - ((row.weight - min) / span) * 150;
    return [Math.round(x * 10) / 10, Math.round(y * 10) / 10];
  });
  const last = coords[coords.length - 1];

  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', `0 0 ${width} ${height}`);
  svg.setAttribute('preserveAspectRatio', 'none');
  svg.setAttribute('aria-hidden', 'true');
  const polyline = document.createElementNS('http://www.w3.org/2000/svg', 'polyline');
  polyline.setAttribute('fill', 'none');
  polyline.setAttribute('stroke', '#0B1B2B');
  polyline.setAttribute('stroke-width', '2.5');
  polyline.setAttribute('points', coords.map(([x, y]) => `${x},${y}`).join(' '));
  const dot = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
  dot.setAttribute('cx', String(last[0]));
  dot.setAttribute('cy', String(last[1]));
  dot.setAttribute('r', '3.5');
  dot.setAttribute('fill', '#2BAF95');
  svg.append(polyline, dot);
  render(container, svg);

  const delta = round1(points[points.length - 1].weight - points[0].weight);
  $('weightTrendChip').textContent = `${points.length}건 · ${delta > 0 ? '+' : ''}${delta} kg`;
}

function renderList() {
  const container = $('weightList');
  const recent = sorted().slice(-14).reverse();
  if (recent.length === 0) {
    render(container, emptyNote('기록된 체중이 없습니다'));
    return;
  }
  render(container, recent.map((row) => h('div', { class: 'food' },
    h('div', {
      title: '탭하여 수정',
      style: { cursor: 'pointer' },
      onclick: () => edit(row),
    },
      row.dateKey,
      h('small', { text: row.dateKey === state.dateKey ? '선택일' : '' })),
    h('div', { class: 'val' },
      h('strong', { text: `${round1(row.weight)} kg` }),
      h('button', {
        class: 'icon-btn',
        type: 'button',
        title: '삭제',
        onclick: () => remove(row),
      }, '🗑')))));
}

function edit(row) {
  editingUuid = row.uuid;
  $('weightEditChip').hidden = false;
  $('weightEditCancel').hidden = false;
  $('weightSubmit').textContent = '수정 저장';
  $('weightValue').value = String(row.weight);
  $('weightForm').scrollIntoView({ block: 'nearest' });
}

function resetForm() {
  editingUuid = null;
  $('weightEditChip').hidden = true;
  $('weightEditCancel').hidden = true;
  $('weightSubmit').textContent = '선택일에 기록';
  $('weightForm').reset();
}

async function onSubmit(event) {
  event.preventDefault();
  const weight = num($('weightValue').value, 0);
  if (weight <= 0) {
    toast('체중을 입력하세요', true);
    return;
  }
  const existing = editingUuid ? records.find((row) => row.uuid === editingUuid) : null;
  const payload = {
    weight,
    recorded_at: existing ? existing.recordedAt : isoForDateKey(state.dateKey),
  };
  const submit = $('weightSubmit');
  const wasEditing = Boolean(editingUuid);
  guard(submit, true);
  try {
    if (wasEditing) {
      await api.patch('/api/v1/weight/' + editingUuid, payload);
      toast('체중 수정됨');
    } else {
      await api.post('/api/v1/weight', payload);
      toast('체중 기록됨');
    }
    resetForm();
    await refresh();
  } catch (err) {
    toast('저장 실패: ' + err.message, true);
  } finally {
    guard(submit, false);
  }
}

async function remove(row) {
  if (!window.confirm(`${row.dateKey} 체중 기록을 삭제할까요?`)) return;
  try {
    await api.del('/api/v1/weight/' + row.uuid);
    toast('삭제됨');
    await refresh();
  } catch (err) {
    toast('삭제 실패: ' + err.message, true);
  }
}
