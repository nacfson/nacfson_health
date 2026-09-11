// Selected day (Asia/Seoul — matches server date filters), current user, formatting.
import { api, asList, pick, num } from './api.js';

export const SEOUL_TZ = 'Asia/Seoul';

const WEEKDAYS = ['일', '월', '화', '수', '목', '금', '토'];

export const state = {
  dateKey: todayKey(),
  user: null,
  master: { categories: [], exercises: [] },
  profile: null,
  templates: null,
};

// Shared exercise_templates cache (workout rest overrides + settings list).
export async function exerciseTemplates(force) {
  if (state.templates && !force) return state.templates;
  const payload = await api.get('/api/v1/exercise-templates');
  state.templates = asList(payload).map((row) => ({
    uuid: pick(row, 'uuid', 'id'),
    name: pick(row, 'name') || '',
    type: pick(row, 'exercise_type', 'exerciseType') || '기타',
    exerciseKey: pick(row, 'exercise_key', 'exerciseKey') || '',
    categoryKey: pick(row, 'category_key', 'categoryKey') || '',
    restSeconds: num(pick(row, 'rest_seconds_override', 'restSecondsOverride'), 0),
  })).filter((row) => row.uuid);
  return state.templates;
}

const dateListeners = new Set();

export function onDateChange(fn) {
  dateListeners.add(fn);
}

export function setDateKey(key) {
  if (!key || key === state.dateKey) return;
  state.dateKey = key;
  for (const fn of dateListeners) fn(key);
}

export function shiftDate(days) {
  setDateKey(addDays(state.dateKey, days));
}

export function todayKey() {
  // en-CA yields YYYY-MM-DD.
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: SEOUL_TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date());
}

export function addDays(key, days) {
  const { y, m, d } = parseKey(key);
  const next = new Date(Date.UTC(y, m - 1, d + days));
  return toKey(next.getUTCFullYear(), next.getUTCMonth() + 1, next.getUTCDate());
}

export function parseKey(key) {
  const [y, m, d] = String(key).split('-').map(Number);
  return { y, m, d };
}

export function toKey(y, m, d) {
  return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

export function labelKo(key) {
  const { y, m, d } = parseKey(key);
  const weekday = WEEKDAYS[new Date(Date.UTC(y, m - 1, d)).getUTCDay()];
  return `${m}월 ${d}일 (${weekday})`;
}

// Midday Asia/Seoul of the given calendar day — keeps records inside the
// Seoul day the API filters on, regardless of browser timezone.
export function isoForDateKey(key) {
  const { y, m, d } = parseKey(key);
  return new Date(Date.UTC(y, m - 1, d, 3, 0, 0)).toISOString();
}

export function isoDate(iso) {
  if (!iso) return '';
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return '';
  return new Intl.DateTimeFormat('en-CA', { timeZone: SEOUL_TZ, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(t));
}

export function timeKo(iso) {
  if (!iso) return '';
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return '';
  return new Intl.DateTimeFormat('ko-KR', { timeZone: SEOUL_TZ, hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date(t));
}

export function dayOffset(key) {
  const { y, m, d } = parseKey(key);
  const a = Date.UTC(y, m - 1, d);
  const { y: ty, m: tm, d: td } = parseKey(todayKey());
  return Math.round((a - Date.UTC(ty, tm - 1, td)) / 86400000);
}

export const pct = (value, target) => (target > 0 ? Math.max(0, Math.min(100, Math.round((value / target) * 100))) : 0);

export const round1 = (value) => Math.round(value * 10) / 10;

export const commas = (value) => Math.round(numSafe(value)).toLocaleString('ko-KR');

function numSafe(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}
