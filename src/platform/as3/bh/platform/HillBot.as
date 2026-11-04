package bh.platform
{
   import flash.geom.Point;

   public class HillBot extends CTFState
   {
      public function HillBot(param1:class_123, param2:String = undefined)
      {
         if(param2 == null)
         {
            param2 = "HillState";
         }
         super(param1,param2);
      }

      public static function pick(brain:class_40, picked:Class) : Class
      {
         if(brain.owner == null || !(brain.owner.var_2208.var_1712 is class_341) || !ModSettings.flag("hillBots",true))
         {
            return picked;
         }
         if(brain.var_13063 is HillBot)
         {
            return picked == class_271 || picked == class_185 ? picked : null;
         }
         if(brain.var_13063 is class_185 && picked == null)
         {
            return null;
         }
         var target:class_123 = brain.var_11718;
         if(target != null && target.var_661 != 3 && target.var_661 != 4 && target.var_661 != 5 && hillCentre(brain.owner,spot))
         {
            var dx:Number = target.var_10228.method_113(target.var_10836) - spot.x;
            var dy:Number = target.var_10228.method_113(target.var_13590) - spot.y;
            if(dx * dx + dy * dy < FIGHT_RANGE * FIGHT_RANGE)
            {
               return picked;
            }
         }
         return HillBot;
      }

      public static const FIGHT_RANGE:Number = 600;

      public static const STAND:Number = 45;

      private static var spot:Point = new Point();

      public static function hillCentre(game:GameCore, p:Point) : Boolean
      {
         var rules:class_341 = game.var_2208.var_1712 as class_341;
         if(rules == null || rules.var_11536 == null)
         {
            return false;
         }
         for each(var volume:Volume in rules.var_11536)
         {
            if(volume.var_4708 == rules.var_7460)
            {
               p.x = (volume.var_4759 + volume.var_2285) / 2;
               p.y = Math.max(volume.var_3440,volume.var_7467) - STAND;
               return true;
            }
         }
         return false;
      }

      override public function method_8808() : void
      {
         var_10149 = 1;
      }

      override public function method_3593(param1:Point) : void
      {
         hillCentre(owner,param1);
      }
   }
}
