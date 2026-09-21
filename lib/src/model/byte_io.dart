import 'dart:convert';
import 'dart:typed_data';

/// The primitives every OpenWord binary format is written in: LEB128
/// varints, length-prefixed UTF-8, and big-endian fixed-width fields where a
/// field has to be found without reading what comes before it.
class ByteWriter {
  Uint8List _buffer = Uint8List(1 << 16);
  int _length = 0;

  int get length => _length;

  void _ensure(int extra) {
    if (_length + extra <= _buffer.length) return;
    var size = _buffer.length * 2;
    while (size < _length + extra) {
      size *= 2;
    }
    _buffer = Uint8List(size)..setRange(0, _length, _buffer);
  }

  void byte(int value) {
    _ensure(1);
    _buffer[_length++] = value & 0xff;
  }

  void bytes(List<int> values) {
    _ensure(values.length);
    _buffer.setRange(_length, _length + values.length, values);
    _length += values.length;
  }

  void uint32(int value) {
    _ensure(4);
    _buffer[_length++] = (value >> 24) & 0xff;
    _buffer[_length++] = (value >> 16) & 0xff;
    _buffer[_length++] = (value >> 8) & 0xff;
    _buffer[_length++] = value & 0xff;
  }

  void varint(int value) {
    var remaining = value;
    while (remaining >= 0x80) {
      byte((remaining & 0x7f) | 0x80);
      remaining >>= 7;
    }
    byte(remaining);
  }

  void string(String value) {
    final encoded = utf8.encode(value);
    varint(encoded.length);
    bytes(encoded);
  }

  /// A view of what has been written. Valid until the next write.
  Uint8List take() => Uint8List.sublistView(_buffer, 0, _length);

  /// A copy, for when the bytes have to outlive further writing.
  Uint8List takeCopy() => Uint8List.fromList(take());
}

class ByteReader {
  ByteReader(this.data, [this.offset = 0]);

  final Uint8List data;
  int offset;

  bool get atEnd => offset >= data.length;
  int get remaining => data.length - offset;

  Never _short() => throw const FormatException('the file ended early');

  int byte() {
    if (offset >= data.length) _short();
    return data[offset++];
  }

  int uint32() {
    if (offset + 4 > data.length) _short();
    final value =
        (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
    offset += 4;
    return value;
  }

  int varint() {
    var result = 0;
    var shift = 0;
    while (true) {
      final part = byte();
      result |= (part & 0x7f) << shift;
      if (part & 0x80 == 0) return result;
      shift += 7;
      if (shift > 63) {
        throw const FormatException('a length in the file is nonsense');
      }
    }
  }

  Uint8List take(int length) {
    if (length < 0 || offset + length > data.length) _short();
    final view = Uint8List.sublistView(data, offset, offset + length);
    offset += length;
    return view;
  }

  String string() {
    final length = varint();
    return utf8.decode(take(length));
  }
}
