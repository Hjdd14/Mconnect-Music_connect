# Killing outgoing-route ghosting in a go_router `CustomTransitionPage` slide, with a persistent wallpaper

**Scope of evidence.** All framework statements below were read from the Flutter SDK installed on this machine
(`C:\Users\PC\flutter\flutter`, `version` = **3.47.5**, git revision **`6a19cca56475dbfba1478ee68d7bd0c2ef891da1`**).
Permalinks point at that revision, so line numbers are stable and match what this machine compiles.
go_router source is from `flutter/packages` `main` (`CustomTransitionPage` docs page reports **go_router 18.0.2** —
your pinned version may differ; the API shape shown here has been stable across 6.x–18.x).
Nothing in this report was verified by running an app; it is source + docs reading. Items that are inference are labelled.

---

## (a) Framework paint-semantics facts (with citations)

### F1. `opaque` on a route controls *lower overlay entries only* — never ancestors

`TransitionRoute.opaque` is documented as *"Whether the route obscures previous routes when the transition is complete"*
([api.flutter.dev `TransitionRoute`](https://api.flutter.dev/flutter/widgets/TransitionRoute-class.html)); go_router re-states it
(*"Whether the route obscures previous routes when the transition is complete"*,
[pub.dev `CustomTransitionPage.opaque`](https://pub.dev/documentation/go_router/latest/go_router/CustomTransitionPage/opaque.html)).
It is applied by writing the flag onto the route's **first overlay entry**
([`routes.dart#L293-L298`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/routes.dart#L293-L298)),
and `ModalRoute.createOverlayEntries()` makes that first entry the **modal barrier**, with the page scope second
([`routes.dart#L2349-L2359`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/routes.dart#L2349-L2359)).

`OverlayEntry.opaque` only tells the `Overlay` to skip painting *entries below that entry*
([`overlay.dart#L132-L146`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/overlay.dart#L132-L146)).
**Consequence that unlocks this whole problem:** a wallpaper painted by `MaterialApp.builder` is an **ancestor** of the `Overlay`,
not an overlay entry, so no value of `opaque` can hide it. You get "wallpaper always visible" **for free** and only have to
remove the *other route*.

### F2. The framework forces the incoming entry to be NON-opaque for the whole animation

`_handleStatusChanged`:
* `forward` / `reverse` → `overlayEntries.first.opaque = false` — [`routes.dart#L301-L308`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/routes.dart#L301-L308)
* `completed` → `overlayEntries.first.opaque = opaque` — [`routes.dart#L295-L298`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/routes.dart#L295-L298)
* `install()` sets it to `opaque` only if the animation is *already* completed — [`routes.dart#L331-L333`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/routes.dart#L331-L333)

`didPush()` starts `controller.forward()` ([`routes.dart#L336-L350`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/routes.dart#L336-L350)),
so the flag goes false essentially at frame 0. **This is deliberate**: a sliding page does not cover the viewport at frame 0,
so *something* must paint underneath, and the framework's answer is "the previous route".

> **Answer to "when does the outgoing route stop painting?"**
> * **During** a push or pop: it paints. Always. `opaque` cannot change this.
> * **After** a push settles: it stops painting **iff** `opaque == true` (F3).
> * The transition itself is exactly the window in which it is guaranteed to paint.

### F3. `opaque: true` (go_router's default) is what makes the ghost stop after the transition

`OverlayState.build` walks entries top-down, admitting each until it meets an opaque one; entries below that are added only
if `maintainState`, with `tickerEnabled: false`, and the rest are dropped — `skipCount: children.length - onstageCount`
([`overlay.dart#L886-L917`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/overlay.dart#L886-L917)).
`CustomTransitionPage.opaque` defaults to **true** and `maintainState` defaults to **true**
([go_router source `custom_transition_page.dart`](https://raw.githubusercontent.com/flutter/packages/main/packages/go_router/lib/src/pages/custom_transition_page.dart),
[pub.dev constructor](https://pub.dev/documentation/go_router/latest/go_router/CustomTransitionPage/CustomTransitionPage.html)).

Two important corollaries:

* With **`opaque: false`** the incoming entry never becomes opaque, so the route below is *onstage forever* — it paints for the
  entire lifetime of the top route. Through a transparent/acrylic plate this is a **permanent** ghost, not a transient one.
* With **`opaque: true`** the covered route goes offstage after settling: **not laid out, not painted, not hit-tested**
  (only `_childrenInPaintOrder()` is laid out — [`overlay.dart#L1466-L1485`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/overlay.dart#L1466-L1485),
  [`#L1424-L1459`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/overlay.dart#L1424-L1459)) but **still built** if `maintainState` is true
  ([`overlay.dart#L148-L161`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/overlay.dart#L148-L161)),
  wrapped in `TickerMode(enabled: false)` ([`overlay.dart#L418-L430`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/overlay.dart#L418-L430)).
  **Side effect to know about in a music app:** a covered page's animations freeze (its state survives).

Note the go_router doc text ("the routes behind the opaque route **will not be built**") is imprecise: the flag lands on the
**barrier** entry (which has `maintainState: false`), while the **scope** entry carries `maintainState: maintainState`
(true by default) and therefore stays built-but-offstage.

The "opaque content above stops the content behind from painting" behaviour is also acknowledged upstream in
[flutter/flutter#45797](https://github.com/flutter/flutter/issues/45797) (rrousselGit, framework/perf discussion).

### F4. `_Theatre` is `_Theater` in 3.47.5; `skipCount` is where offstage begins

Renamed in this revision: `class _Theater` ([`overlay.dart#L980-L1040`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/overlay.dart#L980-L1040)),
`skipCount` doc *"The first `skipCount` children are considered 'offstage'"*, `_firstOnstageChild`
([`overlay.dart#L1344-L1357`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/overlay.dart#L1344-L1357)).
It is private API — read it, don't depend on it.

### F5. `barrierColor` cannot be used as a static mask, and cannot be a photo

`barrierColor` is a `Color` ([`routes.dart#L1765-L1808`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/routes.dart#L1765-L1808)) and the barrier colour is
**animated from `barrierColor.withOpacity(0.0)` to `barrierColor`, driven by the route's own `animation`**, wrapped in
`AnimatedModalBarrier` ([`routes.dart#L2298-L2327`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/routes.dart#L2298-L2327)); the doc states it plainly:
*"While the route is animating into position, the color is animated from transparent to the specified color."* So it ramps in
over the transition — it cannot mask frame 0 — and a flat colour would replace the wallpaper anyway.

### F6. The framework has a first-class hook for "the incoming route dictates the outgoing route's exit"

`ModalRoute.delegatedTransition` (provided by the **incoming** route) is picked up by the route below as `receivedTransition`
([`routes.dart#L1600-L1645`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/routes.dart#L1600-L1645)) and applied in
`_buildFlexibleTransitions`, which **proxies away the outgoing route's own secondary transition** while the delegated one runs
([`routes.dart#L1647-L1680`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/routes.dart#L1647-L1680)).
Signature: `DelegatedTransitionBuilder = Widget? Function(BuildContext, Animation animation, Animation secondaryAnimation, bool allowSnapshotting, Widget? child)`
([`transitions.dart#L142-L158`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/transitions.dart#L142-L158)); `PageTransitionsBuilder.delegatedTransition`
defaults to `null` ([`page_transitions_builder.dart#L60-L61`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/page_transitions_builder.dart#L60-L61)).
The **canonical example is a custom `Page` + custom `PageRoute` subclass overriding `delegatedTransition`**, including the
`onDidRemovePage`/`MaterialApp.router` variant:
[`examples/api/lib/widgets/routes/flexible_route_transitions.1.dart`](https://raw.githubusercontent.com/flutter/flutter/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/examples/api/lib/widgets/routes/flexible_route_transitions.1.dart)
(doc-comment referenced from [`routes.dart#L1618-L1632`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/routes.dart#L1618-L1632)).

**go_router caveat:** `_CustomTransitionPageRoute<T> extends PageRoute<T>` and overrides only
`barrierDismissible/barrierColor/barrierLabel/transitionDuration/reverseTransitionDuration/maintainState/fullscreenDialog/opaque/buildPage/buildTransitions`
— **it does not expose `delegatedTransition`** ([source](https://raw.githubusercontent.com/flutter/packages/main/packages/go_router/lib/src/pages/custom_transition_page.dart)).
To use F6 you must supply your own `Page` subclass returning your own `PageRoute` subclass (exactly as the framework example does);
go_router accepts arbitrary `Page`s from `pageBuilder`.

### F7. The outgoing route *does* get a live `secondaryAnimation` (so family B needs no route subclassing)

`TransitionRoute.didChangeNext` wires `secondaryAnimation` to the next route's animation when
`canTransitionTo(next)` **and** `next.canTransitionFrom(this)` — both default `true`
([`routes.dart#L429-L492`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/routes.dart#L429-L492), `canTransitionTo` doc
[`#L512-L536`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/routes.dart#L512-L536)). Since go_router's route is a plain `PageRoute`, the
**covered** `CustomTransitionPage`'s own `transitionsBuilder(context, animation, secondaryAnimation, child)` receives
`secondaryAnimation` running 0→1 as it is covered, and 1→0 as it is revealed. The framework explicitly points at this for
"my route is being obscured" ([`routes.dart#L2528-L2545`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/routes.dart#L2528-L2545), incl. the
`ModalRoute.of(context)?.secondaryAnimation?.addStatusListener(...)` snippet).

### F8. What the built-in transitions do with `secondaryAnimation` (prior art, framework-authored)

* **FadeForwards (M3)** — the previous page fades out, slides left 25%, and for an **opaque** route the framework paints an
  opaque `ColoredBox(surface)` **behind** the fading page while `secondaryAnimation.isAnimating`, returning to
  `Colors.transparent` otherwise, gated on `ModalRoute.opaqueOf(context) ?? true`:
  [`page_transitions_theme.dart#L472-L570`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/material/page_transitions_theme.dart#L472-L570).
  **This is the framework's own "replace the outgoing page with a flat plate while it is covered" idiom**, and it is
  `ModalRoute.opaqueOf`-gated — see the merged fix below.
* **Zoom** — the outgoing page is driven by `DualTransitionBuilder(animation: ReverseAnimation(secondaryAnimation), …)` running
  the zoom *exit* transition: [`page_transitions_theme.dart#L1205-L1226`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/material/page_transitions_theme.dart#L1205-L1226).
* **Cupertino** — `CupertinoPageTransition.delegatedTransition` slides the previous route by a third:
  [`cupertino/route.dart#L452-L479`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/cupertino/route.dart#L452-L479).

**Merged upstream fix that is directly about transparent routes:** PR
[flutter/flutter#167032](https://github.com/flutter/flutter/pull/167032) — *"Fix visual overlap of transparent routes barrier when using
FadeForwardsPageTransitionsBuilder"* (merged 2025-08-13). Its diff moves the opaque `ColoredBox` so that
**`if (!isOpaque) return builder;`** — i.e. the flat plate is *not* painted for transparent routes, with the test
*"FadeForwardsPageTransitionBuilder does not use ColoredBox for non-opaque routes"*
([diff](https://patch-diff.githubusercontent.com/raw/flutter/flutter/pull/167032.diff)). The local 3.47.5 source already contains
the post-fix form. Lesson: the flat-plate trick is only correct when the route claims to be opaque.

### F9. `BackdropFilter` blurs *everything already painted*, which is why the ghost is blurred

*"A widget that applies a filter to the existing painted content and then paints child. … If there's no clip, the filter will be
applied to the full screen."* ([api.flutter.dev `BackdropFilter`](https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html)).
That "existing painted content" includes the ancestor wallpaper **and** any still-painting lower route — so an acrylic panel over a
transparent page will always blur whatever is underneath. The same page documents that a parent using a temporary buffer/save layer
(as `Opacity`/`FadeTransition` do) "may produce surprising results" with `BlendMode.srcOver` and suggests `BlendMode.src`, that the
effect is "relatively expensive", and that for blurring *one* widget, `ImageFiltered` is "both easier to use and less expensive".

### F10. Snapshotting replaces live painting with the *same* pixels (it cannot delete a ghost)

`SnapshotWidget` = *"A snapshot is a frozen texture-backed representation of all child pictures and layers stored as a `ui.Image`"*,
used "to avoid the expensive scale animation … may briefly pause any animations on the page"
([api.flutter.dev `SnapshotWidget`](https://api.flutter.dev/flutter/widgets/SnapshotWidget-class.html));
`TransitionRoute.allowSnapshotting` = *"will snapshot the entering and exiting routes. These snapshots are then animated **in place of
the underlying widgets** to improve performance"* ([api.flutter.dev](https://api.flutter.dev/flutter/widgets/TransitionRoute/allowSnapshotting.html)).
`SnapshotMode` members are exactly `permissive`, `normal` (default), `forced`
([`snapshot_widget.dart#L18-L38`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/snapshot_widget.dart#L18-L38)).

---

## (b) The five solution families

### A. Route/overlay paint semantics

**Exact API:** `TransitionRoute.opaque` / `ModalRoute.opaque` / `PageRoute.opaque`; go_router
`CustomTransitionPage(opaque: true)` (default), `maintainState`, `barrierColor`, `barrierDismissible`;
`OverlayEntry.opaque` (public setter, [`overlay.dart#L137-L146`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/overlay.dart#L137-L146));
`ModalRoute.opaqueOf(context)` ([`routes.dart#L1372-L1380`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/routes.dart#L1372-L1380)).

**What it buys you:** the "after the transition" half, for free, plus the fact that the ancestor wallpaper is never affected (F1).
**What it cannot buy you:** anything during the animation (F2). Also: `opaque` is *not* "make this page opaque on screen" — the page's
own pixels are your responsibility.

**Pitfalls:** `opaque: false` ⇒ permanent ghost (F3); `maintainState: true` keeps the covered route built with tickers disabled;
setting `overlayEntries.first.opaque` from outside works (the setter is public) but is overwritten by the route's status listener on
the next `forward`/`reverse`/`completed` event.

### B. Hiding the outgoing page via its own `secondaryAnimation` — **the idiomatic answer**

**Exact API:** the covered page's `transitionsBuilder` (or any widget inside it) + `secondaryAnimation`;
`AnimationStatus`; `Visibility`/`Offstage`; the framework-provided `ModalRoute.delegatedTransition` +
`DelegatedTransitionBuilder` when you want the *incoming* route to dictate the exit (F6).

**Canonical examples:** `FadeForwardsPageTransitionsBuilder._delegatedTransition` (framework replaces the outgoing page's
background with an opaque plate while covered, gated on `ModalRoute.opaqueOf`) — F8; `CupertinoPageTransition.delegatedTransition`
(previous route slides a third) — F8; the official `flexible_route_transitions` sample — F6; the third-party
[`sheet` 1.0.1 `SheetRoute.buildSecondaryTransitionForPreviousRoute`](https://pub.dev/documentation/sheet/latest/route/SheetRoute/buildSecondaryTransitionForPreviousRoute.html)
with `handleSecondaryAnimationTransitionForPreviousRoute` as its gate — **note: this method/flag does NOT exist anywhere in the
Flutter framework in 3.47.5** (grepped `packages/flutter/lib/src` — zero hits); it is a package-level equivalent, and when it applies
the previous route's own `secondaryAnimation` becomes `kAlwaysDismissedAnimation`, mirroring the framework's `ProxyAnimation` trick
in F6.

**Is it visually acceptable?** Yes, and it is what "opaque app with a wallpaper" looks like everywhere: the covered page is gone, the
wallpaper shows in the strip and behind the acrylic, and the arriving page slides over it. The one honest asymmetry: hiding the
covered page instantly on **push** costs nothing visually; on **pop** the route being hidden is the *destination*, so either it
appears progressively (visible reveal, but the departing glass page sits on top of it for ~200 ms) or it appears at the very end
(no overlap at all, but a 6%-wide strip of wallpaper during the pop). You must choose; the requirement as written ("zero trace of the
outgoing page in both directions") favours the second.

**Pitfalls:**
* Do **not** implement it as `secondaryAnimation.value > 0 ? SizedBox.shrink() : child` — removing the subtree disposes `State`
  (scroll offsets, controllers). Use `Visibility(visible: …, maintainState: true)` which compiles to
  `TickerMode(enabled: visible)` + `Offstage(offstage: !visible)` ([`indexed_stack.dart#L451-L474`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/indexed_stack.dart#L451-L474)),
  or plain `Offstage` (*"lays the child out as if it was in the tree, but without painting anything, without making the child
  available for hit testing"* — [api.flutter.dev `Offstage`](https://api.flutter.dev/flutter/widgets/Offstage-class.html)).
  `Offstage` keeps layout running; `Visibility(visible:false, maintainState:true, maintainAnimation:false)` also pauses its tickers.
* Predicate choice matters. `!secondaryAnimation.isDismissed` is the framework's own idiom for "something is on top"
  ([`cupertino/sheet.dart#L347`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/cupertino/sheet.dart#L347),
  [`routes.dart#L1655`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/routes.dart#L1655)) and is true from the first frame of a
  push (status is already `forward`), avoiding a one-frame flash that `value > 0` would produce.
* If the covered page contains a `BackdropFilter`, hiding it changes the acrylic's input — which is the point, but means the
  acrylic must be designed to look right over the raw wallpaper.

### C. Making the incoming route truly opaque

* **(i) plate that paints the photo** — works at paint level (the incoming scope entry is inserted above the outgoing entries, so a
  full-screen opaque child covers them from frame 0), but the photo is then rendered twice. Two renders of the same asset agree only
  if the box, alignment and `BoxFit` are identical; differences arise from `SafeArea`/`MediaQuery.padding`, `Navigator` insets,
  differing widget sizes under `BoxFit.cover` (crop anchor shifts), or device-pixel rounding. This is the "double background /
  scale mismatch / black bars" failure mode. There is no framework-side guarantee that two renders coincide.
* **(ii) plate outside the `SlideTransition`** — `Stack([Positioned.fill(plate), SlideTransition(child: content)])` is the correct
  shape *if* a plate is used at all: a static plate has no uncovered strip, whereas a sliding one does (which is precisely the
  current bug). Cheap and self-contained; still pays the double-render risk above (or a flat colour, which loses the wallpaper).
* **(iii) `opaque = true` "from frame zero"** — **not achievable through `opaque`**: F2 forces the entry non-opaque while animating.
  Only two things produce a frame-0 cut-off: an opaque *widget* inside the incoming route (i/ii), or imperatively flipping the
  incoming route's first overlay entry (see the observer trick below).

**Real-app wallpaper patterns.** I could **not** find a primary source for how Telegram/Spotify/Apple Music implement their
wallpaper (closed-source apps; no official engineering write-ups located). What is verifiable is the Flutter-side shape of the
pattern and its known interaction: the wallpaper is painted by an ancestor of the `Navigator` (`MaterialApp.builder` /
`Stack`-under-`Navigator`), pages that must show it are transparent (`Scaffold(backgroundColor: Colors.transparent)` /
`Material(color: Colors.transparent)` or no `Material` at all), and the acrylic layer is a `BackdropFilter`. A corroborating
community report of the `opaque: false` + background interaction is
[auto_route#2205](https://github.com/Milad-Akarie/auto_route_library/issues/2205)
(*"Routes with opaque: false show black background instead of underlying screen …"*, closed 2025-10). A related, unreadable-from-here
SO thread exists: [Push a transparent page with go_router?](https://stackoverflow.com/questions/75949913/push-a-transparent-page-with-go-router)
(HTTP 403 to my fetcher — cite only as a pointer).

### D. Freezing / snapshotting

**Exact APIs:** framework `SnapshotWidget(controller:, child:, mode: SnapshotMode.normal, painter:, autoresize: false)`,
`SnapshotController(allowSnapshotting: false)`, `SnapshotPainter`; `PageRoute.allowSnapshotting`;
`RenderRepaintBoundary.toImage({double pixelRatio = 1.0}) → Future<ui.Image>` (requires `debugNeedsPaint == false`;
*"uncompressed raw RGBA bytes … multiplied by the pixelRatio"*, so ≈ `w*h*4*pixelRatio²` bytes, plus a GPU→CPU readback) —
[api.flutter.dev `toImage`](https://api.flutter.dev/flutter/rendering/RenderRepaintBoundary/toImage.html), also `OffsetLayer.toImage`,
`Scene.toImage`; `ui.Image.toByteData`.

**The pub package named `snapshot_widget` is a different thing**: 1.0.1, publisher `inteniquetic.com`, 3 years old, 2 likes,
5 downloads, API `SnapshotsWidget` / `SnapshotsController.value(pixelRatio:) → Uint8List`
([pub.dev](https://pub.dev/packages/snapshot_widget)). It is not the framework class and is not a navigation primitive.

**Verdict: it does not help here.** Snapshotting reproduces the same pixels from a texture; `allowSnapshotting`'s own wording is
"animated in place of the underlying widgets … to improve performance", not "hidden". A snapshot of the outgoing route is a frozen
ghost, not the absence of one. Its costs are real: platform views cannot be captured (`SnapshotMode.normal` throws,
`permissive` silently falls back, `forced` ignores them), CanvasKit may regress because UI and engine share a thread
([`SnapshotWidget` caveats](https://api.flutter.dev/flutter/widgets/SnapshotWidget-class.html)), and a per-frame `toImage` readback
is exactly the wrong trade for a 300 ms transition. Use it (at most) as a perf trick for the *arriving* page's expensive blur, not
as a visibility mask.

### E. External suppression (Offstage/Visibility around the Navigator, custom `transitionsBuilder`)

* **Wrapping the Navigator** in `Offstage`/`Visibility` hides *everything*, including the arriving page — it cannot express
  "suppress the route below the top one". There is no public API that says "stop painting routes below the top route" other than the
  per-entry `opaque` flag (F1/F3).
* **Observer route (inference, unverified):** `NavigatorObserver.didPushNext(route, previousRoute)` fires "synchronously during the
  push operation, before the transition animation completes" ([`routes.dart#L2528-L2546`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/routes.dart#L2528-L2546)), and
  `didPush(route, previousRoute)` fires after `route.didPush()` — the push observation is queued
  ([`navigator.dart#L3249`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/navigator.dart#L3249), [`#L3274`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/navigator.dart#L3274), [`#L3308`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/navigator.dart#L3308))
  and dispatched later from `_flushHistoryUpdates` ([`#L4624-L4628`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/navigator.dart#L4624-L4628), [`#L3639`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/navigator.dart#L3639)).
  So an observer *could* set `route.overlayEntries.first.opaque = true` after the framework has set it false, producing a frame-0
  cut-off with no widget changes. **I did not verify this at runtime and found no upstream usage**; it depends on status-listener
  ordering, will be reset on the next status change, and freezes the covered route's tickers. Treat as experimental.
* **`PageRouteBuilder` with a `transitionsBuilder` that "never lets the two routes composite"** is not expressible: transitions build
  *within* one route's scope; compositing across routes is the `Overlay`'s job, decided by `opaque` (F1–F3). The closest legitimate
  form is the opaque static plate (C-ii) or hiding the outgoing route (B).
* **`BackdropFilter` → `ImageFiltered` is worth doing regardless:** if the acrylic blurs a private copy of the wallpaper
  (`ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30), child: <wallpaper copy>)`) instead of sampling the backdrop,
  then no route below can ever bleed into it — the "blurred white text" symptom becomes structurally impossible, and the docs call
  this cheaper than `BackdropFilter` for a single-widget blur.

---

## (c) Ranked recommendation

**#1 — `opaque: true` (do not set `false`) + hide the covered route from its own `secondaryAnimation` (family B).**
Exact shape:

```dart
// The page that can be COVERED (your primary/previous route content):
transitionsBuilder: (context, animation, secondaryAnimation, child) {
  return AnimatedBuilder(
    animation: secondaryAnimation,
    child: child,
    builder: (context, child) => Visibility(
      // Strict (zero overlap, both directions):
      visible: secondaryAnimation.isDismissed,
      // Variant that reveals the destination during pop instead:
      // visible: secondaryAnimation.isDismissed ||
      //     secondaryAnimation.status == AnimationStatus.reverse,
      maintainState: true,      // keep State / scroll offsets / controllers
      maintainAnimation: true,  // don't pause its animations while hidden
      child: child!,
    ),
  );
}
```

Why this is the right one: the wallpaper is an ancestor and is therefore untouched (F1); `opaque: true` removes the covered route
after the transition (F3); `secondaryAnimation.isDismissed` is the framework's own "nothing is above me" test (F8, F7) so the route
stops painting on the push's first frame and (strict variant) only returns when the pop has fully settled; no second render of the
photo, no alignment risk; state survives; the acrylic then blurs only the wallpaper.

**#1b (same rank, complementary) — make the acrylic backdrop-independent** with `ImageFiltered` over a private wallpaper copy
(F9). This removes the "blurred text through the glass" class of bug entirely, and is cheaper per the docs. Keep `BackdropFilter`
only if you specifically need to blur live content beneath (you don't, in this design).

**#2 — If the covered page must stay live, use an opaque static plate inside the arriving route, outside the slide (family C-ii).**
`Stack(fit: StackFit.expand, children: [plate, SlideTransition(child: content)])`, with the plate painting either the wallpaper
(double render: verify alignment) or a flat colour (loses the wallpaper). Use this when you cannot modify the covered route. Keep
`opaque: true` regardless.

**#3 — `ModalRoute.delegatedTransition` (F6) if the arriving route must own the exit choreography.** Costs a custom `Page` +
`PageRoute` subclass (go_router does not expose it), so only worth it if you also need the producer/consumer pattern.

**#4 — `NavigatorObserver` + `overlayEntries.first.opaque = true` (experimental, F-caveats in E).** No widget changes; fragile.

**Not recommended — family D (snapshotting):** it cannot hide anything (F10) and adds readback/memory cost.

**Both directions, explicitly:**
* **Push:** incoming page slides in over the wallpaper; covered page must stop painting from the first frame ⇒
  `visible: secondaryAnimation.isDismissed` (or the reverse-variant) — no strip ghost, no ghost through the acrylic.
* **Pop:** the departing page *is* the animation, so "zero trace" means the departing page must not sit on top of the destination's
  text. The strict predicate hides the destination until the pop settles (wallpaper-only strip, destination appears at the end — the
  requirement as written). The reverse-variant instead reveals the destination progressively under the departing glass — prettier,
  but it is a *deliberate* overlap.

---

## (d) Do not do this

1. **Do not set `opaque: false`** on a full-screen `CustomTransitionPage` if you expect the route below to stop painting — it paints
   for the top route's entire lifetime (F3), and any `BackdropFilter` will sample it forever.
2. **Do not expect `opaque: true` to stop the outgoing route painting during the animation** — the framework forces the flag false
   (F2). No `opaque` value does this.
3. **Do not use `barrierColor` as a mask or as the wallpaper** — it animates from transparent to its value over the transition
   (F5), and it is a `Color`, not an image.
4. **Do not hide the covered page by removing it from the tree** (`value > 0 ? SizedBox.shrink() : child`) — `State` is disposed and
   scroll positions/controllers are lost. `Visibility(maintainState: true)` or `Offstage`.
5. **Do not wrap the `Navigator` in `Offstage`/`Visibility`** to fix this — it hides the incoming page too, and `Visibility` with
   `maintainState: true` also disables tickers.
6. **Do not paint the same wallpaper at two different box sizes** (ancestor + route plate) without pinning the exact constraints:
   `SafeArea`/`MediaQuery` insets and `BoxFit.cover` cropping disagree invisibly until they show as a seam, a scale jump or bars.
7. **Do not use `RepaintBoundary.toImage` (or a per-frame `ui.Image`) to hide the outgoing route** — it reproduces the pixels, costs a
   readback (≈`w*h*4·r²` bytes) and requires a painted frame (F10).
8. **Do not rely on `SnapshotMode.forced`/`permissive` to dodge platform views** — `normal` throws on a platform view; the snapshot
   modes only decide what happens to the *un*-snapshottable content.
9. **Do not put an `Opacity`/`FadeTransition`/`AnimatedOpacity` above a `BackdropFilter`** — the save layer changes what the backdrop
   filter sees, and the docs warn about exactly this (`BlendMode.srcOver` "surprising results"; `BlendMode.src` suggested) — F9.
10. **Do not reach for `_Theatre`** — it is `_Theater`, private, and can change (F4). Public equivalent: `skipCount` semantics via
    `OverlayEntry.opaque` + `maintainState` only.
11. **Do not assume go_router's `opaque` doc** ("routes behind … will not be built") matches your build: with the default
    `maintainState: true` the covered route stays built (offstage, tickers disabled) — F3.

---

## (e) Explicitly NOT confirmed

1. **No runtime verification.** Nothing here was executed against a Flutter app or a widget test; every claim is derived from
   framework/package source and API docs at the stated revision. The predicates in (c) are derived, not observed.
2. **The `NavigatorObserver` + `overlayEntries.first.opaque = true` trick** is inference from source; I found no upstream usage and
   did not test it.
3. **The StackOverflow thread "Push a transparent page with go_router?"** returned HTTP 403 to my fetcher; I could not read its
   answers, so I cite it only as a pointer, not as evidence.
4. **No upstream issue describing this exact app symptom** was located. A GitHub search for issues with the relevant title terms
   returned 0 results; the closest primary sources are PR
   [#167032](https://github.com/flutter/flutter/pull/167032) (merged fix about transparent-route barrier overlap) and
   [auto_route#2205](https://github.com/Milad-Akarie/auto_route_library/issues/2205). I also could not read the 13 review comments /
   18 review-comment thread on #167032 (only the diff, via the API).
5. **How Telegram / Spotify / Apple Music actually implement their wallpaper** — not confirmed; those apps are closed-source and I
   found no primary engineering source. Only the generic Flutter pattern is confirmed.
6. **`sheet` package internals beyond the published doc page** — `buildSecondaryTransitionForPreviousRoute`,
   `handleSecondaryAnimationTransitionForPreviousRoute`, `DelegatedTransitionsRoute` are confirmed as *package* API by the docs page
   for `sheet` 1.0.1 and confirmed *absent* from the Flutter framework by grep; I did not read the package's implementation.
7. **Whether `secondaryAnimation` has already reached `AnimationStatus.forward` in the very first painted frame of a push** is
   expected from the code path (`didPush → forward() → status listener`) but not measured; if a one-frame flash ever appears, use the
   recorded final values in PR #167032 as precedent (`isAnimating`-style checks) or track the status change explicitly.
8. **`_RenderTheater` layout of offstage children**: I confirmed `performLayout` iterates `_childrenInPaintOrder()` only
   ([`#L1466-L1485`](https://github.com/flutter/flutter/blob/6a19cca56475dbfba1478ee68d7bd0c2ef891da1/packages/flutter/lib/src/widgets/overlay.dart#L1466-L1485)), i.e. offstage entries are not laid out;
   I did not confirm every downstream consequence of a stale size for a route that returns onstage.
