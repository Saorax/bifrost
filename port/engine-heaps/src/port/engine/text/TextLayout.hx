package port.engine.text;

import port.runtime.swf.SwfFonts;
import port.runtime.swf.SwfFonts.FontData;

@:access(flash.text.TextField)
class TextLayout {
	public static var missing(default, null) = new Map<String, Int>();

	static var keyCache = Sys.getEnv("BH_PORT_TEXT_KEY_CACHE") != "0";

	public static function key(tf:flash.text.TextField):String {
		if (!keyCache) return build(tf);
		var snap = tf.__keySnap;
		if (snap == null) tf.__keySnap = snap = new KeySnap();
		if (snap.key == null || !snap.same(tf)) {
			snap.take(tf);
			snap.key = build(tf);
		}
		return snap.key;
	}

	static function build(tf:flash.text.TextField):String {
		var b = new StringBuf();
		b.add(tf.__text);
		b.add("|");
		b.add(tf.__width);
		b.add("x");
		b.add(tf.__height);
		b.add(tf.wordWrap ? "w" : "-");
		b.add(tf.autoSize);
		b.add(tf.background ? "b" + tf.backgroundColor : "-");
		b.add(tf.border ? "B" + tf.borderColor : "-");
		b.add(tf.displayAsPassword ? "p" : "-");
		b.add(tf.antiAliasType);
		b.add(tf.gridFitType);
		inline function fmt(f:openfl.text.TextFormat) {
			b.add(f.font);
			b.add(",");
			b.add(f.size);
			b.add(",");
			b.add(f.color);
			b.add(",");
			b.add(f.bold);
			b.add(f.italic);
			b.add(",");
			b.add(f.align);
			b.add(",");
			b.add(f.letterSpacing);
			b.add(",");
			b.add(f.leading);
			b.add(",");
			b.add(f.leftMargin);
			b.add(",");
			b.add(f.rightMargin);
			b.add(",");
			b.add(f.indent);
			b.add(",");
			b.add(f.blockIndent);
		}
		fmt(tf.__textFormat);
		for (r in tf.textFormatRanges) {
			b.add(";");
			b.add(r.start);
			b.add("-");
			b.add(r.end);
			b.add(":");
			fmt(r.format);
		}
		return b.toString();
	}

	public static function measure(tf:flash.text.TextField):{width:Float, height:Float, lines:Int, heights:Array<Float>} {
		var text = tf.__text;
		if (tf.displayAsPassword) text = [for (_ in 0...text.length) tf.passwordChar].join("");
		var all = lines(tf, text);
		var width = 0.0, height = 0.0, y = 0.0;
		for (line in all) {
			if (line.margin + line.fullWidth > width) width = line.margin + line.fullWidth;
			if (y + line.ascent + line.descent > height) height = y + line.ascent + line.descent;
			y += line.height;
		}
		if (all.length == 1 && all[0].leading > 0) height += all[0].leading;
		return {width: width, height: height, lines: all.length, heights: [for (line in all) line.height]};
	}

	static function scrollOffset(all:Array<Line>, scrollV:Int):Float {
		var first = scrollV - 1;
		if (first <= 0 || first >= all.length) return 0;
		return all[first].baseline - all[first].ascent - 2;
	}

	static function lineIndexAt(all:Array<Line>, y:Float, clamp:Bool):Int {
		for (i in 0...all.length) {
			var top = all[i].baseline - all[i].ascent;
			if (y >= top && y < top + all[i].height) return i;
			if (clamp && y < top) return i;
		}
		return clamp ? all.length - 1 : -1;
	}

	public static function lineAt(tf:flash.text.TextField, x:Float, y:Float):Int {
		if (x < 0 || x > tf.__width || y < 0 || y > tf.__height) return -1;
		var all = lines(tf, tf.__text);
		return lineIndexAt(all, y + scrollOffset(all, tf.__scrollV), false);
	}

	public static function indexAt(tf:flash.text.TextField, x:Float, y:Float, caret:Bool):Int {
		var text = tf.__text;
		var all = lines(tf, text);
		var li = lineIndexAt(all, y + scrollOffset(all, tf.__scrollV), caret);
		if (li < 0) return caret ? text.length : -1;
		var at = 0;
		for (i in 0...li) {
			for (run in all[i].runs) at += run.codes.length;
			if (at < text.length && (text.charCodeAt(at) == 10 || text.charCodeAt(at) == 13)) at++;
		}
		var start = at;
		for (run in all[li].runs) for (k in 0...run.codes.length) {
			var x0 = run.xs[k], w = run.ws[k];
			if (x >= x0 && x < x0 + w) return caret && x >= x0 + w / 2 ? at + 1 : at;
			if (caret && x < x0) return at;
			at++;
		}
		return caret ? at : -1;
	}

