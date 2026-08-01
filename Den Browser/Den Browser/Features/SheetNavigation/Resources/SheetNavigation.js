(() => {
  if (window.__denSheetNavigation) return;

  let enabled = false;
  let ignored = false;
  let alphabet = "asdfghjkl";
  let hints = [];
  let hintAction = "activate";
  let prefix = "";
  let countPrefix = "";
  let pendingKey = "";
  let pendingTimer = null;
  let lastFindQuery = "";
  let overlay = null;
  let findBar = null;
  let helpOverlay = null;

  const actionableSelector =
    'a[href],button,input:not([type="hidden"]),select,textarea,[role="button"]';
  const editableSelector =
    'input:not([type="hidden"]):not([type="file"]):not([type="checkbox"]):not([type="radio"]),textarea,[contenteditable="true"]';

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

  function openHints(action) {
    closeHints();
    hintAction = action;
    const selector = action === "openBoard" || action === "keepInDrawer"
      ? "a[href]"
      : actionableSelector;
    const targets = Array.from(document.querySelectorAll(selector)).filter((target) => {
      if (!isVisibleAndEnabled(target)) return false;
      return !["openBoard", "keepInDrawer"].includes(action)
        || ["http:", "https:"].includes(new URL(target.href, location.href).protocol);
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
      if (hintAction === "openBoard") {
        postMessage({ action: "openBoard", url: target.href });
      } else if (hintAction === "keepInDrawer") {
        postMessage({ action: "keepInDrawer", url: target.href });
      } else {
        target.click();
      }
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
    if (!["http:", "https:"].includes(url.protocol)) return;

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

  function closeFind() {
    findBar?.remove();
    findBar = null;
  }

  function closeHelp() {
    helpOverlay?.remove();
    helpOverlay = null;
  }

  function openHelp() {
    closeHints();
    closeFind();
    closeHelp();

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
      ["Sheet and URL", [["H / L", "back / forward in Sheet Stack"], ["r", "reload Current Sheet"], ["gu / gU", "URL parent / root"], ["ge / gE", "edit URL / open URL in new Board"], ["t / T", "Open Board / Overview"], ["yy", "copy Current Sheet URL"]]],
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

  function runFind(backward = false) {
    if (!lastFindQuery) return;
    window.find(lastFindQuery, false, backward, true, false, true, false);
  }

  function openFind() {
    closeHints();
    closeFind();
    const container = document.createElement("div");
    container.setAttribute("data-den-sheet-find", "");
    Object.assign(container.style, {
      position: "fixed",
      right: "16px",
      bottom: "16px",
      zIndex: "2147483647",
      display: "flex",
      alignItems: "center",
      gap: "6px",
      padding: "6px 9px",
      border: "1px solid #666",
      borderRadius: "6px",
      background: "#202124",
      color: "white",
      font: "13px ui-monospace, monospace",
      boxShadow: "0 4px 18px #0008",
    });
    const label = document.createElement("span");
    label.textContent = "/";
    const input = document.createElement("input");
    input.type = "text";
    input.value = lastFindQuery;
    input.setAttribute("aria-label", "Find in Current Sheet");
    Object.assign(input.style, {
      width: "220px",
      border: "0",
      outline: "0",
      background: "transparent",
      color: "white",
      font: "inherit",
    });
    input.addEventListener("keydown", (event) => {
      if (event.key !== "Enter") return;
      event.preventDefault();
      lastFindQuery = input.value;
      closeFind();
      runFind(event.shiftKey);
    });
    container.append(label, input);
    document.documentElement.append(container);
    findBar = container;
    input.focus();
    input.select();
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
      case "zH": scrollToEdge("x", false); break;
      case "zL": scrollToEdge("x", true); break;
      case "yy":
        postMessage({ action: "copyURL", url: location.href });
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
      case "t": postMessage({ action: "openBoardPanel" }); break;
      case "T": postMessage({ action: "showOverview" }); break;
      case "r": location.reload(); break;
      case "x": postMessage({ action: "removeBoard" }); break;
      case "X": postMessage({ action: "restoreBoard" }); break;
      case "/": openFind(); break;
      case "n": runFind(false); break;
      case "N": runFind(true); break;
      default: return false;
    }
    consume(event);
    return true;
  }

  function onKeyDown(event) {
    if (!event.isTrusted || !enabled || ignored || hasDisallowedModifier(event)) return;
    if (["Shift", "Control", "Alt", "Meta"].includes(event.key)) return;

    if (findBar) {
      if (event.key === "Escape") {
        consume(event);
        closeFind();
      }
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
      if (!enabled || ignored) {
        closeHints();
        closeFind();
        closeHelp();
        resetCommand();
      }
    },
  };
})();
