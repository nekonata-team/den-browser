export interface DenAPI {
  boards: {
    /** Focus an existing Board in this Profile without activating its window. */
    focus(boardId: string): Promise<void>;
  };
}

declare global {
  interface Window {
    den?: DenAPI;
  }
}

// Supplied by the native, document-scoped wrapper; not an HTML authoring API.
declare const denAPITransport: {
  postMessage(message: { action: string; boardId: string }): Promise<unknown>;
};

window.den = Object.freeze({
  boards: Object.freeze({
    async focus(boardId: string): Promise<void> {
      await denAPITransport.postMessage({ action: 'board.focus', boardId });
    },
  }),
});
