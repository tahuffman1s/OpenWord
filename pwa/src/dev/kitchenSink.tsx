import { render } from 'preact';
import { useState } from 'preact/hooks';
import '../ui/m3/m3.css';
import {
  AlertDialog, AppBar, Button, Card, Checkbox, Chip, ChipRow, DialogAction, Divider, Fab, IconButton, LinearProgress,
  CircularProgress, ListTile, MenuItem, NavigationBar, OutlinedButton, OverlayHost, PopupMenuButton, Radio, Screen, SectionHeader,
  SegmentedButton, Sheet, Slider, Switch, Tabs, TextButton, TextField, TonalButton, applyScheme, schemeFromSeed, showDialog,
  showSheet, showSnackBar, nav, installRipples,
} from '../ui/m3';

function Demo() {
  const [on, setOn] = useState(true);
  const [tab, setTab] = useState('a');
  const [v, setV] = useState(0.4);
  const [text, setText] = useState('');
  const [dark, setDark] = useState(false);
  return (
    <Screen
      appBar={(s) => (
        <AppBar
          scrolled={s}
          leading="none"
          title="Kitchen sink"
          subtitle="Material 3"
          actions={
            <>
              <IconButton icon="search" label="Search" />
              <PopupMenuButton
                label="More"
                items={() => (
                  <>
                    <MenuItem icon="settings" label="Settings" value="s" />
                    <MenuItem icon="delete" label="Delete" value="d" destructive />
                  </>
                )}
                onSelected={(v) => showSnackBar(`chose ${v}`)}
              />
            </>
          }
        />
      )}
      padded
      fab={<Fab icon="add" label="Add" onClick={() => showSnackBar('FAB', { action: { label: 'Undo', onPressed: () => {} } })} />}
      bottom={
        <NavigationBar
          destinations={[
            { value: 'read', label: 'Read', icon: 'auto_stories' },
            { value: 'learn', label: 'Learn', icon: 'school', badge: true },
            { value: 'friends', label: 'Friends', icon: 'group', badge: 3 },
          ]}
          selected={tab === 'a' ? 'read' : 'learn'}
          onSelect={() => {}}
        />
      }
    >
      <SectionHeader>Buttons</SectionHeader>
      <div class="ow-row" style="flex-wrap:wrap">
        <Button icon="add">Filled</Button>
        <TonalButton>Tonal</TonalButton>
        <OutlinedButton>Outlined</OutlinedButton>
        <TextButton>Text</TextButton>
        <Button disabled>Disabled</Button>
        <IconButton icon="favorite" label="Like" variant="tonal" />
        <IconButton icon="bookmark" label="Bookmark" variant="filled" />
      </div>
      <SectionHeader>Controls</SectionHeader>
      <ListTile icon="dark_mode" title="Dark theme" subtitle="Follow the system" trailing={<Switch value={dark} onChange={(d) => { setDark(d); applyScheme(schemeFromSeed(0xff1b6c4f, d ? 'dark' : 'light')); }} />} onClick={() => setDark(!dark)} />
      <ListTile icon="check" title="Checkbox" trailing={<Checkbox value={on} onChange={setOn} />} onClick={() => setOn(!on)} />
      <ListTile title="Radio" trailing={<Radio checked={on} onSelect={() => setOn(true)} />} />
      <Slider value={v} min={0} max={1} onChange={setV} label="Size" />
      <SegmentedButton options={[{ value: 'a', label: 'Canon' }, { value: 'b', label: 'A–Z' }]} selected={tab} onSelect={setTab} />
      <div style="height:12px" />
      <ChipRow>
        <Chip label="Yellow" selected />
        <Chip label="Green" />
        <Chip label="Assist" variant="assist" icon="map" />
        <Chip label="Input" variant="input" onDelete={() => {}} />
      </ChipRow>
      <div style="height:12px" />
      <TextField label="Go to" placeholder="jn 3:16" value={text} onInput={setText} leading={<IconButton icon="search" label="Search" size="small" />} supporting="Type a reference" />
      <SectionHeader>Progress</SectionHeader>
      <LinearProgress value={v} />
      <div style="height:8px" />
      <LinearProgress />
      <div class="ow-row"><CircularProgress /><CircularProgress value={v} /></div>
      <SectionHeader>Cards</SectionHeader>
      <Card variant="primary" onClick={() => showSnackBar('card')}><div class="m3-title-medium">Today's lesson</div><div class="m3-body-medium">3 verses due · a short round</div></Card>
      <div style="height:8px" />
      <Card variant="outlined">Outlined card</Card>
      <Divider />
      <Tabs tabs={[{ value: 'a', label: 'Learn' }, { value: 'b', label: 'Progress' }, { value: 'c', label: 'Saved' }]} selected={tab} onSelect={setTab} />
      <SectionHeader>Overlays</SectionHeader>
      <div class="ow-row" style="flex-wrap:wrap">
        <Button onClick={() => showSheet(<Sheet title="A sheet" padded><p>Hello from a bottom sheet.</p>{Array.from({ length: 30 }, (_, i) => <ListTile key={i} title={`Row ${i}`} onClick={() => nav.pop()} />)}</Sheet>)}>Sheet</Button>
        <Button onClick={() => showSheet(<Sheet title="Full sheet" padded><p>Full height.</p></Sheet>, { full: true })}>Full sheet</Button>
        <Button onClick={async () => { const r = await showDialog<boolean>(<AlertDialog icon="delete" title="Delete everything?" actions={<><DialogAction result={false}>Cancel</DialogAction><DialogAction result={true} destructive>Delete</DialogAction></>}>This cannot be undone.</AlertDialog>); showSnackBar(`dialog: ${r}`); }}>Dialog</Button>
        <Button onClick={() => nav.push(<Screen appBar={(s) => <AppBar scrolled={s} title="Pushed screen" />} padded>{Array.from({ length: 60 }, (_, i) => <p key={i}>Line {i}</p>)}</Screen>)}>Push screen</Button>
      </div>
      {Array.from({ length: 10 }, (_, i) => <p key={i}>Scroll filler {i}</p>)}
    </Screen>
  );
}

applyScheme(schemeFromSeed(0xff1b6c4f, 'light'));
installRipples();
render(
  <>
    <Demo />
    <OverlayHost />
  </>,
  document.getElementById('app')!,
);
