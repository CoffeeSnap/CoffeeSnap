# CoffeeSnap AI — a memory that learns your palate

CoffeeSnap is now a local-first SwiftUI taste companion. It does more than keep a coffee journal: it learns a time-sensitive taste profile from ratings and behavior, deliberately explores outside that profile, explains every recommendation, and helps the user retain coffee knowledge through active recall.

## What is implemented

- A **versioned 32-dimensional hybrid embedding**: interpretable acidity/body/sweetness/bitterness, roast, confidence and coffee-family features plus a compact projection of Apple's on-device `NLEmbedding`. A deterministic semantic fallback keeps the app functional when the system model is unavailable.
- A **private multimodal vector database** backed by SQLite WAL. Taste vectors, Apple Vision feature-print vectors, source documents, feedback events and review state are stored atomically and remain available offline.
- **Failure-safe persistence**: each tasting, its learning signals and recall cards commit as one transaction. Failed writes remain visible for retry without showing state that was never saved.
- **Truthful visual memory**: users can take or choose a photo, which is resized locally and encoded with pinned Vision feature-print revision 2. The Journal can retrieve visually similar past cups without uploading an image. Unlike the dormant prototype, appearance is never used to invent flavor, brew method or origin.
- An **honest cold start**: three quick, choice-based palate questions create a low-confidence calibration anchor. The app never invents sample tastings, and real cups progressively overrule that anchor.
- A **continual taste model** that weights explicit feedback, ML confidence and a 120-day preference half-life. Recent preferences can evolve without erasing older memories.
- **Hybrid recommendation ranking** combining semantic fit, note overlap, candidate-specific behavioral feedback, uncertainty-driven exploration and novelty. A bounded epsilon-softmax policy samples without replacement over maximal-marginal-relevance utility: strong matches remain dominant, every eligible action retains non-zero support, and the user's adventure preference controls the exploration budget.
- A **personal sensory lens** learned from prediction error: recommendation forms begin with catalog descriptors, the user corrects what they actually perceived, and a recency-weighted shrinkage estimate adjusts future candidate vectors. Catalog tasting notes become a prior rather than universal truth.
- **Explainable recommendations** that say whether a result is a strong match or a deliberate exploration.
- A **Taste Lab** built around retrieval practice, adaptive spacing and interleaving across origin, flavor, brew and roast concepts. New concepts are staged from 20 minutes through three days instead of producing an exhausting quiz immediately after a tasting.
- **Counterfactual-ready event telemetry** stored locally with slate position, policy score, exact conditional selection probability, the complete available-action distribution, policy/catalog versions and session ID for shown/opened/skipped/converted recommendations. Ordered-slate propensity is recoverable as the product of its conditional probabilities. Conversion attribution remains attached to the slate the user actually opened, and re-rating a journal memory cannot create a duplicate conversion.
- A real SwiftUI experience with Memory, Discover, Taste Lab and Journal surfaces, responsive rating/favorite feedback and a guided tasting form.
- A production-hardened media path that bounds image size, removes imported metadata, prevents stale photo-selection races and caches decoded thumbnails.

## Why SQLite instead of Pinecone, Weaviate, Chroma or DuckDB?

The database decision is based on the workload, not vector-database fashion:

| Option | Best fit | Decision for the iOS journal |
| --- | --- | --- |
| SQLite + exact vector scans | Private, offline personal collections | **Used now.** No service, API key, network dependency or approximate-index failure mode. Exact taste-cosine and visual feature-distance scans are appropriate for hundreds or low thousands of memories. |
| Pinecone | Managed cloud-scale, shared corpora, namespaces and metadata filtering | Future sync/shared-catalog provider. It would make a personal journal network-dependent today. |
| Weaviate | Self-hosted/cloud object + vector search with pre-filtering | Strong server option. Embedded Weaviate is documented as experimental and distributed as Linux binaries, not an iOS database. |
| Chroma | Python/JS experimentation and service deployments | Excellent prototyping ergonomics, but its local mode is an embedded library for those runtimes rather than Swift/iOS. |
| DuckDB VSS | Analytical vector workloads and local data science | Worth revisiting for offline analytics. Its HNSW extension and persistent indexes are documented as experimental, with WAL-recovery caveats. |

