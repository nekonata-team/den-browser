type InspectionConsoleLevel = "debug" | "info" | "log" | "warn" | "error";

type InspectionPageSelection = {
  tag: string;
  id: string;
  className: string;
  role: string;
  ariaLabel: string;
  text: string;
  attributes: string[];
  labels: string[];
  ancestors: string[];
};

type InspectionDOMAttribute = { name: string; value: string };

type InspectionDOMNode = {
  id: string;
  tag: string;
  attributes: InspectionDOMAttribute[];
  text: string;
  childCount: number;
};

type InspectionConsoleEvent = {
  id: string;
  time: string;
  level: string;
  message: string;
};

type InspectionConsoleHook = {
  original: (...values: any[]) => void;
  wrapped: (...values: any[]) => void;
};

type InspectionPageState = {
  document: Document;
  active: boolean;
  collecting: boolean;
  picking: boolean;
  selection: InspectionPageSelection | null;
  selectedElement: Element | null;
  nodeIDs: WeakMap<Element, string>;
  elements: Map<string, Element>;
  nextNodeID: number;
  nextEventID: number;
  events: InspectionConsoleEvent[];
  previousCursor: string;
  consoleHooks: Partial<Record<InspectionConsoleLevel, InspectionConsoleHook>>;
  listeners: {
    error?: (event: ErrorEvent) => void;
    rejection?: (event: PromiseRejectionEvent) => void;
    pointermove?: (event: PointerEvent) => void;
    reposition?: () => void;
    click?: (event: MouseEvent) => void;
    pointerout?: (event: PointerEvent) => void;
    pagehide?: () => void;
  };
  installed: boolean;
  collectionInstalled: boolean;
  highlight: HTMLDivElement | null;
  pointer: { x: number; y: number } | null;
  install: () => void;
  uninstall: () => void;
  installCollection: () => void;
  uninstallCollection: () => void;
  removeHighlight: () => void;
  showHighlight: (element: Element) => void;
  repositionHighlight: () => void;
  startPicking: () => void;
  startCollection: () => void;
  readSnapshot: () => string;
  readChildren: (id: string) => string;
  selectNode: (id: string) => boolean;
  highlightNode: (id: string) => boolean;
  clearHighlight: () => void;
  stop: () => void;
};

interface Window {
  __denInspection?: InspectionPageState;
}

