import TurndownService from 'turndown';
import { strikethrough, tables, taskListItems } from 'turndown-plugin-gfm';

function hidesSubtree(element: Element, style: CSSStyleDeclaration): boolean {
  const parent = element.parentElement;
  return element.matches('script, style, template, noscript, [hidden]')
    || style.display === 'none' || style.contentVisibility === 'hidden'
    || (parent instanceof HTMLDetailsElement && !parent.open
      && element !== parent.querySelector(':scope > summary'));
}

function renderedChildren(element: Element): Node[] {
  if (element instanceof HTMLSlotElement) {
    const assigned = element.assignedNodes();
    return assigned.length ? assigned : [...element.childNodes];
  }
  return [...(element.shadowRoot ?? element).childNodes];
}

function renderedParent(element: Element): Element | null {
  if (element.assignedSlot) return element.assignedSlot;
  const parent = element.parentNode;
  return parent instanceof ShadowRoot ? parent.host : element.parentElement;
}

const BLOCK_DISPLAY = /^(block|flow-root|flex|grid|list-item|table|table-row|table-caption)$/;
const FLEX_GRID_DISPLAY = /^(flex|inline-flex|grid|inline-grid)$/;
const NATIVE_BLOCK_TAGS = new Set([
  'ADDRESS', 'ARTICLE', 'ASIDE', 'BLOCKQUOTE', 'BR', 'CAPTION', 'DD', 'DETAILS', 'DIALOG',
  'DIV', 'DL', 'DT', 'FIELDSET', 'FIGCAPTION', 'FIGURE', 'FOOTER', 'FORM', 'H1', 'H2',
  'H3', 'H4', 'H5', 'H6', 'HEADER', 'HGROUP', 'HR', 'LI', 'MAIN', 'NAV', 'OL', 'P',
  'PRE', 'SECTION', 'SUMMARY', 'TABLE', 'TBODY', 'TD', 'TFOOT', 'TH', 'THEAD', 'TR', 'UL',
]);

function copyVisibleContent(root: Element): { container: HTMLElement; text: string } {
  // Import shallow nodes into an inert document so custom element constructors never run.
  const inertDocument = document.implementation.createHTMLDocument('');
  const container = inertDocument.createElement('div');
  function copyElement(original: Element, inCode: boolean): { copy: Element; text: string; separate: boolean } | null {
    const style = getComputedStyle(original);
    if (hidesSubtree(original, style)) return null;
    const copy = inertDocument.importNode(original, false);
    const visible = style.visibility !== 'hidden' && style.visibility !== 'collapse';
    const closed = original instanceof HTMLDetailsElement && !original.open;
    const insideCode = inCode || original.tagName === 'PRE' || original.tagName === 'CODE';
    const isFlexOrGrid = !insideCode && FLEX_GRID_DISPLAY.test(style.display);
    let text = '';
    let prevSeparated = false;
    for (const child of renderedChildren(original)) {
      if (child instanceof Element) {
        const result = copyElement(child, insideCode);
        if (result) {
          const hasText = Boolean(result.copy.textContent?.trim());
          if (!insideCode && copy.lastChild && (prevSeparated || (isFlexOrGrid && hasText))
            && !/\s$/.test(copy.lastChild.textContent ?? '')) {
            copy.append(' ');
          }
          copy.append(result.copy);
          text += result.text;
          prevSeparated = result.separate || (isFlexOrGrid && hasText);
        }
      } else if (child.nodeType === Node.TEXT_NODE && visible && !closed) {
        const value = child.textContent ?? '';
        if (!insideCode && prevSeparated && value && !/^\s/.test(value)) {
          copy.append(' ');
        }
        copy.append(inertDocument.importNode(child, false));
        text += /^(pre|break-spaces)/.test(style.whiteSpace) ? value : value.replace(/[\t\n\r\f ]+/g, ' ');
        if (value) prevSeparated = false;
      }
    }
    if ((!visible || closed) && copy.childElementCount === 0) return null;
    if (original instanceof HTMLAnchorElement && original.hasAttribute('href')) {
      copy.setAttribute('href', original.href);
    }
    if (original instanceof HTMLImageElement && original.hasAttribute('src')) {
      copy.setAttribute('src', original.currentSrc || original.src);
    }
    if (visible && original instanceof HTMLBRElement) text = '\n';
    if (text && BLOCK_DISPLAY.test(style.display)) {
      text = (text.startsWith('\n') ? '' : '\n') + text + (text.endsWith('\n') ? '' : '\n');
    } else if (text && style.display === 'table-cell') {
      text += '\t';
    }
    const separate = !insideCode && BLOCK_DISPLAY.test(style.display) && !NATIVE_BLOCK_TAGS.has(original.tagName);
    return { copy, text, separate };
  }
  const result = copyElement(root, false);
  if (result) container.append(result.copy);
  return { container, text: result?.text ?? '' };
}