	public static function charBounds(tf:flash.text.TextField, index:Int):flash.geom.Rectangle {
		var text = tf.__text;
		if (index < 0 || index >= text.length) return null;
		var at = 0;
		for (line in lines(tf, text)) {
			for (run in line.runs) for (k in 0...run.codes.length) {
				if (at == index)
					return new flash.geom.Rectangle(run.xs[k], line.baseline - line.ascent, run.ws[k], line.ascent + line.descent);
				at++;
			}
			if (at < text.length && (text.charCodeAt(at) == 10 || text.charCodeAt(at) == 13)) {
				if (at == index) return null;
				at++;
			}
		}
		return null;
	}

	static inline function fitted(tf:flash.text.TextField):Bool {
		return tf.antiAliasType == flash.text.AntiAliasType.ADVANCED && tf.gridFitType == flash.text.GridFitType.PIXEL;
	}

	public static function deviceKey(tf:flash.text.TextField, m:flash.geom.Matrix):String {
		deviceProbe(tf, m);
		return deviceKind == 0 ? "" : deviceKind == 1 ? "|r" + deviceScale : "|d" + deviceScale + "," + devicePhase;
	}

	public static var deviceKind(default, null) = 0;
	public static var deviceScale(default, null) = 0.0;
	public static var devicePhase(default, null) = 0;

	public static function deviceProbe(tf:flash.text.TextField, m:flash.geom.Matrix):Void {
		deviceScale = 0;
		devicePhase = 0;
		if (m == null || !fitted(tf)) {
			deviceKind = 0;
		} else if (!upright(m)) {
			if (turned(m)) {
				deviceKind = 1;
				deviceScale = turnScale(m);
			} else {
				deviceKind = 0;
			}
		} else {
			deviceKind = 2;
			deviceScale = m.a;
			devicePhase = Math.floor((m.tx - Math.floor(m.tx)) * 64 + 0.5);
		}
	}

	static inline function upright(m:flash.geom.Matrix):Bool return m.b == 0 && m.c == 0 && m.a > 0;

	static inline function turned(m:flash.geom.Matrix):Bool
		return turnedFit && m.b != 0 && Math.abs(m.a - m.d) < 1e-3 * Math.abs(m.a) + 1e-4
			&& Math.abs(m.b + m.c) < 1e-3 * Math.abs(m.a) + 1e-4 && m.a * m.d - m.b * m.c > 0;

	static inline function turnScale(m:flash.geom.Matrix):Float return Math.sqrt(m.a * m.a + m.b * m.b);

	static var turnedMode = Sys.getEnv("BH_PORT_TEXT_TURNED") == null ? 3 : Std.parseInt(Sys.getEnv("BH_PORT_TEXT_TURNED"));
	static var turnedFit = turnedMode != 0;

