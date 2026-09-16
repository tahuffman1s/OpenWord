/// Short editorial notes giving each book some historical footing.
///
/// These are a summary, not a commentary, and they are deliberately cautious:
/// where a book is anonymous the note says so, traditional authorship is
/// labelled as tradition rather than fact, and the "setting" is the period a
/// book is *about*, which is far less contested than when it was written.
/// Readers who want dates and authorship argued out should reach for a study
/// Bible; this is here so that opening Habakkuk tells you something.
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
  'GEN': BookNote(
    genre: 'Narrative and law',
    attribution: 'Anonymous; traditionally ascribed to Moses',
    setting: 'From the creation to Israel’s descent into Egypt',
    summary:
        'Origins: of the world, of the nations, and of one family through '
        'whom the rest of the story runs — Abraham, Isaac, Jacob and Joseph.',
  ),
  'EXO': BookNote(
    genre: 'Narrative and law',
    attribution: 'Anonymous; traditionally ascribed to Moses',
    setting: 'Israel in Egypt, the escape, and the first year at Sinai',
    summary:
        'A people enslaved is brought out by a series of plagues and a sea '
        'crossing, given the covenant and the Ten Commandments at Sinai, and '
        'told how to build the tabernacle.',
  ),
  'LEV': BookNote(
    genre: 'Law',
    attribution: 'Anonymous; traditionally ascribed to Moses',
    setting: 'Israel encamped at Sinai',
    summary:
        'Instructions for sacrifice, priesthood, purity and festival, built '
        'around the idea that a holy God can be lived with on set terms.',
  ),
  'NUM': BookNote(
    genre: 'Narrative and law',
    attribution: 'Anonymous; traditionally ascribed to Moses',
    setting: 'The wilderness, from Sinai to the plains of Moab',
    summary:
        'Two censuses frame a generation that refuses to enter the land and '
        'dies in the desert, while its children are prepared to go in.',
  ),
  'DEU': BookNote(
    genre: 'Law and speeches',
    attribution: 'Anonymous; traditionally ascribed to Moses',
    setting: 'The plains of Moab, on the edge of Canaan',
    summary:
        'Moses restates the covenant for the next generation in a series of '
        'farewell addresses, then dies within sight of the land.',
  ),
  'JOS': BookNote(
    genre: 'Narrative',
    attribution: 'Anonymous; traditionally ascribed to Joshua',
    setting: 'The entry into Canaan',
    summary:
        'Israel crosses the Jordan, takes territory, and divides it among the '
        'tribes; the book closes with a covenant renewal at Shechem.',
  ),
  'JDG': BookNote(
    genre: 'Narrative',
    attribution: 'Anonymous; traditionally ascribed to Samuel',
    setting: 'Between the settlement and the monarchy',
    summary:
        'A repeating cycle — the people turn away, an enemy oppresses them, a '
        'judge delivers them — running downhill towards the book’s refrain '
        'that everyone did what was right in his own eyes.',
  ),
  'RUT': BookNote(
    genre: 'Narrative',
    attribution: 'Anonymous',
    setting: 'The days of the judges',
    summary:
        'A Moabite widow stays with her Israelite mother-in-law and is '
        'redeemed by Boaz; the genealogy at the end makes her David’s '
        'great-grandmother.',
  ),
  '1SA': BookNote(
    genre: 'Narrative',
    attribution: 'Anonymous',
    setting: 'The end of the judges and the first king',
    summary:
        'Samuel anoints Saul and then David; Saul’s reign unravels while '
        'David, still a fugitive, gathers a following.',
  ),
  '2SA': BookNote(
    genre: 'Narrative',
    attribution: 'Anonymous',
    setting: 'David’s reign in Hebron and Jerusalem',
    summary:
        'David unites the kingdom and is promised a lasting house, then the '
        'Bathsheba affair sets off rebellion and grief inside his own family.',
  ),
  '1KI': BookNote(
    genre: 'Narrative',
    attribution: 'Anonymous',
    setting: 'Solomon to the divided kingdom',
    summary:
        'Solomon builds the temple and the kingdom splits after him; Elijah '
        'confronts Ahab and the prophets of Baal.',
  ),
  '2KI': BookNote(
    genre: 'Narrative',
    attribution: 'Anonymous',
    setting: 'The two kingdoms down to the exile',
    summary:
        'Elisha succeeds Elijah; Assyria takes Samaria and Babylon takes '
        'Jerusalem, each fall read as the outcome of the kings’ choices.',
  ),
  '1CH': BookNote(
    genre: 'Narrative and genealogy',
    attribution: 'Anonymous; traditionally ascribed to Ezra',
    setting: 'From Adam to the death of David, retold after the exile',
    summary:
        'Nine chapters of genealogy place the returned community in a long '
        'line, then David is presented above all as the one who prepares for '
        'the temple.',
  ),
  '2CH': BookNote(
    genre: 'Narrative',
    attribution: 'Anonymous; traditionally ascribed to Ezra',
    setting: 'Solomon to the exile and the edict to return',
    summary:
        'The same period as Kings told from Jerusalem and the temple, with '
        'attention to the reforming kings and to worship kept or neglected.',
  ),
  'EZR': BookNote(
    genre: 'Narrative',
    attribution: 'Anonymous; traditionally ascribed to Ezra',
    setting: 'The Persian period, after the return from Babylon',
    summary:
        'Exiles return in stages, rebuild the altar and the temple against '
        'opposition, and Ezra arrives to teach the law.',
  ),
  'NEH': BookNote(
    genre: 'Narrative and memoir',
    attribution: 'Largely first-person, ascribed to Nehemiah',
    setting: 'Jerusalem under Persian rule',
    summary:
        'A cupbearer to the Persian king returns to rebuild the city wall in '
        'fifty-two days, then works on the community behind it.',
  ),
  'EST': BookNote(
    genre: 'Narrative',
    attribution: 'Anonymous',
    setting: 'The Persian court of Ahasuerus (Xerxes)',
    summary:
        'A Jewish queen risks her life to overturn a decree against her '
        'people; the festival of Purim keeps the deliverance. God is never '
        'named in the Hebrew text.',
  ),
  'JOB': BookNote(
    genre: 'Wisdom, mostly in poetry',
    attribution: 'Anonymous',
    setting: 'Patriarchal in feel, and deliberately placeless',
    summary:
        'An upright man loses everything and argues with three friends who '
        'insist he must deserve it; God answers out of the whirlwind without '
        'explaining.',
  ),
  'PSA': BookNote(
    genre: 'Poetry and song',
    attribution:
        'A collection; many psalms carry David’s name, others '
        'Asaph’s, Korah’s and more',
    setting: 'Gathered over centuries of Israel’s worship',
    summary:
        'A hundred and fifty songs of praise, lament, thanksgiving and '
        'complaint, arranged in five books, each closing with a doxology.',
  ),
  'PRO': BookNote(
    genre: 'Wisdom',
    attribution: 'Largely ascribed to Solomon, with named later collections',
    setting: 'The royal court and the household',
    summary:
        'Short sayings on speech, work, money, friendship and folly, opening '
        'with longer poems in which wisdom calls out in the street.',
  ),
  'ECC': BookNote(
    genre: 'Wisdom',
    attribution: 'The Preacher, Qoheleth; traditionally Solomon',
    setting: 'A life of means and leisure, looked back on',
    summary:
        'Everything under the sun is vapour: the Preacher tests pleasure, '
        'work and wisdom, finds them fleeting, and lands on eating, drinking '
        'and fearing God.',
  ),
  'SNG': BookNote(
    genre: 'Love poetry',
    attribution: 'Ascribed to Solomon',
    setting: 'Gardens, vineyards and the city at night',
    summary:
        'Two lovers speak to and about each other, with a chorus of women of '
        'Jerusalem; read as both a celebration of love and, in long '
        'tradition, an allegory.',
  ),
  'ISA': BookNote(
    genre: 'Prophecy',
    attribution: 'Isaiah of Jerusalem; the later chapters address the exile',
    setting: 'Judah under Assyrian threat, and beyond it the exile and return',
    summary:
        'Judgment on Judah and the nations gives way to comfort, the servant '
        'songs, and a promise of new heavens and a new earth.',
  ),
  'JER': BookNote(
    genre: 'Prophecy and narrative',
    attribution: 'Jeremiah, with his scribe Baruch',
    setting: 'Jerusalem’s last decades and its fall',
    summary:
        'Forty years of warnings nobody wants, the cost of delivering them, '
        'and in the middle of it the promise of a new covenant written on the '
        'heart.',
  ),
  'LAM': BookNote(
    genre: 'Poetry, funeral laments',
    attribution: 'Anonymous; traditionally ascribed to Jeremiah',
    setting: 'Jerusalem after its destruction',
    summary:
        'Five poems, four of them acrostics, over a ruined city; the hinge is '
        'the third, where mercies are new every morning.',
  ),
  'EZK': BookNote(
    genre: 'Prophecy and vision',
    attribution: 'Ezekiel, a priest among the exiles',
    setting: 'Babylonia, before and after Jerusalem falls',
    summary:
        'Visions of God’s glory leaving the temple and returning to it, '
        'enacted signs, the valley of dry bones, and a measured plan for a '
        'restored temple.',
  ),
  'DAN': BookNote(
    genre: 'Court narrative and apocalyptic vision',
    attribution: 'Ascribed to Daniel; the book is partly in Aramaic',
    setting: 'The Babylonian and Persian courts',
    summary:
        'Six stories of faithfulness under pressure — the furnace, the lions '
        '— followed by visions of empires rising and falling and a kingdom '
        'that will not.',
  ),
  'HOS': BookNote(
    genre: 'Prophecy',
    attribution: 'Hosea',
    setting: 'The northern kingdom before its fall',
    summary:
        'A marriage to an unfaithful wife becomes the image for a people who '
        'have left their God, and for a love that will not let them go.',
  ),
  'JOL': BookNote(
    genre: 'Prophecy',
    attribution: 'Joel',
    setting: 'Judah, after a locust plague',
    summary:
        'A devastated harvest becomes a warning of the day of the Lord, and '
        'the promise that God will pour out his Spirit on all flesh.',
  ),
  'AMO': BookNote(
    genre: 'Prophecy',
    attribution: 'Amos, a herdsman from Tekoa',
    setting: 'The prosperous northern kingdom',
    summary:
        'Judgment on the surrounding nations circles round to Israel itself: '
        'worship without justice is refused, and justice is to roll down like '
        'waters.',
  ),
  'OBA': BookNote(
    genre: 'Prophecy',
    attribution: 'Obadiah',
    setting: 'Edom, after Jerusalem’s fall',
    summary:
        'The shortest book in the Old Testament: a single oracle against Edom '
        'for standing by, and worse, while Jerusalem was sacked.',
  ),
  'JON': BookNote(
    genre: 'Narrative',
    attribution: 'Anonymous; about the prophet Jonah',
    setting: 'Israel and Assyrian Nineveh',
    summary:
        'A prophet runs from a commission to a city he would rather see '
        'destroyed, and is angrier at mercy than at the storm.',
  ),
  'MIC': BookNote(
    genre: 'Prophecy',
    attribution: 'Micah of Moresheth',
    setting: 'Judah and Samaria under Assyrian pressure',
    summary:
        'Judgment on those who dispossess the poor, a ruler promised from '
        'Bethlehem, and the summary line: do justly, love mercy, walk humbly.',
  ),
  'NAM': BookNote(
    genre: 'Prophecy',
    attribution: 'Nahum of Elkosh',
    setting: 'Nineveh, near the end of Assyria',
    summary:
        'The city spared in Jonah’s day is now told its end has come; a poem '
        'about the fall of an empire built on cruelty.',
  ),
  'HAB': BookNote(
    genre: 'Prophecy and dialogue',
    attribution: 'Habakkuk',
    setting: 'Judah, as Babylon rises',
    summary:
        'The prophet complains to God about violence, is told the answer is '
        'Babylon, complains harder — and ends in a psalm of trust without '
        'having got an explanation.',
  ),
  'ZEP': BookNote(
    genre: 'Prophecy',
    attribution: 'Zephaniah',
    setting: 'Judah under Josiah',
    summary:
        'A sweeping day of the Lord against Judah and the nations, closing '
        'with a remnant gathered and God singing over his people.',
  ),
  'HAG': BookNote(
    genre: 'Prophecy',
    attribution: 'Haggai',
    setting: 'Jerusalem, early in the Persian period',
    summary:
        'Four dated messages urging returned exiles to stop panelling their '
        'own houses and finish the temple.',
  ),
  'ZEC': BookNote(
    genre: 'Prophecy and vision',
    attribution: 'Zechariah',
    setting: 'Jerusalem, alongside Haggai',
    summary:
        'Night visions and later oracles about a rebuilt temple, a cleansed '
        'priesthood and a king coming humble and riding on a donkey.',
  ),
  'MAL': BookNote(
    genre: 'Prophecy',
    attribution: 'Malachi',
    setting: 'The Persian period, temple standing again',
    summary:
        'A dispute in six rounds over half-hearted offerings, faithless '
        'marriages and withheld tithes, ending with a messenger still to '
        'come.',
  ),
  'MAT': BookNote(
    genre: 'Gospel',
    attribution: 'Anonymous; attributed early to Matthew',
    setting: 'Judaea and Galilee under Roman rule',
    summary:
        'Jesus presented as the promised Messiah of Israel, with five blocks '
        'of teaching including the Sermon on the Mount, and a closing '
        'commission to all nations.',
  ),
  'MRK': BookNote(
    genre: 'Gospel',
    attribution: 'Anonymous; attributed early to Mark',
    setting: 'Galilee to Jerusalem',
    summary:
        'The shortest and fastest gospel, driving towards the cross; the '
        'question of who Jesus is stays open until a centurion answers it.',
  ),
  'LUK': BookNote(
    genre: 'Gospel',
    attribution: 'Anonymous; attributed early to Luke, addressed to Theophilus',
    setting: 'The Roman world, with dates and officials named',
    summary:
        'An orderly account with an eye for outsiders — shepherds, Samaritans, '
        'women, the poor — and the parables of the prodigal son and the good '
        'Samaritan.',
  ),
  'JHN': BookNote(
    genre: 'Gospel',
    attribution: 'Anonymous; attributed to the disciple whom Jesus loved',
    setting: 'Mostly Jerusalem and its feasts',
    summary:
        'Seven signs and seven "I am" sayings, long discourses in place of '
        'parables, and a stated purpose: that you may believe and have life.',
  ),
  'ACT': BookNote(
    genre: 'Narrative',
    attribution: 'The second volume to Luke, same author and addressee',
    setting: 'Jerusalem to Rome, roughly the first thirty years',
    summary:
        'Pentecost, the spread of the church beyond Judaism, and Paul’s '
        'journeys, ending with him preaching in Rome under guard.',
  ),
  'ROM': BookNote(
    genre: 'Letter',
    attribution: 'Paul, dictated to Tertius',
    setting: 'Written to a church in Rome he had not yet visited',
    summary:
        'The most systematic of Paul’s letters: sin, justification by faith, '
        'life in the Spirit, the place of Israel, and what it all means for '
        'how a mixed congregation lives.',
  ),
  '1CO': BookNote(
    genre: 'Letter',
    attribution: 'Paul',
    setting: 'A divided church in a wealthy port city',
    summary:
        'Answers to a congregation’s quarrels and questions — factions, '
        'lawsuits, marriage, food offered to idols, the Lord’s Supper, '
        'spiritual gifts — and the chapter on love.',
  ),
  '2CO': BookNote(
    genre: 'Letter',
    attribution: 'Paul',
    setting: 'After a painful visit and letter',
    summary:
        'The most personal of Paul’s letters: a defence of his ministry, a '
        'collection for Jerusalem, and strength made perfect in weakness.',
  ),
  'GAL': BookNote(
    genre: 'Letter',
    attribution: 'Paul',
    setting: 'Churches being told to take on the law',
    summary:
        'A sharp argument that Gentiles are not obliged to become Jews to '
        'belong, and that freedom is the point of the gospel.',
  ),
  'EPH': BookNote(
    genre: 'Letter',
    attribution: 'Paul; the earliest copies do not name Ephesus',
    setting: 'Written from prison',
    summary:
        'Three chapters on what God has done in Christ, three on the life '
        'that follows, ending with the armour of God.',
  ),
  'PHP': BookNote(
    genre: 'Letter',
    attribution: 'Paul',
    setting: 'From prison, to a church that supported him',
    summary:
        'A warm thank-you letter about joy under pressure, holding the early '
        'hymn about Christ emptying himself.',
  ),
  'COL': BookNote(
    genre: 'Letter',
    attribution: 'Paul',
    setting: 'A church facing teaching that added to Christ',
    summary:
        'Christ as the image of the invisible God and the fullness of deity, '
        'so that rules about food, festivals and visions add nothing.',
  ),
  '1TH': BookNote(
    genre: 'Letter',
    attribution: 'Paul, with Silvanus and Timothy',
    setting: 'A young church Paul had to leave quickly',
    summary:
        'Encouragement under persecution and reassurance about Christians who '
        'have died before the Lord returns.',
  ),
  '2TH': BookNote(
    genre: 'Letter',
    attribution: 'Paul, with Silvanus and Timothy',
    setting: 'The same church, soon after',
    summary:
        'Correcting the idea that the day of the Lord has already come, and '
        'telling the idle to get back to work.',
  ),
  '1TI': BookNote(
    genre: 'Letter',
    attribution: 'Paul, to Timothy',
    setting: 'Timothy left in charge at Ephesus',
    summary:
        'Instructions on teaching, prayer, leadership and money for someone '
        'running a church.',
  ),
  '2TI': BookNote(
    genre: 'Letter',
    attribution: 'Paul, to Timothy',
    setting: 'Written from prison, expecting the end',
    summary:
        'A last charge to preach the word and hold the pattern of sound '
        'teaching; the most personal of the three pastoral letters.',
  ),
  'TIT': BookNote(
    genre: 'Letter',
    attribution: 'Paul, to Titus',
    setting: 'Crete',
    summary:
        'Appointing elders, answering disruptive teaching, and what grace '
        'trains people to do.',
  ),
  'PHM': BookNote(
    genre: 'Letter',
    attribution: 'Paul',
    setting: 'A private letter about a household',
    summary:
        'Paul sends the slave Onesimus back to Philemon and asks him to '
        'receive him as a brother; the shortest of Paul’s letters.',
  ),
  'HEB': BookNote(
    genre: 'Sermon in letter form',
    attribution: 'Anonymous; the author is unknown',
    setting: 'Readers tempted to fall back from their confession',
    summary:
        'A sustained argument that Christ is better — than angels, Moses, the '
        'priesthood and the sacrifices — with a roll-call of faith in chapter '
        'eleven.',
  ),
  'JAS': BookNote(
    genre: 'Letter, close to wisdom writing',
    attribution: 'James; traditionally the brother of Jesus',
    setting: 'Scattered Jewish Christian congregations',
    summary:
        'Practical and blunt: faith shows in what you do, the tongue is a '
        'fire, and favouritism towards the rich is condemned.',
  ),
  '1PE': BookNote(
    genre: 'Letter',
    attribution: 'Peter',
    setting: 'Christians as strangers in Asia Minor',
    summary:
        'How to live under suspicion and hostility without returning it, held '
        'up by a living hope.',
  ),
  '2PE': BookNote(
    genre: 'Letter',
    attribution: 'Peter',
    setting: 'Facing teachers who deny the Lord’s return',
    summary:
        'A warning about false teachers and an answer to scoffers: the delay '
        'is patience, not indifference.',
  ),
  '1JN': BookNote(
    genre: 'Letter',
    attribution: 'Anonymous; associated with John',
    setting: 'A community that has just split',
    summary:
        'Tests of what is real — walking in the light, loving one another, '
        'confessing Christ come in the flesh — so readers may know they have '
        'life.',
  ),
  '2JN': BookNote(
    genre: 'Letter',
    attribution: 'The elder',
    setting: 'To "the chosen lady and her children"',
    summary:
        'Thirteen verses on holding to love and truth and not hosting '
        'teachers who bring neither.',
  ),
  '3JN': BookNote(
    genre: 'Letter',
    attribution: 'The elder, to Gaius',
    setting: 'A dispute about hospitality',
    summary:
        'Commending Gaius and Demetrius, and naming Diotrephes, who likes to '
        'put himself first.',
  ),
  'JUD': BookNote(
    genre: 'Letter',
    attribution: 'Jude, brother of James',
    setting: 'Written in haste about an urgent problem',
    summary:
        'A call to contend for the faith against people who turn grace into '
        'licence, closing with one of the best-known doxologies.',
  ),
  'REV': BookNote(
    genre: 'Apocalyptic vision and letters',
    attribution: 'John, on Patmos',
    setting: 'Asia Minor under Roman power',
    summary:
        'Letters to seven churches open a sequence of visions — seals, '
        'trumpets, bowls, a beast, a fall of Babylon — ending with a new '
        'heaven and new earth and God dwelling with people.',
  ),
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
    attribution: 'Jesus ben Sira, translated by his grandson',
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
