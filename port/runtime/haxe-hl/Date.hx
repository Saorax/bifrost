package;

#if macro
extern class Date {
   function new(year:Int, month:Int, day:Int, hour:Int, min:Int, sec:Int):Void;
   function getTime():Float;
   function getHours():Int;
   function getMinutes():Int;
   function getSeconds():Int;
   function getFullYear():Int;
   function getMonth():Int;
   function getDate():Int;
   function getDay():Int;
   function getUTCHours():Int;
   function getUTCMinutes():Int;
   function getUTCSeconds():Int;
   function getUTCFullYear():Int;
   function getUTCMonth():Int;
   function getUTCDate():Int;
   function getUTCDay():Int;
   function getTimezoneOffset():Int;
   function toString():String;
   static function now():Date;
   static function fromTime(t:Float):Date;
   static function fromString(s:String):Date;
}
#else
import hl.Ref;

final class Date {
   var ms:Float;

   public var time(get, set):Float;
   public var fullYear(get, set):Int;
   public var month(get, set):Int;
   public var date(get, set):Int;
   public var day(get, never):Int;
   public var hours(get, set):Int;
   public var minutes(get, set):Int;
   public var seconds(get, set):Int;
   public var milliseconds(get, set):Int;
   public var timezoneOffset(get, never):Int;

   public function new(?year:Dynamic, ?month:Dynamic, ?day:Dynamic, ?hour:Dynamic, ?min:Dynamic, ?sec:Dynamic,
         ?millis:Dynamic):Void {
      if (year == null) {
         ms = nowMs();
      } else if (month == null) {
         if (Std.isOfType(year, String)) {
            ms = parse(year);
         } else {
            ms = (year : Float);
         }
      } else {
         ms = local(Std.int(year), Std.int(month), day == null ? 1 : Std.int(day), hour == null ? 0 : Std.int(hour),
            min == null ? 0 : Std.int(min), sec == null ? 0 : Std.int(sec), millis == null ? 0 : (millis : Float));
      }
   }

   static function nowMs():Float {
      return Math.ffloor(Sys.time() * 1000);
   }

   static function local(year:Int, month:Int, day:Int, hour:Int, min:Int, sec:Int, millis:Float):Float {
      var extra = Math.floor(millis / 1000);
      return date_get_time(date_new(year, month, day, hour, min, sec + extra)) + (millis - extra * 1000);
   }

   static function parse(value:String):Float {
      var t = date_from_string(@:privateAccess value.bytes, value.length << 1);
      return date_get_time(t);
   }

   inline function seconds32():Int {
      return date_from_time(ms);
   }

   function field(index:Int):Int {
      var y = 0, mo = 0, d = 0, h = 0, mi = 0, s = 0, wd = 0;
      date_get_inf(seconds32(), y, mo, d, h, mi, s, wd);
      return switch (index) {
         case 0: y;
         case 1: mo;
         case 2: d;
         case 3: h;
         case 4: mi;
         case 5: s;
         default: wd;
      }
   }

   function withField(index:Int, value:Int):Int {
      var y = 0, mo = 0, d = 0, h = 0, mi = 0, s = 0;
      date_get_inf(seconds32(), y, mo, d, h, mi, s, null);
      switch (index) {
         case 0: y = value;
         case 1: mo = value;
         case 2: d = value;
         case 3: h = value;
         case 4: mi = value;
         default: s = value;
      }
      ms = local(y, mo, d, h, mi, s, get_milliseconds());
      return value;
   }

   function get_time():Float return ms;
   function set_time(value:Float):Float return ms = value;
   function get_fullYear():Int return field(0);
   function set_fullYear(value:Int):Int return withField(0, value);
   function get_month():Int return field(1);
   function set_month(value:Int):Int return withField(1, value);
   function get_date():Int return field(2);
   function set_date(value:Int):Int return withField(2, value);
   function get_day():Int return field(6);
   function get_hours():Int return field(3);
   function set_hours(value:Int):Int return withField(3, value);
   function get_minutes():Int return field(4);
   function set_minutes(value:Int):Int return withField(4, value);
   function get_seconds():Int return field(5);
   function set_seconds(value:Int):Int return withField(5, value);

   function get_milliseconds():Int {
      return Std.int(ms - Math.ffloor(ms / 1000) * 1000);
   }

   function set_milliseconds(value:Int):Int {
      ms = Math.ffloor(ms / 1000) * 1000 + value;
      return value;
   }

   function get_timezoneOffset():Int return getTimezoneOffset();


