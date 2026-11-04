package bh.platform
{
   public final class MissionRewards
   {
      public function MissionRewards()
      {
      }

      public static function init() : void
      {
         Hooks.frameStarting.add(clearGold);
         Hooks.frameRendering.add(hideHubCoins);
      }

      private static function hideHubCoins() : void
      {
         try
         {
            var hub:Object = ScreenManager.var_8315;
            if(hub == null || !hub.isActive || hub.var_11448 == null)
            {
               return;
            }
            for each(var row:Object in hub.var_11448)
            {
               var d:Object = row.mData;
               if(d != null && d.var_12439 != 0 && d.var_11078 == 0 && row.var_5687 != null)
               {
                  row.var_5687.method_397(false);
                  row.var_11078.method_397(false);
               }
            }
         }
         catch(e:Error)
         {
         }
      }

      private static function clearGold() : void
      {
         var table:Object = class_276.var_230;
         if(table == null || table.h == null)
         {
            return;
         }
         var n:int = 0;
         for each(var m:Object in table.h)
         {
            n++;
            if(m != null)
            {
               m.var_2723 = 0;
            }
         }
         if(n == 0)
         {
            return;
         }
         Hooks.frameStarting.remove(clearGold);
         Platform.log("missions: gold rewards cleared on " + n + " missions");
      }
   }
}
