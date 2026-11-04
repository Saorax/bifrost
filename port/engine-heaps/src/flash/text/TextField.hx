package flash.text;

import openfl.text._internal.TextFormatRange;

@:access(openfl.text.TextFormat)
class TextField extends flash.display.InteractiveObject {
	public var antiAliasType:flash.text.AntiAliasType = flash.text.AntiAliasType.NORMAL;
	public var autoSize:flash.text.TextFieldAutoSize = flash.text.TextFieldAutoSize.NONE;
	public var background:Bool = false;
	public var backgroundColor:Int = 0xFFFFFF;
	public var border:Bool = false;
	public var borderColor:Int = 0x000000;
	public var bottomScrollV(get, never):Int;
	public var caretIndex:Int = 0;
	public var condenseWhite:Bool = false;
	public var defaultTextFormat(get, set):openfl.text.TextFormat;
	public var displayAsPassword:Bool = false;
	public var embedFonts:Bool = false;
	public var gridFitType:flash.text.GridFitType = flash.text.GridFitType.PIXEL;
	public var htmlText(get, set):Dynamic;
	public var length(get, never):Int;
	public var maxChars:Int = 0;
	public var maxScrollH:Int = 0;
	public var maxScrollV(get, never):Int;
	public var mouseWheelEnabled:Bool = true;
	public var multiline:Bool = false;
	public var numLines(get, never):Int;
	public var restrict:Dynamic;
	public var scrollH:Int = 0;
	public var scrollV(get, set):Int;
	public var selectable:Bool = true;
	public var selectionBeginIndex:Int = 0;
	public var selectionEndIndex:Int = 0;
	public var sharpness:Float = 0;
	public var styleSheet:flash.text.StyleSheet;
	public var text(get, set):Dynamic;
	public var textColor(get, set):Int;
	@:isVar public var textHeight(get, null):Float = 0;
	@:isVar public var textWidth(get, null):Float = 0;
	public var type:flash.text.TextFieldType = flash.text.TextFieldType.DYNAMIC;
	public var wordWrap:Bool = false;
	public var passwordChar:String = "*";

	@:noCompletion var __text:String = "";
	@:noCompletion var __htmlText:String;
	@:noCompletion var __isHTML = false;
	@:noCompletion var __textFormat:openfl.text.TextFormat;
	@:noCompletion public var textFormatRanges(default, null):openfl.Vector<TextFormatRange> = [];

	public function appendText(text:String):Void {
		if (text == null || text == "") return;
		__updateText(__text + text);
		textFormatRanges[textFormatRanges.length - 1].end = __text.length;
		selectionBeginIndex = selectionEndIndex = caretIndex = __text.length;
	}

	public function getCharBoundaries(charIndex:Int):flash.geom.Rectangle {
		__layout();
		return port.engine.text.TextLayout.charBounds(this, charIndex);
	}
	public function getCharIndexAtPoint(x:Float, y:Float):Int {
		__layout();
		return port.engine.text.TextLayout.indexAt(this, x, y, false);
	}

	public function getFirstCharInParagraph(charIndex:Int):Int {
		if (charIndex < 0 || charIndex > __text.length) return -1;
		var i = charIndex;
		while (i > 0 && !isBreak(__text.charCodeAt(i - 1))) i--;
		return i;
	}

	public function getLineIndexAtPoint(x:Float, y:Float):Int {
		__layout();
		return port.engine.text.TextLayout.lineAt(this, x, y);
	}

	public function getLineIndexOfChar(charIndex:Int):Int {
		if (charIndex < 0 || charIndex > __text.length) return -1;
		var line = 0;
		for (i in 0...charIndex) if (isBreak(__text.charCodeAt(i))) line++;
		return line;
	}

	public function getLineLength(lineIndex:Int):Int {
		var text = getLineText(lineIndex);
		return text == null ? 0 : text.length;
	}

	public function getLineMetrics(lineIndex:Int):flash.text.TextLineMetrics { return null; }

