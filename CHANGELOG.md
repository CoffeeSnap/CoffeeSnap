# Changelog

All notable changes to CoffeeSnap are documented here.

## 1.1.0 — 2026-08-13

### Highlights

- Adds private, offline taste and visual vector memory with versioned Apple Natural Language and Vision embeddings.
- Adds a bounded stochastic recommendation policy with exact propensity logging and restart-safe conversion attribution.
- Adds adaptive retrieval practice, spacing, and concept interleaving in Taste Lab.

### Production hardening

- Makes tasting records, recall cards, and learning signals atomic so partial writes cannot corrupt a memory.
- Keeps failed ratings, favorites, calibration, and tasting saves visible for retry instead of displaying unpersisted state or dismissing forms.
- Adds retryable startup recovery and prevents database errors from opening false onboarding.
- Moves recommendation computation off the main actor and caches deterministic semantic projections for responsive interaction.
- Ranks compact vectors before decoding photo-backed records to reduce exact-search memory and CPU cost.
- Strips photo metadata during bounded downsampling, prevents selection races, and caches decoded thumbnails.
- Adds confirmation for destructive journal deletion, accurate search-empty states, responsive large-text layouts, and richer VoiceOver labels.
- Ships a production app icon, truthful compiled privacy descriptions, and an explicit no-tracking/no-collection privacy manifest.

### Validation

- Expands the native suite to 29 tests, including failure injection, transaction rollback, migration recovery, relaunch attribution, real Vision feature prints, and stochastic policy replay.
- Passes clean Debug and Release simulator builds plus Xcode static analysis.

## 1.0.0 — 2025-02-25

- Establishes the original CoffeeSnap iOS project and public repository baseline.
