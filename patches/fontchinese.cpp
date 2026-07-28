/* ScummVM - Graphic Adventure Engine
 *
 * ScummVM is the legal property of its developers, whose names
 * are too numerous to list here. Please refer to the COPYRIGHT
 * file distributed with this source distribution.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#include "common/file.h"
#include "graphics/big5.h"

#include "sci/sci.h"
#include "sci/graphics/screen.h"
#include "sci/graphics/fontchinese.h"

namespace Sci {

// Big5 font data file shipped alongside the game (part of the CHT patch).
static const char *kChineseFontFile = "freddy_big5.fnt";
// Advance width used when laying the glyph out on screen. NOTE this is deliberately
// narrower than the glyph bitmap itself -- it is a layout metric, NOT a buffer stride.
static const int kBig5Width = 12;

// Upper bound of what Big5Font::drawBig5Char() may write into a scratch buffer.
// Any buffer handed to it must be sized by these, never by kBig5Width: the low-res
// status-bar path passes kChineseTraditionalWidth (16) as the destination pitch, so a
// kBig5Width-sized buffer is 48 bytes short and drawBig5Char writes straight through
// the stack canary. That is what crashed the macOS build (issue #1): arm64 builds ship
// with -fstack-protector-strong, so it aborted at the first status-bar draw; on Linux
// the same overflow ran silently. Upstream's kChineseTraditionalMaxHeight is private,
// hence the local copy.
static const int kBig5GlyphMaxW = Graphics::Big5Font::kChineseTraditionalWidth;  // 16
static const int kBig5GlyphMaxH = 16;

// Hi-res Big5 font (own format, bake_hires_font.py): 32px-wide, kHiH-row glyphs drawn
// straight onto the 640x400 display buffer for sharp strokes under ZH_TWN upscaling.
static const char *kChineseHiResFontFile = "freddy_big5_hi.fnt";
static const int kHiW = 24;
static const int kHiH = 24;

GfxFontChinese::GfxFontChinese(ResourceManager *resMan, GfxScreen *screen, GuiResourceId resourceId)
	: _screen(screen), _resourceId(resourceId), _big5(nullptr), _big5Height(15) {
	// Original SCI font for single-byte (ASCII / control) glyphs.
	_asciiFont = new GfxFontFromResource(resMan, screen, resourceId);

	Common::File fontFile;
	if (fontFile.open(kChineseFontFile)) {
		_big5 = new Graphics::Big5Font();
		_big5->loadPrefixedRaw(fontFile, _big5Height);
		// Clamp: the glyph scratch buffers below are sized for kBig5GlyphMaxH rows, and
		// a font file claiming more would overflow them.
		_big5Height = MIN<int>(_big5->getFontHeight(), kBig5GlyphMaxH);
	} else {
		warning("GfxFontChinese: could not open '%s'; Chinese glyphs will be blank", kChineseFontFile);
	}

	_hiW = kHiW;
	_hiH = kHiH;
	loadHiResFont();
}

// Load the hi-res Big5 font: repeated { big-endian Big5 code (uint16), _hiH*(_hiW/8) glyph
// bytes }, terminated by 0xFFFF. Keeps a code->offset index into the flat _hiData blob.
// Missing file just means we fall back to the low-res Big5 path (no hi-res sharpening).
bool GfxFontChinese::loadHiResFont() {
	Common::File f;
	if (!f.open(kChineseHiResFontFile))
		return false;
	const uint bytesPerGlyph = _hiH * ((_hiW + 7) / 8);
	while (!f.eos()) {
		uint16 code = f.readUint16BE();
		if (f.eos() || code == 0xFFFF)
			break;
		uint32 offset = _hiData.size();
		_hiData.resize(offset + bytesPerGlyph);
		if (f.read(&_hiData[offset], bytesPerGlyph) != bytesPerGlyph)
			break;
		_hiIndex[code] = offset;
	}
	return !_hiIndex.empty();
}

GfxFontChinese::~GfxFontChinese() {
	delete _big5;
	delete _asciiFont;
}

GuiResourceId GfxFontChinese::getResourceId() {
	return _resourceId;
}

byte GfxFontChinese::getHeight() {
	byte asciiHeight = _asciiFont->getHeight();
	return MAX<byte>(asciiHeight, (byte)_big5Height);
}

// text16 tests this on the first (lead) byte before combining the pair.
bool GfxFontChinese::isDoubleByte(uint16 chr) {
	return (chr >= 0x81) && (chr <= 0xFE);
}

byte GfxFontChinese::getCharWidth(uint16 chr) {
	// chr may arrive either as a bare lead byte (during width scans) or as a
	// combined lead|(trail<<8) value (during drawing). Both mean a Big5 char.
	if (chr > 0xFF || isDoubleByte(chr))
		return kBig5Width;
	return _asciiFont->getCharWidth(chr);
}

byte GfxFontChinese::getCharHeight(uint16 chr) {
	if (chr > 0xFF || isDoubleByte(chr))
		return (byte)_big5Height;
	return _asciiFont->getHeight();
}

void GfxFontChinese::draw(uint16 chr, int16 top, int16 left, byte color, bool greyedOutput) {
	// Single-byte: delegate to the original SCI font (keeps ASCII pixel-identical).
	if (chr <= 0xFF) {
		_asciiFont->draw(chr, top, left, color, greyedOutput);
		return;
	}

	// Double-byte: chr == lead | (trail << 8); Big5Font wants (lead << 8) | trail.
	uint16 point = ((chr & 0xFF) << 8) | (chr >> 8);

	const bool upscaled = _screen->getDisplayWidth() > _screen->getWidth();

	// Compact path: some boxes have their height hard-coded by the game (status bar,
	// pause-panel readout). See GfxScreen::setCompactTextActive. That bar is only 10 script rows (20 display rows) tall, so a 24px
	// hi-res glyph overflows it — characters got clipped at the bottom and bled into the
	// picture. Draw the compact 16x15 glyph 1:1 into the display buffer instead: it fits
	// inside the bar, stays sharp (no 2x nearest blur), and keeps the game's own centring
	// because we still advance by the normal char width.
	if (upscaled && _screen->compactTextActive()) {
		if (drawCompact(point, top, left, color))
			return;
	}

	// Hi-res path: when ZH_TWN runs upscaled (640x400 display) and we have a hi-res glyph,
	// draw sharp 32xN strokes directly onto the display instead of the blocky 2x low-res.
	if (upscaled && _hiIndex.contains(point)) {
		drawHiRes(point, top, left, color);
		return;
	}

	byte glyph[kBig5GlyphMaxW * kBig5GlyphMaxH];
	memset(glyph, 0, sizeof(glyph));
	bool drawn = false;
	if (_big5)
		drawn = _big5->drawBig5Char(glyph, point, kBig5Width, _big5Height, kBig5Width,
		                            /*color*/ 1, /*outlineColor*/ 0, /*outline*/ false, /*bpp*/ 1);
	if (!drawn) {
		// Fall back to a placeholder so missing glyphs are visible, not silent.
		_asciiFont->draw('?', top, left, color, greyedOutput);
		return;
	}

	uint16 screenWidth = _screen->fontIsUpscaled() ? _screen->getDisplayWidth() : _screen->getWidth();
	uint16 screenHeight = _screen->fontIsUpscaled() ? _screen->getDisplayHeight() : _screen->getHeight();

	for (int y = 0; y < _big5Height; y++) {
		for (int x = 0; x < kBig5Width; x++) {
			if (!glyph[y * kBig5Width + x])
				continue;
			int screenX = left + x;
			int screenY = top + y;
			if (0 <= screenX && screenX < screenWidth && 0 <= screenY && screenY < screenHeight)
				_screen->putFontPixel(top, screenX, y, color);
		}
	}
}

