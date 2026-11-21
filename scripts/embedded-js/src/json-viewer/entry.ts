const MAX_JSON_LENGTH = 2 * 1024 * 1024;
const STYLE_ID = 'den-json-viewer-style';
const ROOT_ID = 'den-json-viewer-root';

const CSS = `
:root {
  --jv-bg: #ffffff;
  --jv-fg: #1f2328;
  --jv-muted: #656d76;
  --jv-border: #d0d7de;
  --jv-toolbar-bg: #f6f8fa;
  --jv-key: #0550ae;
  --jv-str: #0a3069;
  --jv-num: #0550ae;
  --jv-bool: #cf222e;
  --jv-null: #6e7781;
  --jv-hover: rgba(175, 184, 193, 0.2);
}
@media (prefers-color-scheme: dark) {
  :root {
    --jv-bg: #0d1117;
    --jv-fg: #e6edf3;
    --jv-muted: #8b949e;
    --jv-border: #30363d;
    --jv-toolbar-bg: #161b22;
    --jv-key: #79c0ff;
    --jv-str: #a5d6ff;
    --jv-num: #79c0ff;
    --jv-bool: #ff7b72;
    --jv-null: #8b949e;
    --jv-hover: rgba(110, 118, 129, 0.2);
  }
}
body.den-jv-active {
  margin: 0;
  background: var(--jv-bg);
  color: var(--jv-fg);
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 13px;
  line-height: 1.5;
}
#${ROOT_ID} {
  padding: 12px 16px 24px;
}
.jv-toolbar {
  position: sticky;
  top: 0;
  z-index: 1;
  display: flex;
  gap: 6px;
  align-items: center;
  padding: 8px 16px;
  background: var(--jv-toolbar-bg);
  border-bottom: 1px solid var(--jv-border);
}
.jv-btn {
  appearance: none;
  border: 1px solid var(--jv-border);
  background: var(--jv-bg);
  color: var(--jv-fg);
  border-radius: 6px;
  padding: 3px 10px;
  font: 12px/1.4 -apple-system, BlinkMacSystemFont, sans-serif;
  cursor: pointer;
}
.jv-btn:hover { background: var(--jv-hover); }
.jv-btn[aria-pressed="true"] {
  font-weight: 600;
  border-color: var(--jv-key);
  color: var(--jv-key);
}
.jv-tree { white-space: pre-wrap; word-break: break-word; }
.jv-row { padding-left: 18px; }
.jv-tree > .jv-row, .jv-tree > details { padding-left: 0; }
details.jv-node { padding-left: 18px; }
details.jv-node > summary {
  list-style: none;
  cursor: pointer;
  margin-left: -14px;
  padding-left: 14px;
  position: relative;
  border-radius: 3px;
}
details.jv-node > summary:hover { background: var(--jv-hover); }
details.jv-node > summary::-webkit-details-marker { display: none; }
details.jv-node > summary::before {
  content: '▸';
  position: absolute;
  left: 2px;
  color: var(--jv-muted);
  transition: transform 0.1s ease;
}
details.jv-node[open] > summary::before { transform: rotate(90deg); }
details.jv-node[open] > summary .jv-collapsed { display: none; }
details.jv-node:not([open]) > summary .jv-open-only { display: none; }
.jv-collapsed { color: var(--jv-muted); font-style: italic; }
.jv-key { color: var(--jv-key); }
.jv-str { color: var(--jv-str); }
.jv-num { color: var(--jv-num); }
.jv-bool { color: var(--jv-bool); }
.jv-null { color: var(--jv-null); }
.jv-punct { color: var(--jv-muted); }
body.den-jv-raw #${ROOT_ID} { display: none; }
body:not(.den-jv-raw) > pre { display: none; }
body.den-jv-raw > pre {
  margin: 0;
  padding: 12px 16px 24px;
  font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  font-size: 13px;
  line-height: 1.5;
  white-space: pre-wrap;
  word-break: break-word;
}
`;