	public static function draw(tf:flash.text.TextField, g:flash.display.Graphics, ?m:flash.geom.Matrix):Void {
		var device = m != null && fitted(tf) && upright(m) && !noDevice;
		var ts = m != null && fitted(tf) && !noDevice && !device && turned(m) ? turnScale(m) : 0.0;
		g.clear();
		var w = tf.__width, h = tf.__height;
		if (tf.background) {
			g.beginFill(tf.backgroundColor & 0xFFFFFF, 1);
			g.drawRect(0, 0, w, h);
			g.endFill();
		}
		var text = tf.__text;
		if (tf.displayAsPassword) text = [for (_ in 0...text.length) tf.passwordChar].join("");
		var all = lines(tf, text);
		var sy = scrollOffset(all, tf.__scrollV);
		if (text.length > 0) {
			for (li in tf.__scrollV - 1...all.length) {
				var line = all[li];
				if (li < 0) continue;
				if (line.baseline - line.ascent - sy >= h) break;
				var ox = !device ? 0.0 : deviceMode != 1 ? Math.round(m.tx) : m.tx;
				var pen = device ? m.a * line.x + ox : ts * line.x;
				for (run in line.runs) {
					var font = run.font;
					if (font == null) continue;
					g.beginFill(run.color & 0xFFFFFF, 1);
					var scale = run.size / port.runtime.swf.SwfFont.UNITS_PER_EM;
					for (k in 0...run.codes.length) {
						var gx = run.gxs[k];
						if (device) {
							var placed = advancedPen(run.codes[k], run.format, pen, m.a);
							gx = (placed[0] - m.tx) / m.a;
							pen = placed[1];
						} else if (ts > 0 && turnedMode == 2) {
							gx = pen / ts;
							pen += advanceOf(run.codes[k], run.format) * ts;
						} else if (ts > 0 && turnedMode == 3) {
							gx = advancedPen(run.codes[k], run.format, pen, ts)[0] / ts;
							pen += advanceOf(run.codes[k], run.format) * ts;
						} else if (ts > 0) {
							var placed = advancedPen(run.codes[k], run.format, pen, ts);
							gx = placed[0] / ts;
							pen = placed[1];
						}
						var index = font.index.get(run.codes[k]);
						if (index == null) continue;
						glyph(g, font.glyphs[index], gx, line.baseline - sy, scale);
					}
					g.endFill();
				}
			}
		}
		var caret = caretPlace(tf, all, sy);
		if (caret != null) {
			g.beginFill(caret.color, 1);
			g.drawRect(caret.x, caret.y, m != null && m.a > 0 ? 1 / m.a : 1, caret.h);
			g.endFill();
		}
		if (tf.border) {
			g.lineStyle(1, tf.borderColor & 0xFFFFFF, 1);
			g.drawRect(0, 0, w - 1, h - 1);
			g.lineStyle();
		}
	}

	public static function caretOn(tf:flash.text.TextField):Bool {
		if (tf.type != flash.text.TextFieldType.INPUT || tf.stage == null || tf.stage.focus != tf) return false;
		if (tf.selectionBeginIndex != tf.selectionEndIndex) return false;
		return Std.int((haxe.Timer.stamp() - tf.__caretSince) * 2) % 2 == 0;
	}

	public static function stateKey(tf:flash.text.TextField):String {
		var b = tf.__scrollV > 1 ? "|v" + tf.__scrollV : "";
		return caretOn(tf) ? b + "|c" + tf.caretIndex : b;
	}

	static function caretPlace(tf:flash.text.TextField, all:Array<Line>, sy:Float):{x:Float, y:Float, h:Float, color:Int} {
		if (!caretOn(tf) || all.length == 0) return null;
		var index = tf.caretIndex;
		var at = 0;
		for (li in 0...all.length) {
			var line = all[li];
			var count = 0;
			for (run in line.runs) count += run.codes.length;
			if (index <= at + count) {
				var k = index - at;
				var x = line.x, color = tf.__textFormat.color == null ? 0 : tf.__textFormat.color;
				var seen = 0;
				for (run in line.runs) {
					if (k < seen + run.codes.length) {
						x = run.xs[k - seen];
						color = run.color;
						break;
					}
					x = run.xs.length > 0 ? run.xs[run.xs.length - 1] + run.ws[run.ws.length - 1] : x;
					color = run.color;
					seen += run.codes.length;
				}
				return {x: x, y: line.baseline - line.ascent - sy, h: line.ascent + line.descent, color: color & 0xFFFFFF};
			}
			at += count;
			if (at < tf.__text.length && (tf.__text.charCodeAt(at) == 10 || tf.__text.charCodeAt(at) == 13)) at++;
		}
		return null;
	}

	static function glyph(g:flash.display.Graphics, glyph:port.runtime.swf.SwfFont.Glyph, ox:Float, baseline:Float,
			scale:Float):Void {
		for (contour in glyph.contours) {
			var n = contour.length;
			if (n < 2) continue;
			var first = contour[0];
			g.moveTo(ox + first.x * scale, baseline - first.y * scale);
			var i = 1;
			while (i <= n) {
				var p = contour[i % n];
				if (p.on) {
					g.lineTo(ox + p.x * scale, baseline - p.y * scale);
					i++;
				} else {
					var q = contour[(i + 1) % n];
					g.curveTo(ox + p.x * scale, baseline - p.y * scale, ox + q.x * scale, baseline - q.y * scale);
					i += 2;
				}
			}
		}
	}

