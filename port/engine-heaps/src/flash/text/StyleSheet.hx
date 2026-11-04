package flash.text;

class StyleSheet extends flash.events.EventDispatcher {
	public var styleNames:Array<String> = [];
	public function clear():Void {}
	public function getStyle(styleName:String):flash.utils.Object { return cast null; }
	public function parseCSS(CSSText:String):Void {}
	public function setStyle(styleName:String, styleObject:flash.utils.Object):Void {}
	public function transform(formatObject:flash.utils.Object):openfl.text.TextFormat { return cast null; }
	@:noCompletion function __applyStyle(name:String, format:openfl.text.TextFormat):Void {}
	public function new() { super(); }
}
