package port.runtime;

#if flash
@:native("String") extern class NativeString {
	static function fromCharCode(code:Dynamic):String;
}
#else
class NativeString {
	public static inline function fromCharCode(code:Dynamic):String {
		return String.fromCharCode(As3.toInt(code) & 0xFFFF);
	}
}
#end
