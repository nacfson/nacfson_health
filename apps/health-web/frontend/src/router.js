// Thin History API router for health-web SPA paths.
// nginx try_files already falls back to index.html for deep links.

export const DEFAULT_TAB = 'summary';

const TAB_PATHS = {
  summary: '/summary',
  workout: '/workout',
  diet: '/diet',
  weight: '/weight',
  settings: '/settings',
};

const PATH_TABS = {
  '/': 'summary',
  '/summary': 'summary',
  '/workout': 'workout',
  '/diet': 'diet',
  '/weight': 'weight',
  '/settings': 'settings',
};

const TAB_LABELS = {
  summary: '요약',
  workout: '운동',
  diet: '식단',
  weight: '체중',
  settings: '설정',
};

export function normalizePath(pathname) {
  if (!pathname || pathname === '/') return '/';
  return pathname.replace(/\/+$/, '') || '/';
}

export function tabFromPath(pathname) {
  return PATH_TABS[normalizePath(pathname)] || null;
}

export function pathForTab(tab) {
  return TAB_PATHS[tab] || TAB_PATHS[DEFAULT_TAB];
}

export function labelForTab(tab) {
  return TAB_LABELS[tab] || TAB_LABELS[DEFAULT_TAB];
}

export function navigate(tab, { replace = false } = {}) {
  const path = pathForTab(tab);
  const state = { tab };
  if (replace) {
    history.replaceState(state, '', path);
  } else if (normalizePath(location.pathname) !== path) {
    history.pushState(state, '', path);
  } else {
    history.replaceState(state, '', path);
  }
}

/** Resolve initial route; unknown paths become /summary via replaceState. */
export function resolveInitialTab() {
  const fromPath = tabFromPath(location.pathname);
  if (fromPath) {
    navigate(fromPath, { replace: true });
    return fromPath;
  }
  navigate(DEFAULT_TAB, { replace: true });
  return DEFAULT_TAB;
}

export function wirePopstate(onTab) {
  window.addEventListener('popstate', () => {
    const tab = tabFromPath(location.pathname) || DEFAULT_TAB;
    onTab(tab, { fromPop: true });
  });
}