	public function getLineOffset(lineIndex:Int):Int {
		var lines = lineTexts();
		if (lineIndex < 0 || lineIndex >= lines.length) throw new flash.errors.RangeError("The supplied index is out of bounds.");
		var offset = 0;
		for (i in 0...lineIndex) offset += lines[i].length;
		return offset;
	}

	public function getLineText(lineIndex:Int):String {
		var lines = lineTexts();
		if (lineIndex < 0 || lineIndex >= lines.length) throw new flash.errors.RangeError("The supplied index is out of bounds.");
		return lines[lineIndex];
	}

	public function getParagraphLength(charIndex:Int):Int {
		var start = getFirstCharInParagraph(charIndex);
		if (start < 0) return -1;
		var end = start;
		while (end < __text.length && !isBreak(__text.charCodeAt(end))) end++;
		return end - start + (end < __text.length ? 1 : 0);
	}

	public function getTextFormat(beginIndex:Int = -1, endIndex:Int = -1):openfl.text.TextFormat {
		var format:openfl.text.TextFormat = null;
		var length = __text.length;
		if (beginIndex >= length || beginIndex < -1 || endIndex > length || endIndex < -1)
			throw new flash.errors.RangeError("The supplied index is out of bounds");
		if (beginIndex == -1) beginIndex = 0;
		if (endIndex == -1) endIndex = length;
		if (beginIndex >= endIndex) return new openfl.text.TextFormat();
		for (group in textFormatRanges) {
			if ((group.start <= beginIndex && group.end > beginIndex) || (group.start < endIndex && group.end >= endIndex)) {
				if (format == null) {
					format = group.format.clone();
				} else {
					var f = group.format;
					if (f.font != format.font) format.font = null;
					if (f.size != format.size) format.size = null;
					if (f.color != format.color) format.color = null;
					if (f.bold != format.bold) format.bold = null;
					if (f.italic != format.italic) format.italic = null;
					if (f.underline != format.underline) format.underline = null;
					if (f.url != format.url) format.url = null;
					if (f.target != format.target) format.target = null;
					if (f.align != format.align) format.align = null;
					if (f.leftMargin != format.leftMargin) format.leftMargin = null;
					if (f.rightMargin != format.rightMargin) format.rightMargin = null;
					if (f.indent != format.indent) format.indent = null;
					if (f.leading != format.leading) format.leading = null;
					if (f.blockIndent != format.blockIndent) format.blockIndent = null;
					if (f.bullet != format.bullet) format.bullet = null;
					if (f.kerning != format.kerning) format.kerning = null;
					if (f.letterSpacing != format.letterSpacing) format.letterSpacing = null;
					if (f.tabStops != format.tabStops) format.tabStops = null;
				}
			}
		}
		return format != null ? format : new openfl.text.TextFormat();
	}

	public function replaceSelectedText(value:String):Void {
		replaceText(selectionBeginIndex, selectionEndIndex, value);
	}

	public function replaceText(beginIndex:Int, endIndex:Int, newText:String):Void {
		if (newText == null) newText = "";
		var length = __text.length;
		if (endIndex < beginIndex || beginIndex < 0 || endIndex > length) return;
		var delta = newText.length - (endIndex - beginIndex);
		__updateText(__text.substring(0, beginIndex) + newText + __text.substring(endIndex));
		for (range in textFormatRanges) {
			if (range.start >= endIndex) range.start += delta;
			else if (range.start > beginIndex) range.start = beginIndex;
			if (range.end >= endIndex) range.end += delta;
			else if (range.end > beginIndex) range.end = beginIndex + newText.length;
		}
		if (textFormatRanges.length > 0) textFormatRanges[textFormatRanges.length - 1].end = __text.length;
	}

	@:noCompletion public var __caretSince:Float = 0;

	public function setSelection(beginIndex:Int, endIndex:Int):Void {
		__caretSince = haxe.Timer.stamp();
		selectionBeginIndex = beginIndex;
		selectionEndIndex = endIndex;
		caretIndex = endIndex;
	}

