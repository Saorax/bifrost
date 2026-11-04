package bh.platform
{
   import bh.platform.net.Cosmetics;
   public final class ProfilePicks
   {
      public static const KEY:String = "profilePicks";
      private static const SETS:Array = [["koEffect","var_6605","var_13282"],["sidekick","var_3827","var_7450"],
         ["frame","var_13887","var_14732"],["theme","var_9090","var_7635"],["podium","var_5174","var_10297"],
         ["victory","var_3278","var_8912"],["defeat","var_4493","var_6340"]];
      private static const SETTLE:int = 90;
      public static const SNAPSHOT:int = 11021;
      private static const LOADOUT:int = 2471;
      private static const INVENTORY:int = 2901;
      private static var serverAt:int = -1000;

      private static var tick:int = 0;
      private static var player:uint = 0;
      private static var since:int = -1;
      private static var restored:Boolean = false;
      private static var last:String = null;
      private static var seen:Vector.<uint> = new Vector.<uint>();

      public function ProfilePicks()
      {
      }

      public static function init() : void
      {
         Hooks.frameStarting.add(onFrame);
         Hooks.packetReceived.add(function(packet:Object):Boolean
         {
            if(packet != null && (packet.type == LOADOUT || packet.type == INVENTORY))
            {
               if(packet.type == LOADOUT)
               {
                  serverAt = tick;
               }
               var inv:Object = inventory();
               if(inv != null)
               {
                  inv.var_5698 = true;
               }
            }
            return false;
         });
      }

      private static function inventory() : Object
      {
         var core:Object = ScreenManager.owner;
         return core != null ? core.var_8329 : null;
      }

      private static function current(inv:Object) : Object
      {
         var taunts:Array = [];
         var emojis:Array = [];
         for(var i:int = 0; i < 8; i++)
         {
            taunts.push(uint(inv.var_15310[i]));
         }
         for(i = 0; i < 20; i++)
         {
            emojis.push(uint(inv.var_8804[i]));
         }
         var sets:Object = {};
         for each(var set:Array in SETS)
         {
            var words:Array = [];
            for each(var w:* in inv[set[1]].var_3813)
            {
               words.push(uint(w));
            }
            sets[set[0]] = words;
         }
         return {"avatar":uint(inv.var_13799),"title":uint(inv.var_15092),"taunts":taunts,"emojis":emojis,"sets":sets};
      }

      private static function changed(inv:Object) : Boolean
      {
         var n:int = 0;
         var diff:Boolean = false;
         var i:int;
         var v:uint;
         for(i = -2; i < 28; i++)
         {
            v = i == -2 ? uint(inv.var_13799) : (i == -1 ? uint(inv.var_15092) : (i < 8 ? uint(inv.var_15310[i]) : uint(inv.var_8804[i - 8])));
            if(n >= seen.length || seen[n] != v)
            {
               diff = true;
               seen[n] = v;
            }
            n++;
         }
         for each(var set:Array in SETS)
         {
            var words:Object = inv[set[1]].var_3813;
            v = uint(words.length);
            if(n >= seen.length || seen[n] != v)
            {
               diff = true;
               seen[n] = v;
            }
            n++;
            for each(var w:* in words)
            {
               if(n >= seen.length || seen[n] != uint(w))
               {
                  diff = true;
                  seen[n] = uint(w);
               }
               n++;
            }
         }
         if(seen.length != n)
         {
            diff = true;
            seen.length = n;
         }
         return diff;
      }

      private static function onFrame() : void
      {
         if(++tick % 15 != 0)
         {
            return;
         }
         try
         {
            var core:Object = ScreenManager.owner;
            var inv:Object = inventory();
            if(core == null || inv == null || uint(core.var_14656) == 0)
            {
               return;
            }
            if(uint(core.var_14656) != player)
            {
               player = uint(core.var_14656);
               since = tick;
               restored = false;
            }
            if(!restored)
            {
               if(tick - since < SETTLE)
               {
                  return;
               }
               if(serverAt >= since - 120)
               {
                  Platform.log("profile picks: the server's (2471) kept, avatar " + inv.var_13799 + ", title " + inv.var_15092);
               }
               else
               {
                  restore(inv);
               }
               restored = true;
               changed(inv);
               last = JSON.stringify(current(inv));
               ModSettings.setValue(KEY,JSON.parse(last));
               send(core,JSON.parse(last));
               return;
            }
            if(changed(inv))
            {
               last = JSON.stringify(current(inv));
               ModSettings.setValue(KEY,JSON.parse(last));
               send(core,JSON.parse(last));
               if(core.serverConnection != null && core.serverConnection.isConnected())
               {
                  Cosmetics.sendMine();
               }
            }
         }
         catch(e:Error)
         {
            ErrorLog.write("profile picks: " + e);
         }
      }

      private static function send(core:Object, picks:Object) : void
      {
         if(core.serverConnection == null || !core.serverConnection.isConnected())
         {
            return;
         }
         var packet:NetPacket = new NetPacket(SNAPSHOT);
         packet.writeUint(uint(picks.avatar));
         packet.writeUint(uint(picks.title));
         for each(var t:* in picks.taunts)
         {
            packet.writeUint(uint(t));
         }
         for each(var e:* in picks.emojis)
         {
            packet.writeUint(uint(e));
         }
         for each(var set:Array in SETS)
         {
            var words:Array = picks.sets[set[0]] as Array || [];
            packet.writeUint(uint(words.length));
            for each(var w:* in words)
            {
               packet.writeUint(uint(w));
            }
         }
         core.sendToServer(packet);
         packet.method_839();
      }

      private static function restore(inv:Object) : void
      {
         var saved:* = ModSettings.value(KEY);
         if(saved == null || typeof saved != "object")
         {
            return;
         }
         var n:int = 0;
         if(saved.avatar is Number && uint(saved.avatar) != uint(inv.var_13799))
         {
            inv.method_5901(uint(saved.avatar),false);
            n++;
         }
         if(saved.title is Number && uint(saved.title) != uint(inv.var_15092))
         {
            inv.method_2876(uint(saved.title));
            n++;
         }
         var i:int;
         if(saved.taunts is Array)
         {
            for(i = 0; i < 8 && i < saved.taunts.length; i++)
            {
               if(uint(saved.taunts[i]) != uint(inv.var_15310[i]))
               {
                  inv.method_7282(i,uint(saved.taunts[i]));
                  n++;
               }
            }
         }
         if(saved.emojis is Array)
         {
            for(i = 0; i < 20 && i < saved.emojis.length; i++)
            {
               if(uint(saved.emojis[i]) != uint(inv.var_8804[i]))
               {
                  inv.method_4534(i,uint(saved.emojis[i]));
                  n++;
               }
            }
         }
         if(saved.sets != null && typeof saved.sets == "object")
         {
            for each(var set:Array in SETS)
            {
               var words:* = saved.sets[set[0]];
               if(!(words is Array))
               {
                  continue;
               }
               var bits:Object = inv[set[1]];
               if(JSON.stringify(words) == JSON.stringify(bits.var_3813))
               {
                  continue;
               }
               var any:Boolean = false;
               for each(var w:* in words)
               {
                  any = any || uint(w) != 0;
               }
               if(!any)
               {
                  continue;
               }
               bits.method_4655(words);
               inv[set[2]] = null;
               n++;
            }
         }
         Platform.log("profile picks: " + n + " put back (avatar " + inv.var_13799 + ", title " + inv.var_15092 + ")");
      }
   }
}