   public function getTime():Float return ms;
   public function getFullYear():Int return field(0);
   public function getMonth():Int return field(1);
   public function getDate():Int return field(2);
   public function getHours():Int return field(3);
   public function getMinutes():Int return field(4);
   public function getSeconds():Int return field(5);
   public function getDay():Int return field(6);
   public function getMilliseconds():Int return get_milliseconds();

   function utcField(index:Int):Int {
      var y = 0, mo = 0, d = 0, h = 0, mi = 0, s = 0, wd = 0;
      date_get_utc_inf(seconds32(), y, mo, d, h, mi, s, wd);
      return switch (index) {
         case 0: y;
         case 1: mo;
         case 2: d;
         case 3: h;
         case 4: mi;
         case 5: s;
         default: wd;
      }
   }

   public function getUTCFullYear():Int return utcField(0);
   public function getUTCMonth():Int return utcField(1);
   public function getUTCDate():Int return utcField(2);
   public function getUTCHours():Int return utcField(3);
   public function getUTCMinutes():Int return utcField(4);
   public function getUTCSeconds():Int return utcField(5);
   public function getUTCDay():Int return utcField(6);

   public function getTimezoneOffset():Int {
      var y = 0, mo = 0, d = 0, h = 0, m = 0, s = 0;
      var t = seconds32();
      date_get_utc_inf(t, y, mo, d, h, m, s, null);
      return Std.int((date_new(y, mo, d, h, m, s) - t) / 60);
   }

   @:keep public function toString():String {
      var outLen = 0;
      var bytes = date_to_string(seconds32(), outLen);
      return @:privateAccess String.__alloc__(bytes, outLen);
   }

   static final DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
   static final MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

   static inline function two(value:Int):String {
      return value < 10 ? "0" + value : "" + value;
   }

   function clock(h:Int, m:Int, s:Int):String {
      return two(h) + ":" + two(m) + ":" + two(s);
   }

   function clock12():String {
      var h = field(3);
      var hour12 = h % 12 == 0 ? 12 : h % 12;
      return clock(hour12, field(4), field(5)) + (h < 12 ? " AM" : " PM");
   }

   function zone():String {
      var offset = -getTimezoneOffset();
      var sign = offset < 0 ? "-" : "+";
      offset = offset < 0 ? -offset : offset;
      return "GMT" + sign + two(Std.int(offset / 60)) + two(offset % 60);
   }

   public function toUTCString():String {
      return DAYS[utcField(6)] + " " + MONTHS[utcField(1)] + " " + utcField(2) + " "
         + clock(utcField(3), utcField(4), utcField(5)) + " " + utcField(0) + " UTC";
   }

   public function toLocaleString():String {
      return DAYS[field(6)] + " " + MONTHS[field(1)] + " " + field(2) + " " + field(0) + " " + clock12();
   }

   public function toLocaleTimeString():String {
      return clock12();
   }

   public function toTimeString():String {
      return clock(field(3), field(4), field(5)) + " " + zone();
   }

   public static function now():Date {
      return fromTime(nowMs());
   }

   static function fromInt(t:Int):Date {
      return fromTime(date_get_time(t));
   }

   public static function fromTime(t:Float):Date {
      var d:Date = untyped $new(Date);
      d.ms = t;
      return d;
   }

   public static function fromString(s:String):Date {
      return fromTime(parse(s));
   }

   @:hlNative("std", "date_new")
   static function date_new(year:Int, month:Int, day:Int, hours:Int, minutes:Int, seconds:Int):Int {
      return 0;
   }

   @:hlNative("std", "date_from_time")
   static function date_from_time(t:Float):Int {
      return 0;
   }

   @:hlNative("std", "date_from_string")
   static function date_from_string(b:hl.Bytes, len:Int):Int {
      return 0;
   }

   @:hlNative("std", "date_get_time")
   static function date_get_time(t:Int):Float {
      return 0.;
   }

   @:hlNative("std", "date_get_inf")
   static function date_get_inf(t:Int, year:Ref<Int>, month:Ref<Int>, day:Ref<Int>, hours:Ref<Int>, minutes:Ref<Int>,
      seconds:Ref<Int>, wday:Ref<Int>):Void {}

   @:hlNative("std", "date_get_utc_inf")
   static function date_get_utc_inf(t:Int, year:Ref<Int>, month:Ref<Int>, day:Ref<Int>, hours:Ref<Int>,
      minutes:Ref<Int>, seconds:Ref<Int>, wday:Ref<Int>):Void {}

   @:hlNative("std", "date_to_string")
   static function date_to_string(t:Int, outLen:Ref<Int>):hl.Bytes {
      return null;
   }
}
#end