	public function setTextFormat(format:openfl.text.TextFormat, beginIndex:Int = -1, endIndex:Int = -1):Void {
		var max = __text.length;
		var range:TextFormatRange;
		if (beginIndex == -1) {
			if (endIndex == -1) endIndex = max;
			beginIndex = 0;
		} else if (endIndex == -1) {
			endIndex = beginIndex + 1;
		}
		if (beginIndex == endIndex) return;
		if (beginIndex < 0 || endIndex <= 0 || endIndex < beginIndex || beginIndex >= max || endIndex > max) throw new flash.errors.RangeError();
		var ranges:Array<TextFormatRange> = textFormatRanges;
		if (beginIndex == 0 && endIndex == max) {
			ranges.splice(1, ranges.length - 1);
			range = ranges[0];
			range.start = 0;
			range.end = max;
			range.format.__merge(format);
			return;
		}
		var index = 0;
		var newRange:TextFormatRange;
		while (index < ranges.length) {
			range = ranges[index];
			if (range.end <= beginIndex) {
				index++;
			} else if (range.start >= endIndex) {
				break;
			} else if (range.start <= beginIndex && range.end >= endIndex) {
				if (range.start == beginIndex && range.end == endIndex) {
					range.format = range.format.clone();
					range.format.__merge(format);
					break;
				} else if (range.start == beginIndex) {
					newRange = new TextFormatRange(range.format.clone(), beginIndex, endIndex);
					newRange.format.__merge(format);
					ranges.insert(index, newRange);
					range.start = endIndex;
					index += 2;
				} else if (range.end == endIndex) {
					newRange = new TextFormatRange(range.format.clone(), beginIndex, endIndex);
					newRange.format.__merge(format);
					ranges.insert(index + 1, newRange);
					range.end = beginIndex;
					break;
				} else {
					newRange = new TextFormatRange(range.format.clone(), beginIndex, endIndex);
					newRange.format.__merge(format);
					ranges.insert(index + 1, newRange);
					newRange = new TextFormatRange(range.format.clone(), endIndex, range.end);
					ranges.insert(index + 2, newRange);
					range.end = beginIndex;
					break;
				}
			} else if (range.start >= beginIndex && range.end <= endIndex) {
				if (range.start == beginIndex) {
					range.format = range.format.clone();
					range.format.__merge(format);
					range.end = endIndex;
				} else {
					ranges.splice(index, 1);
				}
			} else if (range.start > beginIndex && range.end > beginIndex) {
				range.start = endIndex;
				break;
			} else if (range.start < beginIndex && range.end <= endIndex) {
				newRange = new TextFormatRange(range.format.clone(), beginIndex, endIndex);
				newRange.format.__merge(format);
				ranges.insert(index + 1, newRange);
				range.end = beginIndex;
				index += 2;
			} else {
				index++;
			}
		}
	}

	function get_defaultTextFormat():openfl.text.TextFormat return __textFormat.clone();

	function set_defaultTextFormat(value:openfl.text.TextFormat):openfl.text.TextFormat {
		__textFormat.__merge(value);
		return value;
	}

	function get_htmlText():Dynamic return __isHTML ? __htmlText : __text;

	function set_htmlText(value:Dynamic):Dynamic {
		if (value == null) throw new flash.errors.Error("Error #2007: Parameter text must be non-null.", 2007);
		var html:String = Std.string(value);
		__isHTML = true;
		if (condenseWhite) html = ~/\s+/g.replace(html, " ");
		__htmlText = html;
		var plain = openfl.text._internal.HTMLParser.parse(html, multiline, styleSheet, __textFormat, textFormatRanges);
		__updateText(plain);
		return plain;
	}

	function get_length():Int return __text.length;

	function get_numLines():Int {
		__layout();
		return __lines;
	}

	@:noCompletion var __layoutKey:String = null;
	@:noCompletion var __keySnap:port.engine.text.TextLayout.KeySnap = null;
	@:noCompletion var __lines = 1;
	@:noCompletion var __lineHeights:Array<Float> = [];

	@:noCompletion var __scrollV = 1;
	@:noCompletion var __maxScrollV = 1;

	function get_scrollV():Int {
		__layout();
		return __scrollV;
	}

