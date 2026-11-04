package bh.platform.net
{
   import bh.platform.ErrorLog;
   import bh.platform.Hooks;
   import bh.platform.OnlineTraining;
   import bh.platform.RatingExtras;
   import bh.platform.RatingTags;
   import bh.platform.ReplayKeep;
   import flash.display.Shape;
   import flash.events.Event;
   import flash.utils.getTimer;

   public final class P2PMatch
   {
      public static const START_DETAILS:int = 11004;

      public static const START_LOCAL:int = 11005;
      public static const LEVEL_SELECT_OPEN:int = 2460;

      public static const MATCH_FOUND:int = 11020;

      private static var registered:Boolean = false;

      public static var queueMatch:Object = null;

      private static var waiting:Array = null;

      private static var waitingSince:int = 0;

      private static var ticker:Shape = null;

      private static const ROULETTE_WAIT:int = 8000;

      public function P2PMatch()
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
         Hooks.gameStateChanging.add(onState);
      }

      private static function onState(from:uint, to:uint) : void
      {
         if(to != MatchReport.END_STATE || from != 6)
         {
            return;
         }
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var board:Object = ScreenManager.var_6219;
            var wasQueue:Boolean = queueRunning;
            queueRunning = false;
            if(!wasQueue || uint(core.var_10906) != 1 || board == null)
            {
               return;
            }
            var missions:Boolean = Boolean(core.var_3805.var_9215);
            core.var_3805.var_9215 = false;
            board.var_3595 = 4;
            board.method_4243();
            var oldEntity:uint = uint(core.var_6937);
            core.var_6937 = localEntity;
            board.method_1790(board.var_1496);
            core.var_6937 = oldEntity;
            PrivateServer.log("queue match end: the scoreboard's online pages " + board.var_453.join(",") + " (" +
               int(core.var_3805.var_12932.length) + " progression records so far" + (missions ? ", missions flag cleared" : "") + ")");
         }
         catch(e:Error)
         {
            PrivateServer.log("queue match end: could not add the online pages (" + e.message + ")");
         }
      }

      public static function sendStartDetails() : void
      {
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var level:Object = core.var_6244.method_8645();
            if(level == null || uint(level.var_8543) == 0)
            {
               PrivateServer.log("could not start P2P match: the lobby selected no level");
               return;
            }
            if(queueMatch == null)
            {
               RoomNet.hostStarting(core);
            }
            var packet:NetPacket = new NetPacket(START_DETAILS);
            packet.writeUint(uint(level.var_8543));
            var candidates:Object = core.var_6244.method_3153();
            var n:int = int(candidates.length);
            packet.writeUint(uint(n));
            for(var i:int = 0; i < n; i++)
            {
               packet.writeUint(uint(candidates[i].var_8543));
            }
            packet.writeUint(LevelType.var_15021 != null ? uint(LevelType.var_15021.var_8543) : 0);
            packet.writeUint(OnlineTraining.startFlags());
            core.sendToServer(packet);
            packet.method_839();
            PrivateServer.log("sent P2P start level " + uint(level.var_8543) + " and " + n + " level select candidates" +
               (OnlineTraining.requested ? ", as Training" : ""));
         }
         catch(e:Error)
         {
            PrivateServer.log("could not send P2P start details: " + e.message);
         }
      }

      private static function onPacket(packet:Object) : Boolean
      {
         if(packet != null && packet.type == MATCH_FOUND)
         {
            matchFound(packet);
            return true;
         }
         if(packet != null && packet.type == LEVEL_SELECT_OPEN && queueMatch == null)
         {
            try
            {
               var lcore:Object = Object(GameApp.mainInstance).var_13259;
               P2PSession.prepare(uint(lcore.var_6244.var_13482),uint(lcore.var_14656),lcore);
            }
            catch(e0:Error)
            {
               PrivateServer.log("P2P: no ping during the map vote: " + e0.message);
            }
            return false;
         }
         if(packet == null || packet.type != START_LOCAL)
         {
            return false;
         }
         try
         {
            var room:uint = packet.readUint();
            var seed:uint = packet.readUint();
            var levelID:uint = packet.readUint();
            var flags:uint = OnlineTraining.readFlags(packet);
            if(levelSelectShowing())
            {
               waiting = [room,seed,levelID,flags];
               waitingSince = getTimer();
               if(ticker == null)
               {
                  ticker = new Shape();
               }
               ticker.addEventListener(Event.ENTER_FRAME,onWaitFrame);
               PrivateServer.log("P2P room " + room + " starts on level " + levelID + " after the level select");
               return true;
            }
            launch(room,seed,levelID,flags);
         }
         catch(e:Error)
         {
            PrivateServer.log("could not read P2P start: " + e.getStackTrace());
         }
         return true;
      }

      private static function matchFound(packet:Object) : void
      {
         try
         {
            var room:uint = packet.readUint();
            var host:uint = packet.readUint();
            var playlist:uint = packet.readUint();
            var known:Boolean = false;
            var matches:uint = 0;
            var wins:uint = 0;
            var bytes:Object = packet.var_5085.var_15327;
            var series:Object = {};
            var seriesGames:uint = 0;
            if(int(bytes.length) * 8 - int(packet.var_5085.var_11198) >= 8)
            {
               known = packet.method_5885();
               matches = packet.readUint();
               wins = packet.readUint();
               if(int(bytes.length) * 8 - int(packet.var_5085.var_11198) >= 8)
               {
                  var n:uint = packet.readUint();
                  for(var i:uint = 0; i < n && i < 16; i++)
                  {
                     var pid:uint = packet.readUint();
                     var won:uint = packet.readUint();
                     series[pid] = won;
                     seriesGames += won;
                  }
               }
            }
            RatingTags.reset();
            RatingExtras.reset();
            if(int(bytes.length) * 8 - int(packet.var_5085.var_11198) >= 8)
            {
               var rn:uint = packet.readUint();
               for(var ri:uint = 0; ri < rn && ri < 16; ri++)
               {
                  var rid:uint = packet.readUint();
                  RatingTags.before[rid] = {"rating":packet.readUint(),"stars":packet.readUint(),"games":packet.readUint()};
               }
               if(int(bytes.length) * 8 - int(packet.var_5085.var_11198) >= 16)
               {
                  try
                  {
                     RatingTags.cards = JSON.parse(packet.readString());
                  }
                  catch(e3:Error)
                  {
                  }
               }
            }
            teamLeaders = null;
            if(int(bytes.length) * 8 - int(packet.var_5085.var_11198) >= 8)
            {
               var ln:uint = packet.readUint();
               for(var li:uint = 0; li < ln && li < 8; li++)
               {
                  var lteam:uint = packet.readUint();
                  var lpid:uint = packet.readUint();
                  teamLeaders = teamLeaders || {};
                  teamLeaders[lteam] = lpid;
               }
            }
            queueMatch = {"room":room,"playlist":playlist,"known":known,"matches":matches,"wins":wins,"series":series,
               "seriesGames":seriesGames};
            var core:Object = Object(GameApp.mainInstance).var_13259;
            PrivateServer.log("queue match found: room " + room + ", playlist " + playlist + ", " + int(core.var_6244.var_1751.length)
               + " players, host " + host);
            core.var_6244.var_14860 = null;
            sendStartDetails();
            P2PSession.prepare(room,uint(core.var_14656),core);
         }
         catch(e:Error)
         {
            PrivateServer.log("could not read a queue match: " + e.getStackTrace());
         }
      }

      private static function levelSelectShowing() : Boolean
      {
         return ScreenManager.levelSelectScreen != null && ScreenManager.levelSelectScreen.isActive
            || ScreenManager.var_11572 != null && ScreenManager.var_11572.isActive;
      }

      private static function onWaitFrame(e:Event) : void
      {
         var roulette:Boolean = ScreenManager.var_11572 != null && ScreenManager.var_11572.isActive;
         if(roulette && getTimer() - waitingSince < ROULETTE_WAIT)
         {
            return;
         }
         ticker.removeEventListener(Event.ENTER_FRAME,onWaitFrame);
         var w:Array = waiting;
         waiting = null;
         if(w != null)
         {
            PrivateServer.log("P2P level select done after " + (getTimer() - waitingSince) + " ms" + (roulette ? " (roulette still showing)" : ""));
            launch(uint(w[0]),uint(w[1]),uint(w[2]),uint(w[3]));
         }
      }

      private static var localEntity:uint = 0;

      private static var queueRunning:Boolean = false;

      private static var launchLevel:Object = null;

      private static var teamLeaders:Object = null;

      public static function uniqueColours(core:Object) : void
      {
         if(launchLevel == null)
         {
            return;
         }
         var level:Object = launchLevel;
         launchLevel = null;
         try
         {
            var before:Array = [];
            var legends:Object = core.var_7050;
            for(var i:int = 0; i < int(legends.length); i++)
            {
               before.push(legends[i].var_14421 != null ? uint(legends[i].var_14421.var_9518) : 0);
            }
            core.method_2719(uint(core.var_14656),core.var_8999,level,legends,null);
            var changed:Array = [];
            for(i = 0; i < int(legends.length); i++)
            {
               var now:uint = legends[i].var_14421 != null ? uint(legends[i].var_14421.var_9518) : 0;
               if(now != uint(before[i]))
               {
                  changed.push(legends[i].var_14656 + ": " + before[i] + " -> " + now);
               }
            }
            PrivateServer.log("P2P unique colours: " + (changed.length > 0 ? changed.join(", ") : "no change"));
            if(teamLeaders != null)
            {
               teamColours(core,level);
            }
         }
         catch(e:Error)
         {
            ErrorLog.write("P2P unique colours: " + e);
         }
         teamLeaders = null;
      }

      private static function teamColours(core:Object, level:Object) : void
      {
         var legends:Object = core.var_7050;
         var me:uint = uint(core.var_14656);
         var mine:Object = null;
         for(var i:int = 0; i < int(legends.length); i++)
         {
            if(uint(legends[i].var_14656) == me)
            {
               mine = legends[i];
            }
         }
         if(mine == null || uint(mine.var_3540) == 0)
         {
            return;
         }
         var bans:Array = level != null ? level.var_2334 as Array : null;
         var usable:Function = function(c:Object, not:Object):Boolean
         {
            return c != null && c !== class_76.NO_COLOR_SCHEME && uint(c.var_9518) != 0 && !(uint(c.var_9518) >= 128 && uint(c.var_9518) <= 144) && c !== not &&
               !(bans != null && class_50.method_1452(bans,uint(c.var_9518)));
         };
         var own:Object = mine.var_14421;
         if(own == null || own === class_76.NO_COLOR_SCHEME || uint(own.var_9518) == 0 ||
            uint(own.var_9518) >= 128 && uint(own.var_9518) <= 144)
         {
            own = usable(class_76.var_12696[1],null) ? class_76.var_12696[1] : class_76.var_12696[2];
         }
         var leaderColour:Object = null;
         var others:Array = [];
         for(i = 0; i < int(legends.length); i++)
         {
            var l:Object = legends[i];
            if(uint(l.var_3540) == uint(mine.var_3540) || uint(l.var_3540) == 0)
            {
               continue;
            }
            if(uint(l.var_14656) == uint(teamLeaders[uint(l.var_3540)]))
            {
               leaderColour = l.var_14421;
            }
            else
            {
               others.push(l.var_14421);
            }
         }
         var enemy:Object = null;
         var plain:Array = uint(own.var_9518) == 2 ? [class_76.var_12696[1],class_76.var_12696[2]] :
            [class_76.var_12696[2],class_76.var_12696[1]];
         for(var id:int = 3; id < 400; id++)
         {
            plain.push(class_76.var_12696[id]);
         }
         for each(var c:Object in [leaderColour].concat(others,plain))
         {
            if(usable(c,own))
            {
               enemy = c;
               break;
            }
         }
         var changed:Array = [];
         for(i = 0; i < int(legends.length); i++)
         {
            l = legends[i];
            var want:Object = uint(l.var_3540) == uint(mine.var_3540) ? own : (uint(l.var_3540) != 0 ? enemy : null);
            if(want != null && l.var_14421 !== want)
            {
               changed.push(l.var_14656 + ": " + (l.var_14421 != null ? l.var_14421.var_9518 : 0) + " -> " + want.var_9518);
               l.method_364(l.var_108,want,true);
            }
         }
         PrivateServer.log("team colours: own team " + own.var_9518 + ", other team " + (enemy != null ? enemy.var_9518 : "-") +
            (changed.length > 0 ? " (" + changed.join(", ") + ")" : " (no change)"));
      }

      private static function dropRepeatedMembers(room:uint, members:Object) : void
      {
         var seen:Object = {};
         for(var i:int = int(members.length) - 1; i >= 0; i--)
         {
            var m:Object = members[i];
            if(m == null || m.method_4289())
            {
               continue;
            }
            var id:uint = uint(m.var_14656);
            if(seen[id])
            {
               members.splice(i,1);
               PrivateServer.log("P2P room " + room + ": player " + id + " was in the room's list twice; the older entry dropped");
               continue;
            }
            seen[id] = true;
         }
      }

      private static function launch(room:uint, seed:uint, levelID:uint, flags:uint = 0) : void
      {
         try
         {
            if(ScreenManager.var_11572 != null && ScreenManager.var_11572.isActive)
            {
               ScreenManager.var_11572.Hide();
            }
            if(ScreenManager.levelSelectScreen != null && ScreenManager.levelSelectScreen.isActive)
            {
               ScreenManager.levelSelectScreen.method_1159();
            }
            var level:Object = LevelType.var_3683[levelID];
            if(level == null)
            {
               PrivateServer.log("P2P room " + room + " refused unknown level " + levelID);
               return;
            }

            var core:Object = Object(GameApp.mainInstance).var_13259;
            core.var_10906 = queueMatch != null ? 1 : 0;
            queueRunning = queueMatch != null;
            var members:Object = core.var_6244.var_1751;
            dropRepeatedMembers(room,members);
            var localFound:Boolean = false;
            var others:int = 0;
            var bots:int = 0;
            for(var i:int = 0; i < int(members.length); i++)
            {
               var member:Object = members[i];
               if(member.method_4289())
               {
                  bots++;
               }
               else if(uint(member.var_14656) == uint(core.var_14656))
               {
                  member.var_4125 = 0;
                  localFound = true;
               }
               else
               {
                  member.var_4125 = uint(-1);
                  others++;
               }
            }
            if(localFound && others == 0 && bots == 0)
            {
               PrivateServer.log("P2P room " + room + " not started: no other player left in the room");
               core.method_384();
               if(ScreenBase.focusedScreen === ScreenManager.levelSelectScreen)
               {
                  ScreenBase.setFocus(ScreenManager.var_4257);
               }
               return;
            }
            if(!localFound)
            {
               PrivateServer.log("P2P room " + room + " has no lobby entry for local player " + core.var_14656);
               return;
            }

            P2PSession.begin(room,uint(core.var_14656),core);
            Rejoin.begin((flags & Rejoin.FLAG) != 0,room);
            MatchReport.started(room,seed);
            core.var_6244.var_14860 = level;
            class_50.var_5617.method_4224(seed);
            SimRandom.start(seed);
            CheckpointExtras.reset();
            PrivateServer.log("P2P room " + room + " launching level " + levelID + " from shared seed " + seed +
               ((flags & OnlineTraining.TRAINING) != 0 ? " as Training" : ""));
            PeerTraining.alignColours(members);
            if((flags & OnlineTraining.TRAINING) != 0)
            {
               OnlineTraining.launch(core);
            }
            else
            {
               launchLevel = queueRunning ? level : null;
               core.method_4157(false,false,"bifrost");
               uniqueColours(core);
               if(queueRunning)
               {
                  core.var_3805.method_6290();
                  core.var_12029.method_5769(true);
               }
            }
            localEntity = PeerTraining.remotePlayers(core,uint(core.var_14656));
            PeerTraining.sharedKeys(core,seed);
            PrivateServer.log("P2P room " + room + " local match seed " + core.var_10040);
         }
         catch(e:Error)
         {
            PrivateServer.log("could not launch P2P local match: " + e.getStackTrace());
         }
      }
   }
}
