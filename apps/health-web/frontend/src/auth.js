// Sign-in shell for the nacfson platform gateway (spec 001-health-web-gateway-auth).
// The backend owns the whole sign-in flow and keeps the session server-side; this
// module only shows the sign-in screen, starts sign-in on request, and signs out.
// There is no automatic redirect: sign-in starts only from the "Google로 계속" button.
import { api, setUnauthorizedHandler, setUnavailableHandler } from './api.js';
import { state } from './state.js';
import { $ } from './dom.js';

const GATE_MESSAGES = {
  signed_out: '로그인하지 않았습니다',
  session: '세션이 만료되었습니다. 다시 로그인해 주세요',
  failed: '로그인이 완료되지 않았습니다. 다시 시도해 주세요',
  unavailable: '로그인 서비스를 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해 주세요',
  logged_out: '로그아웃되었습니다',
  logged_out_unconfirmed: '로그아웃되었지만 다른 nacfson 서비스의 로그아웃은 확인되지 않았습니다',
};

// Where to land after sign-in: the current page (path + query), never another site.
export function loginURL() {
  const next = location.pathname + location.search;
  return '/api/auth/login?next=' + encodeURIComponent(next || '/');
}

export function startLogin() {
  location.assign(loginURL());
}

// The backend redirects failed callbacks to /?auth=failed|unavailable. Read the
// reason once and drop it from the address bar.
function takeAuthReason() {
  const params = new URLSearchParams(location.search);
  const reason = params.get('auth');
  if (!reason) return null;
  params.delete('auth');
  const query = params.toString();
  history.replaceState(null, '', location.pathname + (query ? '?' + query : '') + location.hash);
  return GATE_MESSAGES[reason] ? reason : 'failed';
}

// Show the sign-in screen. The app DOM stays in place (only hidden), so form
// values typed before a session ended are still there afterwards.
export function showGate(reason) {
  const gate = $('gate');
  const app = $('app');
  $('gateHint').textContent = GATE_MESSAGES[reason] || GATE_MESSAGES.signed_out;
  if (gate) gate.classList.add('on');
  if (app) app.hidden = true;
}

export function showApp(user) {
  const gate = $('gate');
  const app = $('app');
  if (gate) gate.classList.remove('on');
  if (app) app.hidden = false;

  $('whoName').textContent = 'nacfson 계정';
  $('whoHost').textContent = location.host;
  $('statusHost').textContent = location.host;
  const accountUserID = $('accountUserID');
  if (accountUserID) accountUserID.textContent = (user && user.id) || '–';
}

// Returns the signed-in user, or null when the sign-in screen is showing.
export async function bootstrap() {
  setUnauthorizedHandler(() => {
    state.user = null;
    showGate('session');
  });
  setUnavailableHandler(() => showGate('unavailable'));

  const reason = takeAuthReason();
  try {
    const me = await api.get('/api/me');
    const user = { id: me && me.user_id };
    if (!user.id) {
      showGate('failed');
      return null;
    }
    state.user = user;
    showApp(user);
    return user;
  } catch (err) {
    if (err && err.status === 401) {
      showGate(reason || 'signed_out');
    } else if (err && err.status === 503) {
      showGate('unavailable');
    } else {
      showGate(reason || 'unavailable');
    }
    return null;
  }
}

// Platform-wide sign-out: the backend revokes the platform session (every
// nacfson service in this browser) and ends this browser's health-web session.
export async function logout() {
  let reason = 'logged_out';
  try {
    const result = await api.post('/api/auth/logout');
    if (result && result.platform === 'unconfirmed') reason = 'logged_out_unconfirmed';
  } catch (err) {
    if (!err || err.status !== 401) reason = 'logged_out_unconfirmed';
  }
  state.user = null;
  showGate(reason);
}

export function wireAuthHandlers() {
  const login = $('loginButton');
  if (login) login.addEventListener('click', startLogin);
  const out = $('logoutButton');
  if (out) out.addEventListener('click', logout);
}
