package bh.platform
{
   import flash.utils.Dictionary;

   public final class Palette
   {
      private static var table:Dictionary = new Dictionary();

      private static var cache:Object = {};

      private static var active:Boolean = false;

      public function Palette()
      {
      }

      public static function add(palette:Object) : int
      {
         var n:int = 0;
         if(palette == null || palette.colours == null)
         {
            return 0;
         }
         for(var key:String in palette.colours)
         {
            var e:* = palette.colours[key];
            if(!(e is Array) || e.length != 4)
            {
               continue;
            }
            var colour:uint = uint(parseInt(key,16));
            if(table[colour] == null)
            {
               table[colour] = [uint(parseInt(String(e[0]),16)),Number(e[1]),Number(e[2]),Number(e[3])];
               n++;
            }
         }
         active = active || n > 0;
         return n;
      }

      public static function swap(colour:uint, condition:uint, map:Object) : uint
      {
         if(!active)
         {
            return 0;
         }
         var e:Array = table[colour];
         if(e == null)
         {
            return 0;
         }
         var h:Object = map.h;
         var key:uint = colour | uint(condition << 24);
         if(uint(h[key]) != 0 || uint(h[colour]) != 0)
         {
            return 0;
         }
         var anchor:uint = e[0];
         var target:uint = uint(h[anchor | uint(condition << 24)]);
         if(target == 0)
         {
            target = uint(h[anchor]);
         }
         if(target == 0)
         {
            return 0;
         }
         var ck:String = colour + ":" + target;
         var done:* = cache[ck];
         if(done != null)
         {
            return uint(done);
         }
         var t:Array = toHls(target);
         var hue:Number = t[0] + Number(e[1]);
         hue -= Math.floor(hue);
         var result:uint = fromHls(hue,clamp(t[1] + Number(e[2])),clamp(t[2] + Number(e[3])));
         if(result == 0)
         {
            result = 0x010101;
         }
         cache[ck] = result;
         return result;
      }

      private static function clamp(v:Number) : Number
      {
         return v < 0 ? 0 : (v > 1 ? 1 : v);
      }

      private static function toHls(c:uint) : Array
      {
         var r:Number = ((c >> 16) & 0xFF) / 255;
         var g:Number = ((c >> 8) & 0xFF) / 255;
         var b:Number = (c & 0xFF) / 255;
         var max:Number = Math.max(r,g,b);
         var min:Number = Math.min(r,g,b);
         var l:Number = (max + min) / 2;
         if(max == min)
         {
            return [0,l,0];
         }
         var d:Number = max - min;
         var s:Number = l <= 0.5 ? d / (max + min) : d / (2 - max - min);
         var hue:Number;
         if(max == r)
         {
            hue = (g - b) / d + (g < b ? 6 : 0);
         }
         else if(max == g)
         {
            hue = (b - r) / d + 2;
         }
         else
         {
            hue = (r - g) / d + 4;
         }
         return [hue / 6,l,s];
      }

      private static function fromHls(h:Number, l:Number, s:Number) : uint
      {
         if(s == 0)
         {
            var v:uint = uint(Math.round(l * 255));
            return v << 16 | v << 8 | v;
         }
         var q:Number = l < 0.5 ? l * (1 + s) : l + s - l * s;
         var p:Number = 2 * l - q;
         var r:uint = uint(Math.round(channel(p,q,h + 1 / 3) * 255));
         var g:uint = uint(Math.round(channel(p,q,h) * 255));
         var b:uint = uint(Math.round(channel(p,q,h - 1 / 3) * 255));
         return r << 16 | g << 8 | b;
      }

      private static function channel(p:Number, q:Number, t:Number) : Number
      {
         if(t < 0)
         {
            t += 1;
         }
         if(t > 1)
         {
            t -= 1;
         }
         if(t < 1 / 6)
         {
            return p + (q - p) * 6 * t;
         }
         if(t < 1 / 2)
         {
            return q;
         }
         if(t < 2 / 3)
         {
            return p + (q - p) * (2 / 3 - t) * 6;
         }
         return p;
      }
   }
}
