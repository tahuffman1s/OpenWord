// Package images turns an uploaded picture into a small square JPEG avatar.
package images

import (
	"bytes"
	"errors"
	"image"
	"image/jpeg"
	"io"

	// Register decoders. GIF yields its first frame.
	_ "image/gif"
	_ "image/png"

	"golang.org/x/image/draw"
	_ "golang.org/x/image/webp"
)

const (
	// AvatarSize is the edge length of the stored square avatar.
	AvatarSize = 256
	// AvatarQuality is the JPEG quality used for storage.
	AvatarQuality = 82
	// AvatarContentType is what GetAvatar serves.
	AvatarContentType = "image/jpeg"
	// maxPixels bounds the decoded image so a tiny but enormous-dimension
	// file cannot exhaust a 2 GB Pi. 24 MP ≈ 96 MB RGBA.
	maxPixels = 24_000_000
)

// ErrUnsupported is returned when the bytes are not a decodable image.
var ErrUnsupported = errors.New("unsupported or corrupt image")

// ErrTooLarge is returned when the image dimensions exceed maxPixels.
var ErrTooLarge = errors.New("image dimensions are too large")

// Avatar decodes src (PNG/JPEG/GIF/WebP), centre-crops to a square, scales
// to AvatarSize and encodes a JPEG.
func Avatar(src io.Reader) ([]byte, error) {
	raw, err := io.ReadAll(src)
	if err != nil {
		return nil, err
	}
	cfg, _, err := image.DecodeConfig(bytes.NewReader(raw))
	if err != nil {
		return nil, ErrUnsupported
	}
	if cfg.Width <= 0 || cfg.Height <= 0 {
		return nil, ErrUnsupported
	}
	if cfg.Width*cfg.Height > maxPixels {
		return nil, ErrTooLarge
	}
	img, _, err := image.Decode(bytes.NewReader(raw))
	if err != nil {
		return nil, ErrUnsupported
	}

	// Centre crop to a square.
	b := img.Bounds()
	side := min(b.Dx(), b.Dy())
	x0 := b.Min.X + (b.Dx()-side)/2
	y0 := b.Min.Y + (b.Dy()-side)/2
	crop := image.Rect(x0, y0, x0+side, y0+side)

	dst := image.NewRGBA(image.Rect(0, 0, AvatarSize, AvatarSize))
	draw.CatmullRom.Scale(dst, dst.Bounds(), img, crop, draw.Src, nil)

	var out bytes.Buffer
	if err := jpeg.Encode(&out, dst, &jpeg.Options{Quality: AvatarQuality}); err != nil {
		return nil, err
	}
	return out.Bytes(), nil
}
