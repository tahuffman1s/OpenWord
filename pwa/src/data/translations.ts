import { TranslationInfo, Versification } from '../model/bible';

/**
 * The translations that ship inside the app. Every one is in the public
 * domain, which is what makes it possible to bundle the text.
 */
export const Translations = {
  web: new TranslationInfo({
    id: 'eng-web',
    name: 'World English Bible',
    abbreviation: 'WEB',
    license: 'Public Domain',
    sourceUrl: 'https://ebible.org/web/',
    language: 'en',
    script: 'Latn',
    versification: Versification.english,
  }),
  webbe: new TranslationInfo({
    id: 'eng-gb-webbe',
    name: 'World English Bible, British Edition',
    abbreviation: 'WEBBE',
    license: 'Public Domain',
    sourceUrl: 'https://ebible.org/webbe/',
    language: 'en-GB',
    script: 'Latn',
    versification: Versification.english,
  }),
  bsb: new TranslationInfo({
    id: 'eng-bsb',
    name: 'Berean Standard Bible',
    abbreviation: 'BSB',
    license: 'Public Domain',
    sourceUrl: 'https://berean.bible/',
    language: 'en',
    script: 'Latn',
    versification: Versification.english,
  }),
  get all(): readonly TranslationInfo[] {
    return [Translations.web, Translations.bsb, Translations.webbe];
  },
  get fallback(): TranslationInfo {
    return Translations.web;
  },
  byId(id: string): TranslationInfo {
    return Translations.all.find((t) => t.id === id) ?? Translations.fallback;
  },
  assetExtension: '.bib',
  assetFor(id: string): string {
    return `assets/bible/${id}.bib`;
  },
};
