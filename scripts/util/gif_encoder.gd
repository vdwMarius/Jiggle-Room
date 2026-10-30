class_name GifEncoder
extends RefCounted
## Minimal animated-GIF writer (GIF89a, LZW, fixed 6x7x6 colour cube palette).
## Small and dependency-free; meant for short, low-res photo-mode clips.
## Run `encode` on a Thread - it's pure GDScript and takes a few seconds.

const PALETTE_R := 6
const PALETTE_G := 7
const PALETTE_B := 6


static func encode(frames: Array[Image], delay_cs: int) -> PackedByteArray:
	var w := frames[0].get_width()
	var h := frames[0].get_height()
	var out := PackedByteArray()
	out.append_array("GIF89a".to_ascii_buffer())
	_u16(out, w)
	_u16(out, h)
	out.append(0xF7)  # global colour table, 8 bits, 256 entries
	out.append(0)
	out.append(0)
	# Palette: 6*7*6 = 252 colours + 4 greys.
	for r in PALETTE_R:
		for g in PALETTE_G:
			for b in PALETTE_B:
				out.append(int(r * 255.0 / (PALETTE_R - 1)))
				out.append(int(g * 255.0 / (PALETTE_G - 1)))
				out.append(int(b * 255.0 / (PALETTE_B - 1)))
	for i in 4:
		var v := 50 + i * 50
		out.append(v)
		out.append(v)
		out.append(v)
	# Loop forever.
	out.append_array(PackedByteArray([0x21, 0xFF, 0x0B]))
	out.append_array("NETSCAPE2.0".to_ascii_buffer())
	out.append_array(PackedByteArray([0x03, 0x01, 0x00, 0x00, 0x00]))

	for img in frames:
		# Graphic control extension (frame delay).
		out.append_array(PackedByteArray([0x21, 0xF9, 0x04, 0x00]))
		_u16(out, delay_cs)
		out.append_array(PackedByteArray([0x00, 0x00]))
		# Image descriptor.
		out.append(0x2C)
		_u16(out, 0)
		_u16(out, 0)
		_u16(out, w)
		_u16(out, h)
		out.append(0)
		out.append(8)  # LZW minimum code size
		var data := _lzw(_quantize(img), 8)
		var pos := 0
		while pos < data.size():
			var n := mini(255, data.size() - pos)
			out.append(n)
			out.append_array(data.slice(pos, pos + n))
			pos += n
		out.append(0)
	out.append(0x3B)
	return out


static func _u16(out: PackedByteArray, v: int) -> void:
	out.append(v & 0xFF)
	out.append((v >> 8) & 0xFF)


## Ordered-dither each pixel into the colour cube.
static func _quantize(img: Image) -> PackedByteArray:
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	var src := img.get_data()
	var n := img.get_width() * img.get_height()
	var w := img.get_width()
	var bayer := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	var idx := PackedByteArray()
	idx.resize(n)
	for i in n:
		var x := i % w
		var y := i / w
		var d: float = (bayer[(y % 4) * 4 + (x % 4)] / 16.0 - 0.5)
		var r := clampi(int(src[i * 3] / 255.0 * (PALETTE_R - 1) + 0.5 + d * 0.9), 0, PALETTE_R - 1)
		var g := clampi(int(src[i * 3 + 1] / 255.0 * (PALETTE_G - 1) + 0.5 + d * 0.9), 0, PALETTE_G - 1)
		var b := clampi(int(src[i * 3 + 2] / 255.0 * (PALETTE_B - 1) + 0.5 + d * 0.9), 0, PALETTE_B - 1)
		idx[i] = (r * PALETTE_G + g) * PALETTE_B + b
	return idx


## Variable-width LZW as GIF expects it (same scheme as omggif).
static func _lzw(indices: PackedByteArray, min_code_size: int) -> PackedByteArray:
	var clear_code := 1 << min_code_size
	var eoi := clear_code + 1
	var out := PackedByteArray()
	var bit_buf := 0
	var bit_len := 0
	var code_size := min_code_size + 1
	var dict := {}
	var next_code := eoi + 1

	# Codes are packed LSB-first; the emit steps are inlined for speed.
	bit_buf |= clear_code << bit_len
	bit_len += code_size
	var prefix := -1
	for k in indices:
		if prefix == -1:
			prefix = k
			continue
		var key := (prefix << 8) | k
		if dict.has(key):
			prefix = dict[key]
			continue
		bit_buf |= prefix << bit_len
		bit_len += code_size
		while bit_len >= 8:
			out.append(bit_buf & 0xFF)
			bit_buf >>= 8
			bit_len -= 8
		if next_code == 4096:
			# Table full: emit a clear code and start over.
			bit_buf |= clear_code << bit_len
			bit_len += code_size
			while bit_len >= 8:
				out.append(bit_buf & 0xFF)
				bit_buf >>= 8
				bit_len -= 8
			dict.clear()
			code_size = min_code_size + 1
			next_code = eoi + 1
		else:
			if next_code >= (1 << code_size):
				code_size += 1
			dict[key] = next_code
			next_code += 1
		prefix = k
	if prefix != -1:
		bit_buf |= prefix << bit_len
		bit_len += code_size
	bit_buf |= eoi << bit_len
	bit_len += code_size
	while bit_len > 0:
		out.append(bit_buf & 0xFF)
		bit_buf >>= 8
		bit_len -= 8
	return out
