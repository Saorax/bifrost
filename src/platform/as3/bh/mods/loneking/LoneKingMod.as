package bh.mods.loneking
{
   import bh.platform.ModModes;

   public final class LoneKingMod
   {
      public static const MODE:String = "BHLONEKING";

      public function LoneKingMod()
      {
      }

      public static function register() : void
      {
         ModModes.registerRules(MODE,function(game:GameCore):class_334
         {
            return new LoneKingRules(game);
         });
      }
   }
}
