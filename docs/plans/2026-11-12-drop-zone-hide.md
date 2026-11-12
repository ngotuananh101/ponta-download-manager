# Plan: drop zone hides instead of squeezing short rows — 2026-11-12

## Report
With a short body (e.g. the 264px details panel open at the 650px
window) and a few rows, the drop zone sat at exactly its 120px
minimum while the rows were capped to make room for it (2 rows of
40px capped at 74px). It looked like a thin strip, and the user
asked why it does not hide itself.

## Rule (in `_buildTable`, `downloads_screen.dart`)
Let `bodyAfterHeader = available - 32` and
`rowsNatural = visible.length * 40`.
- Show the zone when the rows fit fully with 120px left over
  (`rowsNatural + 120 <= bodyAfterHeader`): rows full, zone takes
  the rest.
- Show the zone when the rows overflow the body on their own
  (`rowsNatural > bodyAfterHeader`): rows capped at
  `bodyAfterHeader - 120`, zone 120px, table scrolls (as before).
- Otherwise hide the zone: rows take `bodyAfterHeader` at full
  height. Dropping still works anywhere in the body (the DropTarget
  wraps the whole body); only the visual hint goes away.
- Unchanged: the zone hides when `bodyAfterHeader < 120`, and the
  empty state (no downloads at all) shows the zone full-body.

## Test
`test/widget_test.dart`: 'the drop zone hides instead of squeezing
short rows' — 2 rows in a 346px window (body leaves 194px under the
header, so only 114px would remain for the zone): the zone is gone
and the ListView is 80px tall. Written RED first, it failed on the
old code with the zone found.

## Verify
- Full desktop suite, `flutter analyze` clean,
  `flutter build linux --release`.

## Status: DONE 2026-11-12 (commit + push pending at plan time)