export function text(): string {
  if (!document.body) return document.documentElement?.textContent ?? '';
  if (![document.body, ...document.body.querySelectorAll('*')].some(element => element.shadowRoot)) {
    return document.body.innerText;
  }
  return copyVisibleContent(document.body).text.replace(/^\n+|\n+$/g, '');
}

export function read(within: string | null = null): { title: string; url: string; markdown: string } {
  if (!document.body) {
    throw new Error('Markdown reading requires a document with an HTML body');
  }

  let root: Element = document.body;
  if (within !== null) {
    if (within.startsWith('@')) {
      const resolveRef = window.__denSheetDOM?.denResolveRef;
      const target = typeof resolveRef === 'function' ? resolveRef(within) : null;
      if (!(target instanceof Element)) throw new Error('Scope not found: ' + within);
      root = target;
    } else {
      const matches = document.querySelectorAll(within);
      if (matches.length === 0) throw new Error('Scope not found: ' + within);
      if (matches.length > 1) throw new Error('Scope matched multiple elements: ' + within);
      root = matches[0];
    }
  }

  for (let ancestor: Element | null = root; ancestor; ancestor = renderedParent(ancestor)) {
    if (hidesSubtree(ancestor, getComputedStyle(ancestor))
      || (ancestor.parentElement?.shadowRoot && !ancestor.assignedSlot)) {
      return { title: document.title, url: location.href, markdown: '' };
    }
  }

  const { container } = copyVisibleContent(root);
  const inertDocument = container.ownerDocument;

  // The GFM plugin requires a first row. Preserve captions when no rows remain.
  for (const table of container.querySelectorAll('table')) {
    if (table.rows.length === 0) table.replaceWith(...table.childNodes);
  }

  // Turndown's core rule needs pre > code first, without sibling controls or highlight spans.
  for (const pre of container.querySelectorAll('pre')) {
    const existing = pre.querySelector(':scope > code');
    const language = pre.parentElement?.className.match(/(?:^|\s)highlight-(?:text|source)-(\S+)/)?.[1];
    const code = inertDocument.createElement('code');
    code.className = existing?.className || (language ? 'language-' + language : '');
    code.textContent = existing?.textContent ?? pre.textContent;
    pre.replaceChildren(code);
  }

  const converter = new TurndownService({
    headingStyle: 'atx',
    codeBlockStyle: 'fenced',
    // The GFM plugin keeps tables without a heading row. Use the converted cells, not outerHTML.
    keepReplacement: content => '\n\n' + content.trim() + '\n\n',
  });
  converter.use([strikethrough, tables, taskListItems]);
  converter.addRule('embeddedDataURL', {
    filter: node => {
      const attribute = node.nodeName === 'IMG' ? 'src' : node.nodeName === 'A' ? 'href' : null;
      return attribute !== null && /^data:/i.test(node.getAttribute(attribute) ?? '');
    },
    replacement: (content, node) => node.nodeName === 'IMG'
      ? converter.escape((node.getAttribute('alt') ?? '').replace(/\s+/g, ' ').trim())
        .replace(/&/g, '&amp;').replace(/</g, '&lt;')
      : content,
  });
  converter.addRule('escapedTableCell', {
    filter: ['th', 'td'],
    replacement: (content, node) => {
      const prefix = node.previousElementSibling ? ' ' : '| ';
      const cell = content.trim().replace(/\|/g, '\\|').replace(/[ \t]*(?:\r\n?|\n)/g, '<br>');
      return prefix + cell + ' |';
    },
  });
  return { title: document.title, url: location.href, markdown: converter.turndown(container) };
}
