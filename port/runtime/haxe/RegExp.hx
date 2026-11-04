package;

#if flash
typedef RegExp = flash.utils.RegExp;
#else
class RegExp {
   final ereg:EReg;
   public var global:Bool;
   public var lastIndex:Int = 0;

   public function new(pattern:String, flags:String = "") {
      ereg = new EReg(pattern, flags);
      global = flags.indexOf("g") >= 0;
   }

   public function test(text:String):Bool {
      return exec(text) != null;
   }

   public function exec(text:String):Array<Dynamic> {
      var from = global ? lastIndex : 0;
      if(from < 0 || from > text.length || !ereg.matchSub(text, from)) {
         if(global) lastIndex = 0;
         return null;
      }
      var pos = ereg.matchedPos();
      if(global) {
         lastIndex = pos.pos + pos.len;
      }
      var out = groups();
      #if hl
      var match:RegExpMatch = cast out;
      match.index = pos.pos;
      match.input = text;
      #end
      return out;
   }

   public function matchAll(text:String):Array<Dynamic> {
      var out:Array<Dynamic> = [];
      var from = 0;
      while(from <= text.length && ereg.matchSub(text, from)) {
         var pos = ereg.matchedPos();
         out.push(ereg.matched(0));
         from = pos.len == 0 ? pos.pos + 1 : pos.pos + pos.len;
      }
      lastIndex = 0;
      return out.length == 0 ? null : out;
   }

   public function splitText(text:String):Array<Dynamic> {
      var out:Array<Dynamic> = [];
      var from = 0, last = 0;
      while(from <= text.length && ereg.matchSub(text, from)) {
         var pos = ereg.matchedPos();
         if(pos.len == 0) {
            from = pos.pos + 1;
            continue;
         }
         out.push(text.substring(last, pos.pos));
         var index = 1;
         while(true) {
            try {
               out.push(ereg.matched(index));
               index++;
            } catch(e:Dynamic) {
               break;
            }
         }
         last = from = pos.pos + pos.len;
      }
      out.push(text.substring(last));
      return out;
   }

   function groups():Array<Dynamic> {
      var out:Array<Dynamic> = #if hl cast new RegExpMatch() #else [] #end;
      out.push(ereg.matched(0));
      var index:Int = 1;
      while(true) {
         try {
            out.push(ereg.matched(index));
            index++;
         } catch(e:Dynamic) {
            break;
         }
      }
      return out;
   }

   public function replace(text:String, by:String):String {
      return ereg.replace(text, by);
   }
}

#if hl
class RegExpMatch extends hl.types.ArrayDyn {
   public var index:Int = 0;
   public var input:String;

   public function new() {
      super();
   }
}
#end
#end
