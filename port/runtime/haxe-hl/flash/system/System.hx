package flash.system;

class System {
   public static var totalMemory(get, never):Int;
   public static var totalMemoryNumber(get, never):Float;
   public static var privateMemory(get, never):Float;
   public static var freeMemory(get, never):Float;
   public static var useCodePage(get, set):Bool;
   public static var vmVersion(get, never):String;

   static function get_totalMemory():Int return openfl.system.System.totalMemory;
   static function get_totalMemoryNumber():Float return openfl.system.System.totalMemoryNumber;
   static function get_privateMemory():Float return hl.Gc.stats().currentMemory;
   static function get_freeMemory():Float return Math.max(0, hl.Gc.stats().currentMemory - totalMemoryNumber);
   static function get_useCodePage():Bool return openfl.system.System.useCodePage;
   static function set_useCodePage(value:Bool):Bool return openfl.system.System.useCodePage = value;
   static function get_vmVersion():String return openfl.system.System.vmVersion;

   public static function exit(code:Int):Void openfl.system.System.exit(code);
   public static var gcCalls(default, null):Int = 0;
   public static var gcPauseCalls(default, null):Int = 0;

   static function noteCall(kind:String):Void {
      if (gcCalls + gcPauseCalls <= 3)
         port.runtime.NativeMain.log(kind + " from " + haxe.CallStack.toString(haxe.CallStack.callStack()).split("\n").slice(0, 6).join(" < "));
   }

   public static function gc():Void {
      gcCalls++;
      noteCall("System.gc");
      openfl.system.System.gc();
   }
   public static function pause():Void openfl.system.System.pause();
   public static function resume():Void openfl.system.System.resume();
   public static function setClipboard(string:String):Void openfl.system.System.setClipboard(string);
   public static function disposeXML(node:Dynamic):Void {}

   public static function pauseForGCIfCollectionImminent(imminence:Float = 0.75):Void {
      gcPauseCalls++;
      noteCall("pauseForGCIfCollectionImminent(" + imminence + ")");
      if (imminence < 0.5) {
         hl.Gc.major();
      }
   }
}
