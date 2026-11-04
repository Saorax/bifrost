package;

extern class Date {
   public var time:Float;
   public var fullYear:Int;
   public var month:Int;
   public var date:Int;
   public var hours:Int;
   public var minutes:Int;
   public var seconds:Int;
   public var milliseconds:Int;

   public function new(?year:Int, ?month:Int, ?day:Int, ?hour:Int, ?min:Int, ?sec:Int):Void;
   public static function now():Date;
   public static function fromString(value:String):Date;
   public static function fromTime(value:Float):Date;
   public function getTime():Float;
   public function getFullYear():Int;
   public function getMonth():Int;
   public function getDate():Int;
   public function getHours():Int;
   public function getMinutes():Int;
   public function getSeconds():Int;
   public function getMilliseconds():Int;
   public function toString():String;
   public function toUTCString():String;
   public function toLocaleString():String;
   public function toLocaleTimeString():String;
   public function toTimeString():String;
}