const WIN1252_REVERSE: Record<number, number> = {
  0x20ac: 0x80, 0x201a: 0x82, 0x0192: 0x83, 0x201e: 0x84, 0x2026: 0x85,
  0x2020: 0x86, 0x2021: 0x87, 0x02c6: 0x88, 0x2030: 0x89, 0x0160: 0x8a,
  0x2039: 0x8b, 0x0152: 0x8c, 0x017d: 0x8e, 0x2018: 0x91, 0x2019: 0x92,
  0x201c: 0x93, 0x201d: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97,
  0x02dc: 0x98, 0x2122: 0x99, 0x0161: 0x9a, 0x203a: 0x9b, 0x0153: 0x9c,
  0x017e: 0x9e, 0x0178: 0x9f,
};

export function decodeUtf8IfLatin1(text: string, characterSet: string): string {
  if (characterSet.toUpperCase() === 'UTF-8') return text;
  const bytes = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    const byte = code <= 0xff ? code : WIN1252_REVERSE[code];
    if (byte === undefined) return text;
    bytes[i] = byte;
  }
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    return text;
  }
}

function isJsonDocument(doc: Document): HTMLPreElement | null {
  const contentType = (doc.contentType || '').toLowerCase();
  const isJsonMime =
    contentType === 'application/json' ||
    contentType === 'text/json' ||
    contentType.endsWith('+json');
  const isPlainCandidate = contentType === 'text/plain' || contentType === '';
  if (!isJsonMime && !isPlainCandidate) return null;

  const body = doc.body;
  if (!body || body.children.length !== 1) return null;
  const first = body.firstElementChild;
  if (!first || first.tagName !== 'PRE') return null;
  return first as HTMLPreElement;
}

function span(doc: Document, className: string, text: string): HTMLSpanElement {
  const el = doc.createElement('span');
  el.className = className;
  el.textContent = text;
  return el;
}

function renderValue(
  doc: Document,
  value: unknown,
  key: string | null,
  hasTrailingComma: boolean,
): HTMLElement {
  const comma = hasTrailingComma ? ',' : '';

  if (value !== null && typeof value === 'object') {
    const isArray = Array.isArray(value);
    const entries: Array<[string | null, unknown]> = isArray
      ? (value as unknown[]).map((item) => [null, item])
      : Object.entries(value as Record<string, unknown>);
    const openBrace = isArray ? '[' : '{';
    const closeBrace = isArray ? ']' : '}';

    if (entries.length === 0) {
      const row = doc.createElement('div');
      row.className = 'jv-row';
      if (key !== null) {
        row.append(span(doc, 'jv-key', JSON.stringify(key)), span(doc, 'jv-punct', ': '));
      }
      row.append(span(doc, 'jv-punct', `${openBrace}${closeBrace}${comma}`));
      return row;
    }

    const details = doc.createElement('details');
    details.className = 'jv-node';
    details.open = true;

    const summary = doc.createElement('summary');
    if (key !== null) {
      summary.append(span(doc, 'jv-key', JSON.stringify(key)), span(doc, 'jv-punct', ': '));
    }
    const countLabel = isArray
      ? `${entries.length} ${entries.length === 1 ? 'item' : 'items'}`
      : `${entries.length} ${entries.length === 1 ? 'key' : 'keys'}`;
    summary.append(
      span(doc, 'jv-punct', openBrace),
      span(doc, 'jv-collapsed', ` ${countLabel} ${closeBrace}${comma}`),
    );
    details.append(summary);

    for (let i = 0; i < entries.length; i++) {
      const [childKey, childValue] = entries[i];
      details.append(renderValue(doc, childValue, childKey, i < entries.length - 1));
    }

    const footer = doc.createElement('div');
    footer.className = 'jv-open-only jv-punct';
    footer.textContent = `${closeBrace}${comma}`;
    details.append(footer);
    return details;
  }

  const row = doc.createElement('div');
  row.className = 'jv-row';
  if (key !== null) {
    row.append(span(doc, 'jv-key', JSON.stringify(key)), span(doc, 'jv-punct', ': '));
  }

  if (typeof value === 'string') {
    row.append(span(doc, 'jv-str', JSON.stringify(value)));
  } else if (typeof value === 'number') {
    row.append(span(doc, 'jv-num', String(value)));
  } else if (typeof value === 'boolean') {
    row.append(span(doc, 'jv-bool', String(value)));
  } else {
    row.append(span(doc, 'jv-null', 'null'));
  }

  if (comma) row.append(span(doc, 'jv-punct', comma));
  return row;
}

