import TurndownService from 'turndown';
import { strikethrough, tables, taskListItems } from 'turndown-plugin-gfm';

function hidesSubtree(element: Element, style: CSSStyleDeclaration): boolean {
  const parent = element.parentElement;
  return element.matches('script, style, template, noscript, [hidden]')
    || style.display === 'none' || style.contentVisibility === 'hidden'
    || (parent instanceof HTMLDetailsElement && !parent.open
      && element !== parent.querySelector(':scope > summary'));
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

  for (let ancestor: Element | null = root; ancestor; ancestor = ancestor.parentElement) {
    if (hidesSubtree(ancestor, getComputedStyle(ancestor))) {
      return { title: document.title, url: location.href, markdown: '' };
    }
  }

  // An inert document prevents custom element constructors from running on either clone.
  const inertDocument = document.implementation.createHTMLDocument('');
  const body = inertDocument.importNode(root, true);
  // Keep the scope element itself, so selecting a heading preserves its level.
  const container = inertDocument.createElement('div');
  container.append(body);
  const originals = [root, ...root.querySelectorAll('*')];
  const copies = [body, ...body.querySelectorAll('*')];
  for (let index = 0; index < originals.length; index++) {
    const original = originals[index];
    const copy = copies[index];
    const style = getComputedStyle(original);
    if (hidesSubtree(original, style)) {
      copy.remove();
      continue;
    }
    if (style.visibility === 'hidden' || style.visibility === 'collapse'
      || (original instanceof HTMLDetailsElement && !original.open)) {
      // A visible descendant or a closed details element's summary can still be readable.
      for (const child of [...copy.childNodes]) {
        if (child.nodeType === Node.TEXT_NODE) child.remove();
      }
      if (copy.childElementCount === 0) copy.remove();
    }
    if (original instanceof HTMLAnchorElement && original.hasAttribute('href')) {
      copy.setAttribute('href', original.href);
    }
    if (original instanceof HTMLImageElement && original.hasAttribute('src')) {
      copy.setAttribute('src', original.currentSrc || original.src);
    }
  }

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