	static function fontFor(format:openfl.text.TextFormat):FontData {
		var name = format.font;
		if (name == null) return null;
		for (suffix in [" Regular", " Normal"]) if (StringTools.endsWith(name, suffix)) name = name.substr(0, name.length - suffix.length);
		var font:FontData = null;
		if (StringTools.startsWith(name, "_")) {
			if (format.bold == true && format.italic == true) port.runtime.swf.SystemFonts.ensure(name + " Bold Italic");
			if (format.bold == true) port.runtime.swf.SystemFonts.ensure(name + " Bold");
			if (format.italic == true) port.runtime.swf.SystemFonts.ensure(name + " Italic");
			port.runtime.swf.SystemFonts.ensure(name);
		}
		if (format.bold == true && format.italic == true) font = SwfFonts.layout.get(name + " Bold Italic");
		if (font == null && format.bold == true) font = SwfFonts.layout.get(name + " Bold");
		if (font == null && format.italic == true) font = SwfFonts.layout.get(name + " Italic");
		if (font == null) font = SwfFonts.layout.get(name);
		if (font == null && name != null) missing.set(name, (missing.exists(name) ? missing.get(name) : 0) + 1);
		return font;
	}

	static function formats(tf:flash.text.TextField, length:Int):Array<openfl.text.TextFormat> {
		var out:Array<openfl.text.TextFormat> = [for (_ in 0...length) tf.__textFormat];
		for (range in tf.textFormatRanges) {
			var end = range.end < length ? range.end : length;
			for (i in range.start...end) out[i] = range.format;
		}
		return out;
	}

	public static function lines(tf:flash.text.TextField, text:String):Array<Line> {
		var formats = formats(tf, text.length);
		var out:Array<Line> = [];
		var limit = tf.__width - 4;
		var wrap = tf.wordWrap;
		var y = 2.0;
		var start = 0;
		var paragraphStart = true;
		while (start <= text.length) {
			var end = start;
			while (end < text.length && text.charCodeAt(end) != 10 && text.charCodeAt(end) != 13) end++;
			var lineStart = start;
			do {
				var f0 = formats.length > 0 ? formats[lineStart < formats.length ? lineStart : formats.length - 1] : tf.__textFormat;
				var margin = num(f0.leftMargin) + num(f0.blockIndent) + (paragraphStart ? num(f0.indent) : 0);
				var room = limit - margin - num(f0.rightMargin);
				var x = 0.0;
				var lineEnd = lineStart;
				var lastSpace = -1;
				while (lineEnd < end) {
					var advance = advanceOf(text.charCodeAt(lineEnd), formats[lineEnd]);
					if (wrap && x + advance > room && lineEnd > lineStart && text.charCodeAt(lineEnd) != 32) {
						if (lastSpace > lineStart) lineEnd = lastSpace + 1;
						break;
					}
					if (text.charCodeAt(lineEnd) == 32) lastSpace = lineEnd;
					x += advance;
					lineEnd++;
				}
				var made = makeLine(text, formats, lineStart, lineEnd, margin, room, f0, tf.__textFormat, fitted(tf));
				if (lineEnd < end) made.fullWidth = made.width;
				out.push(made);
				lineStart = lineEnd;
				paragraphStart = false;
			} while (lineStart < end);
			start = end + 1;
			paragraphStart = true;
			if (end >= text.length) break;
		}
		for (line in out) {
			line.baseline = y + line.ascent;
			y += line.height;
		}
		return out;
	}

	static inline function num(v:Null<Float>):Float return v == null ? 0 : v;

	static inline function sizeOf(format:openfl.text.TextFormat):Float return format.size == null ? 12 : Std.int(format.size);

	static function metrics(format:openfl.text.TextFormat, line:Line):Void {
		var font = fontFor(format);
		var size = sizeOf(format);
		var a = font == null ? size : (font.ascentEm >= 0 ? font.ascentEm : font.ascent / port.runtime.swf.SwfFont.UNITS_PER_EM) * size;
		var d = font == null ? 0.185 * size : (font.descentEm >= 0 ? font.descentEm : font.descent / port.runtime.swf.SwfFont.UNITS_PER_EM) * size;
		a = Math.floor(a * 20 + 1e-9) / 20;
		d = Math.floor(d * 20 + 1e-9) / 20;
		var leading = num(format.leading);
		if (a > line.ascent) line.ascent = a;
		if (d > line.descent) line.descent = d;
		if (leading > line.leading) line.leading = leading;
		if (a + d + leading > line.height) line.height = a + d + leading;
	}

