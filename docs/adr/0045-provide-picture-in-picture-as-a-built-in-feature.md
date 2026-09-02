---
status: accepted
---

# Provide Picture in Picture as a built-in Feature

Den Browser makes native Picture in Picture (PiP) a built-in Feature for every Web Board. The Board header context menu keeps the existing "Toggle Picture in Picture" action, while Settings no longer exposes an enablement toggle.

The original opt-in decision in [ADR 0021](./0021-experimental-native-picture-in-picture.md) limited exposure because PiP depends on a private WebKit preference and site-specific DOM behavior. PiP is now established enough as part of Den Browser's web workflow to provide by default. The runtime selector check and site-specific JavaScript behavior remain unchanged.

The retired `preferences.picture-in-picture.enabled` key is ignored if present. The preference schema does not change because no persisted value is migrated or removed.
