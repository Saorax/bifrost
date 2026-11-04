package bh.platform
{
   public final class ReducedFlashes
   {
      private static const RESPAWN_OFFSET:uint = 0x444444;

      private static var steady:Boolean = false;

      public static const KO_LEVELS:Array = [100,50,25];
      private static var koPercent:int = 100;
      public static var koEffects:int = 0;

      public static var respawnSteps:int = 0;
      public static var timedSteps:int = 0;

      public static function init() : void
      {
         steady = ModSettings.flag("steadyBlinks",false);
         var v:* = ModSettings.value("koEffects");
         koPercent = v is Number && KO_LEVELS.indexOf(int(v)) >= 0 ? int(v) : 100;
         Hooks.legendTinted.add(tinted);
      }

      public static function get on() : Boolean
      {
         return steady;
      }

      public static function set on(v:Boolean) : void
      {
         steady = v;
         ModSettings.setFlag("steadyBlinks",v);
      }

      public static function get koStrength() : int
      {
         return koPercent;
      }

      public static function set koStrength(p:int) : void
      {
         koPercent = KO_LEVELS.indexOf(p) >= 0 ? p : 100;
         ModSettings.setValue("koEffects",koPercent);
      }

      public static function koEffect(effect:class_19) : void
      {
         koEffects++;
         if(koPercent == 100 || effect == null || effect.mTheDO3D == null)
         {
            return;
         }
         effect.mTheDO3D.var_12849 = koPercent / 100;
      }

      private static function tinted(legend:class_123, time:uint) : void
      {
         if(!steady || legend.var_11807 == null)
         {
            return;
         }
         var game:GameCore = legend.owner;
         if(game.var_8999 != null && game.var_8999.var_615 == ScoringType.VOLLEY_BATTLE)
         {
            return;
         }
         if(cooldownMarksShown(game))
         {
            return;
         }
         if(legend.var_661 == 5 || (legend.var_1249 & class_123.var_2394) != 0)
         {
            legend.var_11807.method_7732(0xFFFFFF,RESPAWN_OFFSET);
            respawnSteps++;
         }
         else if((legend.var_1249 & class_123.var_10281) != 0 && legend.var_10889 != 0 && uint(legend.var_10889 - time) < 1000 &&
            !legend.method_2139(time) && !legend.method_3357() && !(legend.var_8895 != 0 && uint(legend.var_8895 + 175) >= time))
         {
            legend.var_11807.method_7732(0xBBBBBB,0x444444);
            timedSteps++;
         }
      }

      private static function cooldownMarksShown(game:GameCore) : Boolean
      {
         var training:class_551 = ScreenManager.var_14532;
         if(training == null || !training.var_14862)
         {
            return false;
         }
         var flags:uint = game.var_3595;
         var shared:Boolean = (flags & 32) != 0;
         if((flags & 32768) != 0 || shared && (game.var_13582 & 32768) != 0)
         {
            return true;
         }
         return game.var_11223 == 2 && ((flags & 16) != 0 || shared && (game.var_13582 & 16) != 0);
      }
   }
}