Primary references: [Apple NLEmbedding](https://developer.apple.com/documentation/naturallanguage/nlembedding), [Apple Vision feature prints](https://developer.apple.com/documentation/vision/analyzing-image-similarity-with-feature-print), [Pinecone indexing](https://docs.pinecone.io/guides/index-data/indexing-overview), [Weaviate storage](https://docs.weaviate.io/weaviate/concepts/storage), [Embedded Weaviate](https://weaviate.io/developers/weaviate/installation/embedded), [Chroma architecture](https://docs.trychroma.com/docs/overview/architecture), and [DuckDB VSS](https://duckdb.org/docs/current/core_extensions/vss).

The persistence service is intentionally isolated from ranking policy. A future cloud adapter can reuse the same versioned embedding, feedback event and recommendation types. Move retrieval to Pinecone or Weaviate when CoffeeSnap adds a large shared bean/café catalog, collaborative signals or tens of thousands of candidates—not before. The private profile and journal should remain on-device even when catalog retrieval moves to the cloud.

## The learning loop

```text
photo ──→ Vision embedding ──→ visual memory search
                                  ↕
tasting → taste embedding → local vector memory
   ↑                              ↓
recall review ← spaced scheduler ← profile + recommendation
   ↓                              ↑
grade / rating / open / skip / try ┘
```

The human-learning behavior follows well-established findings: retrieval practice improves long-term retention, distributed practice is more effective than massed practice, and interleaving can improve category discrimination. The scheduler stores stability, difficulty, lapses and due dates per concept and adapts intervals from the user's recall grade. Cold-start calibration uses concrete choices rather than asking a new user to accurately describe an unfamiliar palate.

Research basis: [Roediger & Karpicke on retrieval practice](https://pubmed.ncbi.nlm.nih.gov/16507066/), [Cepeda et al. on distributed practice](https://pubmed.ncbi.nlm.nih.gov/16719566/), [Kornell & Bjork on interleaved category learning](https://pubmed.ncbi.nlm.nih.gov/18578849/), [choice-based preference elicitation during cold start](https://research.tue.nl/en/publications/improving-user-experience-during-cold-start-through-choice-based-/), and [Google Research on exploration, diversity, novelty and serendipity](https://research.google/pubs/values-of-exploration-in-recommender-systems/).

The `taste-bandit-v4-bounded-softmax` logging policy now supplies the overlap and exact propensities required by counterfactual estimators. CoffeeSnap still does **not** present an offline policy lift estimate before enough independent outcomes exist: inverse-propensity estimates can have high variance, especially for complete ranked slates. Evaluation should begin with predeclared per-action rewards and effective-sample-size/weight diagnostics, then graduate to doubly robust or SWITCH-style estimates. See [Wang, Agarwal & Dudík on IPS/DR/SWITCH](https://proceedings.mlr.press/v70/wang17a.html) and [Swaminathan et al. on slate off-policy evaluation](https://arxiv.org/abs/1605.04812).

## Build and test

Open `CoffeeSnapAI.xcodeproj` and run the `CoffeeSnapAI` scheme on iOS 17 or later.

The ML/persistence core has no third-party package dependency:

```sh
swift test
```

The Xcode app target links the system `sqlite3` library. The 29 tests use a separate temporary database for every persistence case and cover calibration, preference learning, temporal decay, candidate feedback, personal sensory correction, bounded stochastic exploration, probability normalization/replay, multi-seed coverage, restart-safe conversion attribution, policy diagnostics, staged adaptive scheduling, interleaving, taste-vector round trips, real Vision feature-print determinism and ranking, atomic rollback, startup recovery, rich event persistence, repeated recommendation tries, deletion boundaries and migrations through multimodal schema v4.

## Deliberate next steps

1. Train and benchmark a coffee-specific Core ML model only for visually observable attributes such as vessel, foam and brew equipment; keep subjective taste and origin user-supplied unless there is calibrated evidence.
2. Add an opt-in sync provider with end-to-end encrypted journal payloads; keep raw images local by default.
3. Once enough independent sessions exist, add an experiment console with preregistered conversion/retention rewards, effective-sample-size gates and conservative IPS/DR/SWITCH comparisons; do not turn noisy estimates into product claims.
4. Add a shared café/bean catalog and switch only that large collection to Pinecone or Weaviate while retaining the private local profile.

## Author and license

Built by **Pierre-Henry Soria** — [pH7.me](https://ph7.me). Distributed under the [MIT License](LICENSE.md).