	function set_scrollV(value:Int):Int {
		__layout();
		if (value > __maxScrollV) value = __maxScrollV;
		if (value < 1) value = 1;
		return __scrollV = value;
	}

	function get_maxScrollV():Int {
		__layout();
		return __maxScrollV;
	}

	function get_bottomScrollV():Int {
		var first = get_scrollV();
		var room = __height - 4;
		var used = 0.0;
		var last = first;
		for (i in first - 1...__lineHeights.length) {
			if (used + __lineHeights[i] > room && i > first - 1) break;
			used += __lineHeights[i];
			last = i + 1;
		}
		return last;
	}

	function measureScroll():Void {
		var n = __lineHeights.length;
		if (n <= 1) {
			__maxScrollV = 1;
			return;
		}
		var room = Math.ceil(__height - 4);
		var i = n - 1, used = 0.0;
		while (i >= 0 && used + __lineHeights[i] <= room) {
			used += __lineHeights[i];
			i--;
		}
		var max = i == n - 1 ? n : i + 2;
		__maxScrollV = max < 1 ? 1 : max;
	}

	function get_textWidth():Float {
		__layout();
		return textWidth;
	}

	function get_textHeight():Float {
		__layout();
		return textHeight;
	}

	@:noCompletion function __layout():Void {
		var key = port.engine.text.TextLayout.key(this);
		if (key == __layoutKey) return;
		var m = port.engine.text.TextLayout.measure(this);
		textWidth = m.width;
		textHeight = m.height;
		__lines = m.lines;
		__lineHeights = m.heights;
		if (autoSize != null && autoSize != flash.text.TextFieldAutoSize.NONE) {
			if (!wordWrap) {
				var old = __width;
				__width = m.width + 4;
				if (autoSize == flash.text.TextFieldAutoSize.RIGHT) x += old - __width;
				else if (autoSize == flash.text.TextFieldAutoSize.CENTER) x += (old - __width) / 2;
			}
			__height = m.height + 4;
		}
		measureScroll();
		if (__scrollV > __maxScrollV) __scrollV = __maxScrollV;
		__layoutKey = port.engine.text.TextLayout.key(this);
	}

	@:noCompletion public function __portWheel(delta:Int):Void {
		if (mouseWheelEnabled) set_scrollV(get_scrollV() - delta);
	}

	@:noCompletion public function __portMouseDown(lx:Float, ly:Float):Void {
		if (!isInput() && !selectable) return;
		__layout();
		var at = port.engine.text.TextLayout.indexAt(this, lx, ly, true);
		setSelection(at, at);
	}

	function get_text():Dynamic return __text;

	function set_text(value:Dynamic):Dynamic {
		if (value == null) throw new flash.errors.Error("Error #2007: Parameter text must be non-null.", 2007);
		var text:String = Std.string(value);
		if (styleSheet != null) return set_htmlText(text);
		if (!__isHTML && __text == text) return text;
		if (textFormatRanges.length > 1) textFormatRanges.splice(1, textFormatRanges.length - 1);
		var range = textFormatRanges[0];
		range.format = __textFormat;
		range.start = 0;
		range.end = text.length;
		__isHTML = false;
		__updateText(text);
		return text;
	}

	function get_textColor():Int return __textFormat.color;

	function set_textColor(value:Int):Int {
		for (range in textFormatRanges) range.format.color = value;
		return __textFormat.color = value;
	}

	@:noCompletion var __width = 100.0;
	@:noCompletion var __height = 100.0;

	override function get_width():Float {
		__layout();
		var t = __transform;
		if (t.b == 0 && t.c == 0) return port.runtime.Twips.edge(__width * Math.abs(t.a));
		return port.runtime.Twips.edge(Math.abs(t.a) * __width + Math.abs(t.c) * __height);
	}

	override function set_width(value:Float):Float {
		if (value >= 0) __width = value;
		return value;
	}

	override function get_height():Float {
		__layout();
		var t = __transform;
		if (t.b == 0 && t.c == 0) return port.runtime.Twips.edge(__height * Math.abs(t.d));
		return port.runtime.Twips.edge(Math.abs(t.b) * __width + Math.abs(t.d) * __height);
	}