	static function advanceOf(code:Int, format:openfl.text.TextFormat):Float {
		var font = fontFor(format);
		var size = sizeOf(format);
		var spacing = num(format.letterSpacing);
		if (font == null) return 0;
		var index = font.index.get(code);
		if (index == null) return spacing;
		return SwfFonts.twipAdvance(font.advances[index] * size) + spacing;
	}

	static function advancedPen(code:Int, format:openfl.text.TextFormat, P:Float, scale:Float = 1):Array<Float> {
		var font = fontFor(format);
		var spacing = num(format.letterSpacing) * scale;
		if (font == null) return [P, P + spacing];
		var index = font.index.get(code);
		if (index == null) return [P, P + spacing];
		var s = sizeOf(format) * scale;
		var adv = font.advances[index];
		var zones = SwfFonts.zones.get(font.name);
		var zone = zones != null ? zones.get(code) : null;
		if (zone == null) return [P, P + adv * s + spacing];
		var x0 = zone[0], xw = zone[1];
		var f = xw == 0 ? 1.0 : Math.max(1, Math.floor(xw * s + 0.5)) / (xw * s);
		var edge = x0 * s * f;
		var pq = Math.floor(P * 8 + 0.5) / 8;
		var d = Math.floor(pq + edge) + 0.5 - (pq + edge);
		return [P + d + ADV_DX, P + adv * s * f + d + spacing];
	}

	static var deviceMode = Sys.getEnv("BH_PORT_TEXT_DEVICE") == null ? 2 : Std.parseInt(Sys.getEnv("BH_PORT_TEXT_DEVICE"));
	static var noDevice = deviceMode == 0;

	static inline var ADV_DX = 0.5;

	static inline function twipFloor(v:Float):Float return Math.floor(v * 20 + 1e-7) / 20;

	static function makeLine(text:String, formats:Array<openfl.text.TextFormat>, from:Int, to:Int, margin:Float,
			room:Float, first:openfl.text.TextFormat, fallback:openfl.text.TextFormat, advanced:Bool = false):Line {
		var line = new Line();
		var x = 0.0;
		var base = 2 + margin;
		var pen = base;
		var run:Run = null;
		var visibleEnd = to;
		while (visibleEnd > from && text.charCodeAt(visibleEnd - 1) == 32) visibleEnd--;
		var width = 0.0;
		for (i in from...to) {
			var format = formats[i];
			var font = fontFor(format);
			var size = sizeOf(format);
			metrics(format, line);
			if (run == null || run.format != format) {
				run = new Run(format, font, size, format.color == null ? 0 : format.color);
				line.runs.push(run);
			}
			run.codes.push(text.charCodeAt(i));
			run.xs.push(x);
			if (advanced) {
				var placed = advancedPen(text.charCodeAt(i), format, pen);
				run.gxs.push(placed[0] - base);
				pen = placed[1];
				var next = twipFloor(pen) - twipFloor(base);
				run.ws.push(next - x);
				x = next;
			} else {
				var advance = advanceOf(text.charCodeAt(i), format);
				run.gxs.push(x);
				run.ws.push(advance);
				x += advance;
			}
			if (i < visibleEnd) width = x;
		}
		if (from == to) {
			var format = from < formats.length ? formats[from] : (formats.length > 0 ? formats[formats.length - 1] : fallback);
			metrics(format, line);
		}
		line.width = width;
		line.fullWidth = x;
		line.margin = margin;
		var offset = 2 + margin;
		var align = first.align;
		if (width < room) {
			if (align == flash.text.TextFormatAlign.CENTER) offset += Math.round((room - width) / 2);
			else if (align == flash.text.TextFormatAlign.RIGHT || align == flash.text.TextFormatAlign.END) offset += Math.round(room - width);
		}
		for (r in line.runs) for (k in 0...r.xs.length) {
			r.xs[k] += offset;
			r.gxs[k] += offset;
		}
		line.x = offset;
		return line;
	}
}

