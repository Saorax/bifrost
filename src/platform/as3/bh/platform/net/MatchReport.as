package bh.platform.net
{
   import bh.platform.DummyDrift;
   import bh.platform.Hooks;
   import bh.platform.RatingExtras;
   import bh.platform.RatingTags;

   public final class MatchReport
   {
      public static const REPORT:int = 11040;
      public static const RECORDED:int = 11041;
      public static const PROGRESS:int = 2700;
      public static const ACCOUNT_XP:int = 2527;
      public static const END_STATE:uint = 2;
      public static const BACK_FROM_SCOREBOARD:int = 11073;

      private static var room:uint = 0;
      private static var seed:uint = 0;
      private static var pending:Boolean = false;
      private static var onScoreboard:Boolean = false;
      private static var registered:Boolean = false;

      public static var last:String = "";

      public function MatchReport()
      {
      }

      public static function register() : void
      {
         if(registered)
         {
            return;
         }
         registered = true;
         Hooks.gameStateChanging.add(onState);
         Hooks.packetReceived.add(onPacket);
      }

      public static function started(roomNumber:uint, matchSeed:uint) : void
      {
         room = roomNumber;
         seed = matchSeed;
         pending = true;
      }

      private static function onState(from:uint, to:uint) : void
      {
         if(onScoreboard && from == END_STATE && to != END_STATE)
         {
            onScoreboard = false;
            try
            {
               var back:NetPacket = new NetPacket(BACK_FROM_SCOREBOARD);
               Object(GameApp.mainInstance).var_13259.sendToServer(back);
               back.method_839();
            }
            catch(e:Error)
            {
               PrivateServer.log("match report: back from the scoreboard not sent (" + e.message + ")");
            }
         }
         if(!pending || from != 6 || to == 6)
         {
            return;
         }
         pending = false;
         if(to != END_STATE)
         {
            PrivateServer.log("match report: not sent, the match was left (state " + from + " -> " + to + ")",true);
            return;
         }
         if(P2PSession.peerLost)
         {
            PrivateServer.log("match report: not sent, a player was lost or left the match",true);
            return;
         }
         send();
      }

      private static function send() : void
      {
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var level:Object = core.var_14641.var_256;
            var scoring:Object = core.var_8999.var_615;
            var packet:NetPacket = new NetPacket(REPORT);
            var text:Array = [];
            var players:Object = core.var_7050;
            var n:int = int(players.length);
            var details:Array = [];
            for(var d:int = 0; d < n; d++)
            {
               details.push(breakdown(players[d]));
            }
            packet.writeUint(2);
            packet.writeUint(room);
            packet.writeUint(seed);
            packet.writeUint(uint(level.var_8543));
            packet.writeString(clip(String(level.var_5173)));
            packet.writeString(clip(scoring != null ? String(scoring.mDisplayNameKey) : ""));
            packet.writeUint(uint(core.var_14357));
            packet.writeUint(n);
            text.push("room " + room + ", seed " + seed + ", level " + uint(level.var_8543) + " " + level.var_5173 + ", " +
               (scoring != null ? scoring.mDisplayNameKey : "") + ", " + uint(core.var_14357) + " ms");
            for(var i:int = 0; i < n; i++)
            {
               var pl:Object = players[i];
               var hero:Object = pl.var_13881;
               var st:Object = pl.var_3140;
               var row:Array = [uint(pl.var_14656),hero != null ? uint(hero.var_12172) : 0,hero != null ? clip(String(hero.mHeroName)) : "",
                  uint(pl.var_3540),uint(pl.var_7507),uint(st.var_6689),uint(st.var_8654),uint(st.var_4197),uint(st.var_409),uint(st.var_7376)];
               packet.writeUint(row[0]);
               packet.writeUint(row[1]);
               packet.writeString(row[2]);
               for(var k:int = 3; k < row.length; k++)
               {
                  packet.writeUint(row[k]);
               }
               text.push("player " + row.join(" "));
               if(uint(pl.var_14656) == P2PSession.myId)
               {
                  ServerStats.matchPlayed(pl);
               }
            }
            var broken:int = 0;
            for(var j:int = 0; j < n; j++)
            {
               var values:Array = details[j];
               packet.method_5184(values != null);
               if(values != null)
               {
                  broken++;
                  for each(var v:uint in values)
                  {
                     packet.writeUint(v);
                  }
               }
            }
            text.push(broken + " breakdowns");
            core.sendToServer(packet);
            packet.method_839();
            onScoreboard = true;
            last = text.join("; ");
            PrivateServer.log("match report sent: " + last,true);
            ReplayShare.matchEnded(room,seed);
         }
         catch(e:Error)
         {
            PrivateServer.log("match report: could not send (" + e.message + ")",true);
         }
      }

      private static const GADGETS:Object = {"BouncyBomb":0,"HalloweenBouncyBomb":0,"ProxMine":1,"SpikeBall":2,
         "SpawnBotFlyby":3,"Snowball":4,"HeatwaveSnowball":4};

      public static function breakdown(pl:Object) : Array
      {
         try
         {
            var st:Object = pl.var_3140;
            var hero:Object = pl.var_13881;
            if(st == null || hero == null || st.var_15334 == null || st.var_1957 == null || st.var_11755 == null)
            {
               return null;
            }
            var damageBy:Object = Object(st.var_15334).h;
            var usesBy:Object = Object(st.var_1957).h;
            var heldBy:Object = Object(st.var_11755).h;
            var any:Boolean = false;
            var key:*;
            for(key in damageBy)
            {
               any = true;
               break;
            }
            for(key in heldBy)
            {
               any = true;
               break;
            }
            if(!any)
            {
               return null;
            }
            var w1:String = String(hero.mBaseWeapon1), w2:String = String(hero.mBaseWeapon2);
            var dmg:Array = [0,0,0,0,0];
            var kos:Array = [0,0,0,0,0];
            var gDmg:Array = [0,0,0,0,0];
            var gKos:Array = [0,0,0,0,0];
            var snowHits:uint = 0;
            var k:uint;
            for(key in damageBy)
            {
               k = uint(key);
               if((k & 0x80000000) == 0)
               {
                  var kd:int = kind(k,w1,w2);
                  if(kd >= 0)
                  {
                     dmg[kd] += Number(damageBy[key]);
                  }
                  var gd:* = GADGETS[itemName(k >>> 16 & 0x0FFF)];
                  if(gd != null)
                  {
                     gDmg[int(gd)] += Number(damageBy[key]);
                  }
               }
            }
            for(key in usesBy)
            {
               k = uint(key);
               if((k & 0x80000000) == 0)
               {
                  var packed:uint = uint(usesBy[key]);
                  var ku:int = kind(k,w1,w2);
                  if(ku >= 0)
                  {
                     kos[ku] += packed >>> 24;
                  }
                  var gu:* = GADGETS[itemName(k >>> 16 & 0x0FFF)];
                  if(gu != null)
                  {
                     gKos[int(gu)] += packed >>> 24;
                     if(int(gu) == 4)
                     {
                        snowHits += packed >>> 12 & 0x0FFF;
                     }
                  }
               }
            }
            var held1:uint = 0, held2:uint = 0;
            for(key in heldBy)
            {
               var held:String = itemName(uint(key));
               if(held == w1)
               {
                  held1 += uint(heldBy[key]) * 16;
               }
               else if(held == w2)
               {
                  held2 += uint(heldBy[key]) * 16;
               }
            }
            var out:Array = [];
            for each(var x:Number in dmg)
            {
               out.push(uint(Math.round(x)));
            }
            out = out.concat(kos,[held1,held2,uint(st.var_431)]);
            for(var g:int = 0; g < 5; g++)
            {
               out.push(g == 4 ? snowHits : uint(Math.round(gDmg[g])),gKos[g]);
            }
            return out;
         }
         catch(e:Error)
         {
            PrivateServer.log("match report: no breakdown (" + e.message + ")");
         }
         return null;
      }

      private static function kind(key:uint, w1:String, w2:String) : int
      {
         var name:String = itemName(key >>> 16 & 0x0FFF);
         if(GADGETS[name] != null)
         {
            return 4;
         }
         if(name.indexOf("Throw") == 0 || (key & class_79.var_430) == 1)
         {
            return 1;
         }
         if(name == "Unarmed")
         {
            return 0;
         }
         return name == w1 ? 2 : (name == w2 ? 3 : -1);
      }

      private static function itemName(index:uint) : String
      {
         var item:ItemType = ItemType.var_7348[index];
         return item != null ? String(item.var_12885) : "";
      }

      private static function clip(s:String) : String
      {
         return s == null || s == "null" ? "" : s.substr(0,40);
      }

      private static function onPacket(packet:Object) : Boolean
      {
         if(packet != null && (packet.type == PROGRESS || packet.type == ACCOUNT_XP))
         {
            PrivateServer.log("match report: the server sent " + packet.type + (packet.type == PROGRESS ?
               " (the end screen's Elo change and rewards)" : " (the account XP bar)"));
            return false;
         }
         if(packet == null || packet.type != RECORDED)
         {
            return false;
         }
         try
         {
            var counted:Boolean = packet.method_5885();
            var message:String = packet.readString();
            var change:Object = null;
            try
            {
               change = JSON.parse(packet.readString());
            }
            catch(e2:Error)
            {
            }
            PrivateServer.log("match report: the server says " + (counted ? "counted" : "not counted") + ": " + message);
            if(change != null && change.players != null)
            {
               for(var pid:String in change.players)
               {
                  RatingTags.after[uint(pid)] = change.players[pid];
               }
            }
            if(change != null && change.after != null)
            {
               PrivateServer.log("match report: rating " + change.before + " -> " + change.after);
               RatingExtras.change = change;
            }
            else
            {
               DummyDrift.show(message,6000);
            }
            ServerStats.forget();
         }
         catch(e:Error)
         {
            PrivateServer.log("match report: bad 11041 (" + e.message + ")");
         }
         return true;
      }
   }
}
