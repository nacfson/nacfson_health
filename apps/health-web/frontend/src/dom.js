// Tiny DOM helpers — text nodes only for user data (no innerHTML).
export const $ = (id) => document.getElementById(id);

export function h(tag, props, ...children) {
  const el = document.createElement(tag);
  if (props) {
    for (const [key, value] of Object.entries(props)) {
      if (value === undefined || value === null || value === false) continue;
      if (key === 'class') el.className = value;
      else if (key === 'text') el.textContent = value;
      else if (key === 'style' && typeof value === 'object') Object.assign(el.style, value);
      else if (key.startsWith('on') && typeof value === 'function') el.addEventListener(key.slice(2).toLowerCase(), value);
      else if (key === 'dataset') Object.assign(el.dataset, value);
      else if (key in el) el[key] = value;
      else el.setAttribute(key, value);
    }
  }
  append(el, children);
  return el;
}

function append(parent, children) {
  for (const child of children) {
    if (child === undefined || child === null || child === false) continue;
    if (Array.isArray(child)) append(parent, child);
    else if (child instanceof Node) parent.appendChild(child);
    else parent.appendChild(document.createTextNode(String(child)));
  }
}

export function clear(node) {
  while (node.firstChild) node.removeChild(node.firstChild);
}

export function render(node, ...children) {
  clear(node);
  append(node, children);
  return node;
}

export function emptyNote(text) {
  return h('p', { class: 'empty', text });
}

let toastTimer = 0;
export function toast(message, isError) {
  const el = $('toast');
  if (!el) return;
  el.textContent = message;
  el.classList.toggle('err', Boolean(isError));
  el.classList.add('on');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove('on'), isError ? 4200 : 2200);
}

export function guard(button, busy) {
  if (button) button.disabled = Boolean(busy);
}

// Options for a <select>; preserves current value when still present.
export function fillSelect(select, options, selected) {
  clear(select);
  for (const opt of options) {
    select.appendChild(h('option', { value: opt.value, text: opt.label, selected: opt.value === selected }));
  }
  if (selected !== undefined) select.value = selected;
}

export const MUSCLE_TYPES = ['가슴', '등', '어깨', '팔', '하체', '코어', '유산소', '기타'];

export const MEALS = ['아침', '점심', '저녁', '간식'];

export const SET_TYPE_LABELS = { warmup: '웜업', work: '본세트', drop: '드랍', failure: '실패' };
