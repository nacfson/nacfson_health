// Fetch wrapper: same-origin /api calls with the health-web session cookie + CSRF header.
const CSRF_COOKIE = 'health_csrf';
const CSRF_HEADER = 'X-CSRF-Token';

export class ApiError extends Error {
  constructor(code, message, status) {
    super(message || code);
    this.name = 'ApiError';
    this.code = code;
    this.status = status;
  }
}

export function readCookie(name) {
  const hit = document.cookie.split(';').find((part) => part.trim().startsWith(name + '='));
  return hit ? decodeURIComponent(hit.trim().slice(name.length + 1)) : null;
}

let onUnauthorized = null;
export function setUnauthorizedHandler(fn) {
  onUnauthorized = fn;
}

// Called when the sign-in service cannot confirm the session (503 auth_unavailable).
let onUnavailable = null;
export function setUnavailableHandler(fn) {
  onUnavailable = fn;
}

function buildQuery(query) {
  if (!query) return '';
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(query)) {
    if (value === undefined || value === null || value === '') continue;
    params.set(key, String(value));
  }
  const qs = params.toString();
  return qs ? '?' + qs : '';
}

async function parse(res) {
  const text = await res.text();
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

async function ensureCsrfToken() {
  if (readCookie(CSRF_COOKIE)) return readCookie(CSRF_COOKIE);
  try {
    await fetch('/api/me', { credentials: 'include', headers: { Accept: 'application/json' } });
  } catch {
    /* cookie will stay absent; mutation below reports the real error */
  }
  return readCookie(CSRF_COOKIE);
}

async function request(method, path, body, query) {
  const headers = { Accept: 'application/json' };
  const init = { method, credentials: 'include', headers };
  if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
    init.body = JSON.stringify(body);
  }
  if (method !== 'GET' && method !== 'HEAD') {
    const token = await ensureCsrfToken();
    if (token) headers[CSRF_HEADER] = token;
  }

  const res = await fetch(path + buildQuery(query), init);
  const payload = await parse(res);

  if (res.status === 401) {
    if (onUnauthorized) onUnauthorized();
    throw new ApiError('unauthorized', '세션이 만료되었습니다', 401);
  }
  if (res.status === 503 && payload && payload.error === 'auth_unavailable') {
    if (onUnavailable) onUnavailable();
    throw new ApiError('auth_unavailable', '로그인 서비스를 일시적으로 사용할 수 없습니다', 503);
  }
  if (!res.ok) {
    const code = (payload && payload.error) || 'http_' + res.status;
    const message = (payload && payload.message) || ('요청 실패 (' + res.status + ')');
    throw new ApiError(code, message, res.status);
  }
  return payload;
}

export const api = {
  get: (path, query) => request('GET', path, undefined, query),
  post: (path, body, query) => request('POST', path, body === undefined ? {} : body, query),
  put: (path, body, query) => request('PUT', path, body === undefined ? {} : body, query),
  patch: (path, body, query) => request('PATCH', path, body === undefined ? {} : body, query),
  del: (path, query) => request('DELETE', path, undefined, query),
};

// ---- response helpers (tolerant to list wrappers / snake+lowerCamel) ----
export const pick = (obj, ...keys) => {
  for (const key of keys) {
    if (obj && obj[key] !== undefined && obj[key] !== null) return obj[key];
  }
  return undefined;
};

export const asList = (payload) => {
  if (Array.isArray(payload)) return payload;
  const nested = pick(payload, 'items', 'items_json', 'data', 'results');
  if (Array.isArray(nested)) return nested;
  if (typeof nested === 'string') {
    try {
      const parsed = JSON.parse(nested);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }
  return [];
};

export const num = (value, fallback = 0) => {
  const n = typeof value === 'string' ? Number(value) : value;
  return typeof n === 'number' && Number.isFinite(n) ? n : fallback;
};
