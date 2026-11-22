(() => {
  type PermissionState = 'default' | 'denied' | 'granted';
  type NotificationChannel = 'window.Notification' | 'sw.showNotification';

  interface WebNotificationMessage {
    channel: NotificationChannel;
    title: string;
    body: string;
    tag: string | null;
  }

  interface WebKitTransport {
    postMessage(message: WebNotificationMessage): unknown;
  }

  const getTransport = (): WebKitTransport | null => {
    const webkit = (window as unknown as {
      webkit?: { messageHandlers?: { denWebNotification?: WebKitTransport } };
    }).webkit;
    return webkit?.messageHandlers?.denWebNotification ?? null;
  };

  const forwardNotification = (
    channel: NotificationChannel,
    rawTitle: unknown,
    options?: NotificationOptions,
  ) => {
    const transport = getTransport();
    if (!transport) return;
    const title = typeof rawTitle === 'string' ? rawTitle : String(rawTitle ?? '');
    const body = typeof options?.body === 'string' ? options.body : '';
    const tag = typeof options?.tag === 'string' ? options.tag : null;
    try {
      transport.postMessage({ channel, title, body, tag });
    } catch {
      // Ignore bridge delivery failures in page context.
    }
  };

  class DenWebNotification extends EventTarget {
    static readonly maxActions = 0;

    static get permission(): PermissionState {
      return 'granted';
    }

    static requestPermission(
      callback?: NotificationPermissionCallback,
    ): Promise<NotificationPermission> {
      const result: NotificationPermission = 'granted';
      if (typeof callback === 'function') {
        try {
          callback(result);
        } catch {
          // Ignore callback errors from host page.
        }
      }
      return Promise.resolve(result);
    }

    readonly title: string;
    readonly body: string;
    readonly tag: string;
    readonly data: unknown;
    readonly dir: NotificationDirection;
    readonly icon: string;
    readonly lang: string;
    readonly silent: boolean | null;

    onclick: ((this: Notification, ev: Event) => unknown) | null = null;
    onclose: ((this: Notification, ev: Event) => unknown) | null = null;
    onerror: ((this: Notification, ev: Event) => unknown) | null = null;
    onshow: ((this: Notification, ev: Event) => unknown) | null = null;

    constructor(title: string, options: NotificationOptions = {}) {
      super();
      this.title = typeof title === 'string' ? title : String(title ?? '');
      this.body = typeof options.body === 'string' ? options.body : '';
      this.tag = typeof options.tag === 'string' ? options.tag : '';
      this.data = options.data ?? null;
      this.dir = options.dir ?? 'auto';
      this.icon = typeof options.icon === 'string' ? options.icon : '';
      this.lang = typeof options.lang === 'string' ? options.lang : '';
      this.silent = options.silent ?? null;

      forwardNotification('window.Notification', this.title, options);

      queueMicrotask(() => {
        const event = new Event('show');
        this.dispatchEvent(event);
        this.onshow?.call(this as unknown as Notification, event);
      });
    }

    close(): void {
      const event = new Event('close');
      this.dispatchEvent(event);
      this.onclose?.call(this as unknown as Notification, event);
    }
  }

  Object.defineProperty(window, 'Notification', {
    configurable: true,
    writable: true,
    value: DenWebNotification,
  });

  const swRegistrationProto = (
    window as unknown as {
      ServiceWorkerRegistration?: {
        prototype?: { showNotification?: (title: string, options?: NotificationOptions) => Promise<void> };
      };
    }
  ).ServiceWorkerRegistration?.prototype;

  if (swRegistrationProto && typeof swRegistrationProto.showNotification === 'function') {
    swRegistrationProto.showNotification = function (
      title: string,
      options?: NotificationOptions,
    ): Promise<void> {
      forwardNotification('sw.showNotification', title, options);
      return Promise.resolve();
    };
  }
})();
