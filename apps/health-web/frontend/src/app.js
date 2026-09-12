// App shell: History router, Seoul date bar, master data.
import { api, asList, pick } from './api.js';
import { state, todayKey, labelKo, setDateKey, shiftDate, onDateChange } from './state.js';
import { $, fillSelect, toast, MUSCLE_TYPES } from './dom.js';
import { bootstrap, wireAuthHandlers } from './auth.js';
import {
  DEFAULT_TAB,
  labelForTab,
  navigate,
  resolveInitialTab,
  wirePopstate,
} from './router.js';
import * as workout from './tabs/workout.js';
import * as diet from './tabs/diet.js';
import * as weight from './tabs/weight.js';
import * as summary from './tabs/summary.js';
import * as settings from './tabs/settings.js';

const TABS = { workout, diet, weight, summary, settings };

let activeTab = DEFAULT_TAB;

function setSidebarOpen(open) {
  const shell = $('app');
  const backdrop = $('sidebarBackdrop');
  if (!shell) return;
  shell.classList.toggle('nav-open', open);
  if (backdrop) backdrop.hidden = !open;
}

function switchTab(name, { fromPop = false, skipRefresh = false } = {}) {
  if (!TABS[name]) return;
  activeTab = name;
  if (!fromPop) navigate(name);

  for (const link of document.querySelectorAll('#nav [data-tab]')) {
    link.classList.toggle('on', link.dataset.tab === name);
  }
  for (const brand of document.querySelectorAll('.brand[data-tab]')) {
    brand.classList.toggle('on', brand.dataset.tab === name);
  }
  for (const screen of document.querySelectorAll('.screen')) {
    screen.classList.toggle('on', screen.dataset.screen === name);
  }

  const title = $('pageTitleSlot');
  if (title) title.textContent = labelForTab(name);

  const content = $('content');
  if (content) content.scrollTop = 0;
  setSidebarOpen(false);

  if (!skipRefresh) refreshActive();
}

function refreshActive() {
  const tab = TABS[activeTab];
  if (!tab) return;
  tab.refresh().catch((err) => toast('불러오기 실패: ' + err.message, true));
}

function renderDateBar() {
  $('dateLabel').textContent = labelKo(state.dateKey);
  $('dateToday').hidden = state.dateKey === todayKey();
}

function wireShell() {
  for (const link of document.querySelectorAll('#nav [data-tab], .brand[data-tab]')) {
    link.addEventListener('click', (event) => {
      event.preventDefault();
      switchTab(link.dataset.tab);
    });
  }

  $('datePrev').addEventListener('click', () => shiftDate(-1));
  $('dateNext').addEventListener('click', () => shiftDate(1));
  $('dateToday').addEventListener('click', () => setDateKey(todayKey()));
  onDateChange(() => {
    renderDateBar();
    refreshActive();
  });
  renderDateBar();

  const toggle = $('sidebarToggle');
  if (toggle) toggle.addEventListener('click', () => {
    const shell = $('app');
    setSidebarOpen(!(shell && shell.classList.contains('nav-open')));
  });
  const backdrop = $('sidebarBackdrop');
  if (backdrop) backdrop.addEventListener('click', () => setSidebarOpen(false));

  wirePopstate((tab) => switchTab(tab, { fromPop: true }));
}

export function fillMuscleSelects() {
  for (const id of ['routineType', 'etType', 'setExerciseType']) {
    const select = $(id);
    if (select) fillSelect(select, MUSCLE_TYPES.map((t) => ({ value: t, label: t })), select.value || '가슴');
  }
}

async function loadMaster() {
  try {
    const payload = await api.get('/api/v1/master/exercises', { locale: 'ko' });
    const categories = asList(pick(payload, 'categories'));
    const exercises = asList(pick(payload, 'exercises'));
    state.master = {
      categories: categories.map((c) => ({
        key: pick(c, 'category_key', 'key'),
        name: pick(c, 'display_name', 'name') || pick(c, 'category_key'),
      })),
      exercises: exercises.map((e) => ({
        key: pick(e, 'exercise_key', 'key'),
        categoryKey: pick(e, 'category_key', 'categoryKey'),
        name: pick(e, 'display_name', 'default_name', 'name'),
        isCompound: Boolean(pick(e, 'is_compound')),
      })).filter((e) => e.key && e.name),
    };
  } catch (err) {
    state.master = { categories: [], exercises: [] };
    if (err.status !== 401) console.warn('master data unavailable', err);
  }

  const names = $('exerciseNames');
  if (names) {
    names.replaceChildren(...state.master.exercises.map((e) => {
      const option = document.createElement('option');
      option.value = e.name;
      return option;
    }));
  }
  const routineKey = $('routineKey');
  if (routineKey) {
    routineKey.replaceChildren(
      new Option('– 없음 –', ''),
      ...state.master.exercises.map((e) => new Option(e.name, e.key)),
    );
  }
}

async function main() {
  wireShell();
  wireAuthHandlers();
  fillMuscleSelects();
  for (const tab of Object.values(TABS)) tab.init();

  const user = await bootstrap();
  if (!user) return;

  await loadMaster();

  const initial = resolveInitialTab();
  switchTab(initial, { fromPop: true });
}

main();
