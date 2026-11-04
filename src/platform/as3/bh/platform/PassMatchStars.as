package bh.platform
{
   import flash.display.DisplayObject;
   import flash.utils.getTimer;

   public final class PassMatchStars
   {
      private static const SETTLE_MS:int = 700;
      private static const GIVE_UP_MS:int = 15000;

      private static var shownAt:int = -1;
      private static var quietSince:int = -1;
      private static var done:Boolean = false;

      public function PassMatchStars()
      {
      }

      public static function init() : void
      {
         Hooks.frameRendering.add(tick);
      }

      private static function tick() : void
      {
         try
         {
            var page:Object = ScreenManager.var_12129;
            if(page == null || !page.isActive || !class_393.var_8974)
            {
               shownAt = -1;
               done = false;
               return;
            }
            var now:int = getTimer();
            if(shownAt < 0)
            {
               shownAt = now;
               quietSince = -1;
            }
            if(done)
            {
               return;
            }
            if(!quiet(page) && now - shownAt < GIVE_UP_MS || popup())
            {
               quietSince = -1;
               return;
            }
            if(quietSince < 0)
            {
               quietSince = now;
            }
            if(now - quietSince < SETTLE_MS)
            {
               return;
            }
            done = true;
            fly();
         }
         catch(e:Error)
         {
            done = true;
            Platform.log("pass match stars: " + e);
         }
      }

      private static function popup() : Boolean
      {
         return ScreenManager.var_8391 != null && ScreenManager.var_8391.isActive ||
                ScreenManager.var_638 != null && ScreenManager.var_638.isActive;
      }

      private static function quiet(page:Object) : Boolean
      {
         if(class_398.method_3411())
         {
            return false;
         }
         for each(var list:Object in [page.var_2937,page.var_10604,page.var_1071])
         {
            if(list == null || list.var_14219 == null)
            {
               continue;
            }
            for each(var row:Object in list.var_14219)
            {
               if(row != null && row.var_11559 && row.var_6725 < 1)
               {
                  return false;
               }
            }
         }
         return true;
      }

      private static function fly() : void
      {
         var c:Object = ScreenManager.owner.var_12029;
         var bar:Object = ScreenManager.var_8969;
         if(c == null || bar == null || class_375.var_13238)
         {
            return;
         }
         var gained:int = int(c.var_10477) - int(c.var_13962);
         var n:int = gained - int(class_375.var_14176);
         if(n <= 0)
         {
            return;
         }
         var from:DisplayObject = bar.var_2288 as DisplayObject;
         if(from == null || from.stage == null)
         {
            from = bar.var_2459 != null ? bar.var_2459.clip as DisplayObject : null;
         }
         if(from == null)
         {
            return;
         }
         var path:uint = c.var_7060;
         var tier:uint = c.method_707(path);
         var max:uint = class_25.method_8846(path,c.var_6800);
         if(path == c.var_5683 && tier == max)
         {
            return;
         }
         var star:uint = c.var_13962 % 12;
         var pos:uint = star + tier * 12;
         var end:uint = max * 12;
         if(end < pos)
         {
            return;
         }
         class_377.var_11721 = 0;
         var skip:uint = class_375.var_14176;
         while(skip > 0)
         {
            if(pos + skip < end)
            {
               pos += skip;
               tier = uint(int(pos / 12));
               star = pos % 12;
               break;
            }
            if(path == c.var_5683)
            {
               return;
            }
            skip -= end - pos;
            var next:uint = nextPath(c,path);
            if(next == path)
            {
               return;
            }
            path = next;
            tier = c.method_707(path);
            max = class_25.method_8846(path,c.var_6800);
            star = 0;
            pos = tier * 12;
            end = max * 12;
         }
         if(tier == max)
         {
            return;
         }
         Platform.log("pass match stars: " + n + " (gained " + gained + ", " + class_375.var_14176 + " from quests)");
         for(var i:int = 0; i < n; i++)
         {
            var last:Boolean = false;
            star++;
            if(star >= 12)
            {
               tier++;
               star = 0;
               if(tier >= max)
               {
                  if(path == c.var_5683)
                  {
                     star = 12;
                     last = true;
                  }
                  else
                  {
                     next = nextPath(c,path);
                     if(next == path)
                     {
                        return;
                     }
                     path = next;
                     tier = c.method_707(path);
                     max = class_25.method_8846(path,c.var_6800);
                  }
               }
            }
            bar.method_7968(from,340 + Math.random() * 80,-320 + Math.random() * 80,1.32,0.54,800,star,path,tier);
            ++class_375.var_14176;
            if(last)
            {
               return;
            }
         }
      }

      private static function nextPath(c:Object, full:uint) : uint
      {
         class_377.var_11721 |= 1 << full;
         var last:uint = uint(class_25.var_8404.method_4935(c.var_6800));
         if(c.var_5683 < last)
         {
            return c.var_5683;
         }
         for(var p:int = 0; p < last + 1; p++)
         {
            if(uint(p) != full && (class_377.var_11721 & 1 << p) == 0 && c.method_707(p) < class_25.method_8846(p,c.var_6800))
            {
               return p;
            }
         }
         return full;
      }
   }
}
