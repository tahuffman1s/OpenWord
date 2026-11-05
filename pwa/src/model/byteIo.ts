/**
 * The primitives every OpenWord binary format is written in: LEB128
 * varints, length-prefixed UTF-8, and big-endian fixed-width fields where a
 * field has to be found without reading what comes before it.
 */

const utf8Encoder = new TextEncoder();
const utf8Decoder = new TextDecoder('utf-8');

export class FormatException extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'FormatException';
  }
}

export class ByteWriter {
  private buffer = new Uint8Array(1 << 16);
  private _length = 0;

  get length(): number {
    return this._length;
  }

  private ensure(extra: number): void {
    if (this._length + extra <= this.buffer.length) return;
    let size = this.buffer.length * 2;
    while (size < this._length + extra) size *= 2;
    const next = new Uint8Array(size);
    next.set(this.buffer.subarray(0, this._length));
    this.buffer = next;
  }

  byte(value: number): this {
    this.ensure(1);
    this.buffer[this._length++] = value & 0xff;
    return this;
  }

  bytes(values: ArrayLike<number>): this {
    this.ensure(values.length);
    this.buffer.set(values, this._length);
    this._length += values.length;
    return this;
  }

  uint32(value: number): this {
    this.ensure(4);
    this.buffer[this._length++] = (value >>> 24) & 0xff;
    this.buffer[this._length++] = (value >>> 16) & 0xff;
    this.buffer[this._length++] = (value >>> 8) & 0xff;
    this.buffer[this._length++] = value & 0xff;
    return this;
  }

  varint(value: number): this {
    let remaining = value;
    while (remaining >= 0x80) {
      this.byte((remaining % 0x80) | 0x80);
      remaining = Math.floor(remaining / 0x80);
    }
    this.byte(remaining);
    return this;
  }

  string(value: string): this {
    const encoded = utf8Encoder.encode(value);
    this.varint(encoded.length);
    this.bytes(encoded);
    return this;
  }

  /** A view of what has been written. Valid until the next write. */
  take(): Uint8Array {
    return this.buffer.subarray(0, this._length);
  }

  /** A copy, for when the bytes have to outlive further writing. */
  takeCopy(): Uint8Array {
    return this.buffer.slice(0, this._length);
  }
}

export class ByteReader {
  constructor(
    readonly data: Uint8Array,
    public offset = 0,
  ) {}

  get atEnd(): boolean {
    return this.offset >= this.data.length;
  }

  get remaining(): number {
    return this.data.length - this.offset;
  }

  private short(): never {
    throw new FormatException('the file ended early');
  }

  byte(): number {
    if (this.offset >= this.data.length) this.short();
    return this.data[this.offset++];
  }

  uint32(): number {
    if (this.offset + 4 > this.data.length) this.short();
    const d = this.data;
    const o = this.offset;
    const value = ((d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3]) >>> 0;
    this.offset += 4;
    return value;
  }

  varint(): number {
    let result = 0;
    let multiplier = 1;
    let shift = 0;
    for (;;) {
      const part = this.byte();
      result += (part & 0x7f) * multiplier;
      if ((part & 0x80) === 0) return result;
      multiplier *= 0x80;
      shift += 7;
      if (shift > 63) throw new FormatException('a length in the file is nonsense');
    }
  }

  take(length: number): Uint8Array {
    if (length < 0 || this.offset + length > this.data.length) this.short();
    const view = this.data.subarray(this.offset, this.offset + length);
    this.offset += length;
    return view;
  }

  string(): string {
    const length = this.varint();
    return utf8Decoder.decode(this.take(length));
  }
}

export const utf8 = {
  encode: (s: string): Uint8Array => utf8Encoder.encode(s),
  decode: (b: Uint8Array): string => utf8Decoder.decode(b),
};
