---
status: accepted
---

# Keep Desk Preset search dependency-free

Desk Preset search uses a small local scorer instead of a fuzzy-search package. The expected collection is small, while the required ranking is product-specific: Desk Preset Label matches rank before Board Label matches, which rank before Current Sheet host matches. Prefix, substring, and ordered-character matching provide sufficient keyboard filtering without adding a package dependency.

This choice does not aim to provide typo correction. Reconsider a dedicated fuzzy-search package if Desk Preset collections become large or the product requires typo tolerance, match highlighting, or more advanced language-aware ranking.
