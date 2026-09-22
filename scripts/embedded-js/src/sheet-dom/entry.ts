window.__denSheetDOM = window.__denSheetDOM || (() => {
const denRefStore: { elements: Map<string, DenRefEntry>; nextRef: number } = {
    elements: window.__denRefs || new Map(),
    nextRef: window.__denNextRef || 1,
};
window.__denRefs = denRefStore.elements;
window.__denNextRef = denRefStore.nextRef;

type DenElement = Element;

function denNormalize(value: unknown): string {
    return String(value || '').trim().replace(/\s+/g, ' ');
}

function denIsVisible(el: DenElement | null): boolean {
    if (!el || el.nodeType !== 1 || !el.isConnected) return false;
    const rect = el.getBoundingClientRect();
    if (rect.width === 0 && rect.height === 0) return false;
    const style = window.getComputedStyle(el);
    if (style.display === 'none' ||
        style.visibility === 'hidden' ||
        style.visibility === 'collapse' ||
        style.opacity === '0') return false;
    return true;
}

function denElementForRef(ref: string): DenElement | null {
    const entry = denRefStore.elements.get(ref);
    if (!entry) return null;
    if ('deref' in entry) return entry.deref() ?? null;
    return entry;
}

function denRefFor(el: DenElement | null): string | null {
    if (!el || !el.isConnected) return null;
    const existing = el.getAttribute('data-den-ref');
    if (existing && /^@e\d+$/.test(existing)) {
        const mapped = denElementForRef(existing);
        if (mapped === el) return existing;
        if (!mapped || !mapped.isConnected) {
            denRefStore.elements.set(existing, new WeakRef(el));
            return existing;
        }
    }

    let ref;
    do {
        ref = '@e' + denRefStore.nextRef++;
    } while (denRefStore.elements.has(ref));
    window.__denNextRef = denRefStore.nextRef;
    denRefStore.elements.set(ref, new WeakRef(el));
    el.setAttribute('data-den-ref', ref);
    return ref;
}

function denResolveRef(target: string): DenElement | null {
    if (!/^@e\d+$/.test(target)) return null;
    const mapped = denElementForRef(target);
    if (mapped?.isConnected) return mapped;
    const fallback = Array.from(document.querySelectorAll<DenElement>('[data-den-ref]'))
        .find(el => el.getAttribute('data-den-ref') === target) ?? null;
    if (fallback) {
        denRefStore.elements.set(target, new WeakRef<DenElement>(fallback));
        return fallback;
    }
    denRefStore.elements.delete(target);
    return null;
}

function denResolveTarget(target: string): DenElement | null {
    if (target.startsWith('@')) return denResolveRef(target);
    return document.querySelector<DenElement>(target);
}

function denRole(el: DenElement): string {
    const explicit = denNormalize(el.getAttribute('role')).toLowerCase();
    if (explicit) return explicit.split(/\s+/)[0];

    const tag = el.tagName.toLowerCase();
    if (tag === 'a' && el.hasAttribute('href')) return 'link';
    if (tag === 'button' || tag === 'summary') return 'button';
    if (tag === 'textarea' || (el instanceof HTMLElement && el.isContentEditable)) return 'textbox';
    if (tag === 'select') return 'combobox';
    if (tag === 'option') return 'option';
    if (/^h[1-6]$/.test(tag)) return 'heading';
    if (['ul', 'ol'].includes(tag)) return 'list';
    if (tag === 'li') return 'listitem';
    if (tag === 'nav') return 'navigation';
    if (tag === 'main') return 'main';
    if (tag === 'aside') return 'complementary';
    if (tag === 'header') return 'banner';
    if (tag === 'footer') return 'contentinfo';
    if (tag === 'form') return 'form';
    if (tag === 'img') return 'img';
    if (tag === 'table') return 'table';
    if (tag === 'tr') return 'row';
    if (tag === 'th') return 'columnheader';
    if (tag === 'td') return 'cell';
    if (tag === 'dialog') return 'dialog';
    if (tag === 'input') {
        const type = (el.getAttribute('type') || 'text').toLowerCase();
        if (type === 'checkbox') return 'checkbox';
        if (type === 'radio') return 'radio';
        if (['submit', 'reset', 'button', 'image'].includes(type)) return 'button';
        if (!['hidden', 'file', 'range', 'color'].includes(type)) return 'textbox';
    }
    return tag;
}

function denText(el: DenElement): string {
    const innerText = el instanceof HTMLElement ? el.innerText : '';
    return denNormalize(innerText || el.textContent || '');
}

function denAccessibleName(el: DenElement): string {
    const labelledBy = el.getAttribute('aria-labelledby');
    if (labelledBy) {
        const labelledText = labelledBy.split(/\s+/)
            .map(id => document.getElementById(id))
            .filter((node): node is HTMLElement => node !== null)
            .map(node => denText(node))
            .filter(Boolean)
            .join(' ');
        if (labelledText) return labelledText;
    }

    const ariaLabel = denNormalize(el.getAttribute('aria-label'));
    if (ariaLabel) return ariaLabel;

    const labels = (el as DenElement & { labels?: NodeListOf<HTMLLabelElement> }).labels;
    if (labels?.length) {
        const labelText = Array.from(labels).map(label => denText(label)).filter(Boolean).join(' ');
        if (labelText) return labelText;
    }

    const alt = denNormalize(el.getAttribute('alt'));
    if (alt) return alt;

    const placeholder = denNormalize(el.getAttribute('placeholder'));
    if (placeholder) return placeholder;

    const type = (el.getAttribute('type') || '').toLowerCase();
    if (el.tagName.toLowerCase() === 'input' && 'value' in el &&
        typeof el.value === 'string' && ['button', 'submit', 'reset'].includes(type)) {
        const value = denNormalize(el.value);
        if (value) return value;
    }

    const title = denNormalize(el.getAttribute('title'));
    if (title) return title;

    return denText(el);
}

function denValue(el: DenElement | null): string | null {
    if (!el) return null;
    if ('value' in el && typeof el.value === 'string') return el.value;
    if ((el instanceof HTMLElement && el.isContentEditable) ||
        ['textbox', 'searchbox', 'combobox'].includes(denRole(el))) {
        const innerText = el instanceof HTMLElement ? el.innerText : '';
        const text = innerText || el.textContent || '';
        return text === '\n' ? '' : text;
    }
    return null;
}

function denChecked(el: DenElement | null): boolean | null {
    if (!el) return null;
    const type = (el.getAttribute('type') || '').toLowerCase();
    if ('checked' in el && typeof el.checked === 'boolean' && ['checkbox', 'radio'].includes(type)) {
        return !!el.checked;
    }
    const ariaChecked = el.getAttribute('aria-checked');
    if (ariaChecked === 'true') return true;
    if (ariaChecked === 'false') return false;
    return null;
}

function denDisabled(el: DenElement | null): boolean | null {
    if (!el) return null;
    if (el.matches(':disabled')) return true;
    const ariaDisabled = el.getAttribute('aria-disabled');
    if (ariaDisabled === 'true') return true;
    if (ariaDisabled === 'false') return false;
    const nativeControl = ['button', 'fieldset', 'input', 'optgroup', 'option', 'select', 'textarea']
        .includes(el.tagName.toLowerCase());
    return nativeControl ? !!('disabled' in el && el.disabled) : null;
}

function denSelected(el: DenElement | null): boolean | null {
    if (!el) return null;
    if (el.tagName.toLowerCase() === 'option' && 'selected' in el) return !!el.selected;
    const ariaSelected = el.getAttribute('aria-selected');
    if (ariaSelected === 'true') return true;
    if (ariaSelected === 'false') return false;
    return null;
}

function denExpanded(el: DenElement | null): boolean | null {
    if (!el) return null;
    if (el.tagName.toLowerCase() === 'details' && 'open' in el) return !!el.open;
    const ariaExpanded = el.getAttribute('aria-expanded');
    if (ariaExpanded === 'true') return true;
    if (ariaExpanded === 'false') return false;
    return null;
}

function denSnapshotStates(el: DenElement): string[] {
    const states: string[] = [];
    const checked = denChecked(el);
    if (checked !== null) states.push(checked ? 'checked' : 'unchecked');
    const disabled = denDisabled(el);
    if (disabled === true) states.push('disabled');
    const selected = denSelected(el);
    if (selected === true) states.push('selected');
    const expanded = denExpanded(el);
    if (expanded !== null) states.push(expanded ? 'expanded' : 'collapsed');
    return states;
}

function denSnapshotEligible(el: DenElement, selectors: string[]): boolean {
    const tag = el.tagName.toLowerCase();
    const explicitRole = denNormalize(el.getAttribute('role')).toLowerCase();
    if (el.closest('[aria-hidden="true"]') || ['none', 'presentation'].includes(explicitRole)) {
        return false;
    }
    if (el.hasAttribute('role') || el.hasAttribute('aria-label') || el.hasAttribute('aria-labelledby')) {
        return true;
    }
    if (el.matches(selectors.join(','))) return true;
    return [
        'a', 'button', 'form', 'footer', 'header', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
        'img', 'li', 'main', 'nav', 'ol', 'option', 'section', 'table', 'tbody', 'td',
        'tfoot', 'th', 'thead', 'tr', 'ul', 'textarea', 'select', 'dialog', 'details', 'summary',
    ].includes(tag);
}

function denSnapshotName(el: DenElement, role: string): string {
    const hasExplicitName = el.hasAttribute('aria-label') || el.hasAttribute('aria-labelledby');
    const namedRoles = [
        'button', 'cell', 'checkbox', 'columnheader', 'combobox', 'dialog', 'heading', 'img',
        'link', 'listitem', 'menuitem', 'option', 'radio', 'row', 'switch', 'tab', 'textbox',
    ];
    if (!hasExplicitName && !namedRoles.includes(role)) return '';
    return denAccessibleName(el);
}

function denSnapshotLevel(el: DenElement): number | null {
    const tag = el.tagName.toLowerCase();
    if (/^h[1-6]$/.test(tag)) return Number(tag.slice(1));
    return null;
}

function denDispatchInput(el: DenElement, value: string, isDelete = false): void {
    el.dispatchEvent(new InputEvent('input', {
        bubbles: true,
        cancelable: true,
        inputType: isDelete ? 'deleteContentBackward' : 'insertText',
        data: isDelete ? null : value,
    }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
}

function denSetValue(el: DenElement | null, value: string): boolean {
    if (!el) return false;

    // 1. Native form controls
    if ('value' in el && typeof el.value === 'string') {
        const descriptor = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), 'value');
        descriptor?.set?.call(el, value);
        el.value = value;
        denDispatchInput(el, value);
        return true;
    }

    // 2. Editable elements (contenteditable or ARIA textbox/searchbox)
    if ((el instanceof HTMLElement && el.isContentEditable) ||
        ['textbox', 'searchbox'].includes(denRole(el))) {
        if ('focus' in el && typeof el.focus === 'function') el.focus();
        try { window.getSelection()?.selectAllChildren(el); } catch (_) {}
        const ok = value
            ? document.execCommand('insertText', false, value)
            : document.execCommand('delete', false);
        if (!ok || !value) el.textContent = value;
        denDispatchInput(el, value, !value);
        return true;
    }

    return false;
}

function denInspect(el: DenElement, fields: string[]): Record<string, unknown> {
    const info: Record<string, unknown> = {
        ref: denRefFor(el),
        visible: denIsVisible(el),
    };
    if (fields.includes('tag')) info.tag = el.tagName.toLowerCase();
    if (fields.includes('role')) info.role = denRole(el);
    if (fields.includes('name')) info.name = denAccessibleName(el);
    if (fields.includes('text')) info.text = denText(el);
    if (fields.includes('value')) {
        const value = denValue(el);
        if (value !== null) info.value = value;
    }
    if (fields.includes('checked')) {
        const checked = denChecked(el);
        if (checked !== null) info.checked = checked;
    }
    if (fields.includes('disabled')) {
        const disabled = denDisabled(el);
        if (disabled !== null) info.disabled = disabled;
    }
    if (fields.includes('selected')) {
        const selected = denSelected(el);
        if (selected !== null) info.selected = selected;
    }
    if (fields.includes('expanded')) {
        const expanded = denExpanded(el);
        if (expanded !== null) info.expanded = expanded;
    }

    const attributes: Record<string, string> = {};
    fields.forEach(field => {
        let attribute: string | null = null;
        if (field === 'class') attribute = 'class';
        if (field.startsWith('attr:')) attribute = field.slice(5);
        if (attribute) {
            const value = el.getAttribute(attribute);
            if (value !== null) attributes[attribute] = value;
        }
    });
    if (Object.keys(attributes).length) info.attributes = attributes;
    return info;
}

    return {
        denNormalize,
        denIsVisible,
        denRefFor,
        denResolveRef,
        denResolveTarget,
        denRole,
        denText,
        denAccessibleName,
        denValue,
        denChecked,
        denDisabled,
        denSelected,
        denExpanded,
        denSnapshotStates,
        denSnapshotEligible,
        denSnapshotName,
        denSnapshotLevel,
        denDispatchInput,
        denSetValue,
        denInspect,
    };
})();