	override function set_height(value:Float):Float {
		if (value >= 0) __height = value;
		return value;
	}

	@:access(flash.geom.Rectangle)
	@:noCompletion override function __getBounds(rect:flash.geom.Rectangle, matrix:flash.geom.Matrix):Void {
		__layout();
		var bounds = new flash.geom.Rectangle(0, 0, __width, __height);
		var out = new flash.geom.Rectangle();
		bounds.__transform(out, matrix);
		rect.__expand(out.x, out.y, out.width, out.height);
	}

	@:noCompletion override public function __hitTest(x:Float, y:Float, lx:Float, ly:Float, shapeFlag:Bool,
			stack:Array<flash.display.DisplayObject>, interactiveOnly:Bool, hitObject:flash.display.DisplayObject):Bool {
		if (!hitObject.visible || __isMask || (interactiveOnly && !mouseEnabled)) return false;
		if (!__inMask(x, y)) return false;
		__layout();
		if (lx >= 0 && ly >= 0 && lx < __width && ly < __height) {
			if (stack != null) stack.push(hitObject);
			return true;
		}
		return false;
	}

	@:noCompletion override public function __hitTestMask(x:Float, y:Float, lx:Float, ly:Float):Bool {
		__layout();
		return lx >= 0 && ly >= 0 && lx < __width && ly < __height;
	}

	@:noCompletion override public function __allowMouseFocus():Bool {
		return mouseEnabled;
	}

	@:noCompletion override function __tabDefault():Bool {
		return type == flash.text.TextFieldType.INPUT;
	}

	inline function isInput():Bool {
		return type == flash.text.TextFieldType.INPUT;
	}

	@:noCompletion public function __portTextInput(value:String):Void {
		if (!isInput() || value == null || value == "" || value.charCodeAt(0) < 32 || value.charCodeAt(0) == 127) return;
		var event = new flash.events.TextEvent(flash.events.TextEvent.TEXT_INPUT, true, true, value);
		dispatchEvent(event);
		if (event.isDefaultPrevented()) return;
		if (__insert(value)) dispatchEvent(new flash.events.Event(flash.events.Event.CHANGE, true));
	}

	@:noCompletion public function __portKeyDown(keyCode:Int, ctrl:Bool, shift:Bool):Void {
		if (!isInput()) return;
		var begin = selectionBeginIndex < selectionEndIndex ? selectionBeginIndex : selectionEndIndex;
		var end = selectionBeginIndex < selectionEndIndex ? selectionEndIndex : selectionBeginIndex;
		function move(to:Int) {
			if (to < 0) to = 0;
			if (to > __text.length) to = __text.length;
			var anchor = caretIndex == selectionEndIndex ? selectionBeginIndex : selectionEndIndex;
			if (shift) setSelection(anchor, to) else setSelection(to, to);
		}
		switch (keyCode) {
			case 8 | 46:
				if (begin == end) {
					if (keyCode == 8 && begin > 0) begin--;
					else if (keyCode == 46 && end < __text.length) end++;
				}
				if (begin != end) {
					replaceText(begin, end, "");
					setSelection(begin, begin);
					dispatchEvent(new flash.events.Event(flash.events.Event.CHANGE, true));
				}
			case 37: move(!shift && begin != end ? begin : caretIndex - 1);
			case 39: move(!shift && begin != end ? end : caretIndex + 1);
			case 36 | 38: move(0);
			case 35 | 40: move(__text.length);
			case 13:
				if (multiline) {
					var event = new flash.events.TextEvent(flash.events.TextEvent.TEXT_INPUT, true, true, "\n");
					dispatchEvent(event);
					if (!event.isDefaultPrevented() && __insert("\n")) dispatchEvent(new flash.events.Event(flash.events.Event.CHANGE, true));
				}
			case 65 if (ctrl):
				setSelection(0, __text.length);
			case 67 | 88 if (ctrl && begin != end && !displayAsPassword):
				hxd.System.setClipboardText(__text.substring(begin, end));
				if (keyCode == 88) {
					replaceText(begin, end, "");
					setSelection(begin, begin);
					dispatchEvent(new flash.events.Event(flash.events.Event.CHANGE, true));
				}
			case 86 if (ctrl):
				__paste();
			default:
		}
	}