(() => {
  const previousState = window.__denInspection;
  const state: InspectionPageState = previousState && previousState.document === document
    ? previousState
    : {
      document,
      active: true,
      collecting: false,
      picking: false,
      selection: null,
      selectedElement: null,
      nodeIDs: new WeakMap(),
      elements: new Map(),
      nextNodeID: 0,
      nextEventID: 0,
      events: [],
      previousCursor: "",
      consoleHooks: {},
      listeners: {},
      installed: false,
      collectionInstalled: false,
      highlight: null,
      pointer: null,
      install: () => {},
      uninstall: () => {},
      installCollection: () => {},
      uninstallCollection: () => {},
      removeHighlight: () => {},
      showHighlight: () => {},
      repositionHighlight: () => {},
      startPicking: () => {},
      startCollection: () => {},
      readSnapshot: () => "",
      readChildren: () => "[]",
      selectNode: () => false,
      highlightNode: () => false,
      clearHighlight: () => {},
      stop: () => {},
    };
  if (state !== previousState) {
    const record = (level: string, values: unknown[]) => {
      if (!state.active || !state.collecting) return;
      const message = values.map(value => {
        if (typeof value === "string") return value;
        if (value instanceof Error) return String(value);
        try { return JSON.stringify(value) ?? String(value); } catch { return String(value); }
      }).join(" ");
      state.events.push({ id: `${Date.now()}-${++state.nextEventID}`, time: new Date().toLocaleTimeString(), level, message });
      if (state.events.length > 80) state.events.shift();
    };
    state.listeners.error = event => record("error", [event.message]);
    state.listeners.rejection = event => record("rejection", [event.reason]);
    state.installCollection = () => {
      if (state.collectionInstalled) return;
      for (const level of ["debug", "info", "log", "warn", "error"] as const) {
        const hook = state.consoleHooks[level] ?? { original: () => {}, wrapped: () => {} };
        hook.original = console[level];
        hook.wrapped = function (this: Console, ...values: any[]) {
          record(level, values);
          hook.original.apply(this, values);
        };
        state.consoleHooks[level] = hook;
        console[level] = hook.wrapped;
      }
      window.addEventListener("error", state.listeners.error!);
      window.addEventListener("unhandledrejection", state.listeners.rejection!);
      window.addEventListener("pagehide", state.listeners.pagehide!);
      state.collectionInstalled = true;
    };
    state.uninstallCollection = () => {
      if (!state.collectionInstalled) return;
      for (const [level, hook] of Object.entries(state.consoleHooks)) {
        if (hook && console[level as InspectionConsoleLevel] === hook.wrapped) {
          console[level as InspectionConsoleLevel] = hook.original;
        }
      }
      window.removeEventListener("error", state.listeners.error!);
      window.removeEventListener("unhandledrejection", state.listeners.rejection!);
      window.removeEventListener("pagehide", state.listeners.pagehide!);
      state.collectionInstalled = false;
    };
    state.install = () => {
      if (state.installed) return;
      document.addEventListener("pointermove", state.listeners.pointermove!, true);
      document.addEventListener("scroll", state.listeners.reposition!, true);
      window.addEventListener("resize", state.listeners.reposition!);
      document.addEventListener("click", state.listeners.click!, true);
      document.addEventListener("pointerout", state.listeners.pointerout!, true);
      state.installed = true;
    };
    state.uninstall = () => {
      if (!state.installed) return;
      document.removeEventListener("pointermove", state.listeners.pointermove!, true);
      document.removeEventListener("scroll", state.listeners.reposition!, true);
      window.removeEventListener("resize", state.listeners.reposition!);
      document.removeEventListener("click", state.listeners.click!, true);
      document.removeEventListener("pointerout", state.listeners.pointerout!, true);
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
        state.highlight = document.createElement("div");
        state.highlight.setAttribute("data-den-inspection-highlight", "");
        state.highlight.setAttribute("aria-hidden", "true");
        state.highlight.style.cssText = "all:initial!important;display:block!important;position:fixed!important;pointer-events:none!important;z-index:2147483647!important;box-sizing:border-box!important;border:2px solid #ff5a1f!important;background:rgba(255,90,31,.12)!important;";
        document.documentElement.appendChild(state.highlight);
      }
      const rect = element.getBoundingClientRect();
      const highlight = state.highlight;
      if (!highlight) return;
      highlight.style.setProperty("left", `${rect.left}px`, "important");
      highlight.style.setProperty("top", `${rect.top}px`, "important");
      highlight.style.setProperty("width", `${rect.width}px`, "important");
      highlight.style.setProperty("height", `${rect.height}px`, "important");
    };
    state.repositionHighlight = () => {
      const pointer = state.pointer;
      if (!pointer || !state.active || !state.picking) return;
      const element = document.elementFromPoint(pointer.x, pointer.y);
      if (element) state.showHighlight(element);
    };
    state.listeners.pointermove = event => {
      if (!state.active || !state.picking) return;
      state.pointer = { x: event.clientX, y: event.clientY };
      const target = event.target;
      const element = target instanceof Element
        ? target
        : target instanceof Node ? target.parentElement : null;
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
      state.collecting = false;
      state.picking = false;
      state.events.length = 0;
      state.selection = null;
      state.selectedElement = null;
      state.uninstallCollection();
      state.uninstall();
      document.documentElement.style.cursor = state.previousCursor;
    };
    const textOf = (element: Element) => (element.textContent || "").replace(/\s+/g, " ").trim().slice(0, 240);
    const idOf = (element: Element) => {
      let id = state.nodeIDs.get(element);
      if (!id) {
        id = `n${++state.nextNodeID}`;
        state.nodeIDs.set(element, id);
      }
      state.elements.set(id, element);
      return id;
    };
    const domNode = (element: Element): InspectionDOMNode => ({
      id: idOf(element),
      tag: element.tagName.toLowerCase(),
      attributes: Array.from(element.attributes).slice(0, 16).map(attribute => ({
        name: attribute.name,
        value: attribute.value.slice(0, 160),
      })),
      text: element.children.length === 0 ? textOf(element) : "",
      childCount: element.children.length,
    });
    const selectedPath = () => {
      const selected = state.selectedElement;
      if (!selected?.isConnected) return [];
      const path: Element[] = [];
      for (let element: Element | null = selected; element; element = element.parentElement) path.push(element);
      return path.reverse().map(domNode);
    };
    const describe = (element: Element): InspectionPageSelection => {
      const id = element.id || "";
      const labelledBy = (element.getAttribute("aria-labelledby") || "").split(/\s+/).filter(Boolean);
      const labels = Array.from((element as HTMLInputElement).labels || []).map(textOf);
      const closestLabel = element.closest("label");
      if (closestLabel) labels.push(textOf(closestLabel));
      const attributes = Array.from(element.attributes)
        .filter(attribute => attribute.name === "role" || attribute.name.startsWith("aria-") || ["title", "name", "placeholder"].includes(attribute.name))
        .map(attribute => `${attribute.name}=${attribute.value}`);
      const ancestors: string[] = [];
      for (let parent = element.parentElement; parent && ancestors.length < 6; parent = parent.parentElement) {
        const parentRole = parent.getAttribute("role") || "";
        const parentLabel = parent.getAttribute("aria-label") || "";
        ancestors.push(`${parent.tagName.toLowerCase()}${parentRole ? ` role=${parentRole}` : ""}${parentLabel ? ` aria-label=${parentLabel}` : ""}: ${textOf(parent)}`);
      }
      return {
        tag: element.tagName.toLowerCase(), id, className: String((element as HTMLElement).className || ""),
        role: element.getAttribute("role") || "", ariaLabel: element.getAttribute("aria-label") || "",
        text: textOf(element), attributes,
        labels: [...labels, ...labelledBy.map(labelID => {
          const label = document.getElementById(labelID);
          return label ? textOf(label) : "";
        }).filter(Boolean)],
        ancestors,
      };
    };
    state.listeners.click = event => {
      if (!state.active || !state.picking) return;
      const target = event.target;
      const element = target instanceof Element
        ? target
        : target instanceof Node ? target.parentElement : null;
      if (!element) return;
      event.preventDefault();
      event.stopPropagation();
      event.stopImmediatePropagation();
      state.selection = describe(element);
      state.selectedElement = element;
      idOf(element);
      state.picking = false;
      state.removeHighlight();
      document.documentElement.style.cursor = state.previousCursor;
    };
    state.startPicking = () => {
      state.install();
      state.active = true;
      if (!state.picking) state.previousCursor = document.documentElement.style.cursor;
      state.removeHighlight();
      state.picking = true;
      document.documentElement.style.cursor = "crosshair";
    };
    state.startCollection = () => {
      state.active = true;
      state.collecting = true;
      state.installCollection();
    };
    state.readSnapshot = () => JSON.stringify({
      isPicking: state.picking,
      isCollecting: state.collecting,
      selection: state.selection,
      treePath: selectedPath(),
      events: state.events.slice(-80),
    });
    state.readChildren = id => {
      const element = state.elements.get(id);
      return JSON.stringify(element ? Array.from(element.children).map(domNode) : []);
    };
    state.selectNode = id => {
      const element = state.elements.get(id);
      if (!element) return false;
      state.selection = describe(element);
      state.selectedElement = element;
      state.picking = false;
      state.removeHighlight();
      document.documentElement.style.cursor = state.previousCursor;
      return true;
    };
    state.highlightNode = id => {
      const element = state.elements.get(id);
      if (!element) return false;
      state.showHighlight(element);
      return true;
    };
    state.clearHighlight = () => state.removeHighlight();
    state.stop = () => {
      state.active = false;
      state.collecting = false;
      state.picking = false;
      state.selection = null;
      state.selectedElement = null;
      state.events.length = 0;
      state.nodeIDs = new WeakMap();
      state.elements.clear();
      state.nextNodeID = 0;
      state.uninstallCollection();
      state.uninstall();
      state.pointer = null;
      document.documentElement.style.cursor = state.previousCursor;
      window.__denInspection = undefined;
    };
    window.__denInspection = state;
  }
})();
