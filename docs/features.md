# Everything OpenWord does

[← Back to the README](../README.md)

The whole list, in detail. The web app and the native builds share all of it unless a line says otherwise; accounts and friends are the web app's alone, and Android Auto is the native Android build's.

- **Printed-Bible layout.** The text is built from USFX, so the translation's
  own structure survives: prose paragraphs that verses flow through, poetry
  indented by level, psalm titles, section headings and their parallel-passage
  references, stanza breaks, the words of Jesus in red, translator additions in
  italics and tappable footnotes. Verse numbers are superscripts, and hang in
  the margin on poetry lines so wrapped lines keep their indent.
- **Go to anything in one field.** Type `jn 3:16`, `1 co 13`, `ps 23` or just
  `mat` and the navigator offers the jump; the same field filters the book
  list, which is grouped by division or sorted A–Z, and leads on to chapter
  and verse grids.
- **Compare two translations** verse by verse, in columns on a wide window and
  stacked on a phone. The second translation is loaded only while you are
  comparing.
- **Highlights in five colours, bookmarks and notes**, any combination on the
  same verse. Highlights tint the text in place; bookmarked and annotated
  verses are flagged in the margin and in the pickers.
- **Updates from GitHub.** OpenWord asks GitHub once a day whether a newer
  release is out, shows what is in it, and on Android downloads and hands it
  to the system installer. It is the only thing here that uses the network,
  and Settings can turn it off.
- **Maps of the places a chapter names**, drawn from open data and bundled
  with the app. Drag, pinch, scroll or double-tap to move about; tap a place
  for what the data knows about it and for the verses of the chapter that name
  it. Locations scholars dispute are marked as such.
- **Context where the translation offers it.** Citations in footnotes and in
  parallel-passage lines are links — tap `Ezekiel 34:11` under the heading of
  Psalm 23 and you are there. Every book also opens an introduction from its
  name above the chapter number — canon division, length, and a full essay on
  the book's setting, authorship, structure and themes.
- **Bring your own translation.** Import an EPUB of a Bible and OpenWord
  converts it to a `.bib` file — its own single-file format — and reads it
  like the ones that ship with it: search, compare, highlight, bookmark, map
  and all. `.bib` files import directly, and any imported translation can be
  saved back out as one.
- **The Hebrew and Greek behind any verse.** Tap a verse and it offers the
  original: every word with its Strong's number, how it is said, and its
  parsing spelled out. Tap a word for Strong's own entry, and from there
  every other verse it occurs in. Tap an English word and the word it most
  likely came from lights up. It works under *any* translation — the three
  that ship and any you import — because it is keyed to the verse, not to
  one edition's wording.
- **Cross-references on every verse.** Tap a verse and it offers the places
  Scripture takes up what it says — three hundred thousand of them, from the
  Treasury of Scripture Knowledge, grouped under the phrase that prompted
  each one and carrying the words they point at, so the list reads without
  leaving it. Tap one to go there. Bundled, like everything else.
