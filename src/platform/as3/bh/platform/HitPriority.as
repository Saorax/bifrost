package bh.platform
{
   public class HitPriority
   {
      private static var known:Boolean = false;
      private static var original:Boolean = false;

      private static var kept:uint = 0;

      private static var seen:Boolean = false;

      public function HitPriority()
      {
         super();
      }

      public static function related(a:Object, b:Object) : Boolean
      {
         if(!known)
         {
            known = true;
            original = ModSettings.flag("carryHitsEverywhere",false);
         }
         if(original)
         {
            return true;
         }
         if(!seen && (a.var_4251.var_8950 || b.var_4251.var_8950))
         {
            seen = true;
            Platform.log("carry hit priority: a carry signature's hit met another hit in the same step");
         }
         var at:uint = uint(a.var_3699);
         var aa:uint = uint(a.var_1164);
         var bt:uint = uint(b.var_3699);
         var ba:uint = uint(b.var_1164);
         if(at == bt || at == ba || aa == bt || aa == ba)
         {
            return true;
         }
         if(Boolean(a.var_4251.var_8950) != Boolean(b.var_4251.var_8950))
         {
            kept++;
            if(kept <= 5 || kept % 100 == 0)
            {
               Platform.log("carry hit priority " + kept + ": a hit between other players kept (the game cancelled it)");
            }
         }
         return false;
      }
   }
}
