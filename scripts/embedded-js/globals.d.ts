type DenSheetDOMApi = Record<string, unknown>;
type DenRefEntry = Element | WeakRef<Element>;

interface SheetNavigationConfiguration {
  enabled: boolean;
  alphabet: string;
  ignoredHosts: string[];
  paused: boolean;
  reduceMotion: boolean;
}

interface SheetNavigationMessage {
  action: string;
  [key: string]: unknown;
}

interface Window {
  __denRefs: Map<string, DenRefEntry>;
  __denNextRef: number;
  __denSheetDOM?: DenSheetDOMApi;
  __denSheetNavigation?: {
    configure(configuration: SheetNavigationConfiguration): void;
  };
  webkit?: {
    messageHandlers?: {
      denSheetNavigation?: {
        postMessage(message: SheetNavigationMessage): void;
      };
    };
  };
}

interface HTMLVideoElement {
  webkitSupportsPresentationMode?(presentationMode: string): boolean;
  webkitSetPresentationMode?(presentationMode: string): void;
}

interface HighlightRegistry {
  delete(name: string): boolean;
  set(name: string, highlight: Highlight): HighlightRegistry;
}
