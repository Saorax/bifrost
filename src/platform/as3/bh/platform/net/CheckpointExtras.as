package bh.platform.net
{
   import flash.utils.ByteArray;
   import flash.utils.Dictionary;

   public final class CheckpointExtras
   {
      private static var kept:Dictionary = new Dictionary(true);
      public static var edgeFlags:Boolean = true;
      public static var savedCount:uint = 0;
      public static var restoredCount:uint = 0;
      public static var missing:uint = 0;
      public static var trimmed:uint = 0;

      public function CheckpointExtras()
      {
      }

      public static function reset() : void
      {
         kept = new Dictionary(true);
         savedCount = restoredCount = missing = trimmed = 0;
      }

      public static function saved(store:Object, checkpoint:Object) : void
      {
         if(!SimRandom.active || !(checkpoint is class_362))
         {
            return;
         }
         var bytes:ByteArray = checkpoint.var_5133 as ByteArray;
         if(bytes != null && bytes.length > bytes.position)
         {
            bytes.length = bytes.position;
            trimmed++;
         }
         if(!edgeFlags)
         {
            return;
         }
         var core:Object = Object(GameApp.mainInstance).var_13259;
         if(core == null)
         {
            return;
         }
         var players:Object = core.var_7050;
         for(var i:int = 0; i < int(players.length); i++)
         {
            var p:Object = players[i];
            if(p.var_7944 == store)
            {
               kept[checkpoint] = (p.var_7424 ? 1 : 0) | (p.var_7775 ? 2 : 0) | (p.var_4601 ? 4 : 0) | (p.var_4411 ? 8 : 0) | (p.var_2242 ? 16 : 0);
               savedCount++;
               return;
            }
         }
      }

      public static function restored(checkpoint:Object, player:Object) : void
      {
         if(!edgeFlags || !SimRandom.active)
         {
            return;
         }
         var v:* = kept[checkpoint];
         if(v === undefined)
         {
            missing++;
            return;
         }
         player.var_7424 = (uint(v) & 1) != 0;
         player.var_7775 = (uint(v) & 2) != 0;
         player.var_4601 = (uint(v) & 4) != 0;
         player.var_4411 = (uint(v) & 8) != 0;
         player.var_2242 = (uint(v) & 16) != 0;
         restoredCount++;
      }

      public static function summary() : String
      {
         return "checkpoints: " + trimmed + " cut to their length, edge flags " + (edgeFlags ? savedCount + " saved, " + restoredCount + " restored" + (missing > 0 ? ", " + missing + " MISSING" : "") : "off");
      }
   }
}
