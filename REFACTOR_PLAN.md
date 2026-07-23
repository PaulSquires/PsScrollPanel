# CScrollPanel — design notes

Why the control is shaped the way it is, what was decided deliberately, and what the build
turned up. `README.md` is the usage document; this is the reasoning.

## Origin

Settings dialogs routinely hold more options than fit on one page, and every app that has
one re-derives the same container: a clipping parent, a taller inner window, a scrollbar,
wheel routing, and focus-into-view logic. This packages it as the thirteenth sibling in the
owner-drawn control family.

Seeded from `CListBox`'s container half (the only sibling that owns both a child window and
a `CVScrollBar`) and `CSplitter`'s WndProc/Create skeleton.

## Decisions taken deliberately

Each of these had a plausible alternative; none should be re-litigated without a new reason.

### The page is MOVED, not scrolled

`SetWindowPos( hPanel, 0, -nPos, cx, cy )`, with the container clipping. The alternative —
keep the page viewport-sized and `ScrollWindowEx` its contents — would mean the host's
controls no longer have fixed coordinates, so every child would have to be repositioned on
every scroll and `EnsureVisible` would have to invent a coordinate space to talk about them
in. Moving one window gives the host one stable coordinate system (the page) and lets USER32
blit the whole subtree.

The page is `max( contentHeight, viewportHeight )` tall, never shorter than the viewport, so
a short page still fills the visible area and the container's own fill can only ever show
through in the reserved strip.

### The strip is reserved, not reclaimed

When the thumb hides, only the bar window hides — the strip stays. `CListBox` does the
opposite (its bar's auto-hide gives the width back to the list), and that is right for a
list, whose rows simply re-wrap. Here the page is full of the host's controls, laid out
against a width: reclaiming 12 px would re-flow the whole page and jitter every right-aligned
edit box each time the mouse crossed the boundary. The bar's back colour tracks the page's,
so a reserved-but-empty strip is invisible.

### The reveal rule is a pure function

`CScrollPanel_ShouldShow( bNeeds, bMouse, bFocus )` is not a method and takes no window. All
eight rows of its truth table are asserted directly; the wiring from it to `ShowWindow` is
asserted separately, by driving the real timer handler with the cursor parked off-screen.
Had the rule been a method reading `GetFocus` and the cursor, neither would have been
testable and the whole feature would have rested on the interactive pass.

### The reveal is POLLED

The other siblings poll as a *safety net* because `WM_MOUSELEAVE` is unreliable. Here the
poll is the primary mechanism, for a stronger reason: the cursor can enter this control
directly over one of the host's child controls — moving fast onto an `EDIT` — in which case
neither the container nor the panel ever receives a `WM_MOUSEMOVE` at all. There is no
message to hang a `TrackMouseEvent` request off. A geometric cursor test does not care.

The same tick carries focus-change detection, so the feature costs one timer, not two.

### Focus-into-view fires on the CHANGE only

Scrolling to the focused control on every tick would fight the user: scroll the focused
control off screen deliberately and it would be yanked back under the cursor 100 ms later.
The tick compares `GetFocus()` against the last value and acts only when it differs. There
is an assertion for exactly this ("an unchanged focus does not re-scroll").

`EnsureVisible` never calls `SetFocus` — see Learnings.md on layout routines that steal it.

### `SCP_MESSAGEINFO` carries `lResult`

The only structural departure from the family's message-info struct. The panel is the parent
of the host's controls, so `WM_CTLCOLOR*` arrives there and nowhere else, and those messages
answer with an `HBRUSH`. A `boolean` "handled" cannot express a return value. The control
answers them itself by default (so a plain settings page is themed by one `SetColors` call
with no host code), and the callback overrides.

### `WM_COMMAND` is forwarded to the container's parent

Unclaimed `WM_COMMAND`/`WM_NOTIFY`/`WM_HSCROLL`/`WM_VSCROLL` are sent on to
`GetParent(hContainer)`. Without this, moving an existing settings page onto a CScrollPanel
would silently break every control notification the host already handles, and the failure
would look like "my checkboxes stopped working" rather than "my parent changed".

### No capture, no `CS_DBLCLKS`

Both are the *output* of the family's tests, not inherited defaults. The control tracks no
press state and owns no drag, so capture would buy nothing and could only be leaked. And
`CS_DBLCLKS` would turn every second rapid click on one of the *host's* controls into a
`WM_LBUTTONDBLCLK` (CIconPanel's reasoning, and the host's controls make it worse here).

### The wheel converts units here

`SPI_GETWHEELSCROLLLINES` counts lines; this range is pixels. Passing the system number
straight through would give three pixels a notch — the CHScrollBar bug in Learnings.md,
whose symptom is "the gesture barely works", which reads as a broken feature rather than a
wrong constant. One notch = system lines x `LineHeight`, recomputed per message so a Control
Panel change takes effect immediately. That per-message recompute is only safe because
`CVScrollBar_SetWheelStep` documents a no-op set as free — otherwise it would reset the
sub-notch accumulator on every message and put the dead-then-jump behaviour back.

## Two things the build turned up

**`IsWindowVisible` measured the page as zero.** `AutoSizeContent` skipped hidden children
using `IsWindowVisible`, which walks the *whole ancestor chain* — so while the control was
created but not yet shown, which is exactly when a host builds its page, every child read as
invisible and the page measured 0. The right question is "did the host hide this row", which
is the child's own `WS_VISIBLE` bit. Caught by the self-test, which runs against a control
that is deliberately never shown; an interactive pass would have missed it, because by then
the window is up.

**fbc does not evaluate call arguments left to right.** The first cut of the self-test wrote
`SelfTest_Check( name, EnsureVisible(...) andalso GetPos() = 530, "pos=" & str(GetPos()) )`
and the detail string reported the position from *before* the scroll — several assertions
printed `PASS` beside a number that contradicted them. Every side effect is now hoisted into
a local first. Worth knowing generally: a trace string built in the same call as the action
it describes is not necessarily describing it.

## Layout pass ordering (load-bearing)

1. the page's **width** is applied first, so the layout callback re-flows against a panel
   that is already the width it was told about
2. the layout callback runs, guarded by `bInLayout` against re-entering the pass (a host
   calling `SetContentHeight` from inside it records the value instead)
3. the height it returned is applied
4. the position is re-clamped — a shorter page can strand it past the end
5. the bar takes its strip (sized even while hidden: a 0x0 bar could not derive its own
   thumb geometry, and the reveal rule would then show an empty window)
6. the model is pushed into the bar and the reveal rule re-evaluated

## Verification status

- Builds clean with `-w all`, zero warnings.
- `CSCROLLPANEL_SELFTEST=1` — 48 assertions, all passing (counted from the output, not
  inferred from a zero failure count).
- `CSCROLLPANEL_TRACE=1` — the real demo page traces
  `viewport=664x541 panel=(0,0,652x1178) bar=(652,0,12x541) content=1178 pos=0/637`, i.e.
  page width + strip = client width exactly.
- **The interactive pass has been run and passed** (2026-07-23, by the author): the thumb
  revealing and hiding under a real cursor, focus holding it visible with the mouse away,
  Tab scrolling controls into view, the wheel over both the page and an `EDIT`, thumb
  dragging, the seam where the hidden strip meets the page, and resize re-flow. That pass is
  the only check on the half of this control the assertions cannot reach, so it is what
  closes this out.
