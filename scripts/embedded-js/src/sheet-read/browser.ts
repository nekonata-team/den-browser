import { read } from './entry';

// Bun IIFE output does not support esbuild's globalName.
Object.assign(globalThis, { denSheetRead: { read } });
