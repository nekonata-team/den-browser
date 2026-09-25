import Foundation

struct InspectionPageSnapshot: Decodable, Equatable {
    var isPicking: Bool
    var selection: InspectionElementSummary?
    var events: [InspectionConsoleEvent]

    static let empty = InspectionPageSnapshot(isPicking: false, selection: nil, events: [])
}

struct InspectionElementSummary: Decodable, Equatable {
    var tag: String
    var id: String
    var className: String
    var role: String
    var ariaLabel: String
    var text: String
    var attributes: [String]
    var labels: [String]
    var ancestors: [String]
}

struct InspectionConsoleEvent: Decodable, Equatable, Identifiable {
    var id: String
    var time: String
    var level: String
    var message: String
}

enum InspectionPageScript {
    static let startPicking = #"""
        (() => {
          let state = window.__denInspection;
          if (!state || state.document !== document) {
            state = { document, active: true, picking: false, selection: null, events: [], previousCursor: '', consoleHooks: {}, listeners: {}, installed: false, highlight: null, pointer: null };
            const record = (level, values) => {
              if (!state.active) return;
              const message = values.map(value => {
                if (typeof value === 'string') return value;
                if (value instanceof Error) return String(value);
                try { return JSON.stringify(value) ?? String(value); } catch { return String(value); }
              }).join(' ');
              state.events.push({ id: `${Date.now()}-${state.events.length}`, time: new Date().toLocaleTimeString(), level, message });
              if (state.events.length > 80) state.events.shift();
            };
            state.listeners.error = event => record('error', [event.message]);
            state.listeners.rejection = event => record('rejection', [event.reason]);
            state.install = () => {
              if (state.installed) return;
              for (const level of ['log', 'warn', 'error']) {
                const hook = state.consoleHooks[level] || {};
                hook.original = console[level];
                hook.wrapped = function (...values) { record(level, values); return hook.original.apply(this, values); };
                state.consoleHooks[level] = hook;
                console[level] = hook.wrapped;
              }
              window.addEventListener('error', state.listeners.error);
              window.addEventListener('unhandledrejection', state.listeners.rejection);
              document.addEventListener('pointermove', state.listeners.pointermove, true);
              document.addEventListener('scroll', state.listeners.reposition, true);
              window.addEventListener('resize', state.listeners.reposition);
              document.addEventListener('click', state.listeners.click, true);
              document.addEventListener('pointerout', state.listeners.pointerout, true);
              window.addEventListener('pagehide', state.listeners.pagehide);
              state.installed = true;
            };
            state.uninstall = () => {
              if (!state.installed) return;
              for (const [level, hook] of Object.entries(state.consoleHooks)) {
                if (console[level] === hook.wrapped) console[level] = hook.original;
              }
              window.removeEventListener('error', state.listeners.error);
              window.removeEventListener('unhandledrejection', state.listeners.rejection);
              document.removeEventListener('pointermove', state.listeners.pointermove, true);
              document.removeEventListener('scroll', state.listeners.reposition, true);
              window.removeEventListener('resize', state.listeners.reposition);
              document.removeEventListener('click', state.listeners.click, true);
              document.removeEventListener('pointerout', state.listeners.pointerout, true);
              window.removeEventListener('pagehide', state.listeners.pagehide);
              state.removeHighlight();
              state.installed = false;
            };
            state.removeHighlight = () => {
              state.highlight?.remove();
              state.highlight = null;
            };
            state.showHighlight = element => {
              if (!(element instanceof Element) || element === state.highlight) return;
              if (!state.highlight) {
                state.highlight = document.createElement('div');
                state.highlight.setAttribute('data-den-inspection-highlight', '');
                state.highlight.setAttribute('aria-hidden', 'true');
                state.highlight.style.cssText = 'all:initial!important;display:block!important;position:fixed!important;pointer-events:none!important;z-index:2147483647!important;box-sizing:border-box!important;border:2px solid #ff5a1f!important;background:rgba(255,90,31,.12)!important;';
                document.documentElement.appendChild(state.highlight);
              }
              const rect = element.getBoundingClientRect();
              state.highlight.style.setProperty('left', `${rect.left}px`, 'important');
              state.highlight.style.setProperty('top', `${rect.top}px`, 'important');
              state.highlight.style.setProperty('width', `${rect.width}px`, 'important');
              state.highlight.style.setProperty('height', `${rect.height}px`, 'important');
            };
            state.repositionHighlight = () => {
              if (!state.pointer || !state.active || !state.picking) return;
              const element = document.elementFromPoint(state.pointer.x, state.pointer.y);
              if (element) state.showHighlight(element);
            };
            state.listeners.pointermove = event => {
              if (!state.active || !state.picking) return;
              state.pointer = { x: event.clientX, y: event.clientY };
              const element = event.target instanceof Element ? event.target : event.target?.parentElement;
              if (element) state.showHighlight(element);
            };
            state.listeners.reposition = () => state.repositionHighlight();
            state.listeners.pointerout = event => {
              if (event.relatedTarget) return;
              state.pointer = null;
              state.removeHighlight();
            };
            state.listeners.pagehide = () => {
              state.active = false;
              state.picking = false;
              state.uninstall();
              document.documentElement.style.cursor = state.previousCursor;
            };
            state.listeners.click = event => {
              if (!state.active || !state.picking) return;
              const element = event.target instanceof Element ? event.target : event.target?.parentElement;
              if (!element) return;
              event.preventDefault();
              event.stopPropagation();
              event.stopImmediatePropagation();
              state.selection = describe(element);
              state.picking = false;
              state.removeHighlight();
              document.documentElement.style.cursor = state.previousCursor;
            };
            const textOf = element => (element.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 240);
            const describe = element => {
              const id = element.id || '';
              const labelledBy = (element.getAttribute('aria-labelledby') || '').split(/\s+/).filter(Boolean);
              const labels = Array.from(element.labels || []).map(textOf);
              if (element.closest('label')) labels.push(textOf(element.closest('label')));
              const attributes = Array.from(element.attributes)
                .filter(attribute => attribute.name === 'role' || attribute.name.startsWith('aria-') || ['title', 'name', 'placeholder'].includes(attribute.name))
                .map(attribute => `${attribute.name}=${attribute.value}`);
              const ancestors = [];
              for (let parent = element.parentElement; parent && ancestors.length < 6; parent = parent.parentElement) {
                const parentRole = parent.getAttribute('role') || '';
                const parentLabel = parent.getAttribute('aria-label') || '';
                ancestors.push(`${parent.tagName.toLowerCase()}${parentRole ? ` role=${parentRole}` : ''}${parentLabel ? ` aria-label=${parentLabel}` : ''}: ${textOf(parent)}`);
              }
              return {
                tag: element.tagName.toLowerCase(), id, className: String(element.className || ''),
                role: element.getAttribute('role') || '', ariaLabel: element.getAttribute('aria-label') || '',
                text: textOf(element), attributes,
                labels: [...labels, ...labelledBy.map(labelID => {
                  const label = document.getElementById(labelID);
                  return label ? textOf(label) : '';
                }).filter(Boolean)],
                ancestors
              };
            };
            window.__denInspection = state;
          }
          state.install();
          state.active = true;
          state.previousCursor = document.documentElement.style.cursor;
          state.removeHighlight();
          state.picking = true;
          document.documentElement.style.cursor = 'crosshair';
        })();
        """#

    static let readSnapshot = #"""
        (() => {
          const state = window.__denInspection;
          if (!state || state.document !== document) return JSON.stringify({ isPicking: false, selection: null, events: [] });
          return JSON.stringify({ isPicking: state.picking, selection: state.selection, events: state.events.slice(-80) });
        })();
        """#

    static let stop = #"""
        (() => {
          const state = window.__denInspection;
          if (!state || state.document !== document) return;
          state.active = false;
          state.picking = false;
          state.selection = null;
          state.events.length = 0;
          state.uninstall();
          state.pointer = null;
          document.documentElement.style.cursor = state.previousCursor;
        })();
        """#
}
