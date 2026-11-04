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

function copyVisibleContent(root: Element): { container: HTMLElement; text: string } {
  // Import shallow nodes into an inert document so custom element constructors never run.
  const inertDocument = document.implementation.createHTMLDocument('');
  const container = inertDocument.createElement('div');
  function copyElement(original: Element): { copy: Element; text: string } | null {
    const style = getComputedStyle(original);
    if (hidesSubtree(original, style)) return null;
    const copy = inertDocument.importNode(original, false);
    const visible = style.visibility !== 'hidden' && style.visibility !== 'collapse';
    const closed = original instanceof HTMLDetailsElement && !original.open;
    let text = '';
    for (const child of renderedChildren(original)) {
      if (child instanceof Element) {
        const result = copyElement(child);
        if (result) {
          copy.append(result.copy);
          text += result.text;
        }
      } else if (child.nodeType === Node.TEXT_NODE && visible && !closed) {
        copy.append(inertDocument.importNode(child, false));
        const value = child.textContent ?? '';
        text += /^(pre|break-spaces)/.test(style.whiteSpace) ? value : value.replace(/[\t\n\r\f ]+/g, ' ');
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
    if (text && /^(block|flow-root|flex|grid|list-item|table|table-row|table-caption)$/.test(style.display)) {
      text = (text.startsWith('\n') ? '' : '\n') + text + (text.endsWith('\n') ? '' : '\n');
    } else if (text && style.display === 'table-cell') {
      text += '\t';
    }
    return { copy, text };
  }
  const result = copyElement(root);
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

  const converter = new TurndownService({ headingStyle: 'atx', codeBlockStyle: 'fenced' });
  converter.use([strikethrough, tables, taskListItems]);
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
