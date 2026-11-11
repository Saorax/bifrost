package bh.platform.net
{
   import bh.platform.ContentMods;
   import bh.platform.Hooks;

   public final class ModItems
   {
      public static const PACKET:int = 11049;

      public static const TABLES:Array = ["costumeTypes","weaponSkinTypes","ColorSchemeTypes","SpawnBotTypes",
         "CompanionTypes","TrailEffectTypes","avatarTypes","PodiumTypes","SeasonBorderTypes","PlayerThemeTypes",
         "TauntTypes","EmojiTypes","MonikerTypes"];

      private static const ROOM:int = 2445;

      private static var known:Object = {};

      private static var mine:Object = null;

      private static var list:Array = null;

      private static var registered:Boolean = false;

      public function ModItems()
      {
      }

      public static function register() : void
      {
         if(registered)
         {
            return;
         }
         registered = true;
         Hooks.packetReceived.add(onPacket);
      }

      public static function items() : Array
      {
         if(list != null)
         {
            return list;
         }
         list = [];
         mine = {};
         for each(var table:String in TABLES)
         {
            var ids:Object = ContentMods.ids[table];
            mine[table] = {};
            for(var key:String in ids)
            {
               var id:int = int(ids[key]);
               mine[table][key] = id;
               var stand:Object = ContentMods.copiedIds[table] != null ? ContentMods.copiedIds[table][key] : null;
               var fallback:int = stand != null ? int(stand) : (table == "ColorSchemeTypes" ? nearestColour(key) : 0);
               list.push([table,id,key,fallback]);
            }
         }
         PrivateServer.log("mod items: " + list.length + " to send");
         return list;
      }

      private static function nearestColour(key:String) : int
      {
         try
         {
            var scheme:Object = class_76.method_4680(key);
            var slot:int = class_76.method_1421("Body1");
            if(scheme == null || slot < 0 || scheme.var_10427 == null)
            {
               return 0;
            }
            var want:uint = uint(scheme.var_10427[slot]);
            var best:int = 0;
            var bestDist:Number = Number.MAX_VALUE;
            var addedColours:Object = ContentMods.added["ColorSchemeTypes"] || {};
            for each(var s:Object in class_76.var_3762)
            {
               if(s == null || s === class_76.NO_COLOR_SCHEME || s.var_3938 != 0 || addedColours[s.mColorSchemeName] != null ||
                  s.var_10427 == null || s.var_10427.length <= slot)
               {
                  continue;
               }
               var c:uint = uint(s.var_10427[slot]);
               var dr:int = int((c >> 16 & 255) - (want >> 16 & 255));
               var dg:int = int((c >> 8 & 255) - (want >> 8 & 255));
               var db:int = int((c & 255) - (want & 255));
               var d:Number = dr * dr * 0.3 + dg * dg * 0.59 + db * db * 0.11;
               if(d < bestDist)
               {
                  bestDist = d;
                  best = int(s.var_9518);
               }
            }
            return best;
         }
         catch(e:Error)
         {
         }
         return 0;
      }

      public static function send() : void
      {
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var packet:NetPacket = new NetPacket(PACKET);
            packet.writeString(JSON.stringify(items()));
            core.sendToServer(packet);
            packet.method_839();
         }
         catch(e:Error)
         {
            PrivateServer.log("mod items: could not send ours (" + e.message + ")");
         }
      }

      public static function roomHost() : uint
      {
         try
         {
            return uint(Object(GameApp.mainInstance).var_13259.var_6244.var_2468);
         }
         catch(e:Error)
         {
         }
         return 0;
      }

      public static function knows(player:uint) : Boolean
      {
         return player != 0 && known[player] != null;
      }

      public static function id(table:String, player:uint, value:uint, bot:Boolean = false) : uint
      {
         if(bot)
         {
            player = roomHost();
         }
         if(value == 0 || player == 0)
         {
            return value;
         }
         var theirs:Object = known[player];
         if(theirs == null || theirs[table] == null)
         {
            return value;
         }
         var item:Array = theirs[table][value] as Array;
         if(item == null)
         {
            return value;
         }
         items();
         var here:* = mine[table] != null ? mine[table][item[0]] : undefined;
         return here !== undefined ? uint(here) : uint(item[1]);
      }

      public static function weapons(player:uint, value:uint, bot:Boolean = false) : uint
      {
         if(bot)
         {
            player = roomHost();
         }
         if(player == 0 || known[player] == null)
         {
            return value;
         }
         var a:uint = id("weaponSkinTypes",player,value & 0x7FFF);
         var b:uint = id("weaponSkinTypes",player,(value & 0x7FFF0000) >>> 16);
         return (value & 0x80008000) | (a & 0x7FFF) | (b & 0x7FFF) << 16;
      }

      private static function onPacket(packet:Object) : Boolean
      {
         if(packet == null)
         {
            return false;
         }
         if(packet.type == ROOM || packet.type == P2PMatch.MATCH_FOUND)
         {
            if(items().length > 0)
            {
               send();
            }
            return false;
         }
         if(packet.type != PACKET)
         {
            return false;
         }
         try
         {
            var player:uint = packet.readUint();
            var rows:Array = JSON.parse(packet.readString()) as Array;
            var byTable:Object = {};
            for each(var r:Array in rows || [])
            {
               if(byTable[r[0]] == null)
               {
                  byTable[r[0]] = {};
               }
               byTable[r[0]][uint(r[1])] = [String(r[2]),uint(r[3])];
            }
            known[player] = byTable;
            PrivateServer.log("mod items: " + (rows ? rows.length : 0) + " from player " + player);
         }
         catch(e:Error)
         {
            PrivateServer.log("mod items: bad 11049 (" + e.message + ")");
         }
         return true;
      }

   }
}
