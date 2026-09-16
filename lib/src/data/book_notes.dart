/// Short editorial notes for the books the bundled introductions do not
/// cover.
///
/// The sixty-six books of the Protestant canon use the Aquifer Open Study
/// Notes introductions (see [BookIntros]); these notes fill the gap for the
/// deuterocanonical books, which that resource does not include. They are
/// written for this app and are deliberately cautious: where a book is
/// anonymous the note says so, traditional authorship is labelled as
/// tradition, and the "setting" is the period a book is *about*, which is far
/// less contested than when it was written.
library;

class BookNote {
  const BookNote({
    required this.genre,
    required this.attribution,
    required this.setting,
    required this.summary,
  });

  /// What kind of writing it is: narrative, law, poetry, prophecy and so on.
  final String genre;

  /// Who it is ascribed to, and by whom.
  final String attribution;

  /// The period the book is set in.
  final String setting;

  final String summary;
}

/// Notes keyed by book code. Every book in the bundled editions has one.
const Map<String, BookNote> bookNotes = {
  'TOB': BookNote(
    genre: 'Narrative',
    attribution: 'Anonymous',
    setting: 'The Assyrian exile, in Nineveh and Ecbatana',
    summary:
        'A blinded, charitable exile and a young woman freed from a demon are '
        'brought together by the angel Raphael travelling in disguise.',
  ),
  'JDT': BookNote(
    genre: 'Narrative',
    attribution: 'Anonymous',
    setting: 'A deliberately unhistorical siege of a Judaean town',
    summary:
        'A widow talks her way into an enemy camp and returns with the '
        'general’s head, saving her people.',
  ),
  'ESG': BookNote(
    genre: 'Narrative',
    attribution: 'Anonymous',
    setting: 'The Persian court, as in Esther',
    summary:
        'The Greek Esther, with additions that supply the prayers, the decree '
        'texts and the explicit mention of God that the Hebrew leaves out.',
  ),
  'WIS': BookNote(
    genre: 'Wisdom',
    attribution: 'Written in Solomon’s voice',
    setting: 'Greek-speaking Judaism, most likely Alexandria',
    summary:
        'Wisdom personified, an argument for immortality of the righteous, '
        'and a long retelling of the exodus.',
  ),
  'SIR': BookNote(
    genre: 'Wisdom',
    attribution:
        'Jesus ben Sira, who names himself; his grandson translated it',
    setting: 'Jerusalem, before the Maccabean crisis',
    summary:
        'A teacher’s collected instruction on friendship, speech, money and '
        'the fear of the Lord, closing with a praise of famous men.',
  ),
  'BAR': BookNote(
    genre: 'Mixed: prayer, poetry, prophecy',
    attribution: 'Ascribed to Baruch, Jeremiah’s scribe',
    setting: 'Presented as written in Babylon',
    summary:
        'A confession for the exiles, a poem on wisdom found in the law, and '
        'a promise of return.',
  ),
  'LJE': BookNote(
    genre: 'Polemic letter',
    attribution: 'Presented as a letter of Jeremiah',
    setting: 'Addressed to exiles going to Babylon',
    summary:
        'A sustained argument that idols are carpentry: they cannot save '
        'themselves, let alone anyone else.',
  ),
  'S3Y': BookNote(
    genre: 'Prayer and hymn',
    attribution: 'Anonymous addition to Daniel',
    setting: 'Inside the fiery furnace',
    summary:
        'Azariah’s prayer and the hymn of the three young men, calling on all '
        'creation to bless the Lord.',
  ),
  'SUS': BookNote(
    genre: 'Narrative',
    attribution: 'Anonymous addition to Daniel',
    setting: 'The Jewish community in Babylon',
    summary:
        'Two elders blackmail and then falsely accuse Susanna; a young Daniel '
        'cross-examines them separately and their story falls apart.',
  ),
  'BEL': BookNote(
    genre: 'Narrative',
    attribution: 'Anonymous addition to Daniel',
    setting: 'The Babylonian court',
    summary:
        'Two detective stories against idolatry: ash on the temple floor '
        'exposes the priests of Bel, and the dragon is fed a fatal recipe.',
  ),
  '1MA': BookNote(
    genre: 'History',
    attribution: 'Anonymous',
    setting: 'Judaea under the Seleucids, second century BC',
    summary:
        'The desecration of the temple, the revolt led by Mattathias and his '
        'sons, and the rise of the Hasmonean house; the background to '
        'Hanukkah.',
  ),
  '2MA': BookNote(
    genre: 'History',
    attribution: 'An abridgement of a five-volume work by Jason of Cyrene',
    setting: 'The same revolt, told differently',
    summary:
        'A shorter span than 1 Maccabees and a more heated telling, including '
        'the martyrdoms that made the resistance famous.',
  ),
  '3MA': BookNote(
    genre: 'Narrative',
    attribution: 'Anonymous',
    setting: 'Egypt under Ptolemy IV',
    summary:
        'Despite the name, not about the Maccabees: Egyptian Jews are '
        'condemned to die in the hippodrome and are delivered.',
  ),
  '4MA': BookNote(
    genre: 'Philosophical discourse',
    attribution: 'Anonymous',
    setting: 'Greek-speaking Judaism',
    summary:
        'An argument that devout reason masters the passions, illustrated at '
        'length by the martyrs of the Maccabean persecution.',
  ),
  '1ES': BookNote(
    genre: 'History',
    attribution: 'Anonymous',
    setting: 'From Josiah’s passover to Ezra’s reading of the law',
    summary:
        'A Greek retelling that overlaps Chronicles, Ezra and Nehemiah, with '
        'the debate of the three guardsmen found nowhere else.',
  ),
  '2ES': BookNote(
    genre: 'Apocalyptic vision',
    attribution: 'Ascribed to Ezra',
    setting: 'Presented as after the fall of Jerusalem',
    summary:
        'Seven visions wrestling with why God allows the wicked to prosper, '
        'framed by later Christian additions.',
  ),
  'MAN': BookNote(
    genre: 'Prayer',
    attribution: 'Ascribed to King Manasseh',
    setting: 'Manasseh’s captivity, as told in 2 Chronicles',
    summary:
        'Fifteen verses of penitence from the worst-remembered king of Judah, '
        'long used as a model confession.',
  ),
  'PS2': BookNote(
    genre: 'Psalm',
    attribution: 'Ascribed to David',
    setting: 'After the fight with Goliath',
    summary:
        'A short psalm, numbered 151, in which David remembers being the '
        'youngest, keeping the sheep, and being chosen anyway.',
  ),
};
