package bh.platform
{
   public final class TrainingPlayers
   {
      public static const TRAINING:uint = 32;

      private static var lastSeen:String = "";

      public function TrainingPlayers()
      {
      }

      public static function get players() : int
      {
         var v:* = ModSettings.value("trainingPlayers");
         return v == null ? 2 : Math.max(1,Math.min(2,int(v)));
      }

      private static function joinable(party:Object) : Boolean
      {
         return players >= 2 && uint(party.var_9946) == TRAINING && uint(party.method_7629()) < uint(players);
      }

      public static function join(party:Object, input:int, device:uint) : Boolean
      {
         try
         {
            if(!joinable(party) || input == 18 || input == 19)
            {
               return false;
            }
            var game:Object = party.owner;
            var profile:Object = game.var_8329;
            var flag:uint = profile.var_13799 != 0 ? uint(profile.var_13799) : uint(class_16.var_13871.var_9656);
            var slot:int = int(party.method_3311(game.var_8412,"",0,0,game.var_14656,party.method_7629(),device,game.var_15161,
               game.var_7572,flag,profile.method_7366(),profile.var_15092));
            Platform.log("training join: device " + device + " input " + input + " -> slot " + slot + " of " +
               party.var_1751.length);
            if(slot < 0)
            {
               return false;
            }
            if((uint(game.var_8999.var_2458) & 1) != 0)
            {
               party.method_3257(slot,party.method_4668(slot));
            }
            var select:Object = ScreenManager.var_4257;
            select.method_2913(slot);
            select.method_3789();
            select.method_4169();
            return true;
         }
         catch(e:Error)
         {
            Platform.log("training join: " + e.message);
         }
         return false;
      }

      public static function inputType(screen:Object, device:uint) : uint
      {
         var party:Object = screen.owner.var_6244;
         var type:uint = uint(party.var_9946);
         if(type != TRAINING || players < 2)
         {
            return type;
         }
         try
         {
            var slot:int = int(party.method_4034(screen.owner.var_14656,device,true));
            if(slot > 0)
            {
               var member:Object = party.method_8549(slot);
               if(member != null && member.method_5111() && member != party.var_13561)
               {
                  return 0;
               }
            }
         }
         catch(e:Error)
         {
            Platform.log("training input: " + e.message);
         }
         return type;
      }

      public static function maxPlayers(party:Object) : uint
      {
         if(players < 2 || uint(party.var_9946) != TRAINING)
         {
            return 0;
         }
         return uint(class_163.var_2518.var_1100) + uint(players - 1);
      }

      public static function back(screen:Object, slot:uint, device:uint, member:Object) : Boolean
      {
         try
         {
            var party:Object = screen.owner.var_6244;
            if(players < 2 || uint(party.var_9946) != TRAINING || slot == 0 || member == null || !member.method_5111() ||
               member.var_6607 != 0)
            {
               return false;
            }
            var podium:Object = screen.method_8904(slot);
            if(podium != null && podium.var_5326)
            {
               return false;
            }
            party.method_2797(screen.owner.var_14656,device,false);
            class_112.method_1883(device);
            screen.method_3013();
            Platform.log("training join: device " + device + " left, " + party.var_1751.length + " in the party");
            return true;
         }
         catch(e:Error)
         {
            Platform.log("training back: " + e.message);
         }
         return false;
      }

      public static function applyingLook(settings:Object, player:Object) : Boolean
      {
         var game:Object = settings.owner;
         var mine:Boolean = player == game.var_9499;
         if(mine || players < 2 && !OnlineTraining.active || player == null || player.var_8233 != null)
         {
            return mine;
         }
         try
         {
            var botChanged:Boolean = settings.var_7724 != settings.var_14680 || settings.var_15109 != settings.var_3652;
            var mineChanged:Boolean = settings.var_4103 != settings.var_1096 || settings.var_6764 != settings.var_2964 ||
               settings.var_8985 != settings.var_14908;
            return botChanged && !mineChanged;
         }
         catch(e:Error)
         {
            Platform.log("training look: " + e.message);
         }
         return mine;
      }

      public static function podiums(screen:Object) : uint
      {
         if(players < 2)
         {
            return 0;
         }
         var answer:uint = 0;
         var type:uint = 0;
         var slots:int = 0;
         try
         {
            var party:Object = screen.owner.var_6244;
            type = uint(party.var_9946);
            slots = int(party.var_1751.length);
            if(type == TRAINING)
            {
               answer = uint(Math.min(slots + 1,players + 1));
            }
         }
         catch(e:Error)
         {
            Platform.log("training podiums: " + e.message);
         }
         var row:String = "none";
         try
         {
            var r:Object = screen.owner.var_6244.var_6474;
            row = r == null ? "none" : "min players " + r.var_133;
         }
         catch(e2:Error)
         {
         }
         var seen:String = type + "/" + slots + "/" + answer + "/" + row;
         if(seen != lastSeen)
         {
            lastSeen = seen;
            Platform.log("training podiums: lobby type " + type + ", " + slots + " slots -> " + (answer || "the game's count") +
               ", lobby row " + row);
         }
         return answer;
      }
   }
}
