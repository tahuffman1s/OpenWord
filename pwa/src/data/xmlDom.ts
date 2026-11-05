/**
 * The little of an XML document the EPUB importer reads.
 *
 * The Dart importer leans on `package:xml`; here the tree comes from
 * `htmlparser2` and `domhandler`, which run in a Web Worker — `DOMParser`
 * does not — and this is the thin layer that gives the port the handful of
 * operations the Dart uses, so it reads like the Dart: an element's local
 * name, its attributes, its children, its text, its descendants, and a
 * search by tag.
 *
 * Two parsing modes. A package file, a `container.xml` and an NCX are XML
 * and are read as XML. A content document is XHTML in name and HTML in
 * practice — unclosed `<br>`s, stray entities, tags in whatever case —
 * and is read tolerantly, which is more than the Dart managed: a document
 * the XML parser refused was skipped whole, and here it is read.
 *
 * Names are matched by local name, ignoring case and namespace prefix:
 * `dc:title` answers to `title`, `navPoint` to `navpoint`. The HTML mode
 * lowercases tag names and the XML mode keeps them, and the port compares
 * lowercase in either case, as the Dart does.
 */
import { parseDocument } from 'htmlparser2';
import { Document, Element, Text, isTag, isText, isCDATA, type ChildNode, type AnyNode } from 'domhandler';
import { textContent } from 'domutils';

export type XmlDocument = Document;
export type XmlElement = Element;
export type XmlNode = ChildNode;

/** Parses XML: the package file, the container, an NCX. */
export function parseXml(text: string): XmlDocument {
  return parseDocument(text, { xmlMode: true, decodeEntities: true });
}

/**
 * Parses a content document tolerantly, as a browser would: unclosed
 * tags closed, void elements known, self-closing tags honoured, tag
 * names lowercased.
 */
export function parseXhtml(text: string): XmlDocument {
  return parseDocument(text, {
    xmlMode: false,
    decodeEntities: true,
    recognizeSelfClosing: true,
    lowerCaseTags: true,
    lowerCaseAttributeNames: true,
  });
}

export function isElement(node: AnyNode): node is Element {
  return isTag(node);
}

/** Whether a node carries text: a text node or a CDATA section. */
export function isTextNode(node: AnyNode): boolean {
  return isText(node) || isCDATA(node);
}

/** The text of a text node or CDATA section; empty for anything else. */
export function textOf(node: AnyNode): string {
  if (isText(node)) return (node as Text).data;
  if (isCDATA(node)) return textContent(node);
  return '';
}

/** The element's name without its namespace prefix, in the case it was written. */
export function localName(element: Element): string {
  const name = element.name;
  const colon = name.lastIndexOf(':');
  return colon < 0 ? name : name.substring(colon + 1);
}

/**
 * An attribute by name, or null. With `anyNamespace`, an attribute whose
 * local name matches under any prefix: `epub:type` answers to `type`.
 */
export function getAttribute(element: Element, name: string, anyNamespace = false): string | null {
  const attribs = element.attribs;
  if (Object.prototype.hasOwnProperty.call(attribs, name)) return attribs[name];
  if (!anyNamespace) return null;
  const suffix = `:${name}`;
  for (const key of Object.keys(attribs)) {
    if (key.endsWith(suffix)) return attribs[key];
  }
  return null;
}

/** The node's children, in document order. */
export function childrenOf(node: Document | Element): readonly ChildNode[] {
  return node.children;
}

/** The concatenated text of every text node and CDATA section under the node. */
export function innerText(node: Document | Element): string {
  let out = '';
  const visit = (n: AnyNode): void => {
    if (isText(n)) {
      out += (n as Text).data;
      return;
    }
    if (isCDATA(n)) {
      out += textContent(n);
      return;
    }
    if (isTag(n)) for (const child of n.children) visit(child);
  };
  for (const child of node.children) visit(child);
  return out;
}

function nameMatches(element: Element, wanted: string): boolean {
  return localName(element).toLowerCase() === wanted;
}

/** Every descendant element with this local name, in document order. */
export function findAllElements(node: Document | Element, name: string): Element[] {
  const wanted = name.toLowerCase();
  const found: Element[] = [];
  const visit = (n: AnyNode): void => {
    if (!isTag(n)) return;
    if (nameMatches(n, wanted)) found.push(n);
    for (const child of n.children) visit(child);
  };
  for (const child of node.children) visit(child);
  return found;
}

/** The direct child elements with this local name. */
export function findElements(node: Document | Element, name: string): Element[] {
  const wanted = name.toLowerCase();
  const found: Element[] = [];
  for (const child of node.children) {
    if (isTag(child) && nameMatches(child, wanted)) found.push(child);
  }
  return found;
}

/** The document's root element, or null for a document with none. */
export function rootElement(document: Document): Element | null {
  for (const child of document.children) if (isTag(child)) return child;
  return null;
}
