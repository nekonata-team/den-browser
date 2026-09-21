window.__denSheetDOM = window.__denSheetDOM || (() => {
window.__denRefs = window.__denRefs || new Map();
window.__denNextRef = window.__denNextRef || 1;

function denNormalize(value) {
    return String(value || '').trim().replace(/\s+/g, ' ');
}

function denIsVisible(el) {
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

function denElementForRef(ref) {
    const entry = window.__denRefs.get(ref);
    return entry?.deref ? entry.deref() : entry;
}

function denRefFor(el) {
    if (!el || !el.isConnected) return null;
    const existing = el.getAttribute('data-den-ref');
    if (existing && /^@e\d+$/.test(existing)) {
        const mapped = denElementForRef(existing);
        if (mapped === el) return existing;
        if (!mapped || !mapped.isConnected) {
            window.__denRefs.set(existing, new WeakRef(el));
            return existing;
        }
    }

    let ref;
    do {
        ref = '@e' + window.__denNextRef++;
    } while (window.__denRefs.has(ref));
    window.__denRefs.set(ref, new WeakRef(el));
    el.setAttribute('data-den-ref', ref);
    return ref;
}

function denResolveRef(target) {
    if (!/^@e\d+$/.test(target)) return null;
    const mapped = denElementForRef(target);
    if (mapped?.isConnected) return mapped;
    const fallback = Array.from(document.querySelectorAll('[data-den-ref]'))
        .find(el => el.getAttribute('data-den-ref') === target);
    if (fallback) {
        window.__denRefs.set(target, new WeakRef(fallback));
        return fallback;
    }
    window.__denRefs.delete(target);
    return null;
}

function denResolveTarget(target) {
    if (target.startsWith('@')) return denResolveRef(target);
    return document.querySelector(target);
}

function denRole(el) {
    const explicit = denNormalize(el.getAttribute('role')).toLowerCase();
    if (explicit) return explicit.split(/\s+/)[0];

    const tag = el.tagName.toLowerCase();
    if (tag === 'a' && el.hasAttribute('href')) return 'link';
    if (tag === 'button' || tag === 'summary') return 'button';
    if (tag === 'textarea' || el.isContentEditable) return 'textbox';
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

function denText(el) {
    return denNormalize(el.innerText || el.textContent || '');
}

function denAccessibleName(el) {
    const labelledBy = el.getAttribute('aria-labelledby');
    if (labelledBy) {
        const labelledText = labelledBy.split(/\s+/)
            .map(id => document.getElementById(id))
            .filter(Boolean)
            .map(node => denText(node))
            .filter(Boolean)
            .join(' ');
        if (labelledText) return labelledText;
    }

    const ariaLabel = denNormalize(el.getAttribute('aria-label'));
    if (ariaLabel) return ariaLabel;

    if (el.labels && el.labels.length) {
        const labelText = Array.from(el.labels).map(label => denText(label)).filter(Boolean).join(' ');
        if (labelText) return labelText;
    }

    const alt = denNormalize(el.getAttribute('alt'));
    if (alt) return alt;

    const placeholder = denNormalize(el.getAttribute('placeholder'));
    if (placeholder) return placeholder;

    const type = (el.getAttribute('type') || '').toLowerCase();
    if (el.tagName.toLowerCase() === 'input' && ['button', 'submit', 'reset'].includes(type)) {
        const value = denNormalize(el.value);
        if (value) return value;
    }

    const title = denNormalize(el.getAttribute('title'));
    if (title) return title;

    return denText(el);
}

function denValue(el) {
    if (!el) return null;
    if (typeof el.value === 'string') return el.value;
    if (el.isContentEditable || ['textbox', 'searchbox', 'combobox'].includes(denRole(el))) {
        const text = el.innerText || el.textContent || '';
        return text === '\n' ? '' : text;
    }
    return null;
}

function denChecked(el) {
    if (!el) return null;
    const type = (el.getAttribute('type') || '').toLowerCase();
    if (typeof el.checked === 'boolean' && ['checkbox', 'radio'].includes(type)) {
        return !!el.checked;
    }
    const ariaChecked = el.getAttribute('aria-checked');
    if (ariaChecked === 'true') return true;
    if (ariaChecked === 'false') return false;
    return null;
}

function denDisabled(el) {
    if (!el) return null;
    if (el.matches(':disabled')) return true;
    const ariaDisabled = el.getAttribute('aria-disabled');
    if (ariaDisabled === 'true') return true;
    if (ariaDisabled === 'false') return false;
    const nativeControl = ['button', 'fieldset', 'input', 'optgroup', 'option', 'select', 'textarea']
        .includes(el.tagName.toLowerCase());
    return nativeControl ? !!el.disabled : null;
}

function denSelected(el) {
    if (!el) return null;
    if (el.tagName.toLowerCase() === 'option') return !!el.selected;
    const ariaSelected = el.getAttribute('aria-selected');
    if (ariaSelected === 'true') return true;
    if (ariaSelected === 'false') return false;
    return null;
}

function denExpanded(el) {
    if (!el) return null;
    if (el.tagName.toLowerCase() === 'details') return !!el.open;
    const ariaExpanded = el.getAttribute('aria-expanded');
    if (ariaExpanded === 'true') return true;
    if (ariaExpanded === 'false') return false;
    return null;
}

function denSnapshotStates(el) {
    const states = [];
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

function denSnapshotEligible(el, selectors) {
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

function denSnapshotName(el, role) {
    const hasExplicitName = el.hasAttribute('aria-label') || el.hasAttribute('aria-labelledby');
    const namedRoles = [
        'button', 'cell', 'checkbox', 'columnheader', 'combobox', 'dialog', 'heading', 'img',
        'link', 'listitem', 'menuitem', 'option', 'radio', 'row', 'switch', 'tab', 'textbox',
    ];
    if (!hasExplicitName && !namedRoles.includes(role)) return '';
    return denAccessibleName(el);
}

function denSnapshotLevel(el) {
    const tag = el.tagName.toLowerCase();
    if (/^h[1-6]$/.test(tag)) return Number(tag.slice(1));
    return null;
}

function denDispatchInput(el, value, isDelete = false) {
    el.dispatchEvent(new InputEvent('input', {
        bubbles: true,
        cancelable: true,
        inputType: isDelete ? 'deleteContentBackward' : 'insertText',
        data: isDelete ? null : value,
    }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
}

function denSetValue(el, value) {
    if (!el) return false;

    // 1. Native form controls
    if (typeof el.value === 'string') {
        const descriptor = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), 'value');
        descriptor?.set?.call(el, value);
        el.value = value;
        denDispatchInput(el, value);
        return true;
    }

    // 2. Editable elements (contenteditable or ARIA textbox/searchbox)
    if (el.isContentEditable || ['textbox', 'searchbox'].includes(denRole(el))) {
        el.focus();
        try { window.getSelection()?.selectAllChildren(el); } catch (_) {}
        const ok = value
            ? document.execCommand('insertText', false, value)
            : document.execCommand('delete', false, null);
        if (!ok || !value) el.textContent = value;
        denDispatchInput(el, value, !value);
        return true;
    }

    return false;
}

function denInspect(el, fields) {
    const info = {
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

    const attributes = {};
    fields.forEach(field => {
        let attribute = null;
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
