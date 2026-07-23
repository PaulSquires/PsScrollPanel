# CScrollPanel

A reusable owner-drawn **scrolling panel** for FreeBASIC / Win32, built on
[AfxNova](https://github.com/PaulSquires/AfxNova). It is the container behind a settings
dialog whose list of options is longer than one page: a viewport, a taller page of ordinary
child controls, and a vertical scrollbar whose **thumb is normally invisible**.

Thirteenth member of the owner-drawn control family (`CListBox`, `CVScrollBar`,
`CHScrollBar`, `CStatusBar`, `CTabBar`, `CTextBox`, `CMenuBar`, `CPopupMenu`, `CSplitter`,
`CIconPanel`, `CSelectBar`, `CToggle`, `CBufferPaint`) and follows the same shape: one real
`HWND`, per-instance state in the `CWindow` UserData area, one `WndProc`, host callbacks,
all rendering through `CBufferPaint`.

---

## What it is

```
CScrollPanel container HWND      WS_CLIPCHILDREN -- this is the VIEWPORT
├── panel (CWindow)              the PAGE. Taller than the viewport.
│     └── your controls          parented HERE, laid out in PAGE coordinates, once
└── CVScrollBar                  a reserved strip on the right edge
```

Scrolling **moves the page**: `SetWindowPos( hPanel, 0, -nPos, ... )`. Your controls keep
their page-relative coordinates forever, the container clips, and USER32 blits the whole
subtree in one go. You never reposition anything to scroll.

Everything scroll-related is in **pixels**: content height, position, wheel step.

## The auto-hiding thumb

The thumb is shown when

    there is something to scroll  AND  ( the cursor is over the control  OR  focus is on the page )

Either of the last two alone is enough, so a keyboard-only user Tabbing through the page
still sees where they are. The rule is a pure function — `CScrollPanel_ShouldShow( bNeeds,
bMouse, bFocus )` — which is why its truth table is in the self-test rather than in your
eyes.

**The bar's strip stays reserved whether or not the thumb is shown.** Only the bar window
hides, so the page's width never changes and your content never jumps sideways as the mouse
comes and goes. The bar's background colour tracks the page's, so the strip is invisible
when empty. (`CListBox` does the opposite — it reclaims the width — because a list has no
controls to jitter.)

## Quick start

```freebasic
' 1. create, theme, wire up
ghPanel = CScrollPanel_Create( hWndParent, IDC_SETTINGS )
CScrollPanel_SetColors( ghPanel, theme.BackColor, theme.ForeColor )
CScrollPanel_SetLayoutCallback( ghPanel, @Settings_Layout )

' 2. build the page -- parent everything to GetPanel(), NOT to the control
dim as HWND hPage = CScrollPanel_GetPanel( ghPanel )
hChk = CreateWindowExW( 0, @wstr("BUTTON"), @wstr("Word wrap"), _
        WS_CHILD or WS_VISIBLE or WS_TABSTOP or BS_AUTOCHECKBOX, _
        0, 0, 0, 0, hPage, cast(HMENU, cast(LONG_PTR, IDC_WRAP)), hInst, NULL )
CScrollPanel_SetFont( ghPanel, ghFont )

' 3. size it. The layout callback runs from here and every later resize.
SetWindowPos( ghPanel, 0, x, y, cx, cy, SWP_NOZORDER or SWP_SHOWWINDOW )
```

```freebasic
' The layout callback: re-flow against the width you are HANDED, return the page height.
function Settings_Layout( byval hPanel as HWND, byval cxPanel as integer ) as integer
    dim as integer y = 16
    SetWindowPos( hChk, 0, 16, y, cxPanel - 32, 24, SWP_NOZORDER )
    y += 34
    ...
    return y + 16                ' 0 would mean "leave the content height alone"
end function
```

If you would rather not track the height yourself, lay the controls out and call
`CScrollPanel_AutoSizeContent( h, padding )` — it measures the deepest **visible** child.

## Host obligations

1. **Parent your controls to `CScrollPanel_GetPanel()`**, never to the control itself. A
   control created on the container sits over the viewport and never scrolls.
2. **`AfxGdipInit` / `AfxGdipShutdown` must bracket your message loop** — `CBufferPaint`
   draws all geometry through GDI+.
3. **Never name an identifier `ok`.** GDI+'s `Status` enum defines `Ok = 0` in namespace
   `AfxNova`, and every host says `using AfxNova`. The family convention is `bOK`.
4. **`IsDialogMessage` in your pump** if you want Tab navigation across the page. The
   control's two windows already carry `WS_EX_CONTROLPARENT`, which is what lets
   `IsDialogMessage` recurse into them — without it Tab stops dead at the viewport.
5. **Call `CScrollPanel_Recalc`** after adding, removing or moving children outside a
   resize. The control does not watch the page for you.

## API

### Creation
| | |
|---|---|
| `CScrollPanel_Create( hWndParent, CtrlID )` | returns the container `HWND`. Created hidden and zero-sized: place it with `SetWindowPos`. The panel and the bar take `CtrlID + 1` and `CtrlID + 2`. |
| `CScrollPanel_GetPanel( h )` | the page. **Parent your controls to this.** |
| `CScrollPanel_GetScrollBar( h )` | the owned `CVScrollBar`, for anything this API does not expose (e.g. a custom bar painter). |

### Content and scrolling — pixels, in page coordinates
| | |
|---|---|
| `CScrollPanel_SetContentHeight( h, px )` | how tall the page is. Silent; re-clamps the position. |
| `CScrollPanel_GetContentHeight( h )` | |
| `CScrollPanel_AutoSizeContent( h, padding = 0 )` | deepest **visible** child's bottom + padding, pushed through `SetContentHeight`. Returns what it set. Hidden children are skipped, so a collapsed section leaves no empty tail. |
| `CScrollPanel_GetPos( h )` / `SetPos( h, px )` | `SetPos` is silent. |
| `CScrollPanel_ScrollBy( h, dy )` | returns TRUE if it actually moved. |
| `CScrollPanel_EnsureVisible( h, hChild, margin = 0 )` | scrolls the **minimum** distance; a child taller than the viewport is top-aligned. Silent, and it never calls `SetFocus`. |
| `CScrollPanel_GetViewportHeight( h )` / `GetPanelWidth( h )` | |
| `CScrollPanel_Recalc( h )` | force a full layout pass. |

### Appearance
| | |
|---|---|
| `CScrollPanel_SetColors( h, back, fore )` | the page fill **and** the colours handed to your controls through `WM_CTLCOLOR*`. One call themes a page of plain labels and checkboxes. |
| `CScrollPanel_SetScrollBarColors( h, back, fore, forehot )` | |
| `CScrollPanel_SetScrollBarWidth( h, px )` | unscaled; the width of the reserved strip. Default 12. |
| `CScrollPanel_SetLineHeight( h, px )` | unscaled; one "line" for the wheel. Default 20. Set it to your row pitch and a notch moves whole rows. |
| `CScrollPanel_SetFont( h, hFont )` | applied to every existing child. **You keep ownership of the `HFONT`.** |

### Behaviour
| | |
|---|---|
| `CScrollPanel_SetAutoScrollToFocus( h, bEnable )` | ON by default. Focus landing on an off-screen child scrolls it into view — on a focus **change** only, so scrolling the focused control away deliberately does not yank it back. |
| `CScrollPanel_IsThumbVisible( h )` | |
| `CScrollPanel_HandleWheelDelta( h, nDelta )` | route a wheel gesture you received yourself. Pass `cast(short, hiword(wParam))` — the cast is not optional. |
| `CScrollPanel_ShouldShow( bNeeds, bMouse, bFocus )` | the reveal rule, exposed because it is pure. |

### Callbacks
| | |
|---|---|
| `SCP_PaintCallbackSub( p )` | draw the page background. `p->rcClient` is the **whole page**, not the visible slice. Replaces the built-in flat fill entirely. |
| `SCP_MessageCallbackFunc( m ) as boolean` | observe container/panel messages. Return TRUE to suppress default handling, setting `m->lResult` first if the message returns a value. |
| `SCP_LayoutCallbackFunc( hPanel, cxPanel ) as integer` | the viewport resized: re-flow, return the new content height (0 = unchanged). |
| `SCP_ScrollCallbackSub( h, newPos )` | the **user** scrolled. |

`SCP_MESSAGEINFO` carries an `lResult` field, which no other control in the family has.
It is there because the panel is the parent of your controls, so `WM_CTLCOLORSTATIC` /
`BTN` / `EDIT` / `LISTBOX` arrive here and nowhere else — and they answer with an `HBRUSH`,
which a bare "handled" boolean cannot express.

### WM_COMMAND and friends

`WM_COMMAND` / `WM_NOTIFY` / `WM_HSCROLL` / `WM_VSCROLL` from your controls arrive at the
**panel**, since it is their parent. They are offered to your message callback and, if not
claimed, **forwarded to the container's parent** — so an existing page moved onto a
CScrollPanel keeps working with its `WM_COMMAND` handling unchanged.

## Notes on the design

- **No mouse capture anywhere.** The control tracks no press state and owns no drag; the
  scrollbar does, inside its own window, and pays that price already.
- **No `CS_DBLCLKS`.** A double-click on page background has no meaning here, and setting it
  would turn every second rapid click on one of *your* controls into `WM_LBUTTONDBLCLK`.
- **The reveal rule is polled, not tracked.** The cursor can enter the control directly over
  one of your `EDIT` boxes, in which case neither the container nor the panel ever receives
  a `WM_MOUSEMOVE` — there is no message to hang a `TrackMouseEvent` request off. A 100 ms
  cursor test sees it regardless, and carries the focus-change detection with it.
- **The wheel converts units at this boundary.** `SPI_GETWHEELSCROLLLINES` counts *lines*;
  this control's range is *pixels*. One notch = system lines x `LineHeight`.
- **Programmatic setters are silent.** Only user action fires `SCP_ScrollCallback`.

## Demo and verification

`main.bas` builds a settings page of ~30 plain `STATIC` / `BUTTON` / `EDIT` rows in five
sections, longer than the window at any sane size.

```
fbc64.exe -i "C:\dev" main.bas
```

| | |
|---|---|
| `CSCROLLPANEL_SELFTEST=1` | 49 assertions: strip/page geometry, clamping, the reveal truth table, `EnsureVisible` in all four cases, `AutoSizeContent`, wheel arithmetic including sub-notch accumulation, and the focus-into-view scroll driven through the real handler. |
| `CSCROLLPANEL_TRACE=1` | dumps every computed rect on each layout pass. |