// Draw the 16x15 low-res Big5 glyph at 1:1 into the display buffer, centred inside the
// character cell (2 * kBig5Width display pixels wide). Used for the short status bar.
// Returns false when the glyph is unavailable so the caller can fall back.
bool GfxFontChinese::drawCompact(uint16 point, int16 top, int16 left, byte color) {
	if (!_big5)
		return false;
	byte glyph[kBig5GlyphMaxW * kBig5GlyphMaxH];
	memset(glyph, 0, sizeof(glyph));
	if (!_big5->drawBig5Char(glyph, point, Graphics::Big5Font::kChineseTraditionalWidth,
	                         _big5Height, Graphics::Big5Font::kChineseTraditionalWidth,
	                         /*color*/ 1, /*outlineColor*/ 0, /*outline*/ false, /*bpp*/ 1))
		return false;

	const int cellW = kBig5Width * 2;
	const int gw = Graphics::Big5Font::kChineseTraditionalWidth;
	const int dispLeft = left * 2 + (cellW - gw) / 2;
	const int dispTop = top * 2;
	const int dispW = _screen->getDisplayWidth();
	const int dispH = _screen->getDisplayHeight();

	const bool savedUpscaled = _screen->fontIsUpscaled();
	_screen->setFontIsUpscaled(true);
	for (int gy = 0; gy < _big5Height; gy++) {
		const int dispY = dispTop + gy;
		if (dispY < 0 || dispY >= dispH)
			continue;
		for (int gx = 0; gx < gw; gx++) {
			if (!glyph[gy * gw + gx])
				continue;
			const int dispX = dispLeft + gx;
			if (dispX < 0 || dispX >= dispW)
				continue;
			_screen->putFontPixel(dispTop, dispX, gy, color);
		}
	}
	_screen->setFontIsUpscaled(savedUpscaled);
	return true;
}

// Draw a hi-res Big5 glyph directly onto the 640x400 display buffer. The game positions
// text in logical 320x200 coords, so we map (left, top) -> (left*2, top*2) on the display
// and toggle _fontIsUpscaled so putFontPixel writes straight to the display (no further
// nearest-scale), giving sharp 32xN strokes. ASCII glyphs are unaffected (they draw with
// _fontIsUpscaled == false and get the normal 2x upscale, matching the game art).
void GfxFontChinese::drawHiRes(uint16 point, int16 top, int16 left, byte color) {
	Common::HashMap<uint16, uint32>::const_iterator it = _hiIndex.find(point);
	if (it == _hiIndex.end())
		return;
	const byte *bmp = &_hiData[it->_value];
	const int rowBytes = (_hiW + 7) / 8;
	const int dispLeft = left * 2;
	const int dispTop = top * 2;
	const int dispW = _screen->getDisplayWidth();
	const int dispH = _screen->getDisplayHeight();

	const bool savedUpscaled = _screen->fontIsUpscaled();
	_screen->setFontIsUpscaled(true);
	for (int gy = 0; gy < _hiH; gy++) {
		const int dispY = dispTop + gy;
		if (dispY < 0 || dispY >= dispH)
			continue;
		for (int gx = 0; gx < _hiW; gx++) {
			if (!(bmp[gy * rowBytes + (gx >> 3)] & (0x80 >> (gx & 7))))
				continue;
			const int dispX = dispLeft + gx;
			if (dispX < 0 || dispX >= dispW)
				continue;
			_screen->putFontPixel(dispTop, dispX, gy, color);
		}
	}
	_screen->setFontIsUpscaled(savedUpscaled);
}

} // End of namespace Sci