	function __paste():Void {
		var value = hxd.System.getClipboardText();
		if (value == null) return;
		value = value.split("\r\n").join("\n").split("\r").join("\n");
		if (!multiline) value = StringTools.trim(value.split("\n").join(" "));
		value = [for (i in 0...value.length) if (value.charCodeAt(i) >= 32 && value.charCodeAt(i) != 127 || multiline && value.charAt(i) == "\n") value.charAt(i)].join("");
		if (value == "") return;
		var event = new flash.events.TextEvent(flash.events.TextEvent.TEXT_INPUT, true, true, value);
		dispatchEvent(event);
		if (event.isDefaultPrevented()) return;
		if (__insert(value)) dispatchEvent(new flash.events.Event(flash.events.Event.CHANGE, true));
	}

	function __insert(value:String):Bool {
		var begin = selectionBeginIndex < selectionEndIndex ? selectionBeginIndex : selectionEndIndex;
		var end = selectionBeginIndex < selectionEndIndex ? selectionEndIndex : selectionBeginIndex;
		if (begin > __text.length) begin = __text.length;
		if (end > __text.length) end = __text.length;
		if (begin == end && maxChars > 0 && __text.length >= maxChars) return false;
		value = [for (i in 0...value.length) if (allowed(restrict, value.charAt(i))) value.charAt(i)].join("");
		if (maxChars > 0) {
			var room = maxChars - __text.length + (end - begin);
			if (room <= 0) value = "" else if (room < value.length) value = value.substr(0, room);
		}
		if (value == "" && begin == end) return false;
		replaceText(begin, end, value);
		setSelection(begin + value.length, begin + value.length);
		return true;
	}

	@:noCompletion public static function allowed(restrict:Dynamic, c:String):Bool {
		if (restrict == null) return true;
		var r:String = Std.string(restrict);
		if (r == "") return false;
		var result = r.charAt(0) == "^";
		var include = true;
		var i = 0;
		while (i < r.length) {
			var ch = r.charAt(i);
			if (ch == "^") {
				include = !include;
				i++;
				continue;
			}
			if (ch == "\\" && i + 1 < r.length) ch = r.charAt(++i);
			var hi = ch;
			if (i + 2 < r.length && r.charAt(i + 1) == "-") {
				i += 2;
				hi = r.charAt(i);
				if (hi == "\\" && i + 1 < r.length) hi = r.charAt(++i);
			}
			if (c >= ch && c <= hi) result = include;
			i++;
		}
		return result;
	}

	@:noCompletion function __updateText(value:String):Void {
		__text = value;
		if (maxChars > 0 && __text.length > maxChars) __text = __text.substr(0, maxChars);
		if (caretIndex > __text.length) caretIndex = __text.length;
		if (selectionBeginIndex > __text.length) selectionBeginIndex = __text.length;
		if (selectionEndIndex > __text.length) selectionEndIndex = __text.length;
	}

	static inline function isBreak(code:Null<Int>):Bool return code == 10 || code == 13;

	function lineTexts():Array<String> {
		var lines = [];
		var start = 0;
		for (i in 0...__text.length) {
			if (isBreak(__text.charCodeAt(i))) {
				lines.push(__text.substring(start, i + 1));
				start = i + 1;
			}
		}
		lines.push(__text.substring(start));
		return lines;
	}

	public function new() {
		super();
		var format = new openfl.text.TextFormat("Times New Roman", 12, 0x000000, false, false, false, "", "",
			flash.text.TextFormatAlign.LEFT, 0, 0, 0, 0);
		format.blockIndent = 0;
		format.bullet = false;
		format.letterSpacing = 0;
		format.kerning = false;
		__textFormat = format;
		textFormatRanges.push(new TextFormatRange(__textFormat, 0, 0));
	}
}
