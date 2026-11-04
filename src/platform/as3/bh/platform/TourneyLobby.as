package bh.platform
{
   public final class TourneyLobby
   {
      public function TourneyLobby()
      {
      }

      public static function roomSize(room:Object) : uint
      {
         try
         {
            if(uint(room.var_9946) == 4 && uint(room.owner.var_8999.var_1100) == 2)
            {
               return 2;
            }
         }
         catch(e:Error)
         {
         }
         return 0;
      }

      public static function spread(podium:Object, slot:uint) : Boolean
      {
         try
         {
            if(slot != 1)
            {
               return false;
            }
            var room:Object = podium.owner.var_6244;
            var game:Object = podium.owner.var_8999;
            return room != null && game != null && uint(room.var_9946) == 4 && uint(game.var_1100) == 2;
         }
         catch(e:Error)
         {
         }
         return false;
      }
   }
}
