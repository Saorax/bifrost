package bh.platform
{
   import flash.display.DisplayObject;
   import flash.display.Sprite;
   import flash.display.Stage;
   import flash.events.Event;
   import flash.events.MouseEvent;

   public final class PostMatchStats
   {
      public static const KEY:uint = 9;
      public static const INPUT:int = 36;
      private static const STEP:uint = 16;
      private static const BUCKET:int = 16;
      public static const COLORS:Array = [0xF5554A,0x4FA8F5,0x7AD151,0xFDE725,0xC77DFF,0xFF9F43,0x4FE3D0,0xFF6FB5];

      private static var stage:Stage;
      private static var button:Sprite;
      private static var buttonLayer:Sprite;
      private static var buttonForReplay:Boolean = false;
      private static var window:PostMatchStatsWindow;
      private static var ownDump:Boolean = false;
      private static var fresh:Boolean = true;
      private static var at:String = "";
      private static var tracking:Boolean = false;
      private static var strings:Array = [];
      private static var dealt:Array = [];
      private static var dodgeGrids:Array = [];
      private static var dodgeSeen:Array = [];
      private static var lastTime:uint = 0;
      private static var replayArmed:Boolean = false;
      private static var replaySaved:Boolean = false;
      private static var replayGaps:Boolean = false;
      private static var lastStep:uint = 0;
      private static const GAP_MS:uint = 500;
      private static var watchButton:Sprite;

      public static var armNext:Boolean = false;
      private static var noted:int = 0, unmatched:int = 0, singles:int = 0;

      public static var last:Object = null;

      public static function init() : void
      {
         Hooks.gameCreated.add(function(main:Object):void
         {
            stage = main.stage;
            stage.addEventListener(Event.ENTER_FRAME,watchScoreboard);
         });
         Hooks.gameStateChanging.add(function(from:uint, to:uint):void
         {
            if(to == 5 && (on || armNext) && replaying)
            {
               armNext = false;
               replayArmed = true;
               replaySaved = false;
               replayGaps = false;
               lastStep = 0;
               GameApp.var_2095 = true;
               ownDump = true;
               tracking = true;
               fresh = false;
               strings = [];
               dealt = [];
               dodgeGrids = [];
               dodgeSeen = [];
               lastTime = 0;
            }
            else if(to == 3 && replayArmed && replaying)
            {
               fresh = false;
            }
            else if(to == 3)
            {
               fresh = true;
               ownDump = false;
               tracking = false;
               strings = [];
               dealt = [];
               dodgeGrids = [];
               dodgeSeen = [];
               lastTime = 0;
            }
            else if(to == 6 && fresh)
            {
               fresh = false;
               record();
            }
         });
         Hooks.matchStatsRecording.add(function(game:Object):void
         {
            if(ownDump)
            {
               GameApp.var_2095 = true;
            }
         });
         Hooks.statsDumping.add(function(dumper:Object):Boolean
         {
            try
            {
               capture(ScreenManager.owner);
            }
            catch(e:Error)
            {
               ErrorLog.write("post-match stats: " + e + " at " + at);
            }
            return ownDump && !GameApp.var_7504;
         });
         Hooks.scoreboardInput.add(function(board:Object, input:int):Boolean
         {
            if(input == 20 && scoreboardShown() && ReplaysWindow.enabled)
            {
               ReplaysWindow.afterMatch();
               return true;
            }
            if(input != INPUT || !scoreboardShown())
            {
               return false;
            }
            if(window == null || !window.isActive)
            {
               open();
            }
            return true;
         });
         Hooks.matchStarted.add(function():void
         {
            last = null;
            ReplayStore.matchStarted();
            ReplaysWindow.matchStarted();
         });
         Hooks.frameRendering.add(function():void
         {
            if(!(replayArmed && replaying))
            {
               watchStrings();
            }
         });
         Hooks.legendStepping.add(function(legend:Object, time:uint):void
         {
            if(replayArmed && time != lastStep && replaying)
            {
               lastStep = time;
               watchStrings(time);
            }
         });
         Hooks.frameStarting.add(holdReplayFlag);
         Hooks.keyDown.add(function(event:Object):Boolean
         {
            if(event == null || event.ctrlKey || event.shiftKey || event.altKey || uint(event.keyCode) != KEY)
            {
               return false;
            }
            if(window != null && window.isActive)
            {
               return true;
            }
            if(!scoreboardShown() && !replayStats())
            {
               return false;
            }
            openNow();
            return true;
         });
      }

      private static function record() : void
      {
         if(on && !GameApp.var_2095)
         {
            GameApp.var_2095 = true;
            ownDump = true;
         }
         else if(!GameApp.var_2095)
         {
            ownDump = false;
         }
         tracking = GameApp.var_2095;
      }

      public static function get on() : Boolean
      {
         return ModSettings.flag("postMatchStats",true);
      }

      public static function set on(v:Boolean) : void
      {
         ModSettings.setFlag("postMatchStats",v);
      }

      public static function get replaying() : Boolean
      {
         try
         {
            var game:Object = ScreenManager.owner;
            return game != null && (uint(game.var_3595) & (1024 | 2048 | 8192)) != 0;
         }
         catch(e:Error)
         {
         }
         return false;
      }

      private static function replayStats() : Boolean
      {
         return replayArmed && tracking && replaying;
      }

      private static function holdReplayFlag() : void
      {
         if(!replayArmed)
         {
            return;
         }
         if(replaying)
         {
            if(!GameApp.var_2095)
            {
               GameApp.var_2095 = true;
            }
            if(!replaySaved && !replayGaps && tracking && (uint(ScreenManager.owner.var_3595) & 2048) != 0)
            {
               replaySaved = true;
               var name:String = replayName();
               if(name != null && !ReplayStore.hasStats(name))
               {
                  ReplayStore.saveStats(name,replaySnapshot(),"watched");
               }
            }
            return;
         }
         replayArmed = false;
         tracking = false;
         ownDump = false;
      }

      private static function rewound(now:uint) : void
      {
         for each(var mine:Object in strings)
         {
            if(mine == null)
            {
               continue;
            }
            for(var k:String in mine)
            {
               if(uint(k) > now)
               {
                  delete mine[k];
               }
            }
         }
         for(var i:int = 0; i < dodgeGrids.length; i++)
         {
            var times:Array = dodgeGrids[i];
            while(times != null && times.length > 0 && uint(times[times.length - 1][0]) > now)
            {
               times.pop();
            }
         }
      }

      private static function grid(times:Array) : Array
      {
         var out:Array = [0,0,0,0,0,0,0,0,0];
         for each(var t:Array in times)
         {
            var cell:int = int(t[1]);
            out[cell] = int(out[cell]) + 1;
         }
         return out;
      }

      private static function scoreboardShown() : Boolean
      {
         return last != null && ScreenManager.var_6219 != null && ScreenManager.var_6219.isActive;
      }

      private static function watchStrings(stepTime:int = -1) : void
      {
         if(!tracking || !(Platform.matchRunning || replayArmed && replaying) || !GameApp.var_2095)
         {
            return;
         }
         var game:GameCore = ScreenManager.owner;
         if(game == null || game.var_7050 == null)
         {
            return;
         }
         var now:uint = stepTime >= 0 ? uint(stepTime) : uint(game.var_13849);
         if(now < lastTime)
         {
            rewound(now);
            replayGaps = replayGaps || replayArmed;
         }
         else if(replayArmed && lastTime != 0 && now > lastTime + GAP_MS)
         {
            replayGaps = true;
         }
         lastTime = now;
         var players:Object = game.var_7050;
         var n:int = int(players.length);
         var i:int;
         var legend:class_123;
         for(i = 0; i < n; i++)
         {
            legend = players[i];
            if(legend == null || legend.var_4712 == 0)
            {
               continue;
            }
            var mine:Object = strings[i];
            if(mine == null)
            {
               mine = strings[i] = {};
            }
            var end:uint = uint(legend.var_8895 + legend.var_9413 + 2 * STEP);
            var rec:Object = mine[legend.var_4712];
            if(rec == null)
            {
               mine[legend.var_4712] = {"end":end,"attacker":attackerOf(players,i,n)};
               noted++;
            }
            else if(end > uint(rec.end))
            {
               rec.end = end;
            }
         }
         for(i = 0; i < n; i++)
         {
            legend = players[i];
            dealt[i] = legend != null && legend.var_3140 != null ? legend.var_3140.var_409 : 0;
            noteDodge(legend,i);
         }
      }

      private static function noteDodge(legend:class_123, i:int) : void
      {
         var s:GameStats = legend != null ? legend.var_3140 : null;
         if(s == null)
         {
            return;
         }
         var count:int = int(s.var_38) + int(s.var_3280);
         var before:* = dodgeSeen[i];
         dodgeSeen[i] = count;
         if(before == null || count <= int(before))
         {
            return;
         }
         var bits:uint = legend.var_10012 != null ? uint(legend.var_10012.var_13063) : 0;
         var row:int = (bits & 1) != 0 ? 0 : ((bits & 2) != 0 ? 2 : 1);
         var col:int = (bits & 4) != 0 ? 0 : ((bits & 8) != 0 ? 2 : 1);
         var times:Array = dodgeGrids[i];
         if(times == null)
         {
            times = dodgeGrids[i] = [];
         }
         times.push([lastTime,row * 3 + col]);
      }

      private static function attackerOf(players:Object, victim:int, n:int) : int
      {
         var found:int = -1;
         for(var j:int = 0; j < n; j++)
         {
            var legend:class_123 = players[j];
            if(j == victim || legend == null || legend.var_3140 == null)
            {
               continue;
            }
            if(legend.var_3140.var_409 > Number(dealt[j]))
            {
               if(found >= 0)
               {
                  return -1;
               }
               found = j;
            }
         }
         if(found < 0 && n == 2)
         {
            found = 1 - victim;
         }
         return found;
      }

      private static function combosOn(victim:int, seq:Array, base:uint) : Array
      {
         var out:Array = [];
         var mine:Object = strings[victim];
         if(mine == null || seq == null)
         {
            return out;
         }
         var starts:Array = [];
         for(var k:* in mine)
         {
            starts.push(uint(k));
         }
         starts.sort(Array.NUMERIC);
         var values:Array = [];
         var value:Number = 0;
         for(var q:int = 0; q < seq.length; q++)
         {
            if(seq[q] is Number && !isNaN(seq[q]))
            {
               value = seq[q];
            }
            values.push(value);
         }
         if(ModSettings.value("matchStatsLog") == true)
         {
            var rises:Array = [];
            for(q = 1; q < values.length; q++)
            {
               if(values[q] > values[q - 1])
               {
                  rises.push(q);
               }
            }
            var spans:Array = [];
            for each(var st:uint in starts)
            {
               spans.push(int((st - base) / STEP) + "-" + int((uint(mine[st].end) - base) / STEP));
            }
            ErrorLog.write("post-match stats: P" + victim + " strings " + spans.join(" ") + " | rises " + rises.join(" "));
         }
         var nextFirst:int = int.MAX_VALUE;
         for(var si:int = starts.length - 1; si >= 0; si--)
         {
            var start:uint = starts[si];
            if(start < base)
            {
               continue;
            }
            var first:int = int((start - base) / STEP);
            if(first < 1 || first >= values.length || values[first] <= values[first - 1])
            {
               unmatched++;
               if(unmatched <= 5)
               {
                  ErrorLog.write("post-match stats: string at " + start + " (step " + first + ") " + values.slice(Math.max(0,first - 3),first + 4).join(","));
               }
               continue;
            }
            var last:int = Math.min(int((uint(mine[start].end) - base) / STEP),nextFirst - 1,values.length - 1);
            nextFirst = first;
            var hits:int = 0;
            var lastHit:int = first;
            for(var x:int = first; x <= last; x++)
            {
               if(values[x] > values[x - 1])
               {
                  if(x == first || values[x - 1] <= values[x - 2])
                  {
                     hits++;
                  }
                  lastHit = x;
               }
               else if(values[x] < values[x - 1])
               {
                  break;
               }
            }
            if(hits < 2)
            {
               singles++;
            }
            if(hits >= 2)
            {
               out.push({"victim":victim,"attacker":int(mine[start].attacker),"start":first * STEP,"hits":hits,
                  "damage":values[lastHit] - values[first - 1]});
            }
         }
         return out;
      }

      private static function capture(game:GameCore, snapshot:Boolean = false) : void
      {
         var end:uint = game != null ? (game.var_14357 != 0 ? uint(game.var_14357) : (replaying ? uint(game.var_13849) : 0)) : 0;
         if(game == null || end == 0 || !GameApp.var_2095 || game.var_8999 == null)
         {
            return;
         }
         at = "players";
         var players:Array = [];
         var longest:int = 0;
         var byLegend:Array = [];
         var combos:Array = [];
         if(!snapshot)
         {
            tracking = false;
         }
         for(var i:int = 0; i < game.var_7050.length; i++)
         {
            var legend:class_123 = game.var_7050[i];
            var s:GameStats = legend != null ? legend.var_3140 : null;
            if(s == null || s.var_5807 == null)
            {
               continue;
            }
            var p:Object = player(legend,s,players.length);
            longest = Math.max(longest,p.damage.length);
            p.dodgeGrid = grid(dodgeGrids[i]);
            byLegend[i] = p;
            players.push(p);
            at = "player " + i + " combos";
            combos = combos.concat(combosOn(i,s.var_5807,uint(game.var_5300 + 6000)));
         }
         if(!snapshot)
         {
            strings = [];
         }
         if(players.length == 0)
         {
            return;
         }
         at = "combos";
         for each(var c:Object in combos)
         {
            var by:Object = c.attacker >= 0 ? byLegend[c.attacker] : null;
            if(by == null)
            {
               continue;
            }
            by.combos++;
            by.comboDamage += c.damage;
            if(by.best == null || c.hits > by.best.hits || c.hits == by.best.hits && c.damage > by.best.damage)
            {
               by.best = c;
            }
         }
         at = "summary";
         last = {
            "players":players,
            "length":end > uint(game.var_5300 + 6000) ? uint(uint(end - game.var_5300) - 6000) : 0,
            "bucket":BUCKET * STEP,
            "points":longest,
            "teams":(game.var_8999.var_2458 & 1) != 0,
            "mode":game.var_8999.var_615 != null ? class_256.method_1351(game.var_8999.var_615.mDisplayNameKey) : ""
         };
         if(!snapshot && !replaying)
         {
            ReplayStore.matchStats(last);
         }
         ErrorLog.write("post-match stats: " + players.length + " players, " + last.length + " ms, " + longest + " points, " +
            combos.length + " combos (" + noted + " strings noted, " + unmatched + " not in the record, " + singles + " single hits)");
         noted = unmatched = singles = 0;
      }

      private static function player(legend:class_123, s:GameStats, index:int) : Object
      {
         at = "player " + index + " legend";
         var hero:HeroType = null;
         if(legend.var_12798 != null && legend.var_12798.length > 0)
         {
            hero = HeroType.var_1273[legend.var_12798[0].var_11835 & 0xFFFF];
         }
         at = "player " + index + " totals";
         var p:Object = {
            "name":legend.var_6307 != null ? legend.var_6307.var_14792 : legend.var_4741,
            "legend":hero != null ? String(hero.mDisplayName) : "",
            "hero":hero != null ? String(hero.mHeroName) : "",
            "team":legend.var_3540,
            "color":COLORS[index % COLORS.length],
            "dealt":s.var_409,
            "taken":s.var_7376 + s.var_14337,
            "kos":s.var_6689,
            "falls":s.var_8654,
            "sds":s.var_4197,
            "dodges":s.var_38,
            "airDodges":s.var_3280,
            "dashes":s.var_13326,
            "jumps":s.var_11550,
            "air":s.var_2463 * STEP,
            "ground":s.var_14786 * STEP,
            "wall":s.var_1009 * STEP,
            "clashes":s.var_8215,
            "score":legend.var_15029,
            "combos":0,"comboDamage":0,"best":null
         };
         at = "player " + index + " damage";
         var damage:Array = [];
         var seq:Array = s.var_5807;
         var value:Number = 0;
         for(var k:int = 0; k < seq.length; k++)
         {
            var v:* = seq[k];
            if(v is Number && !isNaN(v))
            {
               value = v;
            }
            if(k % BUCKET == BUCKET - 1 || k == seq.length - 1)
            {
               damage.push(value);
            }
         }
         p.damage = damage;
         at = "player " + index + " attacks";
         var byKey:Object = {};
         var damageBy:Object = Object(s.var_15334).h;
         var usesBy:Object = Object(s.var_1957).h;
         var key:uint;
         var a:Object;
         for(var dk:* in damageBy)
         {
            key = uint(dk);
            a = attack(byKey,key);
            a.damage += Number(damageBy[dk]);
         }
         for(var uk:* in usesBy)
         {
            key = uint(uk);
            var packed:uint = uint(usesBy[uk]);
            a = attack(byKey,key);
            a.uses += packed & 0x0FFF;
            a.hits += (packed >>> 12) & 0x0FFF;
            a.kos += packed >>> 24;
         }
         at = "player " + index + " sort";
         var attacks:Array = [];
         for each(a in byKey)
         {
            attacks.push(a);
         }
         attacks.sortOn(["damage","hits"],[Array.NUMERIC | Array.DESCENDING,Array.NUMERIC | Array.DESCENDING]);
         p.attacks = attacks;
         return p;
      }

      private static function attack(byKey:Object, key:uint) : Object
      {
         var k:uint = key & ~uint(2 | 0x80000000);
         var a:Object = byKey[k];
         if(a == null)
         {
            at = "attack " + key.toString(16);
            var item:ItemType = ItemType.var_7348[(k >>> 16) & 0x0FFF];
            var name:* = Object(class_79.var_5896).h[k & class_79.var_430];
            a = byKey[k] = {
               "weapon":item != null ? String(item.var_12885) : "",
               "name":name != null ? String(name) : "?",
               "damage":0,"uses":0,"hits":0,"kos":0
            };
         }
         return a;
      }

      private static function watchScoreboard(e:Event) : void
      {
         var inReplay:Boolean = !scoreboardShown() && replayStats();
         var show:Boolean = (scoreboardShown() || inReplay) && !(window != null && window.isActive);
         if(button != null && buttonForReplay != inReplay && show)
         {
            if(buttonLayer != null && buttonLayer.parent != null)
            {
               buttonLayer.parent.removeChild(buttonLayer);
            }
            button = null;
            buttonLayer = null;
         }
         if(show && button == null)
         {
            buttonForReplay = inReplay;
            button = new Sprite();
            button.buttonMode = true;
            UiKit.rect(button,0,0,236,34,UiKit.WHITE,8);
            UiKit.text(button,inReplay ? "MATCH STATS (TAB)" : "MATCH STATS (TAB / R3)",118,7,15,UiKit.NAVY_TEXT,UiKit.XBOLD,0,true);
            button.addEventListener(MouseEvent.CLICK,function(ev:MouseEvent):void
            {
               ev.stopPropagation();
               openNow();
            });
            watchButton = null;
            if(!inReplay && ReplaysWindow.enabled)
            {
               watchButton = new Sprite();
               watchButton.buttonMode = true;
               watchButton.x = 250;
               UiKit.rect(watchButton,0,0,236,34,UiKit.WHITE,8);
               UiKit.text(watchButton,"WATCH REPLAY",118,7,15,UiKit.NAVY_TEXT,UiKit.XBOLD,0,true);
               watchButton.addEventListener(MouseEvent.CLICK,function(ev:MouseEvent):void
               {
                  ev.stopPropagation();
                  ReplaysWindow.afterMatch();
               });
               button.addChild(watchButton);
            }
         }
         if(button == null)
         {
            return;
         }
         if(buttonLayer == null)
         {
            buttonLayer = new Sprite();
            buttonLayer.addChild(button);
         }
         if(show)
         {
            var screen:Object = inReplay ? ScreenManager.var_14460 : ScreenManager.var_6219;
            Layers.put(buttonLayer,Layers.screenOf(screen != null && screen.var_2459 != null ? screen.var_2459.clip as DisplayObject : null),stage);
         }
         else if(buttonLayer.parent != null)
         {
            buttonLayer.parent.removeChild(buttonLayer);
         }
         if(show)
         {
            var sx:Number = stage.stageWidth / 1920;
            var sy:Number = stage.stageHeight / 1080;
            var sc:Number = Math.min(sx,sy);
            button.scaleX = button.scaleY = sc;
            button.x = 24 * sc;
            button.y = stage.stageHeight - 60 * sc;
         }
      }

      private static function openNow() : void
      {
         if(!scoreboardShown() && replayStats())
         {
            try
            {
               capture(ScreenManager.owner,true);
            }
            catch(e:Error)
            {
               ErrorLog.write("post-match stats: replay snapshot: " + e + " at " + at);
            }
         }
         open();
      }

      public static function replayName() : String
      {
         try
         {
            var header:Object = ScreenManager.owner.var_5368;
            return header != null && header.clipLibrary ? String(header.clipLibrary) + ".replay" : null;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      public static function get replayComplete() : Boolean
      {
         return replayArmed && !replayGaps;
      }

      public static function replaySnapshot() : Object
      {
         if(!replayStats())
         {
            return null;
         }
         try
         {
            capture(ScreenManager.owner,true);
         }
         catch(e:Error)
         {
            ErrorLog.write("post-match stats: replay snapshot: " + e + " at " + at);
            return null;
         }
         return last;
      }

      public static function openWith(stats:Object) : void
      {
         if(stats == null)
         {
            return;
         }
         last = stats;
         open();
      }

      public static function open() : void
      {
         if(last == null)
         {
            return;
         }
         if(window == null || ScreenManager.allScreens.indexOf(window) < 0)
         {
            window = new PostMatchStatsWindow(ScreenManager.owner);
            ScreenManager.registerScreen(window);
            if(ScreenManager.var_14744 != null)
            {
               window.registrationIndex = ScreenManager.var_14744.registrationIndex;
            }
         }
         if(!window.isActive)
         {
            window.focusBefore = ScreenBase.focusedScreen;
            window.stats = last;
            window.Display();
         }
      }

      public static function get shown() : PostMatchStatsWindow
      {
         return window != null && window.isActive ? window : null;
      }
   }
}
