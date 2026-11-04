export type DenToastSeverity = 'info' | 'success' | 'warning' | 'error';

export interface DenAPI {
  boards: {
    /** Focus an existing Board in this Profile without activating its window. */
    focus(boardId: string): Promise<void>;
  };
  toast: {
    /** Show transient feedback in the owning Den window. Defaults to info. */
    show(message: string, options?: { severity?: DenToastSeverity }): Promise<void>;
  };
}

declare global {
  interface Window {
    den?: DenAPI;
  }
}

// Supplied by the native, document-scoped wrapper; not an HTML authoring API.
declare const denAPITransport: {
  postMessage(message:
    | { action: 'board.focus'; boardId: string }
    | { action: 'toast.show'; message: string; severity: DenToastSeverity }
  ): Promise<unknown>;
};

window.den = Object.freeze({
  boards: Object.freeze({
    async focus(boardId: string): Promise<void> {
      await denAPITransport.postMessage({ action: 'board.focus', boardId });
    },
  }),
  toast: Object.freeze({
    async show(message: string, options?: { severity?: DenToastSeverity }): Promise<void> {
      await denAPITransport.postMessage({ action: 'toast.show', message, severity: options?.severity ?? 'info' });
    },
  }),
});
