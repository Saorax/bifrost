package bh.platform.net
{
   import bh.platform.OnlineTraining;
   import bh.platform.Platform;

   public final class PeerTraining
   {
      private static const SLOTS:int = 5;

      public function PeerTraining()
      {
      }

      private static const TRAINING_MODE:uint = 32768;

      public static function game() : Object
      {
         try
         {
            return Object(GameApp.mainInstance).var_13259;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      public static function myId() : uint
      {
         var core:Object = game();
         return core != null ? uint(core.var_14656) : 0;
      }

      public static function inMatch() : Boolean
      {
         var core:Object = game();
         return core != null && uint(core.gameState) == Platform.MATCH_RUNNING;
      }

      public static function leaveMatch() : void
      {
         if(inMatch())
         {
            ScreenManager.var_4724.method_598(null,0,0);
         }
      }

      public static function maps() : Array
      {
         var core:Object = game();
         var out:Array = [];
         var seen:Object = {};
         var list:Object = core != null ? core.var_6244.method_3153() : null;
         for(var i:int = 0; list != null && i < int(list.length); i++)
         {
            var level:Object = list[i];
            if(level == null || seen[uint(level.var_8543)])
            {
               continue;
            }
            seen[uint(level.var_8543)] = true;
            out.push([uint(level.var_8543),String(level.mDisplayName || level.var_8543)]);
         }
         out.sort(function(a:Array, b:Array):int
         {
            return String(a[1]) < String(b[1]) ? -1 : (String(a[1]) > String(b[1]) ? 1 : 0);
         });
         return out;
      }

      public static function currentMap() : String
      {
         var level:Object = LevelType.var_3683[levelId()];
         return level != null ? String(level.mDisplayName || levelId()) : "";
      }

      public static function currentRecords() : Array
      {
         var core:Object = game();
         var out:Array = [];
         var members:Object = core.var_6244.var_1751;
         var players:Object = core.var_7050;
         var bots:Array = [];
         var humans:Object = {};
         for(var j:int = 0; players != null && j < int(players.length); j++)
         {
            if(players[j].var_8233 != null)
            {
               bots.push(players[j]);
            }
            else
            {
               humans[uint(players[j].var_14656)] = players[j];
            }
         }
         var bot:int = 0;
         for(var i:int = 0; i < int(members.length); i++)
         {
            var m:Object = members[i];
            if(m != null)
            {
               out.push(asPlaying(record(m),m.method_4289() ? (bot < bots.length ? bots[bot++] : null) : humans[uint(m.var_14656)]));
            }
         }
         return out;
      }

      public static function stopIfIdle() : void
      {
         if(SimRandom.active && !OnlineTraining.active)
         {
            SimRandom.stop();
         }
      }

      public static function offlineId(id:uint) : void
      {
         var core:Object = game();
         if(core == null || uint(core.var_14656) != 0 || id == 0)
         {
            return;
         }
         var members:Object = core.var_6244.var_1751;
         for(var i:int = 0; i < int(members.length); i++)
         {
            if(members[i] != null && !members[i].method_4289() && uint(members[i].var_14656) == 0)
            {
               members[i].var_14656 = id;
            }
         }
         core.var_14656 = id;
         PrivateServer.log("peer training: offline, playing as id " + id);
      }

      public static function describe() : String
      {
         var core:Object = game();
         if(core == null)
         {
            return "no game";
         }
         var out:Array = [];
         var players:Object = core.var_7050;
         for(var i:int = 0; players != null && i < int(players.length); i++)
         {
            var p:Object = players[i];
            out.push(uint(p.var_14656) + (p.var_8233 != null ? " bot" : "") + " " + (p.var_13881 != null ? p.var_13881.mHeroName : "?") +
               " at " + Number(p.method_338()).toFixed(0) + "," + Number(p.method_4344()).toFixed(0));
         }
         return "me " + core.var_14656 + ", training " + OnlineTraining.active + ", " + out.join("; ");
      }

      public static function notReady() : String
      {
         var core:Object = game();
         if(core == null)
         {
            return "the game isn't ready";
         }
         if(OnlineTraining.active)
         {
            return "online training is already running";
         }
         if(!Platform.matchRunning || (uint(core.var_3595) & TRAINING_MODE) == 0)
         {
            return "start Training first";
         }
         var members:Object = core.var_6244.var_1751;
         var humans:int = 0;
         for(var i:int = 0; i < int(members.length); i++)
         {
            if(members[i] != null && !members[i].method_4289())
            {
               humans++;
            }
         }
         if(humans != 1)
         {
            return "online training needs a Training session with one player";
         }
         return null;
      }

      public static function levelId() : uint
      {
         var core:Object = game();
         var level:Object = core != null ? core.var_6244.method_8645() : null;
         return level != null ? uint(level.var_8543) : 0;
      }

      public static function localRecords(core:Object = null) : Array
      {
         core = core || game();
         var out:Array = [];
         var members:Object = core.var_6244.var_1751;
         var players:Object = core.var_7050;
         var mine:Object = null;
         var bots:Array = [];
         for(var j:int = 0; players != null && j < int(players.length); j++)
         {
            var pl:Object = players[j];
            if(pl.var_8233 != null)
            {
               bots.push(pl);
            }
            else if(uint(pl.var_14656) == uint(core.var_14656))
            {
               mine = pl;
            }
         }
         var bot:int = 0;
         for(var i:int = 0; i < int(members.length); i++)
         {
            var m:Object = members[i];
            if(m == null)
            {
               continue;
            }
            if(m.method_4289())
            {
               out.push(asPlaying(record(m),bot < bots.length ? bots[bot] : null));
               bot++;
            }
            else if(uint(m.var_14656) == uint(core.var_14656))
            {
               out.push(asPlaying(record(m),mine));
            }
         }
         return out;
      }

      private static function asPlaying(r:Array, player:Object) : Array
      {
         if(player == null || player.var_13881 == null)
         {
            return r;
         }
         var costume:Object = player.var_108;
         if(costume != null && costume.var_9162 && player.var_10767 != null)
         {
            costume = player.var_10767[0];
         }
         var slot:int = Math.max(0,Math.min(SLOTS - 1,int(r[19])));
         var look:uint = HeroType.method_5610(player.var_13881,costume);
         r[22][slot][4] = look;
         r[23][0] = look;
         if(costume != null)
         {
            r[22][slot][6] = uint(costume.var_14823);
            r[23][1] = uint(costume.var_14823);
         }
         if(player.var_14421 != null)
         {
            r[9] = uint(player.var_14421.var_9518);
            r[23][2] = uint(player.var_14421.var_9518);
         }
         return r;
      }

      public static function record(member:Object) : Array
      {
         var slots:Array = [];
         for(var i:int = 0; i < SLOTS; i++)
         {
            var s:Object = member.var_12798[i];
            slots.push([s.var_12905 ? 1 : 0,uint(s.var_13852),uint(s.var_15258),uint(s.var_3173),uint(s.var_11835),uint(s.var_9049),
               uint(s.var_14823)]);
         }
         var stats:Object = member.var_9478;
         return [uint(member.var_12512),uint(member.var_14656),String(member.var_6307 != null ? member.var_6307.var_14792 : ""),
            String(member.var_1077 != null ? member.var_1077.var_14792 : ""),uint(member.var_2826),uint(member.var_7621),
            uint(member.var_9352),String(member.var_7572 || ""),uint(member.var_3540),uint(member.var_7774),int(member.var_8790),
            uint(member.var_8173),uint(member.var_12935),uint(member.var_8902),uint(member.var_6607),uint(member.var_14618),
            uint(member.var_9656),uint(member.var_7600),uint(member.var_14291),uint(member.var_10722),int(member.var_8079),
            [uint(stats.var_13360),uint(stats.var_11025),uint(stats.var_4371)],slots,
            [member.var_5540 != null ? uint(member.var_5540.var_11835) : 0,member.var_2483 != null ? uint(member.var_2483.var_14823) : 0,
            member.var_13724 != null ? uint(member.var_13724.var_9518) : 0,uint(member.var_5158),uint(member.var_12551),
            uint(member.var_12740),uint(member.var_5378),uint(member.var_12121)]];
      }

      private static function build(core:Object, r:Array) : Object
      {
         var m:Object = new class_107(core,String(r[2]),uint(r[1]),uint(r[6]),String(r[7]),String(r[3]),uint(r[4]),uint(r[5]));
         m.var_12512 = uint(r[0]);
         m.var_3540 = uint(r[8]);
         m.var_7774 = uint(r[9]);
         m.var_8790 = int(r[10]);
         m.var_8173 = uint(r[11]);
         m.var_12935 = uint(r[12]);
         m.var_8902 = uint(r[13]);
         m.var_6607 = uint(r[14]);
         m.var_14618 = uint(r[15]);
         m.var_9656 = uint(r[16]);
         m.var_7600 = uint(r[17]);
         m.var_14291 = uint(r[18]);
         m.var_10722 = uint(r[19]);
         m.var_8079 = int(r[20]);
         m.var_9478.var_13360 = uint(r[21][0]);
         m.var_9478.var_11025 = uint(r[21][1]);
         m.var_9478.var_4371 = uint(r[21][2]);
         look(m,r);
         var view:Array = r[23];
         m.var_5158 = uint(view[3]);
         m.var_12551 = uint(view[4]);
         m.var_12740 = uint(view[5]);
         m.var_5378 = uint(view[6]);
         m.var_12121 = uint(view[7]);
         m.var_3605 = true;
         return m;
      }

      private static function look(m:Object, r:Array) : void
      {
         m.var_7774 = uint(r[9]);
         for(var i:int = 0; i < SLOTS; i++)
         {
            var s:Object = m.var_12798[i];
            var v:Array = r[22][i];
            s.var_12905 = int(v[0]) != 0;
            s.var_13852 = uint(v[1]);
            s.var_15258 = uint(v[2]);
            s.var_3173 = uint(v[3]);
            s.var_11835 = uint(v[4]);
            s.var_9049 = uint(v[5]);
            s.var_14823 = uint(v[6]);
         }
         var view:Array = r[23];
         m.var_5540 = uint(view[0]) != 0 ? HeroType.var_2158.method_4935(uint(view[0])) : null;
         m.var_2483 = uint(view[1]) != 0 ? CostumeType.var_12721[uint(view[1])] : null;
         m.var_13724 = uint(view[2]) != 0 ? class_76.var_12696[uint(view[2])] : null;
      }

      public static function apply(core:Object, records:Array) : void
      {
         core = core || game();
         var members:Object = core.var_6244.var_1751;
         var mine:Object = null;
         for(var i:int = 0; i < int(members.length); i++)
         {
            if(members[i] != null && !members[i].method_4289() && uint(members[i].var_14656) == uint(core.var_14656))
            {
               mine = members[i];
            }
         }
         var list:Array = [];
         for each(var r:Array in records)
         {
            if(uint(r[0]) != 3 && uint(r[1]) == uint(core.var_14656) && mine != null)
            {
               mine.var_4125 = 0;
               look(mine,r);
               list.push(mine);
            }
            else
            {
               var m:Object = build(core,r);
               m.var_4125 = uint(r[0]) == 3 ? 0 : uint(-1);
               list.push(m);
            }
         }
         members.length = 0;
         for each(var entry:Object in list)
         {
            members.push(entry);
         }
      }

      public static function launch(core:Object, room:uint, seed:uint, levelID:uint) : Boolean
      {
         core = core || game();
         var level:Object = LevelType.var_3683[levelID];
         if(level == null)
         {
            PrivateServer.log("peer training " + room + " refused unknown level " + levelID);
            return false;
         }
         core.var_10906 = 0;
         P2PSession.begin(room,uint(core.var_14656),core);
         core.var_6244.var_14860 = level;
         class_50.var_5617.method_4224(seed);
         SimRandom.start(seed);
         CheckpointExtras.reset();
         PrivateServer.log("peer training " + room + " launching level " + levelID + " from shared seed " + seed);
         alignColours(core.var_6244.var_1751);
         OnlineTraining.launch(core);
         remotePlayers(core,uint(core.var_14656));
         sharedKeys(core,seed);
         PrivateServer.log("peer training " + room + " local match seed " + core.var_10040);
         return true;
      }

      public static function alignColours(members:Object) : void
      {
         for(var i:int = 0; i < int(members.length); i++)
         {
            try
            {
               var m:Object = members[i];
               if(!m.method_4289() && m.var_13724 != null && uint(m.var_13724.var_9518) != uint(m.var_7774))
               {
                  PrivateServer.log("P2P colour of player " + m.var_14656 + ": " + m.var_7774 + " -> " + m.var_13724.var_9518);
                  m.method_939(uint(m.var_13724.var_9518),true);
               }
            }
            catch(e:Error)
            {
            }
         }
      }

      public static function remotePlayers(core:Object, me:uint) : uint
      {
         var local:uint = 0;
         var players:Object = core.var_7050;
         for(var i:int = 0; i < int(players.length); i++)
         {
            var p:Object = players[i];
            if(uint(p.var_14656) == me && local == 0)
            {
               local = uint(p.var_11355);
            }
            var f:uint = uint(p.var_1249);
            if(uint(p.var_14656) != me && (f & 8) != 0 && (f & (32 | 128)) == 0)
            {
               p.var_1249 = (f & ~8) | 4;
            }
         }
         return local;
      }

      public static function sharedKeys(core:Object, seed:uint) : void
      {
         var players:Object = core.var_7050;
         var keys:Random = new Random();
         var drifted:Array = [];
         for(var i:int = 0; i < int(players.length); i++)
         {
            var p:Object = players[i];
            keys.method_4224(uint(seed ^ 0x6A4B3C2D ^ uint(uint(p.var_14656) * 2654435761)));
            var key:uint = keys.method_207();
            var unset:Boolean = uint(p.var_6333) == 0;
            var value:uint = unset ? key : uint(p.method_5661());
            if(unset)
            {
               drifted.push(uint(p.var_14656) + ":" + uint(p.var_3596).toString(16));
            }
            p.var_3596 = key;
            p.method_3321(value);
         }
         var general:Random = class_50.var_5617;
         var h:uint = uint(2166136261 ^ general.var_12730);
         for(var w:int = 0; w < 16; w++)
         {
            h = uint((h ^ general.var_12512[w]) * 16777619);
         }
         PrivateServer.log("P2P shared player keys set; the build's own keys " + drifted.join(" ") +
            ", general generator after the build " + h.toString(16));
      }
   }
}
