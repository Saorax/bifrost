package bh.mods.loneking
{
   import bh.platform.Platform;

   public class LoneKingRules extends class_341
   {
      private var contested:uint = 0;

      private var held:uint = 0;

      public function LoneKingRules(game:GameCore)
      {
         super(game);
      }

      override public function method_448(param1:uint) : void
      {
         var hill:int = var_7460;
         var scoring:Boolean = hill >= 0 && param1 % 400 == 0 && param1 < uint(var_6272 + var_13088);
         var teams:int = scoring ? teamsOnHill(hill) : 0;
         if(teams < 2)
         {
            if(teams == 1)
            {
               held++;
            }
            super.method_448(param1);
            return;
         }
         contested++;
         var_7460 = -1;
         super.method_448(param1);
         var_7460 = hill;
         var blue:Array = owner.var_2208.var_5235;
         var red:Array = owner.var_2208.var_13136;
         for(var i:int = 0; i < blue.length; i++)
         {
            blue[i].isActive = i != hill;
            red[i].isActive = i == hill;
         }
      }

      private function teamsOnHill(hill:int) : int
      {
         var seen:Object = {};
         var count:int = 0;
         var byTeam:Boolean = (owner.var_8999.var_2458 & 1) != 0;
         for each(var legend:class_123 in owner.var_7050)
         {
            if(legend.var_661 == 5 || legend.var_661 == 4 || legend.var_661 == 3 || legend.method_503())
            {
               continue;
            }
            var x:Number = legend.var_10228.method_113(legend.var_10836);
            var y:Number = legend.var_10228.method_113(legend.var_13590);
            for each(var volume:Volume in var_11536)
            {
               if(volume.var_4708 == hill && volume.method_6114(x,y))
               {
                  var key:uint = byTeam ? legend.var_3540 : legend.var_11355;
                  if(!seen[key])
                  {
                     seen[key] = true;
                     count++;
                  }
                  break;
               }
            }
         }
         return count;
      }

      override public function method_1894() : void
      {
         Platform.log("lone king: " + held + " scoring steps held alone, " + contested + " contested (no points)");
         contested = 0;
         held = 0;
         super.method_1894();
      }
   }
}
