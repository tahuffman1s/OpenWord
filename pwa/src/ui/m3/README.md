# The Material 3 kit (`src/ui/m3`)

Flutter's Material widgets, as Preact components styled by `m3.css` with
the colour roles `theme.ts` writes to `<html>` (`--md-sys-color-*`). Import
everything from `'../m3'` (or `'./m3'` from `src/ui`).

| Flutter                              | Here                                                        |
|--------------------------------------|-------------------------------------------------------------|
| `Scaffold`                           | `<Screen appBar={…} bottom={…} fab={…} padded>`             |
| `AppBar`                             | `<AppBar title leading="back|close|none" actions scrolled>` — use `appBar={(scrolled) => <AppBar scrolled={scrolled} …/>}` on `Screen` |
| `FilledButton`, `FilledButton.tonal`, `OutlinedButton`, `TextButton`, `ElevatedButton` | `<Button variant="filled|tonal|outlined|text|elevated" icon="add">` or `FilledButton`, `TonalButton`, `OutlinedButton`, `TextButton` |
| `IconButton`                         | `<IconButton icon="close" label="Close" variant="filled|tonal|outlined" selected size="small|large">` — `label` is required |
| `FloatingActionButton(.extended)`    | `<Fab icon label color="primary|tertiary|surface" size="small">` |
| `Icon(Icons.foo_rounded)`            | `<Icon name="foo" size={20}>`; `Icons.foo_outlined` → `name="foo_outlined"`; `Icons.foo` (filled) → `name="foo_filled"`. Add missing icons to `icons.txt` and run `npm run icons`. |
| `ListTile`                           | `<ListTile icon leading title subtitle trailing selected dense threeLine onClick>` |
| `Divider`                            | `<Divider inset>`                                           |
| Section header text                  | `<SectionHeader>`                                           |
| `Switch`, `Checkbox`, `Radio`        | `<Switch value onChange>`, `<Checkbox value onChange>`, `<Radio checked onSelect>` |
| `SwitchListTile`                     | `<ListTile title subtitle trailing={<Switch …/>} onClick={toggle}>` |
| `Slider`                             | `<Slider value min max step onChange onChangeEnd>`          |
| `SegmentedButton`                    | `<SegmentedButton options selected onSelect>`               |
| `FilterChip`, `ChoiceChip`, `ActionChip`, `InputChip` | `<Chip label icon selected variant="filter|choice|assist|input|elevated" onDelete>` in a `<ChipRow scroll>` |
| `TextField`                          | `<TextField value onInput onSubmit label placeholder supporting error leading trailing multiline autoFocus>` |
| `TabBar`                             | `<Tabs tabs selected onSelect scroll>`                      |
| `NavigationBar`                      | `<NavigationBar destinations selected onSelect>`            |
| `LinearProgressIndicator`, `CircularProgressIndicator` | `<LinearProgress value?>`, `<CircularProgress value? size>` |
| `Card`                               | `<Card variant="low|filled|outlined|elevated|primary|secondary|tertiary" onClick>` |
| `Navigator.push(MaterialPageRoute(...))` | `await nav.push(<FooScreen …/>)`; `nav.pop(result)`; `nav.canPop` |
| `showModalBottomSheet`               | `const r = await showSheet<T>(<FooSheet …/>, { full?, dismissible? })`; inside, `<Sheet title>…</Sheet>` (handle + scrolling body) and `useOverlay().close(result)` |
| `showDialog` + `AlertDialog`         | `await showDialog<T>(<AlertDialog icon title actions={<><DialogAction result={false}>Cancel</DialogAction><DialogAction result>OK</DialogAction></>}>body</AlertDialog>)`; shortcuts `confirm({title, body, confirmLabel, destructive})` → boolean, `alert(title, body)` |
| `PopupMenuButton`                    | `<PopupMenuButton items={() => <><MenuItem icon label value/>…</>} onSelected>`; or `showMenu(<>…</>, anchorElement)` |
| `ScaffoldMessenger.showSnackBar`     | `showSnackBar('text', { action: { label, onPressed }, duration })` |
| `Theme.of(context).colorScheme.x`    | CSS `var(--md-sys-color-x-in-kebab-case)`; in JS `currentScheme().x` (ARGB) + `hexOf()` |
| `AppTheme.redLetter / highlights`    | `redLetter(brightness)`, `highlights(brightness)`, `highlightSwatch(i)`, `highlightNames` from `theme.ts` |
| `textTheme.titleMedium` etc.         | classes `m3-title-medium`, `m3-body-large`, `m3-label-small`… |
| `MediaQuery.of(context).size.width`  | CSS media queries; `useMediaQuery('(min-width: 840px)')` from `src/ui/hooks.ts` |

Rules of thumb:
- Every tappable thing gets the `m3-interactive` class (the kit's components
  already have it) so it ripples and shows hover/press state layers.
- Colours only through the `--md-sys-color-*` variables, so the seed
  colour and dark mode apply everywhere. Never hard-code a grey.
- Screens pushed with `nav.push` render inside a `.m3-screen` already; return
  a `<Screen>` from your component.
- Each screen/sheet/dialog is a history entry: the back button closes it.
- Layout: phones first; `max-width` containers (`.ow-content` = 720px) for
  readable text on wide windows; `ow-row`, `ow-col`, `ow-spacer` helpers.