export function formatJsonDocument(doc: Document): boolean {
  if (doc.getElementById(ROOT_ID)) return false;
  const pre = isJsonDocument(doc);
  if (!pre) return false;

  const rawOriginal = pre.textContent ?? '';
  if (rawOriginal.length === 0 || rawOriginal.length > MAX_JSON_LENGTH) return false;

  const decoded = decodeUtf8IfLatin1(rawOriginal, doc.characterSet || '');
  const trimmed = decoded.replace(/^\uFEFF/, '').trim();
  const contentType = (doc.contentType || '').toLowerCase();
  const isJsonMime =
    contentType === 'application/json' ||
    contentType === 'text/json' ||
    contentType.endsWith('+json');
  if (!isJsonMime && !trimmed.startsWith('{') && !trimmed.startsWith('[')) {
    return false;
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(trimmed);
  } catch {
    return false;
  }

  if (decoded !== rawOriginal) {
    pre.textContent = decoded;
  }

  if (!doc.getElementById(STYLE_ID)) {
    const style = doc.createElement('style');
    style.id = STYLE_ID;
    style.textContent = CSS;
    (doc.head || doc.documentElement).append(style);
  }

  const toolbar = doc.createElement('div');
  toolbar.className = 'jv-toolbar';

  const formattedBtn = doc.createElement('button');
  formattedBtn.className = 'jv-btn';
  formattedBtn.type = 'button';
  formattedBtn.textContent = 'Formatted';
  formattedBtn.setAttribute('aria-pressed', 'true');

  const rawBtn = doc.createElement('button');
  rawBtn.className = 'jv-btn';
  rawBtn.type = 'button';
  rawBtn.textContent = 'Raw';
  rawBtn.setAttribute('aria-pressed', 'false');

  const expandBtn = doc.createElement('button');
  expandBtn.className = 'jv-btn';
  expandBtn.type = 'button';
  expandBtn.textContent = 'Expand all';

  const collapseBtn = doc.createElement('button');
  collapseBtn.className = 'jv-btn';
  collapseBtn.type = 'button';
  collapseBtn.textContent = 'Collapse all';

  toolbar.append(formattedBtn, rawBtn, expandBtn, collapseBtn);

  const root = doc.createElement('div');
  root.id = ROOT_ID;
  const tree = doc.createElement('div');
  tree.className = 'jv-tree';
  tree.append(renderValue(doc, parsed, null, false));
  root.append(tree);

  const setRawMode = (raw: boolean) => {
    doc.body.classList.toggle('den-jv-raw', raw);
    formattedBtn.setAttribute('aria-pressed', String(!raw));
    rawBtn.setAttribute('aria-pressed', String(raw));
    expandBtn.hidden = raw;
    collapseBtn.hidden = raw;
  };

  formattedBtn.addEventListener('click', () => setRawMode(false));
  rawBtn.addEventListener('click', () => setRawMode(true));
  expandBtn.addEventListener('click', () => {
    root.querySelectorAll('details.jv-node').forEach((node) => {
      (node as HTMLDetailsElement).open = true;
    });
  });
  collapseBtn.addEventListener('click', () => {
    root.querySelectorAll('details.jv-node').forEach((node) => {
      (node as HTMLDetailsElement).open = false;
    });
  });

  doc.body.classList.add('den-jv-active');
  doc.body.prepend(toolbar, root);
  return true;
}

if (typeof document !== 'undefined') {
  formatJsonDocument(document);
}
