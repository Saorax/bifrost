package bh.platform
{
   public final class Ranks
   {
      public static const VALHALLAN_AT:uint = 3000;

      public function Ranks()
      {
      }

      public static function steps() : Vector.<uint>
      {
         var v:Vector.<uint> = Vector.<uint>([0,1,0,100,200,300,400]);
         for(var t:int = 1; t < 6; t++)
         {
            v.push(500 * t - 100);
            for(var k:int = 0; k < 5; k++)
            {
               v.push(500 * t + 100 * k);
            }
         }
         return v;
      }

      public static const RANKED_MODES:Array = ["1v1StockRanked","TeamStockRanked"];

      public static function init() : void
      {
         try
         {
            class_189.var_2469 = steps();
            class_189.var_11921 = int(class_189.var_2469.length);
         }
         catch(e:Error)
         {
            Platform.log("ranks: could not set the rank steps (" + e.message + ")");
         }
         Hooks.frameStarting.add(applyRankedRules);
      }

      private static function applyRankedRules() : void
      {
         if(class_163.var_12703 == null || class_163.method_7804(RANKED_MODES[0]) == null)
         {
            return;
         }
         Hooks.frameStarting.remove(applyRankedRules);
         rankedRules();
         Hooks.frameStarting.add(warmUpRules);
      }

      private static var warmUp:Object = null;
      private static var warmUpItems:Object = null;
      private static var warmUpRanked:Boolean = false;

      private static function warmUpRules() : void
      {
         try
         {
            if(warmUp == null)
            {
               warmUp = class_163.method_7804("TrainingModeQueue");
               if(warmUp == null)
               {
                  Hooks.frameStarting.remove(warmUpRules);
                  return;
               }
               warmUpItems = warmUp.var_139;
            }
            var core:Object = ScreenManager.owner;
            var pl:Object = core != null && core.var_6244 != null ? core.var_6244.var_2390 : null;
            var ranked:Boolean = pl != null && pl.var_9135;
            if(ranked != warmUpRanked)
            {
               warmUpRanked = ranked;
               warmUp.var_139 = ranked ? "StandardNoGadgets" : warmUpItems;
               Platform.log("ranks: the queue's warm-up plays with " + warmUp.var_139 + (ranked ? " (ranked queue)" : ""));
            }
         }
         catch(e:Error)
         {
         }
      }

      private static function rankedRules() : void
      {
         for each(var name:String in RANKED_MODES)
         {
            try
            {
               var row:Object = class_163.method_7804(name);
               if(row == null)
               {
                  continue;
               }
               if(row.var_9821)
               {
                  row.var_11695 = row.var_9821;
               }
               row.var_139 = "StandardNoGadgets";
               Platform.log("ranks: " + name + " plays " + row.var_11695 + " with " + row.var_139);
            }
            catch(e:Error)
            {
               Platform.log("ranks: " + name + ": " + e.message);
            }
         }
      }

      public static function tierNumber(rating:int) : int
      {
         if(rating < 0 || rating >= int(VALHALLAN_AT))
         {
            return 0;
         }
         var stars:uint = class_189.method_5563(uint(Math.max(1,rating)));
         return stars == 0 ? 0 : 6 - int(class_189.method_1542(stars));
      }
   }
}
