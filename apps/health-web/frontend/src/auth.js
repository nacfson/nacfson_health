// SSO cookie session bootstrap: GET /api/me → app, 401 → Auth login redirect.
import { api, setUnauthorizedHandler } from './api.js';
import { state } from './state.js';
import { $, toast } from './dom.js';

export const AUTH_LOGIN_URL = 'https://auth.nacfson.cloud/login';

let redirecting = false;

export function loginURL() {
  return `${AUTH_LOGIN_URL}?rd=${encodeURIComponent(location.href)}`;
}

export function redirectToLogin() {
  if (redirecting) return;
  redirecting = true;
  location.replace(loginURL());
}

export function showGate(hint) {
  const gate = $('gate');
  const app = $('app');
  if (hint) $('gateHint').textContent = hint;
  if (gate) gate.classList.add('on');
  if (app) app.hidden = true;
}

export function showApp(user) {
  const gate = $('gate');
  const app = $('app');
  if (gate) gate.classList.remove('on');
  if (app) app.hidden = false;

  const email = (user && user.email) || '';
  $('whoEmail').textContent = email || '알 수 없음';
  $('whoHost').textContent = location.host;
  $('statusHost').textContent = location.host;
  $('avatar').textContent = initials(email);
  const accountEmail = $('accountEmail');
  if (accountEmail) accountEmail.textContent = email || '–';
  const accountUserID = $('accountUserID');
  if (accountUserID) accountUserID.textContent = (user && user.id) || '–';
}

function initials(email) {
  const name = String(email || '').split('@')[0];
  if (!name) return '–';
  const parts = name.split(/[._-]+/).filter(Boolean);
  const raw = parts.length > 1 ? parts[0][0] + parts[1][0] : name.slice(0, 2);
  return raw.toUpperCase();
}

// Returns the authenticated user, or null when the redirect takes over.
export async function bootstrap() {
  setUnauthorizedHandler(redirectToLogin);
  try {
    const me = await api.get('/api/me');
    const user = { id: me && me.user_id, email: me && me.email };
    if (!user.id || !user.email) {
      showGate('세션 응답이 올바르지 않습니다');
      return null;
    }
    state.user = user;
    showApp(user);
    return user;
  } catch (err) {
    if (err && err.status === 401) {
      redirectToLogin();
      return null;
    }
    showGate('서버에 연결할 수 없습니다');
    toast('API 오류: ' + (err && err.message ? err.message : err), true);
    return null;
  }
}

export async function logout() {
  try {
    await api.post('/api/logout');
  } catch (err) {
    if (err && err.status !== 401) {
      toast('로그아웃 실패: ' + err.message, true);
    }
  }
  state.user = null;
  showGate('로그아웃되었습니다');
}

export function wireAuthHandlers() {
  const login = $('loginButton');
  if (login) login.addEventListener('click', () => redirectToLogin());
  const out = $('logoutButton');
  if (out) out.addEventListener('click', logout);
}
