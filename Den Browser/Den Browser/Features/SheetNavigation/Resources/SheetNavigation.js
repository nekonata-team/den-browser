(() => {
  if (window.__denSheetNavigation) return;

  let enabled = false;
  let ignored = false;
  let paused = false;
  let alphabet = "asdfghjkl";
  let hints = [];
  let hintAction = "activate";
  let prefix = "";
  let countPrefix = "";
  let pendingKey = "";
  let pendingTimer = null;
  let lastFindQuery = "";
  let findMatches = [];
  let findActiveIndex = -1;
  let findInitialScroll = null;
  let findState = "inactive";
  let findHighlight = null;
  let findActiveHighlight = null;
  let findBar = null;
  let findInput = null;
  let findCountLabel = null;
  let overlay = null;
  let helpOverlay = null;
  const supportedSheetProtocols = new Set(["http:", "https:", "file:"]);

  const actionableSelector =
    'a[href],button,input:not([type="hidden"]),select,textarea,[role="button"]';
  const editableSelector =
    'input:not([type="hidden"]):not([type="file"]):not([type="checkbox"]):not([type="radio"]),textarea,[contenteditable="true"]';

  const hintActions = {
    activate: {
      selector: actionableSelector,
      accepts: () => true,
      activate(target) {
        target.click();
      },
    },
    openBoard: {
      selector: "a[href]",
      accepts: isSupportedSheetLink,
      activate(target) {
        postMessage({ action: "openBoard", url: target.href });
      },
    },
    keepInDrawer: {
      selector: "a[href]",
      accepts: isSupportedSheetLink,
      activate(target) {
        postMessage({ action: "keepInDrawer", url: target.href });
      },
    },
  };

  function isEditable(element) {
    return element instanceof HTMLInputElement ||
      element instanceof HTMLTextAreaElement ||
      element instanceof HTMLSelectElement ||
      element?.isContentEditable;
  }

  function hasDisallowedModifier(event) {
    return event.metaKey || event.altKey || event.ctrlKey;
  }

  function bodyHasFocus() {
    const active = document.activeElement;
    return !active || active === document.body || active === document.documentElement;
  }

  function consume(event) {
    event.preventDefault();
    event.stopImmediatePropagation();
  }

  function resetCommand() {
    countPrefix = "";
    pendingKey = "";
    clearTimeout(pendingTimer);
    pendingTimer = null;
  }

  function beginSequence(key) {
    pendingKey = key;
    clearTimeout(pendingTimer);
    pendingTimer = setTimeout(resetCommand, 1000);
  }

  function takeCount() {
    const count = Number.parseInt(countPrefix, 10) || 1;
    resetCommand();
    return count;
  }

  function isRenderedAndEnabled(element) {
    if (element.matches(":disabled") || element.getAttribute("aria-disabled") === "true") return false;
    for (let ancestor = element; ancestor; ancestor = ancestor.parentElement) {
      const style = getComputedStyle(ancestor);
      if (style.display === "none" || style.visibility === "hidden" || style.opacity === "0") return false;
    }
    const rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }

  function isVisibleAndEnabled(element) {
    if (!isRenderedAndEnabled(element)) return false;
    const rect = element.getBoundingClientRect();
    return rect.bottom > 0 && rect.right > 0 &&
      rect.top < innerHeight && rect.left < innerWidth;
  }

  function isSupportedSheetLink(target) {
    try {
      return supportedSheetProtocols.has(new URL(target.href, location.href).protocol);
    } catch {
      return false;
    }
  }

  function labels(count) {
    let width = 1;
    while (alphabet.length ** width < count) width += 1;
    return Array.from({ length: count }, (_, index) => {
      let label = "";
      for (let position = 0; position < width; position += 1) {
        label = alphabet[index % alphabet.length] + label;
        index = Math.floor(index / alphabet.length);
      }
      return label;
    });
  }

  function closeHints() {
    overlay?.remove();
    overlay = null;
    hints.length = 0;
    prefix = "";
  }

  function closeTransientUI() {
    closeHints();
    clearFind();
    closeHelp();
  }

  function openHints(action) {
    closeHints();
    hintAction = action;
    const configuration = hintActions[action];
    if (!configuration) return;
    const targets = Array.from(document.querySelectorAll(configuration.selector)).filter((target) => {
      if (!isVisibleAndEnabled(target)) return false;
      return configuration.accepts(target);
    });
    if (targets.length === 0) return;

    const container = document.createElement("div");
    container.setAttribute("data-den-sheet-hints", "");
    Object.assign(container.style, {
      position: "fixed",
      inset: "0",
      zIndex: "2147483647",
      pointerEvents: "none",
    });

    const targetLabels = labels(targets.length);
    targets.forEach((target, index) => {
      const rect = target.getBoundingClientRect();
      const marker = document.createElement("span");
      marker.textContent = targetLabels[index];
      Object.assign(marker.style, {
        position: "fixed",
        left: `${Math.max(0, rect.left)}px`,
        top: `${Math.max(0, rect.top)}px`,
        padding: "1px 4px",
        border: "1px solid #6b4d00",
        borderRadius: "3px",
        background: "#ffd75a",
        color: "#171100",
        font: "bold 12px ui-monospace, monospace",
        lineHeight: "16px",
      });
      container.append(marker);
      hints.push({ target, label: targetLabels[index], marker });
    });
    document.documentElement.append(container);
    overlay = container;
  }

  function postMessage(message) {
    window.webkit?.messageHandlers?.denSheetNavigation?.postMessage(message);
  }

  function activateHint(character) {
    prefix += character;
    const matching = hints.filter(({ label }) => label.startsWith(prefix));
    for (const hint of hints) {
      hint.marker.style.display = matching.includes(hint) ? "" : "none";
    }
    if (matching.length === 1 && matching[0].label === prefix) {
      const target = matching[0].target;
      closeHints();
      hintActions[hintAction].activate(target);
    } else if (matching.length === 0) {
      closeHints();
    }
  }

  function onClick(event) {
    if (!event.isTrusted || event.button !== 0 || event.ctrlKey) return;

    const opensBoard = event.metaKey && !event.altKey;
    const keepsInDrawer = event.altKey && !event.metaKey && !event.shiftKey;
    if (!opensBoard && !keepsInDrawer) return;

    const link = event.composedPath().find(
      (target) => target instanceof Element && target.matches("a[href]"),
    );
    if (!link) return;

    let url;
    try {
      url = new URL(link.getAttribute("href"), document.baseURI);
    } catch {
      return;
    }
    if (!supportedSheetProtocols.has(url.protocol)) return;

    consume(event);
    if (keepsInDrawer) {
      postMessage({ action: "keepInDrawer", url: url.href });
      return;
    }
    postMessage({
      action: "commandOpenBoard",
      url: url.href,
      focused: event.shiftKey,
    });
  }

  function scrollTarget(axis) {
    let element = document.elementFromPoint(innerWidth / 2, innerHeight * 0.75);
    while (element && element !== document.documentElement) {
      const style = getComputedStyle(element);
      const overflow = axis === "x" ? style.overflowX : style.overflowY;
      const scrollSize = axis === "x" ? element.scrollWidth : element.scrollHeight;
      const clientSize = axis === "x" ? element.clientWidth : element.clientHeight;
      if (/(auto|scroll)/.test(overflow) && scrollSize > clientSize) return element;
      element = element.parentElement;
    }
    return document.scrollingElement;
  }

  function scrollRelative(axis, direction, amount, count = 1) {
    const target = scrollTarget(axis);
    if (!target) return;
    const distance = amount === "half"
      ? ((axis === "x" ? target.clientWidth : target.clientHeight) / 2) * count
      : amount;
    target.scrollBy({
      left: axis === "x" ? direction * distance : 0,
      top: axis === "y" ? direction * distance : 0,
      behavior: "auto",
    });
  }

  function scrollToEdge(axis, end) {
    const target = scrollTarget(axis);
    if (!target) return;
    const position = end ? (axis === "x" ? target.scrollWidth : target.scrollHeight) : 0;
    target.scrollTo(axis === "x" ? { left: position } : { top: position });
  }

  function clearHighlights() {
    try {
      findHighlight?.clear();
    } catch (_) {}
    try {
      findActiveHighlight?.clear();
    } catch (_) {}
    if (typeof CSS !== "undefined" && CSS.highlights) {
      try {
        CSS.highlights.delete("den-find");
        CSS.highlights.delete("den-find-active");
      } catch (_) {}
    }
    findHighlight = null;
    findActiveHighlight = null;
  }

  function closeFind() {
    findBar?.remove();
    findBar = null;
    findInput = null;
    findCountLabel = null;
  }

  function clearFind() {
    findMatches = [];
    findActiveIndex = -1;
    findInitialScroll = null;
    findState = "inactive";
    clearHighlights();
    document.getElementById("den-find-styles")?.remove();
    closeFind();
  }

  function closeHelp() {
    helpOverlay?.remove();
    helpOverlay = null;
  }

  function openHelp() {
    closeTransientUI();

    const container = document.createElement("div");
    container.setAttribute("data-den-sheet-help", "");
    Object.assign(container.style, {
      position: "fixed",
      inset: "8vh 12vw",
      zIndex: "2147483647",
      overflow: "auto",
      padding: "22px 26px",
      border: "1px solid #666",
      borderRadius: "10px",
      background: "#202124f5",
      color: "#f1f3f4",
      font: "13px ui-monospace, monospace",
      lineHeight: "1.5",
      boxShadow: "0 8px 32px #000b",
      pointerEvents: "auto",
    });

    const title = document.createElement("h2");
    title.textContent = "Vim-style Sheet Navigation";
    Object.assign(title.style, { margin: "0 0 4px", font: "bold 18px system-ui" });
    const subtitle = document.createElement("p");
    subtitle.textContent = "Current Sheet commands · Escape closes this guide";
    Object.assign(subtitle.style, { margin: "0 0 18px", color: "#b8bcc2", font: "13px system-ui" });
    container.append(title, subtitle);

    const sections = [
      ["Scrolling", [["j / k", "scroll down / up"], ["d / u", "scroll half page down / up"], ["h / l", "scroll left / right"], ["gg / G", "top / bottom"], ["zH / zL", "left / right edge"]]],
      ["Hints", [["f / Space", "activate a Current Sheet target"], ["F", "open link as a new Board"], ["a", "keep link in Drawer"]]],
      ["Boards and Sheets", [["gt / gT", "next / previous Board in the Desk"], ["g0 / g$", "first / last Board in the Desk"], ["g[ / g]", "First / latest Sheet"], ["H / L", "back / forward in Sheet Stack"], ["r", "reload Current Sheet"], ["gu / gU", "URL parent / root"], ["ge / gE", "edit URL / open URL in new Board"], ["o", "open Essentials; press an Essential key"], ["t / T", "Open Board / Overview"], ["x / gx", "remove Board / remove and focus next Board"], ["yy / ym", "copy Current Sheet URL / Markdown link"]]],
      ["Find", [["/", "find in Current Sheet"], ["n / N", "next / previous match"]]],
    ];

    for (const [sectionTitle, commands] of sections) {
      const heading = document.createElement("h3");
      heading.textContent = sectionTitle;
      Object.assign(heading.style, { margin: "16px 0 6px", color: "#ffd75a", font: "bold 14px system-ui" });
      container.append(heading);
      for (const [keys, description] of commands) {
        const row = document.createElement("div");
        row.style.display = "grid";
        row.style.gridTemplateColumns = "150px 1fr";
        row.style.gap = "14px";
        const keyLabel = document.createElement("strong");
        keyLabel.textContent = keys;
        const descriptionLabel = document.createElement("span");
        descriptionLabel.textContent = description;
        descriptionLabel.style.color = "#d7d9dc";
        row.append(keyLabel, descriptionLabel);
        container.append(row);
      }
    }

    document.documentElement.append(container);
    helpOverlay = container;
  }

  function ensureFindStyles() {
    if (document.getElementById("den-find-styles")) return;
    const style = document.createElement("style");
    style.id = "den-find-styles";
    style.textContent = `
      ::highlight(den-find) {
        background-color: #ffd75a;
        color: #171100;
      }
      ::highlight(den-find-active) {
        background-color: #ff922b;
        color: #000000;
      }
    `;
    (document.head || document.documentElement).append(style);
  }

  function collectMatches(query) {
    findMatches = [];
    if (!query) return;
    const root = document.body || document.documentElement;
    if (!root) return;

    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        const p = node.parentElement;
        if (!p || /^(SCRIPT|STYLE|NOSCRIPT|TEXTAREA|INPUT|SELECT)$/.test(p.tagName)) return NodeFilter.FILTER_REJECT;
        if (p.closest("[data-den-sheet-find], [data-den-sheet-hints], [data-den-sheet-help]")) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      },
    });

    const sensitive = query.toLowerCase() !== query;
    const targetQuery = sensitive ? query : query.toLowerCase();
    let node;
    while ((node = walker.nextNode()) && findMatches.length < 1000) {
      const text = sensitive ? node.data : node.data.toLowerCase();
      let index = 0;
      while ((index = text.indexOf(targetQuery, index)) !== -1 && findMatches.length < 1000) {
        const range = new Range();
        range.setStart(node, index);
        range.setEnd(node, index + query.length);
        findMatches.push(range);
        index += query.length;
      }
    }
  }

  function findInitialMatchIndex() {
    if (findMatches.length === 0) return -1;
    const index = findMatches.findIndex((r) => r.getBoundingClientRect().top >= 0);
    return index === -1 ? 0 : index;
  }

  function scrollMatchIntoView(range) {
    const element = range.startContainer.parentElement;
    if (!element) return;
    const rect = range.getBoundingClientRect();
    if (rect.top < 30 || rect.bottom > (window.innerHeight - 30)) {
      element.scrollIntoView({ behavior: "auto", block: "center", inline: "nearest" });
    }
  }

  function updateFindStatus() {
    if (!findCountLabel) return;
    if (!lastFindQuery) {
      findCountLabel.textContent = "";
      return;
    }
    if (findMatches.length === 0) {
      findCountLabel.textContent = "No matches";
      findCountLabel.style.color = "#ff6b6b";
    } else {
      findCountLabel.textContent = `${findActiveIndex + 1} / ${findMatches.length}`;
      findCountLabel.style.color = "#b8bcc2";
    }
  }

  function updateHighlights(targetIndex = 0) {
    if (findMatches.length === 0) {
      findActiveIndex = -1;
      clearHighlights();
      updateFindStatus();
      if (findState === "input" && findInput && document.activeElement !== findInput) {
        findInput.focus();
      }
      return;
    }

    findActiveIndex =
      ((targetIndex % findMatches.length) + findMatches.length) % findMatches.length;
    const activeRange = findMatches[findActiveIndex];

    if (
      typeof Highlight !== "undefined" &&
      typeof CSS !== "undefined" &&
      CSS.highlights
    ) {
      ensureFindStyles();
      if (!findHighlight) {
        findHighlight = new Highlight();
        CSS.highlights.set("den-find", findHighlight);
      } else {
        findHighlight.clear();
      }
      for (const range of findMatches) {
        findHighlight.add(range);
      }

      if (!findActiveHighlight) {
        findActiveHighlight = new Highlight();
        CSS.highlights.set("den-find-active", findActiveHighlight);
      } else {
        findActiveHighlight.clear();
      }
      findActiveHighlight.add(activeRange);
    } else {
      const selection = window.getSelection();
      selection?.removeAllRanges();
      selection?.addRange(activeRange);
    }

    scrollMatchIntoView(activeRange);
    updateFindStatus();
  }

  function stepFind(delta = 1) {
    if (findMatches.length === 0) {
      if (lastFindQuery) {
        collectMatches(lastFindQuery);
        if (findMatches.length === 0) {
          updateFindStatus();
          return;
        }
        findActiveIndex = 0;
      } else {
        return;
      }
    }
    updateHighlights(findActiveIndex + delta);
  }

  function openFind() {
    closeHints();
    closeHelp();

    findInitialScroll = { x: window.scrollX, y: window.scrollY };
    findState = "input";

    if (!findBar) {
      const container = document.createElement("div");
      container.setAttribute("data-den-sheet-find", "");
      Object.assign(container.style, {
        position: "fixed",
        right: "16px",
        bottom: "16px",
        zIndex: "2147483647",
        display: "flex",
        alignItems: "center",
        gap: "8px",
        padding: "6px 10px",
        minWidth: "280px",
        boxSizing: "border-box",
        border: "1px solid #555",
        borderRadius: "6px",
        background: "#202124f0",
        color: "white",
        font: "13px ui-monospace, monospace",
        boxShadow: "0 4px 18px #0008",
      });

      const label = document.createElement("span");
      label.textContent = "/";
      label.style.color = "#ffd75a";
      label.style.fontWeight = "bold";
      label.style.flexShrink = "0";

      const input = document.createElement("input");
      input.type = "text";
      input.setAttribute("aria-label", "Find in Current Sheet");
      Object.assign(input.style, {
        flex: "1",
        minWidth: "80px",
        border: "0",
        outline: "0",
        background: "transparent",
        color: "white",
        font: "inherit",
      });

      const countLabel = document.createElement("span");
      Object.assign(countLabel.style, {
        font: "12px ui-monospace, monospace",
        fontVariantNumeric: "tabular-nums",
        whiteSpace: "nowrap",
        textAlign: "right",
        flexShrink: "0",
      });

      input.addEventListener("input", () => {
        lastFindQuery = input.value;
        collectMatches(lastFindQuery);
        updateHighlights(findInitialMatchIndex());
      });

      input.addEventListener("keydown", (event) => {
        if (event.key === "Enter") {
          consume(event);
          if (event.shiftKey) {
            stepFind(-1);
          }
          findState = "confirmed";
          input.blur();
          (document.body || document.documentElement)?.focus();
          return;
        }
        if (event.key === "Escape") {
          consume(event);
          if (findInitialScroll) {
            window.scrollTo(findInitialScroll.x, findInitialScroll.y);
          }
          clearFind();
        }
      });

      input.addEventListener("focus", () => {
        findState = "input";
      });

      container.append(label, input, countLabel);
      document.documentElement.append(container);

      findBar = container;
      findInput = input;
      findCountLabel = countLabel;
    }

    findInput.value = lastFindQuery;
    findInput.focus();
    findInput.select();

    if (lastFindQuery) {
      collectMatches(lastFindQuery);
      updateHighlights(findInitialMatchIndex());
    } else {
      updateFindStatus();
    }
  }

  function goUp(root) {
    const url = new URL(location.href);
    const parts = url.pathname.split("/").filter(Boolean);
    if (!root) parts.pop();
    url.pathname = root || parts.length === 0 ? "/" : `/${parts.join("/")}/`;
    url.search = "";
    url.hash = "";
    location.assign(url.href);
  }

  function runSequence(sequence, event) {
    const count = takeCount();
    switch (sequence) {
      case "gg": scrollToEdge("y", false); break;
      case "gu": goUp(false); break;
      case "gU": goUp(true); break;
      case "gi": focusEditable(count); break;
      case "ge": postMessage({ action: "editCurrentSheet" }); break;
      case "gE": postMessage({ action: "openCurrentSheetInNewBoard" }); break;
      case "g0": postMessage({ action: "focusFirstBoard" }); break;
      case "g$": postMessage({ action: "focusLastBoard" }); break;
      case "gt": postMessage({ action: "focusNextBoard" }); break;
      case "gT": postMessage({ action: "focusPreviousBoard" }); break;
      case "gx": postMessage({ action: "removeBoardAndFocusNext" }); break;
      case "g[": postMessage({ action: "goToFirstSheet" }); break;
      case "g]": postMessage({ action: "goToLatestSheet" }); break;
      case "zH": scrollToEdge("x", false); break;
      case "zL": scrollToEdge("x", true); break;
      case "yy":
        postMessage({ action: "copyURL", url: location.href });
        break;
      case "ym":
        postMessage({
          action: "copyMarkdownLink",
          title: document.title,
          url: location.href,
        });
        break;
      default:
        countPrefix = count === 1 ? "" : String(count);
        return false;
    }
    consume(event);
    return true;
  }

  function focusEditable(index) {
    const targets = Array.from(document.querySelectorAll(editableSelector)).filter((target) => {
      if (!isRenderedAndEnabled(target)) return false;
      return !target.readOnly && !target.disabled;
    });
    const target = targets[index - 1];
    if (!target) return;
    target.focus();
    target.scrollIntoView({ block: "nearest", inline: "nearest" });
  }

  function runCommand(key, event) {
    const count = takeCount();
    switch (key) {
      case "j": scrollRelative("y", 1, 60 * count); break;
      case "k": scrollRelative("y", -1, 60 * count); break;
      case "d": scrollRelative("y", 1, "half", count); break;
      case "u": scrollRelative("y", -1, "half", count); break;
      case "h": scrollRelative("x", -1, 60 * count); break;
      case "l": scrollRelative("x", 1, 60 * count); break;
      case "0": scrollToEdge("x", false); break;
      case "$": scrollToEdge("x", true); break;
      case "G": scrollToEdge("y", true); break;
      case "f": openHints("activate"); break;
      case "F": openHints("openBoard"); break;
      case "a": openHints("keepInDrawer"); break;
      case "H": history.back(); break;
      case "L": history.forward(); break;
      case "p": postMessage({ action: "pasteURL" }); break;
      case "P": postMessage({ action: "pasteURLInNewBoard" }); break;
      case "o": postMessage({ action: "showEssentials" }); break;
      case "t": postMessage({ action: "openBoardPanel" }); break;
      case "T": postMessage({ action: "showOverview" }); break;
      case "r": location.reload(); break;
      case "x": postMessage({ action: "removeBoard" }); break;
      case "X": postMessage({ action: "restoreBoard" }); break;
      case "/": openFind(); break;
      case "n": stepFind(count); break;
      case "N": stepFind(-count); break;
      default: return false;
    }
    consume(event);
    return true;
  }

  function onKeyDown(event) {
    if (!event.isTrusted || !enabled || ignored || paused || hasDisallowedModifier(event)) return;
    if (["Shift", "Control", "Alt", "Meta"].includes(event.key)) return;

    if (event.key === "Escape" && (findBar || findMatches.length > 0)) {
      consume(event);
      if (findInitialScroll && findState === "input") {
        window.scrollTo(findInitialScroll.x, findInitialScroll.y);
      }
      clearFind();
      return;
    }

    if (findState === "input") {
      return;
    }

    if (helpOverlay) {
      if (event.key === "Escape") {
        consume(event);
        closeHelp();
      } else {
        consume(event);
      }
      return;
    }

    if (overlay) {
      if (event.key === "Escape") {
        consume(event);
        closeHints();
      } else if (alphabet.includes(event.key.toLowerCase())) {
        consume(event);
        activateHint(event.key.toLowerCase());
      } else if (event.key === " ") {
        consume(event);
      }
      return;
    }

    if (event.key === "Escape" && isEditable(document.activeElement)) {
      if (event.isComposing) return;
      consume(event);
      document.activeElement.blur();
      return;
    }

    if (isEditable(document.activeElement)) return;

    if (event.key === "?" && bodyHasFocus()) {
      consume(event);
      openHelp();
      return;
    }

    if (event.key === "Escape" && (pendingKey || countPrefix)) {
      consume(event);
      resetCommand();
      return;
    }

    if (/^[1-9]$/.test(event.key) || (event.key === "0" && countPrefix)) {
      consume(event);
      countPrefix += event.key;
      return;
    }

    if (pendingKey) {
      const sequence = pendingKey + event.key;
      pendingKey = "";
      clearTimeout(pendingTimer);
      pendingTimer = null;
      if (runSequence(sequence, event)) return;
    }

    if (["g", "y", "z"].includes(event.key)) {
      consume(event);
      beginSequence(event.key);
      return;
    }

    if (event.key === " " && !event.shiftKey && bodyHasFocus()) {
      resetCommand();
      consume(event);
      openHints("activate");
      return;
    }

    runCommand(event.key, event);
  }

  window.addEventListener("click", onClick, true);
  document.addEventListener("keydown", onKeyDown, true);
  window.__denSheetNavigation = {
    configure(configuration) {
      enabled = configuration.enabled;
      alphabet = configuration.alphabet;
      const hostname = location.hostname.toLowerCase().replace(/\.$/, "");
      ignored = configuration.ignoredHosts.some(
        (host) => hostname === host || hostname.endsWith(`.${host}`),
      );
      paused = configuration.paused === true;
      if (!enabled || ignored || paused) {
        closeTransientUI();
        resetCommand();
      }
    },
  };
})();