- **Read aloud.** *Listen* beside the chapter's name reads it in a
  natural voice that runs on the device — nothing leaves it — with
  the verse being read tinted and kept in view and the page turning as it
  goes on. A verse's sheet offers *Listen from here*. The bar along the
  bottom pauses, steps a verse back or on, and sets the speed and the voice.
  Where listening got to is kept, down to the word, so the chapter's
  *Listen* becomes *Resume* and carries on there even after the app has
  been closed. Started from a reading plan it reads the rest of that day and
  stops, and a plan chapter heard to its end is ticked off. It goes on with
  the screen off: the lock screen, a headset and a car pause it and step it
  verse by verse. **Android Auto** lists it as a media app: *Continue
  listening*, today's plan reading, recent chapters and every book and
  chapter, playable from the car's screen or by asking for "Psalm 23", with
  no screen of the app open. The voice is [KittenTTS](https://github.com/KittenML/KittenTTS),
  an open neural model with eight speakers, bundled with the app and run
  with [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx); it speaks
  English. In the browser the same model runs through ONNX Runtime's
  WebAssembly build; Android Auto is the native Android build's alone.
- **Select several verses and share them.** Hold a verse, then tap others
  to add them; a bar along the bottom cites the selection the way a printed
  Bible would — *John 3:16–18, 20* — and copies it, shares it, highlights it
  all at once, or makes a picture of it. The picture is a 1080 × 1350 card in
  one of four styles, with the words, the reference and the translation,
  shared through the system share sheet (saved as a file on Linux, which has
  none). A single verse's sheet shares it in one tap too.
- **Guess before you read.** A plan chapter not yet read offers two of its
  verses to finish before reading, and the same two after, since guessing
  at what is about to be read makes it stick.
- **Reading plans that wait for you.** Six plans, from the Gospels in 30
  days to the whole Bible in a year, with the Old and New Testament side by
  side or Psalms and Proverbs by the month. Days are even in length rather
  than in chapters, and are numbered rather than dated, so a plan starts
  whenever you start it and a missed day is still there tomorrow instead of
  piling up. The end of each chapter in today's reading has one button:
  *Done — next: Matthew 2*. Fall two days behind and the plan says so once,
  kindly, with *Pick up from today*; it never marks anything read for you.
- **Learn a verse by heart.** *Memorise* on a verse's sheet puts it on a
  ladder: it is asked for today, and then each time you have it the wait
  grows — a day, two, five, twelve, a month, two, five, up to a year —
  timed so that it comes round when your chance of recalling it has
  fallen to nine in ten, by a model of memory that learns how long you,
  in particular, keep a verse; a miss drops it to the bottom and marks it
  harder. A verse is met before it is built: where it sits, the words,
  and a word of your own for what it is about, which is the cue given
  when it is asked for bare. A long verse is built up a clause at a
  time, each step rehearsing the last. New verses are timed against sleep,
  since a night's sleep soon after learning helps a memory settle: some
  are learnt in the evening and asked for next morning, some by day and
  asked for hours later, and the app reports which you recall better.
  Answering from memory begins with how sure you are, so a confident miss
  can be caught and corrected. The library's *Learn* tab practises what
  is due, and each practice is an exercise the rung calls for, checked: a
  new verse is put together from tiles with the text in view, then its
  blanks are filled, then it is put together unseen — heard first, in the
  app's own voice — and then written out, a slip of a letter forgiven. A
  wrong answer drops the verse to the bottom and asks it again before the
  session ends, and a session asks the surest verses first. The voice
  runs through it all, as in a language app: the
  verse read as it appears, each tile heard as it is tapped, the verse
  read whole once checked, and a button to hear it slowly; a switch turns
  the automatic reading off. Days in a row with learning done make a
  streak, shown as a flame, and every seventh day earns a freeze that
  forgives a missed one. Right answers earn points, with bonuses for runs
  of them and for perfect rounds; points make levels and a daily goal of
  your choosing, and twelve badges mark the milestones. A dot on the
  library button says something is due.
- **Test yourself.** Rounds of ten questions drawn from the translation you
  are reading, never the same round twice: *Which book?* shows a verse and
  asks where it is from; *Finish the verse* shows the first half and asks
  how it goes on; *Books in order* asks which book comes before or after
  another; or a bit of everything. A wrong answer shows the right one, and
  every answer, and every question missed, is a tap from its passage.
- **Your library, learning first.** It opens on today's lesson — the verses
  due and a short round, one button — with the verses you are learning
  beneath it and suggestions worth knowing by heart when there are none.
  *Progress* holds the level, the week and the badges; *Saved* holds
  bookmarks, highlights, notes and the chapters you have been reading, each
  a tap away from the text.
- **Search** the whole Bible, one testament or the book you are in, with an
  optional whole-word match, results grouped by book and the match emphasised
  in context.
- **Resume where you left off.** The book, chapter and the verse nearest the
  top of the screen are saved as you read and restored on the next launch.
- **Backup without an account.** Copy everything you have saved as JSON to the
  clipboard and paste it back on another device; restoring merges rather than
  overwrites.
- **Material You.** The palette follows the system wallpaper where the platform
  provides one, with a seed-colour picker everywhere else. Light, dark and
  system themes; adjustable text size, line spacing and typeface, reachable
  from the reader itself.
