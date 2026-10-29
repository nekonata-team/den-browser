declare module 'turndown-plugin-gfm' {
  import type TurndownService from 'turndown';
  export const strikethrough: TurndownService.Plugin;
  export const tables: TurndownService.Plugin;
  export const taskListItems: TurndownService.Plugin;
}