class Line {
	public var runs:Array<Run> = [];
	public var ascent = 0.0;
	public var descent = 0.0;
	public var leading = 0.0;
	public var height = 0.0;
	public var width = 0.0;
	public var fullWidth = 0.0;
	public var margin = 0.0;
	public var x = 0.0;
	public var baseline = 0.0;

	public function new() {}
}

class Run {
	public var format:openfl.text.TextFormat;
	public var font:FontData;
	public var size:Float;
	public var color:Int;
	public var codes:Array<Int> = [];
	public var xs:Array<Float> = [];
	public var gxs:Array<Float> = [];
	public var ws:Array<Float> = [];

	public function new(format, font, size, color) {
		this.format = format;
		this.font = font;
		this.size = size;
		this.color = color;
	}
}

@:access(flash.text.TextField)
class KeySnap {
	public var key:String = null;
	var text:String;
	var width:Float;
	var height:Float;
	var wordWrap:Bool;
	var autoSize:flash.text.TextFieldAutoSize;
	var background:Bool;
	var backgroundColor:Int;
	var border:Bool;
	var borderColor:Int;
	var displayAsPassword:Bool;
	var antiAliasType:flash.text.AntiAliasType;
	var gridFitType:flash.text.GridFitType;
	var formats:Array<FormatSnap> = [];
	var starts:Array<Int> = [];
	var ends:Array<Int> = [];

	public function new() {}

	public function same(tf:flash.text.TextField):Bool {
		if (tf.__text != text || tf.__width != width || tf.__height != height || tf.wordWrap != wordWrap
			|| tf.autoSize != autoSize || tf.background != background || tf.backgroundColor != backgroundColor
			|| tf.border != border || tf.borderColor != borderColor || tf.displayAsPassword != displayAsPassword
			|| tf.antiAliasType != antiAliasType || tf.gridFitType != gridFitType)
			return false;
		var ranges = tf.textFormatRanges;
		if (ranges.length + 1 != formats.length) return false;
		if (!formats[0].same(tf.__textFormat)) return false;
		for (i in 0...ranges.length) {
			var r = ranges[i];
			if (r.start != starts[i] || r.end != ends[i] || !formats[i + 1].same(r.format)) return false;
		}
		return true;
	}

	public function take(tf:flash.text.TextField):Void {
		text = tf.__text;
		width = tf.__width;
		height = tf.__height;
		wordWrap = tf.wordWrap;
		autoSize = tf.autoSize;
		background = tf.background;
		backgroundColor = tf.backgroundColor;
		border = tf.border;
		borderColor = tf.borderColor;
		displayAsPassword = tf.displayAsPassword;
		antiAliasType = tf.antiAliasType;
		gridFitType = tf.gridFitType;
		var ranges = tf.textFormatRanges;
		while (formats.length < ranges.length + 1) formats.push(new FormatSnap());
		if (formats.length > ranges.length + 1) formats.resize(ranges.length + 1);
		formats[0].take(tf.__textFormat);
		starts.resize(ranges.length);
		ends.resize(ranges.length);
		for (i in 0...ranges.length) {
			var r = ranges[i];
			starts[i] = r.start;
			ends[i] = r.end;
			formats[i + 1].take(r.format);
		}
	}
}

class FormatSnap {
	var font:String;
	var size:Null<Int>;
	var color:Null<Int>;
	var bold:Null<Bool>;
	var italic:Null<Bool>;
	var align:flash.text.TextFormatAlign;
	var letterSpacing:Null<Float>;
	var leading:Null<Int>;
	var leftMargin:Null<Int>;
	var rightMargin:Null<Int>;
	var indent:Null<Int>;
	var blockIndent:Null<Int>;

	public function new() {}

	public inline function same(f:openfl.text.TextFormat):Bool {
		return f.font == font && f.size == size && f.color == color && f.bold == bold && f.italic == italic
			&& f.align == align && f.letterSpacing == letterSpacing && f.leading == leading && f.leftMargin == leftMargin
			&& f.rightMargin == rightMargin && f.indent == indent && f.blockIndent == blockIndent;
	}

	public function take(f:openfl.text.TextFormat):Void {
		font = f.font;
		size = f.size;
		color = f.color;
		bold = f.bold;
		italic = f.italic;
		align = f.align;
		letterSpacing = f.letterSpacing;
		leading = f.leading;
		leftMargin = f.leftMargin;
		rightMargin = f.rightMargin;
		indent = f.indent;
		blockIndent = f.blockIndent;
	}
}
