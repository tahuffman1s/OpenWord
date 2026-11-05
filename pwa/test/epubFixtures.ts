import { strToU8, zipSync, type Zippable } from 'fflate';

/** A document of the spine: its file name and the body of its XHTML. */
export type EpubDocument = readonly [name: string, xhtml: string];

/**
 * Builds an EPUB around some XHTML documents, the way a real one is laid
 * out: a container pointing at a package file, which lists the spine.
 */
export function epub(options: {
  documents: readonly EpubDocument[];
  title?: string;
  rights?: string | null;
  withSpine?: boolean;
  nav?: EpubDocument;
}): Uint8Array {
  const { documents, nav } = options;
  const title = options.title ?? 'Test Standard Version';
  const rights = options.rights === undefined ? 'Public Domain' : options.rights;
  const withSpine = options.withSpine ?? true;

  let manifest = '';
  let spine = '';
  for (let i = 0; i < documents.length; i++) {
    manifest += `<item id="d${i}" href="${documents[i][0]}" media-type="application/xhtml+xml"/>`;
    spine += `<itemref idref="d${i}"/>`;
  }
  // The navigation document, which most EPUBs put in the reading order.
  if (nav !== undefined) {
    manifest += `<item id="nav" href="${nav[0]}" properties="nav" media-type="application/xhtml+xml"/>`;
    spine += '<itemref idref="nav"/>';
  }

  const opf =
    '<?xml version="1.0" encoding="utf-8"?>' +
    '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">' +
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">' +
    `<dc:title>${title}</dc:title>` +
    `<dc:identifier>urn:test:${title}</dc:identifier>` +
    `${rights === null ? '' : `<dc:rights>${rights}</dc:rights>`}` +
    '</metadata>' +
    `<manifest>${manifest}</manifest>` +
    `${withSpine ? `<spine>${spine}</spine>` : '<spine/>'}` +
    '</package>';

  const files: Zippable = {
    mimetype: [strToU8('application/epub+zip'), { level: 0 }],
    'META-INF/container.xml': strToU8(container),
    'OEBPS/content.opf': strToU8(opf),
  };
  for (const [name, body] of documents) {
    files[`OEBPS/${name}`] = strToU8(page(body));
  }
  if (nav !== undefined) {
    files[`OEBPS/${nav[0]}`] = strToU8(page(nav[1]));
  }
  return zipSync(files);
}

const container =
  '<?xml version="1.0"?>' +
  '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">' +
  '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>' +
  '</container>';

function page(body: string): string {
  return (
    '<?xml version="1.0" encoding="utf-8"?>' +
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>x</title></head>' +
    `<body>${body}</body></html>`
  );
}

/**
 * An EPUB whose table of contents names the documents, for the case where
 * nothing inside them does.
 */
export function epubWithToc(options: {
  documents: readonly EpubDocument[];
  toc: Record<string, string>;
  title?: string;
}): Uint8Array {
  const { documents, toc } = options;
  const title = options.title ?? 'Test Standard Version';

  let manifest = '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>';
  let spine = '';
  for (let i = 0; i < documents.length; i++) {
    manifest += `<item id="d${i}" href="${documents[i][0]}" media-type="application/xhtml+xml"/>`;
    spine += `<itemref idref="d${i}"/>`;
  }

  let points = '';
  let order = 0;
  for (const [href, label] of Object.entries(toc)) {
    order++;
    points +=
      `<navPoint id="n${order}" playOrder="${order}">` +
      `<navLabel><text>${label}</text></navLabel>` +
      `<content src="${href}"/></navPoint>`;
  }

  const ncx =
    '<?xml version="1.0" encoding="utf-8"?>' +
    '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">' +
    `<navMap>${points}</navMap></ncx>`;

  const opf =
    '<?xml version="1.0" encoding="utf-8"?>' +
    '<package xmlns="http://www.idpf.org/2007/opf" version="2.0">' +
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">' +
    `<dc:title>${title}</dc:title></metadata>` +
    `<manifest>${manifest}</manifest>` +
    `<spine toc="ncx">${spine}</spine></package>`;

  const files: Zippable = {
    mimetype: [strToU8('application/epub+zip'), { level: 0 }],
    'META-INF/container.xml': strToU8(container),
    'OEBPS/content.opf': strToU8(opf),
    'OEBPS/toc.ncx': strToU8(ncx),
  };
  for (const [name, body] of documents) {
    files[`OEBPS/${name}`] = strToU8(page(body));
  }
  return zipSync(files);
}
