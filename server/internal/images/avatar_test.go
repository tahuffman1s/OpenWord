package images

import (
	"bytes"
	"encoding/binary"
	"hash/crc32"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"testing"
)

func TestAvatarCropsAndResizes(t *testing.T) {
	// 300x100 image: left third red, rest blue. The centre crop keeps the
	// middle 100x100, which is all blue.
	src := image.NewRGBA(image.Rect(0, 0, 300, 100))
	for y := 0; y < 100; y++ {
		for x := 0; x < 300; x++ {
			c := color.RGBA{0, 0, 255, 255}
			if x < 100 {
				c = color.RGBA{255, 0, 0, 255}
			}
			src.Set(x, y, c)
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, src); err != nil {
		t.Fatal(err)
	}
	out, err := Avatar(&buf)
	if err != nil {
		t.Fatal(err)
	}
	got, err := jpeg.Decode(bytes.NewReader(out))
	if err != nil {
		t.Fatal(err)
	}
	if got.Bounds().Dx() != AvatarSize || got.Bounds().Dy() != AvatarSize {
		t.Fatalf("size %v", got.Bounds())
	}
	r, _, b, _ := got.At(128, 128).RGBA()
	if b < 0x8000 || r > 0x3000 {
		t.Fatalf("centre pixel should be blue, got r=%d b=%d", r>>8, b>>8)
	}
}

func TestAvatarRejectsGarbage(t *testing.T) {
	if _, err := Avatar(bytes.NewReader([]byte("not an image"))); err != ErrUnsupported {
		t.Fatalf("got %v", err)
	}
}

func TestAvatarRejectsHugeDimensions(t *testing.T) {
	// A PNG signature plus a valid IHDR claiming 10000x10000 and nothing
	// else: DecodeConfig reads only the header, so the guard can be tested
	// without allocating the image.
	ihdr := []byte{0, 0, 0x27, 0x10, 0, 0, 0x27, 0x10, 8, 0, 0, 0, 0}
	var raw bytes.Buffer
	raw.Write([]byte("\x89PNG\r\n\x1a\n"))
	_ = binary.Write(&raw, binary.BigEndian, uint32(len(ihdr)))
	chunk := append([]byte("IHDR"), ihdr...)
	raw.Write(chunk)
	_ = binary.Write(&raw, binary.BigEndian, crc32.ChecksumIEEE(chunk))
	if _, err := Avatar(bytes.NewReader(raw.Bytes())); err != ErrTooLarge {
		t.Fatalf("got %v", err)
	}
}
