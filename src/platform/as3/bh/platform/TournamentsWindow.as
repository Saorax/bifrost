package bh.platform
{
   import bh.platform.net.PrivateServer;
   import bh.platform.net.ServerStats;
   import bh.platform.net.Tournaments;
   import flash.display.Bitmap;
   import flash.display.MovieClip;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.events.MouseEvent;
   import flash.text.TextField;

   public class TournamentsWindow extends BigWindow
   {
      private static const TABS:Array = ["TOURNAMENTS","OVERVIEW","STANDINGS","POOLS","BRACKET","CREATE"];
      private static const T_LIST:int = 0;
      private static const T_OVERVIEW:int = 1;
      private static const T_STANDINGS:int = 2;
      private static const T_POOLS:int = 3;
      private static const T_BRACKET:int = 4;
      private static const T_CREATE:int = 5;
      private static const FILTERS:Array = ["ALL","LIVE","OPEN","FINISHED","MINE"];
      private static const LIST_PAGE:int = 6;
      private static const STAND_PAGE:int = 10;
      private static const SLICES:Array = ["FULL","TOP 32","TOP 8"];
      private static const SLICE_SIDES:Array = [0,32,8];
      private static const LINE_OPEN:uint = 0x2A4560;
      private static const LINE_DONE:uint = 0x3F7A8C;
      private static const AMBER:uint = 0xF5B841;
      private static const GREEN:uint = 0x4FD67A;
      private static const GREEN_ROW:uint = 0x0F3326;
      private static const GREEN_CELL:uint = 0x15442F;
      private static const RED_CELL:uint = 0x47202A;
      private static const BEST_OF:Array = [1,3,5];
      private static const LATER_BEST_OF:Array = [0,3,5,7];
      private static const LIMITS:Array = [4,8,16,32,64,128,256];
      private static const MODES:Array = ["1v1","2v2"];
      private static const CHECKINS:Array = [0,5,10,15,20,30];
      private static const ELIMINATIONS:Array = ["SINGLE","DOUBLE","DOUBLE, NO RESET"];
      private static const STOCKS:Array = [1,2,3,4,5,6,7,8,9,10];
      private static const MINUTES:Array = [2,3,4,5,6,7,8,9,10,12,15,20,25,30];
      private static const SCORINGS:Array = [[2,"STOCK","a_ScoringIcon_STOCK","",true,"Last one standing wins."],
         [1,"TIMED","a_ScoringIcon_TIMED","",false,"Most points when time runs out wins."],
         [3,"BRAWLBALL","a_ScoringIcon_BRAWLBALL","2v2",false,"Carry the ball into the other team's goal."],
         [4,"BOMBSKETBALL","a_ScoringIcon_BOMBSKETBALL","2v2",false,"Throw bombs into the other team's hoop."],
         [33,"CAPTURE THE FLAG","a_ScoringIcon_CTF","2v2",false,"Bring the other team's flag home."],
         [39,"KUNG FOOT","a_ScoringIcon_SOCCER","2v2",false,"Knock the ball into the other team's goal."],
         [48,"CREW BATTLE","a_ScoringIcon_CREWBATTLE","2v2",true,"Teammates take turns; the last crew standing wins."],
         [49,"STREET BRAWL","a_ScoringIcon_STREETFIGHT","1v1",true,"A street fight on its own maps."]];
      private static const VARIATION_NAMES:Array = ["NONE","STRIKEOUT","SWITCHCRAFT","MORPH"];
      private static const VARIATION_ABOUT:Array = ["No variation.","A different legend for each stock.",
         "Legends switch during the game.","Legends change into others during the game."];
      private static const WEAPON_RATES:Array = [0,1,2,3];
      private static const GADGET_RATES:Array = [0,4,5,6];
      private static const RATE_NAMES:Array = ["OFF","LOW","MEDIUM","HIGH"];
      private static const PRESETS:Array = [
         {"name":"QUICK","mode":"1v1","limit":16,"losers":0,"bestOf":1,"top8":0,"final":3,"checkin":5,"scoring":2,
          "stocks":3,"minutes":8,"gadgets":0,"mapPick":"tournament","about":"1v1, single elimination, best of 1 (final best of 3)."},
         {"name":"STANDARD","mode":"1v1","limit":32,"losers":1,"bestOf":3,"top8":0,"final":5,"checkin":10,"scoring":2,
          "stocks":3,"minutes":8,"gadgets":0,"mapPick":"tournament","about":"1v1, double elimination, best of 3 (final best of 5)."},
         {"name":"CHAMPIONSHIP","mode":"1v1","limit":64,"losers":1,"bestOf":3,"top8":5,"final":5,"checkin":10,"scoring":2,
          "stocks":3,"minutes":8,"gadgets":0,"mapPick":"tournament","about":"1v1, double elimination, best of 3, best of 5 from the top 8."},
         {"name":"2V2","mode":"2v2","limit":16,"losers":1,"bestOf":3,"top8":0,"final":5,"checkin":10,"scoring":2,
          "stocks":3,"minutes":8,"gadgets":0,"mapPick":"tournament","about":"Teams of two, double elimination, best of 3."},
         {"name":"PARTY","mode":"1v1","limit":16,"losers":0,"bestOf":1,"top8":0,"final":0,"checkin":0,"scoring":1,
          "stocks":3,"minutes":3,"gadgets":5,"mapPick":"random","about":"1v1 timed games with gadgets, random maps, no check-in."}];
      private static const SEEDINGS:Array = ["rating","random","signup","manual"];
      private static const SEEDING_NAMES:Array = ["RATING","RANDOM","SIGN-UP","MANUAL"];
      private static const LIST_RULES:Array = ["","ban","only"];
      private static const RULE_NAMES:Array = ["ANY","BAN","ONLY"];
      private static const WEAPONS:Array = ["Axe","Boots","Bow","Cannon","Chakram","Fists","Greatsword","Hammer","Katar",
         "Orb","Pistol","RocketLance","Scythe","Spear","Sword"];
      private static const WEAPON_NAMES:Array = ["AXE","BATTLE BOOTS","BOW","CANNON","CHAKRAM","GAUNTLETS","GREATSWORD",
         "HAMMER","KATARS","ORB","BLASTERS","ROCKET LANCE","SCYTHE","SPEAR","SWORD"];
      private static const MAP_POOLS:Object = {"1v1":[36,98,3,33],"2v2":[37,99,109,4]};
      private static const POOL_NAMES:Object = {"36":"TOURNAMENT","98":"RANKED","3":"STANDARD","33":"EXPERIMENTAL",
         "37":"TOURNAMENT","99":"RANKED","109":"UNRANKED","4":"STANDARD"};
      private static const MAP_PICKS:Array = ["tournament","random","straight","snake"];
      private static const MAP_PICK_NAMES:Array = ["TOURNAMENT STRIKING","RANDOM","TURNS STRIKING","SNAKE STRIKING"];
      private static const MAP_PICK_ABOUT:Array = ["The loser of the last game strikes maps until 3 are left; the other side picks one.",
         "A random map from the pool each game.","Players take turns striking maps.","Strikes go 1-2-2-1..."];
      private static const DAYS:Array = ["SUN","MON","TUE","WED","THU","FRI","SAT"];
      private static const START_DAYS:int = 365;
      private static const POOL_TOPS:Array = [0,4,8,16,32,64,128];
      private static const POOL_SENDS:Array = [1,2,4];
      private static const POOL_KINDS:Array = ["robin","bracket"];
      private static const POOL_KIND_NAMES:Array = ["ROUND ROBIN","BRACKET"];
      private static const PHASE_SETS:Array = ["","8","32,8","8,2","32,8,2"];
      private static const PHASE_NAMES:Array = ["NONE","TOP 8","TOP 32, TOP 8","TOP 8, FINALS","TOP 32, 8, FINALS"];
      private static const INFO_H:Number = 200;
      private static const HEAD_H:Number = 36;

      private static var window:TournamentsWindow;
      private static var listening:Boolean = false;

      private var detail:Sprite;
      private var info:Sprite;
      private var infoQuery:String = null;
      private var infoTitle:String = null;
      private static const MIN_COL_W:Number = 165;
      private var slice:int = 0;
      private var phasePicked:int = -1;
      private var phasePickedFor:int = -1;
      private var filter:int = 0;
      private var listPage:int = 0;
      private var standPage:int = 0;
      private var detailW:Number = 0;
      private var topFrom:int = 0;
      private var lowFrom:int = 0;
      private var bracketTop:Array = [];
      private var bracketLow:Array = [];
      private var visCols:int = 0;
      private static const DRAG_START:Number = 6;
      private var bracketScroll:Object = null;
      private var bracketColW:Number = 0;
      private var drag:Object = null;
      private var findText:String = "";
      private var pendingW:String = null;
      private var shownId:int = -1;
      private var message:String = null;
      private var armed:String = null;
      private var focusRow:Boolean = false;
      private var newRow:int = -1;

      private var newName:String = "";
      private var newAbout:String = "";
      private var newBestOf:int = 1;
      private var newLimit:int = 1;
      private var newMode:int = 0;
      private var newCheckin:int = 2;
      private var newTop8:int = 0;
      private var editingId:int = -1;
      private var editingName:String = "";
      private var editingBefore:Object = null;
      private var editingStartAt:Number = 0;
      private var newFinal:int = 0;
      private var newLosers:int = 0;
      private var newStocks:int = 2;
      private var newMinutes:int = 5;
      private var newSeeding:int = 0;
      private var newStartAt:Number = 0;
      private var newLegendRule:int = 0;
      private var newLegends:Array = [];
      private var newWeaponRule:int = 0;
      private var newWeapons:Array = [];
      private var newPool:int = 0;
      private var newMapPick:int = 0;
      private var newPreset:int = 1;
      private var newScoring:int = 0;
      private var newDamage:int = 100;
      private var newVariation:int = 0;
      private var newWeaponRate:int = 2;
      private var newGadgetRate:int = 0;
      private var newTeamDamage:Boolean = true;
      private var newPoolsTop:int = 0;
      private var newPoolSend:int = 1;
      private var newPoolKind:int = 0;
      private var newPhaseSet:int = 0;
      private var poolShown:int = 0;
      private var poolRound:int = 0;
      private var createHint:TextField;
      private var newRules:String = "";
      private var newRegion:String = "";
      private var newStream:String = "";
      private var newPrize:String = "";

      public function TournamentsWindow(core:GameCore)
      {
         super(core);
         applyPreset(newPreset);
      }

      public static function open(id:int = -1, create:Boolean = false) : void
      {
         if(window == null || ScreenManager.allScreens.indexOf(window) < 0)
         {
            window = new TournamentsWindow(ScreenManager.owner);
            ScreenManager.registerScreen(window);
            if(ScreenManager.var_14744 != null)
            {
               window.registrationIndex = ScreenManager.var_14744.registrationIndex;
            }
         }
         if(!listening)
         {
            listening = true;
            ServerStats.listeners.push(function(query:String):void
            {
               if(window != null && window.isActive)
               {
                  window.arrived(query);
               }
            });
         }
         if(PrivateServer.host != null)
         {
            ServerStats.ask("tournaments");
            if(id >= 0)
            {
               ServerStats.ask("tournament:" + id);
            }
         }
         window.shownId = id;
         window.focusRow = id >= 0;
         window.focus = 0;
         window.message = null;
         window.armed = null;
         window.tab = create ? T_CREATE : id >= 0 ? T_OVERVIEW : T_LIST;
         window.standPage = 0;
         if(!window.isActive)
         {
            window.Display();
         }
         window.build();
      }

      public static function get shown() : TournamentsWindow
      {
         return window != null && window.isActive ? window : null;
      }

      override protected function get title() : String
      {
         return "TOURNAMENTS";
      }

      override protected function get tabNames() : Array
      {
         return TABS;
      }

      override protected function get confirmLabel() : String
      {
         return "DONE";
      }

      override protected function get fullPage() : Boolean
      {
         return true;
      }

      override protected function tabOff(i:int) : Boolean
      {
         if(i == T_POOLS)
         {
            var v:Object = shownId >= 0 ? ServerStats.get("tournament:" + shownId) : null;
            return v == null || int(v.pools_until) <= 0;
         }
         return i != T_LIST && i != T_CREATE && shownId < 0;
      }

      override protected function statusText() : String
      {
         if(PrivateServer.host == null)
         {
            return "Offline: tournaments live on the project's server.";
         }
         if(message != null)
         {
            return message;
         }
         var list:Object = ServerStats.get("tournaments");
         if(list != null && list.signed_in == false)
         {
            return "Sign in with Discord (Options > Account) to sign up or create one.";
         }
         var shown:Object = shownId >= 0 ? ServerStats.get("tournament:" + shownId) : null;
         return tab == T_LIST ? "Select a tournament to see its page." : tab == T_OVERVIEW ? (shown != null &&
            shown.state == "done" ? "It's over: STANDINGS has every place, BRACKET every match." : shown != null &&
            shown.state == "running" ? "Live: BRACKET shows the matches being played." :
            "Sign up while it's open. For 2v2, invite a teammate or have them in your party.") :
            tab == T_STANDINGS ? "Select a player to see their profile." :
            tab == T_POOLS ? (shown != null && shown.pool_kind == "bracket" ?
            "Each pool is a small bracket, played until its top are left; they go on to the bracket." :
            "Everyone in a pool plays everyone once; the top of each pool goes on to the bracket.") :
            tab == T_BRACKET ? "Your match room opens once both sides have checked in." : "";
      }

      private function arrived(query:String) : void
      {
         if(query == "tournament-act")
         {
            var got:Object = ServerStats.get(query);
            if(got != null)
            {
               message = String(got.message);
               if(got.ok && got.action == "create" && got.id != null)
               {
                  shownId = int(got.id);
                  newName = "";
                  newAbout = "";
                  newRules = newRegion = newStream = newPrize = "";
                  tab = T_OVERVIEW;
                  ServerStats.ask("tournament:" + shownId);
               }
               Tournaments.fetch();
            }
            build();
         }
         else if(query == "tournaments" && tab == T_LIST || query == "tournament:" + shownId)
         {
            if(tab == T_POOLS && query != "tournaments")
            {
               ServerStats.ask(poolQuery());
            }
            build();
         }
         else if(tab == T_POOLS && query == poolQuery())
         {
            build();
         }
         else if(query == infoQuery)
         {
            drawInfo();
         }
      }

      override protected function build() : void
      {
         if((focusRow || newRow >= 0) && tab == T_LIST)
         {
            focus = int.MAX_VALUE;
         }
         super.build();
         if(pendingW != null)
         {
            for(var i:int = 0; i < items.length; i++)
            {
               if(items[i].w == pendingW)
               {
                  pendingW = null;
                  focus = i;
                  paintFocus();
                  focused(items[i]);
                  break;
               }
            }
         }
      }

      override protected function useItem(it:Object, dir:int) : void
      {
         if(dir != 0 && it != null && it.tmatch != null)
         {
            stepRound(it,dir);
            return;
         }
         super.useItem(it,dir);
      }

      private function stepRound(it:Object, dir:int) : void
      {
         var row:Array = it.low ? bracketLow : bracketTop;
         var c:int = int(it.col) + dir;
         if(c < 0 || c >= row.length)
         {
            return;
         }
         var here:int = (row[it.col].matches as Array).length;
         var there:Array = row[c].matches as Array;
         var k:int = Math.min(there.length - 1,int((int(it.k) + 0.5) * there.length / here));
         showMatch(int(row[c].round),int(there[k].slot));
      }

      private function showMatch(rnd:int, slot:int) : void
      {
         var v:Object = shownId >= 0 ? ServerStats.get("tournament:" + shownId) : null;
         for each(var rd:Object in v != null && v.rounds != null ? v.rounds as Array : [])
         {
            if(int(rd.round) == rnd && rd.phase != null && int(rd.phase) != phasePicked && tab == T_BRACKET)
            {
               phasePicked = int(rd.phase);
               phasePickedFor = shownId;
               build();
            }
         }
         for each(var row:Array in [bracketTop,bracketLow])
         {
            for(var c:int = 0; c < row.length; c++)
            {
               if(int(row[c].round) != rnd)
               {
                  continue;
               }
               if(visCols > 0)
               {
                  var from:int = row === bracketLow ? lowFrom : topFrom;
                  if(c < from || c >= from + visCols)
                  {
                     from = c < from ? c : c - visCols + 1;
                  }
                  if(row === bracketLow)
                  {
                     lowFrom = from;
                  }
                  else
                  {
                     topFrom = from;
                  }
               }
            }
         }
         pendingW = "m" + rnd + ":" + slot;
         build();
      }

      public function findPlayer(text:String) : void
      {
         var v:Object = shownId >= 0 ? ServerStats.get("tournament:" + shownId) : null;
         findText = text;
         var hit:Object = v != null && v.rounds != null && findText.length > 0 ? findMatch(v,-1,findText.toLowerCase()) : null;
         message = hit != null ? "\"" + findText + "\": " + String(hit.name).toUpperCase() + "." :
            "Nobody named \"" + findText + "\" in this bracket.";
         if(hit != null)
         {
            showMatch(int(hit.round),int(hit.slot));
         }
         else
         {
            build();
         }
      }

      private function findMatch(v:Object, side:int, name:String) : Object
      {
         var found:Object = null;
         for each(var r:Object in v.rounds)
         {
            for each(var m:Object in r.matches)
            {
               var hit:Boolean = side >= 0 ? m.a != null && int(m.a) == side || m.b != null && int(m.b) == side :
                  m.a_name != null && String(m.a_name).toLowerCase().indexOf(name) >= 0 ||
                  m.b_name != null && String(m.b_name).toLowerCase().indexOf(name) >= 0;
               if(!hit)
               {
                  continue;
               }
               if(m.winner == null && m.a != null && m.b != null)
               {
                  return {"round":int(r.round != null ? r.round : 0),"slot":int(m.slot),"name":String(r.name)};
               }
               if(m.a != null && m.b != null || found == null)
               {
                  found = {"round":int(r.round != null ? r.round : 0),"slot":int(m.slot),"name":String(r.name)};
               }
            }
         }
         return found;
      }

      override protected function showTab(i:int) : void
      {
         message = null;
         if(shownId >= 0 && i != T_LIST && i != T_CREATE && PrivateServer.host != null)
         {
            ServerStats.ask("tournament:" + shownId);
         }
         super.showTab(i);
      }

      private function act(action:String, args:Object) : void
      {
         message = "Asking the server...";
         armed = null;
         if(!Tournaments.act(action,args))
         {
            message = "Not connected to the server.";
         }
         build();
      }

      override protected function buildTab(i:int) : void
      {
         detail = null;
         info = null;
         if(i == T_BRACKET)
         {
            buildBracket();
         }
         else if(i == T_CREATE)
         {
            buildCreate();
         }
         else if(i == T_OVERVIEW)
         {
            buildOverview();
         }
         else if(i == T_STANDINGS)
         {
            buildStandings();
         }
         else if(i == T_POOLS)
         {
            buildPools();
         }
         else
         {
            buildList();
         }
      }

      private function buildList() : void
      {
         var p:Sprite = panel(area.x,area.y,area.width,area.height);
         var got:Object = PrivateServer.host != null ? ServerStats.get("tournaments") : null;
         var all:Array = got != null ? got.tournaments as Array : null;
         var counts:Array = [0,0,0,0,0];
         var rows:Array = [];
         for each(var t:Object in all || [])
         {
            for(var f:int = 0; f < FILTERS.length; f++)
            {
               if(passes(t,f))
               {
                  counts[f]++;
               }
            }
            if(passes(t,filter))
            {
               rows.push(t);
            }
         }
         var chipNames:Array = [];
         for(var c:int = 0; c < FILTERS.length; c++)
         {
            chipNames.push(FILTERS[c] + " " + counts[c]);
         }
         var chipRow:Sprite = new Sprite();
         chipRow.x = 24;
         chipRow.y = 14;
         p.addChild(chipRow);
         var cw:Number = UiKit.chips(chipRow,chipNames,filter,focus == 0,function(i:int):void
         {
            filter = i;
            listPage = 0;
            build();
         });
         items.push({"w":"filter","sprite":chipRow,"parent":p,"width":cw,"height":24,"focusBox":[-12,-2,cw,28],
            "about":"Left / right: which tournaments to list.","change":function(d:int):void
            {
               filter = step(filter,d,FILTERS.length);
               listPage = 0;
            }});
         var nb:Sprite = button(p,"NEW TOURNAMENT",area.width - 224,10,200,function():void
         {
            showTab(T_CREATE);
         },30,13);
         items.push({"w":"new","sprite":nb,"parent":p,"width":200,"height":30,"use":function():void
         {
            showTab(T_CREATE);
         }});
         if(rows.length == 0)
         {
            UiKit.text(p,got == null ? (PrivateServer.host == null ? "Offline." : "Asking the server...") :
               got.error != null ? String(got.error) : all == null || all.length == 0 ?
               "No tournaments yet. Create the first one." : "None here. Pick another filter.",24,62,15,UiKit.LIGHT,
               UiKit.MEDIUM,area.width - 48);
            return;
         }
         var pages:int = Math.ceil(rows.length / LIST_PAGE);
         var focusAt:int = -1;
         if(focusRow || newRow >= 0)
         {
            var want:int = newRow >= 0 ? newRow : shownId;
            for(var k:int = 0; k < rows.length; k++)
            {
               if(int(rows[k].id) == want)
               {
                  listPage = int(k / LIST_PAGE);
               }
            }
         }
         listPage = Math.max(0,Math.min(listPage,pages - 1));
         if(shownId < 0)
         {
            shownId = int(rows[listPage * LIST_PAGE].id);
            ServerStats.get("tournament:" + shownId);
         }
         var cols:int = 2;
         var gap:Number = 14;
         var cardW:Number = (area.width - 40 - gap * (cols - 1)) / cols;
         var cardH:Number = Math.floor((area.height - 54 - 52) / (LIST_PAGE / cols)) - gap;
         for(var n:int = listPage * LIST_PAGE; n < Math.min(rows.length,(listPage + 1) * LIST_PAGE); n++)
         {
            if(int(rows[n].id) == shownId && focusAt < 0)
            {
               focusAt = items.length;
            }
            var k:int = n - listPage * LIST_PAGE;
            row(p,20 + k % cols * (cardW + gap),54 + int(k / cols) * (cardH + gap),cardW,cardH,rows[n]);
         }
         if(pages > 1)
         {
            navBar(p,20,area.height - 40,280,32,"PAGE " + (listPage + 1) + " OF " + pages,"page",
               "Left and right, or the arrows, for another page.",function(d:int):void
               {
                  listPage = (listPage + d + pages) % pages;
               });
         }
         if(focusRow)
         {
            focusRow = false;
            focus = Math.max(0,focusAt);
         }
         else if(newRow >= 0)
         {
            focus = focusAt >= 0 ? focusAt : 0;
            newRow = focusAt >= 0 ? -1 : newRow;
         }
      }

      private static function passes(t:Object, f:int) : Boolean
      {
         return f == 0 || f == 1 && t.state == "running" || f == 2 && t.state == "open" || f == 3 && t.state == "done" ||
            f == 4 && (t.mine == true || t.signed_up == true);
      }

      private function row(list:Sprite, x:Number, y:Number, w:Number, h:Number, t:Object) : void
      {
         var s:Sprite = new Sprite();
         s.x = x;
         s.y = y;
         list.addChild(s);
         var state:String = String(t.state);
         UiKit.rect(s,0,0,w,h,int(t.id) == shownId ? UiKit.ROW_SELECTED : UiKit.BODY,8);
         UiKit.rect(s,0,0,w,5,stateColor(state),4);
         var tx:Number = 18;
         for each(var tag:Array in [[stateName(state),stateColor(state)],[t.signed_up ? "SIGNED UP" : "",UiKit.TEAL],
                                    [t.mine ? "YOURS" : "",UiKit.TEAL]])
         {
            if(tag[0] != "")
            {
               tx = pill(s,String(tag[0]),tx,14,uint(tag[1])) + 8;
            }
         }
         var whenLine:String = state == "open" ? (t.starts != null ? "STARTS " + when(t.starts) : "STARTS WHEN ITS HOST SAYS") :
            state == "running" ? "STARTED " + when(t.started) : "FINISHED " + when(t.finished);
         rtext(s,whenLine,w - 18,16,12,UiKit.GREY,UiKit.XBOLD);
         UiKit.fit(UiKit.text(s,String(t.name),18,36,22,UiKit.WHITE,UiKit.XBOLD),w - 36);
         var cx:Number = 18;
         for each(var chip:String in chipsOf(t))
         {
            if(cx < w - 120)
            {
               cx = pill(s,chip,cx,70,UiKit.LINE) + 6;
            }
         }
         var players:int = int(t.players);
         var most:int = Math.max(1,int(t.max_players));
         var by:Number = h - 36;
         UiKit.text(s,players + " / " + most + (t.mode == "2v2" ? " TEAMS" : " PLAYERS"),18,by,12,UiKit.LIGHT,UiKit.XBOLD);
         if(t.winner_name != null)
         {
            rtext(s,"WON BY " + String(t.winner_name).toUpperCase(),w - 18,by - 1,13,UiKit.GOLD,UiKit.XBOLD);
         }
         UiKit.rect(s,18,h - 18,w - 36,6,UiKit.LINE,6);
         UiKit.rect(s,18,h - 18,Math.max(6,(w - 36) * Math.min(1,players / most)),6,stateColor(state) == UiKit.GREY ?
            UiKit.GREY : UiKit.TEAL,6);
         var id:int = int(t.id);
         var it:Object = {"w":"t" + id,"id":id,"sprite":s,"parent":list,"width":w,"height":h,"dbl":true,
            "focusBox":[0,0,w,h],"use":function():void
            {
               showTab(T_OVERVIEW);
            }};
         s.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            focused(it);
         });
         items.push(it);
      }

      private static function chipsOf(t:Object) : Array
      {
         var out:Array = [String(t.mode || "1v1").toUpperCase()];
         if(t.region)
         {
            out.push(String(t.region).toUpperCase());
         }
         out.push("BEST OF " + int(t.best_of));
         out.push(int(t.losers) > 0 ? "DOUBLE ELIM" : "SINGLE ELIM");
         if(int(t.pools_until) > 0)
         {
            out.push("POOLS TO TOP " + int(t.pools_until));
         }
         return out;
      }

      private function tile(p:Sprite, x:Number, y:Number, w:Number, h:Number, label:String, value:String, color:uint,
                            part:Number = -1) : void
      {
         UiKit.rect(p,x,y,w,h,UiKit.BODY,8);
         UiKit.text(p,label,x + 14,y + 10,11,UiKit.GREY,UiKit.XBOLD);
         UiKit.fit(UiKit.text(p,value,x + 14,y + (value.length > 12 ? 30 : 26),value.length > 12 ? 15 : 20,color,UiKit.XBOLD),
            w - 28);
         if(part >= 0)
         {
            UiKit.rect(p,x + 14,y + h - 12,w - 28,5,UiKit.LINE,5);
            UiKit.rect(p,x + 14,y + h - 12,Math.max(5,(w - 28) * Math.min(1,part)),5,UiKit.TEAL,5);
         }
      }

      private static function pill(p:Sprite, label:String, x:Number, y:Number, color:uint) : Number
      {
         var t:TextField = UiKit.text(p,label,x + 8,y + 3,11,color == UiKit.LINE ? UiKit.LIGHT : UiKit.NAVY_TEXT,UiKit.XBOLD);
         var back:Shape = UiKit.rect(p,x,y,t.width + 16,20,color,20);
         p.setChildIndex(back,p.getChildIndex(t));
         return x + t.width + 16;
      }

      private static function stateColor(state:String) : uint
      {
         return state == "running" ? UiKit.TEAL : state == "open" ? UiKit.WHITE : UiKit.GREY;
      }

      private static const MONTHS:Array = ["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"];

      private static function when(secs:Object) : String
      {
         if(secs == null || Number(secs) <= 0)
         {
            return "";
         }
         var d:Date = new Date(Number(secs) * 1000);
         var mm:int = d.minutes;
         return MONTHS[d.month] + " " + d.date + ", " + d.hours + ":" + (mm < 10 ? "0" : "") + mm;
      }

      private static function ordinal(n:int) : String
      {
         var tens:int = n % 100;
         return n + (tens >= 11 && tens <= 13 ? "TH" : n % 10 == 1 ? "ST" : n % 10 == 2 ? "ND" : n % 10 == 3 ? "RD" : "TH");
      }

      private function buildOverview() : void
      {
         detailW = Math.round(area.width * 0.6);
         detail = panel(area.x,area.y,detailW,area.height);
         drawDetail();
      }

      private function drawCards(cards:Array) : void
      {
         var x:Number = area.x + detailW + 16;
         var w:Number = area.width - detailW - 16;
         var col:Sprite = panel(x,area.y,w,area.height);
         var y:Number = 14;
         for each(var card:Array in cards)
         {
            if(!card[1] || y > area.height - 60)
            {
               continue;
            }
            var c:Sprite = new Sprite();
            c.x = 14;
            c.y = y;
            col.addChild(c);
            UiKit.text(c,String(card[0]),14,10,12,UiKit.TEAL,UiKit.XBOLD);
            var body:TextField = UiKit.text(c,String(card[1]),14,30,13,UiKit.LIGHT,UiKit.MEDIUM,w - 56);
            var h:Number = Math.min(body.height + 40,area.height - 14 - y);
            var back:Shape = UiKit.rect(c,0,0,w - 28,h,UiKit.BODY,6);
            c.setChildIndex(back,0);
            y += h + 10;
         }
      }

      private function buildStandings() : void
      {
         var p:Sprite = panel(area.x,area.y,area.width,area.height);
         var v:Object = shownId >= 0 ? ServerStats.get("tournament:" + shownId) : null;
         if(v == null || v.error != null)
         {
            UiKit.text(p,v == null ? "Asking the server..." : String(v.error),24,14,14,UiKit.LIGHT,UiKit.MEDIUM);
            return;
         }
         UiKit.fit(UiKit.text(p,String(v.name),24,10,18,UiKit.WHITE,UiKit.XBOLD),area.width * 0.5);
         var started:Boolean = (v.rounds as Array || []).length > 0;
         var list:Array = standingsOrder(v);
         for each(var wl:Object in v.waitlist as Array || [])
         {
            list.push({"account":wl.account,"name":wl.name,"waiting":true});
         }
         var records:Object = recordsOf(v);
         var me:int = v.me != null ? int(v.me) : -1;
         var still:int = 0;
         for each(var se:Object in list)
         {
            still += started && !se.waiting && se.placement == null ? 1 : 0;
         }
         rtext(p,started ? (v.state == "done" ? "FINAL STANDINGS" : "STANDINGS SO FAR   ·   " + still + " STILL IN") :
            list.length + " SIGNED UP",area.width - 24,14,13,UiKit.GREY,UiKit.XBOLD);
         if(list.length == 0)
         {
            UiKit.text(p,"Nobody yet.",24,52,14,UiKit.LIGHT,UiKit.MEDIUM);
            return;
         }
         var top:Number = 48;
         var podium:Array = [];
         for each(var pe:Object in list)
         {
            if(pe.placement != null && int(pe.placement) <= 3 && podium.length < 3)
            {
               podium.push(pe);
            }
         }
         if(podium.length > 0)
         {
            var pw:Number = (area.width - 40 - 20) / 3;
            for(var q:int = 0; q < podium.length; q++)
            {
               var pd:Object = podium[q];
               var place:int = int(pd.placement);
               var card:Sprite = new Sprite();
               card.x = 20 + q * (pw + 10);
               card.y = top;
               p.addChild(card);
               UiKit.rect(card,0,0,pw,76,UiKit.BODY,8);
               UiKit.rect(card,0,0,6,76,UiKit.placeColour(place,UiKit.GREY),4);
               UiKit.text(card,ordinal(place),22,18,30,UiKit.placeColour(place,UiKit.GREY),UiKit.XBOLD);
               UiKit.fit(UiKit.text(card,String(pd.name),100,14,20,int(pd.account) == me ? UiKit.TEAL : UiKit.WHITE,UiKit.XBOLD),
                  pw - 116);
               var prec:Array = records[String(pd.account)] as Array || [0,0];
               UiKit.text(card,prec[0] + " WINS   ·   " + prec[1] + " LOSSES" + (pd.seed != null ? "   ·   SEED " + int(pd.seed) :
                  ""),100,44,12,UiKit.GREY,UiKit.XBOLD);
               var pacc:int = int(pd.account);
               var pwho:String = String(pd.name);
               items.push({"w":"p" + pacc,"sprite":card,"parent":p,"width":pw,"height":76,"focusBox":[0,0,pw,76],
                  "use":profileOpener(pacc,pwho),"players":sidePlayers(pacc,pwho),"dbl":true});
            }
            top += 90;
         }
         var cols:int = area.width >= 1100 ? 2 : 1;
         var per:int = STAND_PAGE * cols;
         var pages:int = Math.ceil(list.length / per);
         standPage = Math.max(0,Math.min(standPage,pages - 1));
         var colW:Number = (area.width - 40 - 16 * (cols - 1)) / cols;
         var rowH:Number = Math.max(30,Math.min(46,Math.floor((area.height - top - 24 - 50) / STAND_PAGE)));
         for(var c:int = 0; c < cols; c++)
         {
            var hx:Number = 20 + c * (colW + 16);
            UiKit.text(p,started ? "PLACE" : "SEED",hx + 16,top,11,UiKit.GREY,UiKit.XBOLD);
            UiKit.text(p,v.mode == "2v2" ? "TEAM" : "PLAYER",hx + 96,top,11,UiKit.GREY,UiKit.XBOLD);
            if(started)
            {
               UiKit.text(p,"SEED",hx + colW - 170,top,11,UiKit.GREY,UiKit.XBOLD);
               UiKit.text(p,"RECORD",hx + colW - 96,top,11,UiKit.GREY,UiKit.XBOLD);
            }
         }
         var first:int = standPage * per;
         for(var n:int = first; n < Math.min(list.length,first + per); n++)
         {
            var e:Object = list[n];
            var k:int = n - first;
            var col:int = int(k / STAND_PAGE);
            var s:Sprite = new Sprite();
            s.x = 20 + col * (colW + 16);
            s.y = top + 20 + (k % STAND_PAGE) * rowH;
            p.addChild(s);
            var lh:Number = rowH - 4;
            var pl:int = e.placement != null ? int(e.placement) : 0;
            var mineRow:Boolean = int(e.account) == me;
            UiKit.rect(s,0,0,colW,lh,mineRow ? UiKit.ROW_SELECTED : UiKit.BODY,6);
            if(pl > 0 && pl <= 3)
            {
               UiKit.rect(s,0,0,5,lh,UiKit.placeColour(pl,UiKit.GREY),4);
            }
            var ty:Number = lh / 2 - 10;
            var firstText:String = e.waiting ? "WAIT" : started ? (pl > 0 ? ordinal(pl) : "-") :
               e.seed != null ? "#" + int(e.seed) : String(n + 1);
            UiKit.text(s,firstText,16,ty,15,UiKit.placeColour(pl,UiKit.GREY),UiKit.XBOLD);
            var nameRight:Number = started ? colW - 186 : colW - 20;
            var nt:TextField = UiKit.fit(UiKit.text(s,String(e.name),96,ty,15,mineRow ? UiKit.TEAL : e.disqualified == true ||
               e.waiting ? UiKit.GREY : UiKit.WHITE,UiKit.BOLD),nameRight - 96 - (started && pl == 0 ? 50 : 0));
            if(e.disqualified == true)
            {
               pill(s,"DQ",96 + nt.width + 8,ty + 1,UiKit.RED);
            }
            else if(started && pl == 0 && !e.waiting)
            {
               pill(s,"IN",96 + nt.width + 8,ty + 1,UiKit.TEAL);
            }
            if(started)
            {
               UiKit.text(s,e.seed != null ? "#" + int(e.seed) : "-",colW - 170,ty,14,UiKit.GREY,UiKit.BOLD);
               var rec:Array = records[String(e.account)] as Array || [0,0];
               var wt:TextField = UiKit.text(s,String(rec[0]),colW - 96,ty,15,int(rec[0]) > 0 ? GREEN : UiKit.GREY,UiKit.XBOLD);
               var dash:TextField = UiKit.text(s," - ",wt.x + wt.width,ty,15,UiKit.GREY,UiKit.XBOLD);
               UiKit.text(s,String(rec[1]),dash.x + dash.width,ty,15,int(rec[1]) > 0 ? UiKit.RED : UiKit.GREY,UiKit.XBOLD);
            }
            var acc:int = int(e.account);
            var who:String = String(e.name);
            items.push({"w":"p" + acc,"sprite":s,"parent":p,"width":colW,"height":lh,"focusBox":[0,0,colW,lh],
               "use":profileOpener(acc,who),"players":sidePlayers(acc,who),"dbl":true});
         }
         if(pages > 1)
         {
            navBar(p,20,area.height - 40,280,32,"PAGE " + (standPage + 1) + " OF " + pages,"page",
               "Left and right, or the arrows, for another page.",function(d:int):void
               {
                  standPage = (standPage + d + pages) % pages;
               });
         }
      }

      private function poolQuery() : String
      {
         return "tpool:" + shownId + ":" + poolShown;
      }

      private function navBar(p:Sprite, x:Number, y:Number, w:Number, h:Number, label:String, key:String, about:String,
                              change:Function) : Sprite
      {
         var s:Sprite = new Sprite();
         s.x = x;
         s.y = y;
         p.addChild(s);
         UiKit.rect(s,0,0,w,h,UiKit.PANEL,6);
         var t:TextField = UiKit.fit(UiKit.text(s,label,0,(h - 20) / 2,14,UiKit.WHITE,UiKit.XBOLD),w - 90);
         t.x = (w - t.width) / 2;
         var ay:Number = (h - 22) / 2;
         UiKit.arrow(s,8,ay,-1,function():void
         {
            change(-1);
            pendingW = key;
            build();
         });
         UiKit.arrow(s,w - 30,ay,1,function():void
         {
            change(1);
            pendingW = key;
            build();
         });
         items.push({"w":key,"sprite":s,"parent":p,"width":w,"height":h,"focusBox":[0,0,w,h],"about":about,"change":change});
         return s;
      }

      private function buildPools() : void
      {
         var p:Sprite = panel(area.x,area.y,area.width,area.height);
         var v:Object = shownId >= 0 ? ServerStats.get("tournament:" + shownId) : null;
         if(v == null || v.error != null)
         {
            UiKit.text(p,v == null ? "Asking the server..." : String(v.error),24,14,14,UiKit.LIGHT,UiKit.MEDIUM);
            return;
         }
         UiKit.fit(UiKit.text(p,String(v.name),24,10,18,UiKit.WHITE,UiKit.XBOLD),area.width * 0.5);
         var robin:Boolean = v.pool_kind != "bracket";
         var advance:int = int(v.pool_advance);
         var pools:Array = v.pools as Array || [];
         if(pools.length == 0)
         {
            UiKit.text(p,(robin ? "Round robin pools" : "Bracket pools") + " until top " + int(v.pools_until) + ", " + advance +
               " from each pool. They are drawn when it starts (seeds dealt across the pools).",24,52,15,UiKit.LIGHT,
               UiKit.MEDIUM,area.width - 48);
            return;
         }
         poolShown = Math.max(0,Math.min(poolShown,pools.length - 1));
         var pool:Object = pools[poolShown];
         var got:Object = ServerStats.get(poolQuery());
         var decided:int = 0;
         for each(var gm:Object in got != null ? got.matches as Array || [] : [])
         {
            decided += gm.winner != null && gm.note != "bye" ? 1 : 0;
         }
         if(got == null || got.error == null && decided != int(pool.played))
         {
            ServerStats.ask(poolQuery());
         }
         rtext(p,(robin ? "ROUND ROBIN POOLS" : "BRACKET POOLS") + "   ·   TOP " + advance + " OF EACH POOL GO ON TO THE BRACKET",
            area.width - 24,14,13,UiKit.GREY,UiKit.XBOLD);
         poolTabs(p,pools,20,46,area.width - 40);
         var have:Boolean = got != null && got.error == null && int(got.pool) == poolShown;
         var byRound:Array = [];
         var byPair:Object = {};
         for each(var m:Object in have ? got.matches as Array || [] : [])
         {
            var pr:int = int(m.pool_round);
            while(byRound.length <= pr)
            {
               byRound.push([]);
            }
            byRound[pr].push(m);
            if(m.a != null && m.b != null && m.winner != null && m.note != "bye" && m.note != "not played")
            {
               byPair[int(m.a) + ":" + int(m.b)] = [int(m.wins_a),int(m.wins_b),int(m.winner) == int(m.a)];
               byPair[int(m.b) + ":" + int(m.a)] = [int(m.wins_b),int(m.wins_a),int(m.winner) == int(m.b)];
            }
         }
         var rows:Array = pool.standings as Array || [];
         var grid:Boolean = robin && rows.length > 1 && rows.length <= 10;
         var me:int = v.my_side != null ? int(v.my_side) : v.me != null ? int(v.me) : -1;
         var manage:Boolean = me >= 0 && v.manage == true && (v.state == "running" || v.state == "done");
         if(!robin)
         {
            poolBracket(p,byRound,have,got,me,manage,v);
            return;
         }
         var top:Number = 100;
         var leftW:Number = Math.round((area.width - 60) * (grid ? 0.58 : 0.48));
         poolStandings(p,20,top,leftW,area.height - top - 14,rows,grid,byPair,advance,me,v);
         var rx:Number = 40 + leftW;
         poolMatches(p,rx,top,area.width - rx - 20,area.height - top - 14,byRound,have,got,me,manage,v);
      }

      private function poolBracket(p:Sprite, byRound:Array, have:Boolean, got:Object, me:int, creator:Boolean, v:Object) : void
      {
         var top:Number = 96;
         info = new Sprite();
         info.y = area.height - INFO_H - 2;
         p.addChild(info);
         drawInfo();
         if(!have || byRound.length == 0)
         {
            UiKit.text(p,!have ? (got != null && got.error != null ? String(got.error) : "Asking the server...") :
               "No matches yet.",24,top + 4,14,UiKit.LIGHT,UiKit.MEDIUM);
            return;
         }
         var rounds:Array = [];
         for(var r:int = 0; r < byRound.length; r++)
         {
            var ms:Array = (byRound[r] as Array).concat();
            ms.sortOn("slot",Array.NUMERIC);
            rounds.push({"round":int(ms[0].round),"name":r == byRound.length - 1 ? "QUALIFYING ROUND" : "ROUND " + (r + 1),
               "best_of":v.best_of,"matches":ms});
         }
         var cols:int = rounds.length + 1;
         var colW:Number = Math.min(260,(area.width - 40) / cols);
         var boxH:Number = int(v.checkin) > 0 && v.state == "running" ? 64 : 52;
         var lane:Sprite = scroller(p,0,top,area.width,area.height - top - 6 - INFO_H);
         var keep:int = visCols;
         visCols = 0;
         bracketRow(lane,rounds,0,0,colW,boxH,v,me,creator,false);
         visCols = keep;
         var last:Array = rounds[rounds.length - 1].matches as Array;
         var h:Number = Math.max((rounds[0].matches as Array).length * (boxH + 10),boxH + 30);
         var slotH:Number = h / last.length;
         var qx:Number = 20 + (cols - 1) * colW;
         UiKit.text(lane,"TO THE BRACKET",qx,0,12,GREEN,UiKit.XBOLD);
         UiKit.text(lane,last.length + (last.length == 1 ? " GOES ON" : " GO ON") + "  ·  TOP " + int(v.pools_until),qx,16,10,
            0x5C6E80,UiKit.XBOLD);
         var lines:Shape = new Shape();
         lane.addChild(lines);
         for(var k:int = 0; k < last.length; k++)
         {
            var m:Object = last[k];
            var cy:Number = HEAD_H + k * slotH + slotH / 2;
            var wid:int = m.winner != null ? int(m.winner) : 0;
            var won:String = wid > 0 && m.a != null && wid == int(m.a) ? String(m.a_name) : wid > 0 && m.b != null &&
               wid == int(m.b) ? String(m.b_name) : null;
            lines.graphics.lineStyle(2,won != null ? GREEN : LINE_OPEN);
            lines.graphics.moveTo(qx - 16,cy);
            lines.graphics.lineTo(qx,cy);
            var q:Sprite = new Sprite();
            q.x = qx;
            q.y = cy - 18;
            lane.addChild(q);
            UiKit.rect(q,0,0,colW - 16,36,won != null ? GREEN_ROW : UiKit.BODY,4);
            UiKit.rect(q,0,0,4,36,won != null ? GREEN : UiKit.LINE);
            UiKit.fit(UiKit.text(q,won != null ? won : "WINNER GOES ON",12,8,won != null ? 15 : 12,won != null ? UiKit.WHITE :
               UiKit.GREY,UiKit.XBOLD),colW - 40);
         }
      }

      private function poolTabs(p:Sprite, pools:Array, x:Number, y:Number, w:Number) : void
      {
         var s:Sprite = new Sprite();
         s.x = x;
         s.y = y;
         p.addChild(s);
         var count:int = pools.length;
         var cw:Number = 140;
         var most:int = Math.max(1,int((w - 64) / (cw + 8)));
         var arrows:Boolean = count > most;
         var first:int = arrows ? Math.max(0,Math.min(count - most,poolShown - int(most / 2))) : 0;
         var cx:Number = arrows ? 32 : 0;
         var change:Function = function(d:int):void
         {
            poolShown = (poolShown + d + count) % count;
            poolRound = -1;
            ServerStats.ask(poolQuery());
         };
         if(arrows)
         {
            UiKit.arrow(s,0,9,-1,function():void
            {
               change(-1);
               pendingW = "pool";
               build();
            });
         }
         for(var i:int = first; i < Math.min(count,first + most); i++)
         {
            var pl:Object = pools[i];
            var on:Boolean = i == poolShown;
            var chip:Sprite = new Sprite();
            chip.x = cx;
            chip.buttonMode = true;
            s.addChild(chip);
            UiKit.rect(chip,0,0,cw,40,on ? UiKit.TEAL : UiKit.BODY,6);
            UiKit.fit(UiKit.text(chip,String(pl.name).toUpperCase(),12,3,14,on ? UiKit.NAVY_TEXT : UiKit.WHITE,UiKit.XBOLD),cw - 20);
            UiKit.text(chip,pl.done ? "DONE" : int(pl.played) + " OF " + int(pl.total) + " PLAYED",12,21,10,on ? UiKit.NAVY_TEXT :
               pl.done ? GREEN : UiKit.GREY,UiKit.XBOLD);
            chip.addEventListener(MouseEvent.CLICK,poolClick(i));
            cx += cw + 8;
         }
         if(arrows)
         {
            UiKit.arrow(s,cx,9,1,function():void
            {
               change(1);
               pendingW = "pool";
               build();
            });
            cx += 30;
         }
         items.push({"w":"pool","sprite":s,"parent":p,"width":cx,"height":40,"focusBox":[-6,-4,cx + 4,48],
            "about":count + " pools: left and right, or click one, to see it.","change":change});
      }

      private function poolClick(i:int) : Function
      {
         return function(e:MouseEvent):void
         {
            poolShown = i;
            poolRound = -1;
            ServerStats.ask(poolQuery());
            pendingW = "pool";
            build();
         };
      }

      private function poolStandings(p:Sprite, x:Number, y:Number, w:Number, h:Number, rows:Array, grid:Boolean,
                                     byPair:Object, advance:int, me:int, v:Object) : void
      {
         var box:Sprite = new Sprite();
         box.x = x;
         box.y = y;
         p.addChild(box);
         UiKit.rect(box,0,0,w,h,UiKit.BODY,6);
         UiKit.text(box,"STANDINGS",14,10,12,UiKit.GREY,UiKit.XBOLD);
         var n:int = rows.length;
         var colW:Number = 64;
         var gamesX:Number = w - 14 - colW;
         var setsX:Number = gamesX - colW;
         var cell:Number = grid ? Math.max(30,Math.min(46,(w * 0.4) / n)) : 0;
         var gridX:Number = setsX - 10 - cell * (grid ? n : 0);
         var nameX:Number = 44;
         var headY:Number = 36;
         UiKit.text(box,"#",20,headY,11,UiKit.GREY,UiKit.XBOLD);
         UiKit.text(box,v.mode == "2v2" ? "TEAM" : "PLAYER",nameX + 8,headY,11,UiKit.GREY,UiKit.XBOLD);
         for(var c:int = 0; grid && c < n; c++)
         {
            UiKit.text(box,"VS " + (c + 1),gridX + c * cell + cell / 2,headY,10,UiKit.GREY,UiKit.XBOLD,0,true);
         }
         UiKit.text(box,"SETS",setsX + colW / 2,headY,11,UiKit.GREY,UiKit.XBOLD,0,true);
         UiKit.text(box,"GAMES",gamesX + colW / 2,headY,11,UiKit.GREY,UiKit.XBOLD,0,true);
         var rowH:Number = Math.max(30,Math.min(48,Math.floor((h - headY - 22 - 34) / Math.max(4,n))));
         var ry:Number = headY + 22;
         for(var i:int = 0; i < n; i++)
         {
            var r:Object = rows[i];
            var adv:Boolean = r.advances == true;
            var mine:Boolean = int(r.entrant) == me;
            var line:Sprite = new Sprite();
            line.x = 8;
            line.y = ry;
            box.addChild(line);
            var lw:Number = w - 16;
            var lh:Number = rowH - 4;
            UiKit.rect(line,0,0,lw,lh,adv ? GREEN_ROW : mine ? UiKit.ROW_SELECTED : UiKit.PANEL,4);
            if(adv)
            {
               UiKit.rect(line,0,0,4,lh,GREEN);
            }
            var ty:Number = lh / 2 - 10;
            UiKit.text(line,String(int(r.place)),12,ty,15,adv ? GREEN : UiKit.GREY,UiKit.XBOLD);
            UiKit.fit(UiKit.text(line,String(r.name),nameX,ty,15,mine ? UiKit.TEAL : UiKit.WHITE,UiKit.BOLD),
               (grid ? gridX : setsX) - nameX - 18);
            for(var k:int = 0; grid && k < n; k++)
            {
               var cx:Number = gridX - 8 + k * cell + 2;
               if(k == i)
               {
                  UiKit.rect(line,cx,4,cell - 4,lh - 8,UiKit.LINE,4);
                  continue;
               }
               var res:Array = byPair[int(r.entrant) + ":" + int(rows[k].entrant)] as Array;
               if(res == null)
               {
                  UiKit.text(line,"-",cx + (cell - 4) / 2,ty,14,UiKit.DIM,UiKit.XBOLD,0,true);
                  continue;
               }
               UiKit.rect(line,cx,4,cell - 4,lh - 8,res[2] ? GREEN_CELL : RED_CELL,4);
               UiKit.text(line,res[0] + "-" + res[1],cx + (cell - 4) / 2,ty + 1,12,res[2] ? GREEN : UiKit.RED,UiKit.XBOLD,0,true);
            }
            UiKit.text(line,int(r.wins) + " - " + int(r.losses),setsX - 8 + colW / 2,ty,15,UiKit.WHITE,UiKit.XBOLD,0,true);
            UiKit.text(line,int(r.games_won) + " - " + int(r.games_lost),gamesX - 8 + colW / 2,ty,15,UiKit.GREY,UiKit.BOLD,0,true);
            items.push({"w":"p" + int(r.entrant),"sprite":line,"parent":box,"width":lw,"height":lh,"focusBox":[0,0,lw,lh],
               "use":profileOpener(int(r.entrant),String(r.name)),"players":sidePlayers(int(r.entrant),String(r.name)),"dbl":true});
            ry += rowH;
            if(i == advance - 1 && i < n - 1)
            {
               UiKit.rect(box,8,ry - 3,w - 16,2,GREEN);
            }
         }
         UiKit.rect(box,16,h - 22,10,10,GREEN,3);
         UiKit.text(box,"TOP " + advance + " GO ON TO THE BRACKET",32,h - 27,11,UiKit.GREY,UiKit.XBOLD);
      }

      private function poolMatches(p:Sprite, x:Number, y:Number, w:Number, h:Number, byRound:Array, have:Boolean, got:Object,
                                   me:int, manage:Boolean, v:Object) : void
      {
         var box:Sprite = new Sprite();
         box.x = x;
         box.y = y;
         p.addChild(box);
         UiKit.rect(box,0,0,w,h,UiKit.BODY,6);
         UiKit.text(box,"MATCHES",14,10,12,UiKit.GREY,UiKit.XBOLD);
         if(!have)
         {
            UiKit.text(box,got != null && got.error != null ? String(got.error) : "Asking the server...",14,40,14,UiKit.LIGHT,
               UiKit.MEDIUM);
            return;
         }
         var rounds:int = byRound.length;
         if(rounds == 0)
         {
            UiKit.text(box,"No matches yet.",14,40,14,UiKit.LIGHT,UiKit.MEDIUM);
            return;
         }
         if(poolRound < 0 || poolRound >= rounds)
         {
            poolRound = rounds - 1;
            for(var r:int = 0; r < rounds; r++)
            {
               if(openIn(byRound[r]) > 0)
               {
                  poolRound = r;
                  break;
               }
            }
         }
         var list:Array = byRound[poolRound];
         var played:int = 0;
         for each(var m:Object in list)
         {
            played += m.winner != null ? 1 : 0;
         }
         navBar(box,14,34,w - 28,36,"ROUND " + (poolRound + 1) + " OF " + rounds + "   ·   " + played + " OF " + list.length +
            " PLAYED","poolround","Everyone plays one match a round. Left and right, or the arrows, for another round.",
            function(d:int):void
            {
               poolRound = (poolRound + d + rounds) % rounds;
            });
         var cols:int = w >= 560 ? 2 : 1;
         var gap:Number = 10;
         var cardW:Number = (w - 28 - gap * (cols - 1)) / cols;
         var cardH:Number = Math.max(48,Math.min(62,Math.floor((h - 84) / Math.ceil(list.length / cols)) - gap));
         for(var k:int = 0; k < list.length; k++)
         {
            var pm:Object = list[k];
            var c:Sprite = new Sprite();
            c.x = 14 + k % cols * (cardW + gap);
            c.y = 82 + int(k / cols) * (cardH + gap);
            box.addChild(c);
            matchCard(c,cardW,cardH,pm,me);
            if(manage)
            {
               poolMatchActions(c,box,cardW,cardH,pm,v.state == "running");
            }
         }
      }

      private static function openIn(list:Array) : int
      {
         var n:int = 0;
         for each(var m:Object in list)
         {
            n += m.winner == null && m.note != "bye" ? 1 : 0;
         }
         return n;
      }

      private function matchCard(c:Sprite, w:Number, h:Number, pm:Object, me:int) : void
      {
         var mine:Boolean = pm.a != null && int(pm.a) == me || pm.b != null && int(pm.b) == me;
         UiKit.rect(c,0,0,w,h,mine ? UiKit.ROW_SELECTED : UiKit.PANEL,6);
         var done:Boolean = pm.winner != null;
         var lineH:Number = (h - 4) / 2;
         for(var sd:int = 0; sd < 2; sd++)
         {
            var id:Object = sd == 0 ? pm.a : pm.b;
            var nm:String = String((sd == 0 ? pm.a_name : pm.b_name) || (pm.note == "bye" ? "BYE" : "TBD"));
            var wins:int = int(sd == 0 ? pm.wins_a : pm.wins_b);
            var won:Boolean = done && id != null && int(pm.winner) == int(id);
            var ly:Number = 2 + sd * lineH;
            if(sd == 1)
            {
               UiKit.rect(c,8,ly,w - 16,1,UiKit.LINE);
            }
            UiKit.fit(UiKit.text(c,nm,14,ly + lineH / 2 - 10,14,won ? UiKit.WHITE : done ? UiKit.GREY : UiKit.LIGHT,
               won ? UiKit.XBOLD : UiKit.BOLD),w - 120);
            UiKit.rect(c,w - 42,ly + 3,34,lineH - 6,won ? GREEN_CELL : UiKit.BODY,4);
            UiKit.text(c,done || wins > 0 ? String(wins) : "-",w - 25,ly + lineH / 2 - 10,14,won ? GREEN : UiKit.GREY,
               UiKit.XBOLD,0,true);
         }
         if(!done && pm.checkin_left != null)
         {
            rtext(c,"CHECK-IN " + minutesLeft(pm).toUpperCase(),w - 50,4,9,UiKit.TEAL,UiKit.XBOLD);
         }
      }

      private function poolMatchActions(c:Sprite, parent:Sprite, w:Number, h:Number, pm:Object, running:Boolean) : void
      {
         var it:Object = {"w":"pm" + int(pm.round) + ":" + int(pm.slot),"sprite":c,"parent":parent,"width":w,"height":h,
            "focusBox":[0,0,w,h]};
         var open:Boolean = pm.winner == null && pm.a != null && pm.b != null && running;
         if(open || pm.winner != null && pm.note != "bye" && pm.note != "not played")
         {
            it.about = open ? "Select: award, report a score, check a side in, more check-in time, or disqualify." :
               "Select: undo this result or change its score.";
            it.use = matchActions(pm,int(pm.round),open);
         }
         items.push(it);
      }

      private function matchActions(m:Object, rnd:int, open:Boolean) : Function
      {
         var id:int = shownId;
         var slot:int = int(m.slot);
         var a:String = String(m.a_name);
         var b:String = String(m.b_name);
         var ids:Array = [int(m.a),int(m.b)];
         var labels:Array = [];
         var acts:Array = [];
         var add:Function = function(label:String, f:Function):void
         {
            labels.push(label);
            acts.push(f);
         };
         if(open)
         {
            add(a,function():void
            {
               act("award",{"id":id,"round":rnd,"slot":slot,"winner":ids[0]});
            });
            add(b,function():void
            {
               act("award",{"id":id,"round":rnd,"slot":slot,"winner":ids[1]});
            });
            add("REPORT A SCORE",function():void
            {
               askScore(m,rnd);
            });
            if(m.checkin_left != null)
            {
               var checked:Array = m.checked as Array || [];
               for(var k:int = 0; k < 2; k++)
               {
                  if(checked.indexOf(ids[k]) < 0)
                  {
                     add("CHECK IN " + [a,b][k].toUpperCase(),checkInFor(id,rnd,slot,ids[k]));
                  }
               }
               add("+5 MIN TO CHECK IN",function():void
               {
                  act("extend",{"id":id,"round":rnd,"slot":slot});
               });
            }
            add("DISQUALIFY " + a.toUpperCase(),function():void
            {
               act("disqualify",{"id":id,"account":ids[0]});
            });
            add("DISQUALIFY " + b.toUpperCase(),function():void
            {
               act("disqualify",{"id":id,"account":ids[1]});
            });
         }
         else
         {
            add("UNDO THE RESULT",function():void
            {
               act("undo",{"id":id,"round":rnd,"slot":slot});
            });
            add("CHANGE THE SCORE",function():void
            {
               askScore(m,rnd);
            });
         }
         return function():void
         {
            pickFrom(open ? "AWARD THE MATCH TO" : "THIS MATCH'S RESULT",labels,0,function(i:int):void
            {
               acts[i]();
            });
         };
      }

      private function checkInFor(id:int, rnd:int, slot:int, side:int) : Function
      {
         return function():void
         {
            act("checkin_for",{"id":id,"round":rnd,"slot":slot,"account":side});
         };
      }

      private function askScore(m:Object, rnd:int) : void
      {
         var best:int = roundBestOf(rnd);
         var need:int = (best + 1) / 2;
         var scores:Array = [];
         for(var l:int = 0; l < need; l++)
         {
            scores.push([need,l]);
         }
         for(l = need - 1; l >= 0; l--)
         {
            scores.push([l,need]);
         }
         var labels:Array = [];
         for each(var sc:Array in scores)
         {
            labels.push(sc[0] + " - " + sc[1]);
         }
         var id:int = shownId;
         pickFrom(String(m.a_name).toUpperCase() + " VS " + String(m.b_name).toUpperCase() + ": THE SCORE (BEST OF " + best +
            ")",labels,0,function(i:int):void
         {
            act("score",{"id":id,"round":rnd,"slot":int(m.slot),"wins_a":scores[i][0],"wins_b":scores[i][1]});
         });
      }

      private function roundBestOf(rnd:int) : int
      {
         var tv:Object = ServerStats.get("tournament:" + shownId);
         if(tv == null)
         {
            return 1;
         }
         if(rnd >= 0)
         {
            for each(var r:Object in tv.rounds as Array || [])
            {
               if(r.round != null && int(r.round) == rnd && r.best_of != null)
               {
                  return int(r.best_of);
               }
            }
         }
         return Math.max(1,int(tv.best_of));
      }

      private static function profileOpener(account:int, name:String) : Function
      {
         return function():void
         {
            ProfileWindow.openAccount(account,name);
         };
      }

      private static function standingsOrder(v:Object) : Array
      {
         var list:Array = (v.entrants as Array || []).concat();
         var at:Object = {};
         for(var i:int = 0; i < list.length; i++)
         {
            at[String(list[i].account)] = i;
         }
         list.sort(function(a:Object, b:Object):int
         {
            var pa:int = a.placement != null ? int(a.placement) : 0;
            var pb:int = b.placement != null ? int(b.placement) : 0;
            if(pa != pb)
            {
               return pa == 0 ? -1 : pb == 0 ? 1 : pa - pb;
            }
            return int(at[String(a.account)]) - int(at[String(b.account)]);
         });
         return list;
      }

      private static function recordsOf(v:Object) : Object
      {
         var out:Object = {};
         for each(var pool:Object in v.pools as Array || [])
         {
            for each(var pr:Object in pool.standings as Array || [])
            {
               out[String(pr.entrant)] = [int(pr.wins),int(pr.losses)];
            }
         }
         for each(var r:Object in v.rounds as Array || [])
         {
            for each(var m:Object in r.matches as Array || [])
            {
               if(m.winner == null || m.a == null || m.b == null)
               {
                  continue;
               }
               for each(var side:Object in [m.a,m.b])
               {
                  var rec:Array = out[String(side)] as Array || [0,0];
                  rec[int(side) == int(m.winner) ? 0 : 1]++;
                  out[String(side)] = rec;
               }
            }
         }
         return out;
      }

      private function focusedList(it:Object) : void
      {
         if((tab == T_BRACKET || tab == T_POOLS) && it != null && it.tmatch != null && it.tmatch != infoQuery)
         {
            infoQuery = it.tmatch;
            infoTitle = it.title;
            if(it.played)
            {
               ServerStats.ask(infoQuery);
            }
            drawInfo();
            return;
         }
         if(tab == T_LIST && it != null && it.id != null && int(it.id) != shownId)
         {
            shownId = int(it.id);
            armed = null;
            ServerStats.get("tournament:" + shownId);
            build();
         }
      }

      private function drawDetail() : void
      {
         if(detail == null || shownId < 0)
         {
            return;
         }
         var v:Object = ServerStats.get("tournament:" + shownId);
         if(v == null)
         {
            UiKit.text(detail,"Asking the server...",20,14,14,UiKit.LIGHT,UiKit.MEDIUM);
            return;
         }
         if(v.error != null)
         {
            UiKit.text(detail,String(v.error),20,14,14,UiKit.LIGHT,UiKit.MEDIUM,detailW - 40);
            return;
         }
         var entrants:Array = v.entrants as Array || [];
         var state:String = String(v.state);
         UiKit.rect(detail,12,12,detailW - 24,120,UiKit.BODY,8);
         UiKit.rect(detail,12,12,detailW - 24,5,stateColor(state),4);
         var hx:Number = 28;
         hx = pill(detail,stateName(state),hx,28,stateColor(state)) + 8;
         if(v.paused != null)
         {
            hx = pill(detail,"PAUSED",hx,28,AMBER) + 8;
         }
         if(v.my_side != null)
         {
            hx = pill(detail,"SIGNED UP",hx,28,UiKit.TEAL) + 8;
         }
         if(v.mine == true)
         {
            pill(detail,"YOURS",hx,28,UiKit.TEAL);
         }
         UiKit.fit(UiKit.text(detail,String(v.name),28,52,28,UiKit.WHITE,UiKit.XBOLD),detailW - 56);
         var timeLine:String = state == "open" ? (v.starts != null ? "STARTS " + when(v.starts) : "STARTS WHEN ITS HOST SAYS") :
            state == "running" ? "STARTED " + when(v.started) : state == "done" ? "FINISHED " + when(v.finished) : "";
         UiKit.fit(UiKit.text(detail,"HOSTED BY " + String(v.owner_name).toUpperCase() + "   ·   " + timeLine +
            (v.region ? "   ·   " + String(v.region).toUpperCase() : "") +
            (int(v.min_rating) > 0 || int(v.max_rating) > 0 ? "   ·   RATING " + ratingName([v.min_rating,v.max_rating]) : "") +
            (int(v.checkin) > 0 ? "   ·   CHECK-IN " + int(v.checkin) + " MIN" : ""),28,96,12,UiKit.GREY,UiKit.XBOLD),
            detailW - 56);
         var tw:Number = (detailW - 24 - 30) / 4;
         var most:int = Math.max(1,int(v.max_players));
         var soon:String = state == "open" ? (v.starts != null && v.server_now != null ? minutesTo(Number(v.starts) -
            Number(v.server_now)) : "WHEN THE HOST SAYS") : state == "running" ? (v.paused != null ? "PAUSED" : "LIVE") :
            state == "done" ? String(v.winner_name || "-").toUpperCase() : stateName(state);
         tile(detail,12,144,tw,70,v.mode == "2v2" ? "TEAMS" : "PLAYERS",entrants.length + " / " + most,UiKit.WHITE,
            entrants.length / most);
         tile(detail,12 + (tw + 10),144,tw,70,"FORMAT",int(v.pools_until) > 0 ? (int(v.losers) > 0 ?
            "POOLS, DOUBLE" : "POOLS, SINGLE") : int(v.losers) > 0 ? "DOUBLE ELIM" : "SINGLE ELIM",UiKit.WHITE);
         tile(detail,12 + (tw + 10) * 2,144,tw,70,"BEST OF",String(int(v.best_of)) + (int(v.best_of_top8) > 0 ? ", TOP 8 BO" +
            int(v.best_of_top8) : "") + (int(v.best_of_final) > 0 ? ", FINAL BO" + int(v.best_of_final) : ""),UiKit.WHITE);
         tile(detail,12 + (tw + 10) * 3,144,tw,70,state == "open" ? "STARTS IN" : state == "done" ? "WINNER" : "STATUS",soon,
            state == "done" ? UiKit.GOLD : state == "running" ? UiKit.TEAL : UiKit.WHITE);
         var y:Number = 228;
         if(v.winner_name != null)
         {
            var podium:Array = [];
            for each(var pe:Object in standingsOrder(v))
            {
               if(pe.placement != null && int(pe.placement) <= 3)
               {
                  podium.push(pe);
               }
            }
            if(podium.length == 0)
            {
               podium.push({"placement":1,"name":v.winner_name});
            }
            for each(var po:Object in podium)
            {
               var first:Boolean = int(po.placement) == 1;
               UiKit.text(detail,ordinal(int(po.placement)),20,y,first ? 20 : 16,UiKit.placeColour(int(po.placement),AMBER),
                  UiKit.XBOLD);
               UiKit.fit(UiKit.text(detail,String(po.name).toUpperCase(),84,y,first ? 20 : 16,first ? UiKit.WHITE : UiKit.LIGHT,
                  UiKit.XBOLD),detailW - 110);
               y += first ? 30 : 24;
            }
            y += 6;
         }
         var timed:Boolean = int(v.scoring) == 1;
         var own:String = null;
         for each(var sc:Array in SCORINGS)
         {
            if(sc[0] == int(v.scoring) && sc[3] != "")
            {
               own = String(sc[1]);
            }
         }
         var notes:String = own != null ? own + (v.damage != null && int(v.damage) != 100 ? ", " + int(v.damage) +
            "% DAMAGE" : "") + "   SEEDING " + SEEDING_NAMES[Math.max(0,SEEDINGS.indexOf(String(v.seeding || "rating")))] +
            (v.region ? "   " + String(v.region).toUpperCase() : "") : (timed ? "TIMED" : int(v.stocks || 3) + " STOCK" + (int(v.stocks || 3) == 1 ? "" : "S")) + ", " +
            int(v.minutes || 8) + " MIN" + (v.damage != null && int(v.damage) != 100 ? ", " + int(v.damage) + "% DAMAGE" : "") +
            (int(v.variation) > 0 ? ", " + VARIATION_NAMES[int(v.variation)] : "") +
            (v.gadget_rate != null && int(v.gadget_rate) > 0 ? ", GADGETS " + RATE_NAMES[Math.max(0,GADGET_RATES.indexOf(int(v.gadget_rate)))] : "") +
            (v.weapon_rate != null && int(v.weapon_rate) != 2 ? ", WEAPONS " + RATE_NAMES[Math.max(0,WEAPON_RATES.indexOf(int(v.weapon_rate)))] : "") +
            "   SEEDING " + SEEDING_NAMES[Math.max(0,SEEDINGS.indexOf(String(v.seeding || "rating")))];
         var pool:String = String(POOL_NAMES[String(int(v.map_set) || (MAP_POOLS[String(v.mode || "1v1")] as Array)[0])] ||
            "TOURNAMENT");
         var ruled:String = "MAPS " + pool + ", " + MAP_PICK_NAMES[Math.max(0,MAP_PICKS.indexOf(String(v.map_pick || "random")))];
         var lr:int = LIST_RULES.indexOf(String(v.legend_rule || ""));
         var heroIds:Array = String(v.legends || "").length > 0 ? String(v.legends).split(",") : [];
         if(lr > 0 && heroIds.length > 0)
         {
            ruled += "   LEGENDS " + (lr == 1 ? "BANNED: " : "ONLY: ") + legendNames(heroIds).toUpperCase();
         }
         var wr:int = LIST_RULES.indexOf(String(v.weapon_rule || ""));
         var wlist:Array = String(v.weapons || "").length > 0 ? String(v.weapons).split(",") : [];
         if(wr > 0 && wlist.length > 0)
         {
            ruled += "   " + (wr == 1 ? "NO " : "ONLY ") + weaponNames(wlist).toUpperCase();
         }
         drawCards([["GAME SETTINGS",notes.split("   ").join("\n")],
            ["MAPS AND PICKS",ruled.split("   ").join("\n")],["PRIZE",v.prize],["RULES",v.rules],["STREAM",v.stream],["ABOUT",v.about]]);
         var me:int = v.my_side != null ? int(v.my_side) : v.me != null ? int(v.me) : -1;
         var signed:Boolean = v.my_side != null;
         for each(var e:Object in entrants)
         {
            if(int(e.account) == me)
            {
               signed = true;
            }
         }
         var waiting:Boolean = false;
         var waitNames:Array = [];
         for each(var wl:Object in v.waitlist as Array || [])
         {
            waitNames.push(String(wl.name));
            if(v.me != null && (int(wl.account) == int(v.me) || wl.partner != null && int(wl.partner) == int(v.me)))
            {
               waiting = signed = true;
            }
         }
         var creator:Boolean = me >= 0 && v.mine == true;
         var manage:Boolean = me >= 0 && v.manage == true;
         var id:int = shownId;
         var bx:Number = 20;
         y += 6;
         if(v.state == "open" && me >= 0)
         {
            bx = actionButton(bx,y,waiting ? "LEAVE WAITLIST" : signed ? "LEAVE" : entrants.length >= int(v.max_players) ?
               "JOIN WAITLIST" : "SIGN UP",function():void
            {
               act(signed ? "leave" : "join",{"id":id});
            });
            if(manage)
            {
               bx = actionButton(bx,y,"START",function():void
               {
                  act("start",{"id":id});
               });
            }
         }
         if(creator && (v.state == "open" || v.state == "running"))
         {
            var sure:Boolean = armed == "cancel:" + id;
            bx = actionButton(bx,y,sure ? "SURE?" : "CANCEL IT",function():void
            {
               if(armed == "cancel:" + id)
               {
                  act("cancel",{"id":id});
               }
               else
               {
                  armed = "cancel:" + id;
                  message = "Press again to cancel the tournament.";
                  build();
               }
            });
         }
         var mine:Object = myMatch(v,me);
         if(mine != null && mine.checkIn)
         {
            bx = actionButton(bx,y,"CHECK IN",function():void
            {
               act("checkin",{"id":id});
            });
         }
         if(v.state != "open")
         {
            bx = actionButton(bx,y,"BRACKET",function():void
            {
               showTab(T_BRACKET);
            });
         }
         bx = actionButton(bx,y,"STANDINGS",function():void
         {
            showTab(T_STANDINGS);
         });
         if(bx > 20)
         {
            y += 42;
         }
         if(v.state == "open" && me >= 0 && v.mode == "2v2" && !signed)
         {
            bx = actionButton(20,y,"INVITE TEAMMATE",function():void
            {
               typeText("TEAMMATE'S NAME","",40,function(name:String):void
               {
                  if(name.length > 0)
                  {
                     act("team_invite",{"id":id,"name":name});
                  }
               });
            });
            var out:Array = v.invites_out as Array || [];
            if(out.length > 0)
            {
               UiKit.fit(UiKit.text(detail,"INVITED: " + out.join(", ").toUpperCase(),bx + 6,y + 9,12,UiKit.GREY,UiKit.XBOLD),
                  detailW - bx - 26);
            }
            y += 42;
            for each(var inv:Object in v.invites_in as Array || [])
            {
               var from:int = int(inv.from_acc);
               UiKit.fit(UiKit.text(detail,String(inv.from_name).toUpperCase() + " WANTS YOU AS TEAMMATE",20,y + 9,13,UiKit.TEAL,
                  UiKit.XBOLD),detailW - 280);
               bx = actionButton(detailW - 250,y,"ACCEPT",teamAnswer(id,from,true));
               actionButton(bx,y,"DECLINE",teamAnswer(id,from,false));
               y += 42;
            }
         }
         bx = 20;
         if(manage && v.state == "running")
         {
            var paused:Boolean = v.paused != null;
            bx = actionButton(bx,y,paused ? "RESUME" : "PAUSE",function():void
            {
               act(paused ? "resume" : "pause",{"id":id});
            });
         }
         if(manage && (v.state == "open" || v.state == "running"))
         {
            bx = actionButton(bx,y,int(v.checkin) > 0 ? "CHECK-IN " + int(v.checkin) + " MIN" : "NO CHECK-IN",function():void
            {
               var labels:Array = [];
               for each(var c:int in CHECKINS)
               {
                  labels.push(c > 0 ? c + " MIN" : "OFF");
               }
               pickFrom("CHECK-IN FOR THE NEXT MATCHES",labels,Math.max(0,CHECKINS.indexOf(int(v.checkin))),
                  function(i:int):void
                  {
                     act("settings",{"id":id,"checkin":CHECKINS[i]});
                  });
            });
         }
         if(manage && (v.state == "open" || v.state == "running"))
         {
            bx = actionButton(bx,y,"EDIT SETTINGS",function():void
            {
               editTournament(v);
            });
         }
         if(manage && v.state == "open" && entrants.length > 1)
         {
            bx = actionButton(bx,y,"SEEDS",function():void
            {
               var numbered:Boolean = v.seeding == "manual";
               var who:Array = ["RESEED BY RATING"];
               for(var k:int = 0; k < entrants.length; k++)
               {
                  who.push((numbered ? (k + 1) + ". " : "") + String(entrants[k].name).toUpperCase());
               }
               pickFrom("SWAP WHOSE SEED?" + (numbered ? "" : " (SEEDING BECOMES MANUAL)"),who,0,function(i:int):void
               {
                  if(i == 0)
                  {
                     act("reseed",{"id":id});
                     return;
                  }
                  var first:Object = entrants[i - 1];
                  var others:Array = [];
                  var ids:Array = [];
                  for(var n:int = 0; n < entrants.length; n++)
                  {
                     if(n != i - 1)
                     {
                        others.push((numbered ? (n + 1) + ". " : "") + String(entrants[n].name).toUpperCase());
                        ids.push(int(entrants[n].account));
                     }
                  }
                  pickFrom("SWAP " + String(first.name).toUpperCase() + " WITH",others,0,function(j:int):void
                  {
                     act("swap_seeds",{"id":id,"a":int(first.account),"b":ids[j]});
                  });
               });
            });
         }
         if(creator && (v.state == "open" || v.state == "running"))
         {
            var admins:Array = v.admins as Array || [];
            bx = actionButton(bx,y,"ADMINS",function():void
            {
               var labels:Array = ["ADD AN ADMIN"];
               for each(var ad:Object in admins)
               {
                  labels.push("REMOVE " + String(ad.name).toUpperCase());
               }
               pickFrom("ADMINS: START, PAUSE, EDIT, SEEDS, AWARD, SCORE, CHECK-IN, UNDO, DISQUALIFY",labels,0,
                  function(i:int):void
                  {
                     if(i == 0)
                     {
                        typeText("THE ADMIN'S PLAYER NAME","",40,function(name:String):void
                        {
                           act("admin",{"id":id,"name":name,"add":true});
                        });
                        return;
                     }
                     act("admin",{"id":id,"account":int(admins[i - 1].account),"add":false});
                  });
            });
         }
         if(bx > 20)
         {
            y += 42;
         }
         var adminNames:Array = [];
         for each(var an:Object in v.admins as Array || [])
         {
            adminNames.push(String(an.name));
         }
         if(adminNames.length > 0 || v.paused != null)
         {
            UiKit.fit(UiKit.text(detail,(v.paused != null ? "PAUSED   " : "") + (adminNames.length > 0 ? "ADMINS: " +
               adminNames.join(", ").toUpperCase() : ""),20,y,12,UiKit.TEAL,UiKit.XBOLD),detailW - 40);
            y += 22;
         }
         if(mine != null)
         {
            var card:Sprite = new Sprite();
            card.x = 20;
            card.y = y + 4;
            detail.addChild(card);
            UiKit.text(card,"YOUR MATCH",14,8,12,UiKit.TEAL,UiKit.XBOLD);
            var mt:TextField = UiKit.text(card,mine.text,14,28,14,UiKit.WHITE,UiKit.BOLD,detailW - 68);
            card.setChildIndex(UiKit.rect(card,0,0,detailW - 40,mt.height + 38,UiKit.ROW_SELECTED,6),0);
            y += mt.height + 50;
         }
         if(y < area.height - 90)
         {
            var py:Number = Math.max(y + 10,area.height - 110);
            UiKit.rect(detail,12,py,detailW - 24,area.height - py - 12,UiKit.BODY,8);
            UiKit.text(detail,(entrants.length == 0 ? "NOBODY SIGNED UP YET" : entrants.length + (v.mode == "2v2" ? " TEAMS" :
               " PLAYERS")) + (waitNames.length > 0 ? "   ·   " + waitNames.length + " WAITING" : ""),26,py + 10,11,UiKit.GREY,
               UiKit.XBOLD);
            var nx:Number = 26;
            var ny:Number = py + 32;
            var shownNames:int = 0;
            for each(var en:Object in entrants)
            {
               var label:String = String(en.name).toUpperCase();
               if(nx + label.length * 8 + 30 > detailW - 26)
               {
                  nx = 26;
                  ny += 26;
               }
               if(ny > area.height - 40)
               {
                  break;
               }
               nx = pill(detail,label,nx,ny,int(en.account) == me ? UiKit.TEAL : UiKit.LINE) + 6;
               shownNames++;
            }
            if(shownNames < entrants.length && ny <= area.height - 40)
            {
               pill(detail,"+" + (entrants.length - shownNames) + " MORE",nx,ny,UiKit.LINE);
            }
         }
      }

      private static function minutesTo(secs:Number) : String
      {
         var mins:int = Math.max(0,Math.ceil(secs / 60));
         return mins >= 60 ? int(mins / 60) + " H " + mins % 60 + " MIN" : mins + " MIN";
      }

      private function actionButton(x:Number, y:Number, label:String, act:Function) : Number
      {
         var w:Number = Math.max(100,label.length * 10 + 30);
         var b:Sprite = button(detail,label,x,y,w,act,32,14);
         items.push({"w":"b:" + label,"sprite":b,"parent":detail,"width":w,"height":32,"use":act});
         return x + w + 10;
      }

      private function teamAnswer(id:int, from:int, accept:Boolean) : Function
      {
         return function():void
         {
            act("team_answer",{"id":id,"inviter":from,"accept":accept});
         };
      }

      private static function myMatch(v:Object, me:int) : Object
      {
         if(v.state != "running" || me < 0)
         {
            return null;
         }
         var pm:Object = v.my_pool_match;
         if(pm != null && !pm.ready)
         {
            return {"text":String(pm.name).toUpperCase() + ": your next match (vs " + (int(pm.a) == me ? String(pm.b_name) :
               String(pm.a_name)) + ") starts once you both finish the pool match you're in. " + int(pm.left) +
               " pool match" + (int(pm.left) == 1 ? "" : "es") + " left."};
         }
         for each(var r:Object in pm != null ? [{"name":pm.name,"best_of":pm.best_of,"matches":[pm]}] : v.rounds)
         {
            for each(var m:Object in r.matches)
            {
               if(m.winner == null && (int(m.a) == me && m.a != null || int(m.b) == me && m.b != null))
               {
                  if(m.a == null || m.b == null)
                  {
                     return {"text":String(r.name).toUpperCase() + ": waiting for your opponent's match to finish."};
                  }
                  var other:String = int(m.a) == me ? String(m.b_name) : String(m.a_name);
                  var mineW:int = int(m.a) == me ? int(m.wins_a) : int(m.wins_b);
                  var theirW:int = int(m.a) == me ? int(m.wins_b) : int(m.wins_a);
                  if(m.checkin_left != null)
                  {
                     var done:Boolean = (m.checked as Array || []).indexOf(int(v.me)) >= 0;
                     return {"checkIn":!done,"text":String(r.name).toUpperCase() + " vs " + other + ": " + (done ?
                        "you're checked in, waiting for the other side (" : "CHECK IN to play (") + minutesLeft(m) +
                        "). A side that doesn't check in in time loses the match."};
                  }
                  return {"text":String(r.name).toUpperCase() + " vs " + other + " (" + mineW + " - " + theirW + ", first to " +
                     int((int(r.best_of != null ? r.best_of : v.best_of) + 1) / 2) + "): accept the server's invite into the match room (Tournament " +
                     String(v.mode || "1v1") + ")."};
               }
            }
         }
         return null;
      }

      private static function minutesLeft(m:Object) : String
      {
         var left:int = int(m.checkin_left);
         return left <= 0 ? "closing" : Math.ceil(left / 60) + " min left";
      }

      private function buildBracket() : void
      {
         var p:Sprite = panel(area.x,area.y,area.width,area.height);
         var v:Object = shownId >= 0 ? ServerStats.get("tournament:" + shownId) : null;
         if(v == null || v.error != null)
         {
            UiKit.text(p,v == null ? "Asking the server..." : String(v.error),24,14,14,UiKit.LIGHT,UiKit.MEDIUM);
            return;
         }
         UiKit.fit(UiKit.text(p,String(v.name),24,10,18,UiKit.WHITE,UiKit.XBOLD),Math.min(500,area.width * 0.4));
         var rounds:Array = v.rounds as Array || [];
         if(rounds.length == 0)
         {
            UiKit.text(p,"The bracket is drawn when its creator starts it.",24,44,14,UiKit.LIGHT,UiKit.MEDIUM);
            return;
         }
         var me:int = v.my_side != null ? int(v.my_side) : v.me != null ? int(v.me) : -1;
         var creator:Boolean = me >= 0 && v.manage == true && (v.state == "running" || v.state == "done");
         var lane:Sprite = scroller(p,0,40,area.width,area.height - 46 - INFO_H);
         bracketScroll = scrollers[scrollers.length - 1];
         lane.parent.addEventListener(MouseEvent.MOUSE_DOWN,dragPressed);
         info = new Sprite();
         info.y = area.height - INFO_H - 2;
         p.addChild(info);
         drawInfo();
         var top:Array = [];
         var low:Array = [];
         for each(var rd:Object in rounds)
         {
            (rd.bracket == "l" ? low : top).push(rd);
         }
         var phases:Array = [];
         for each(var ph:Object in v.phase_list as Array || [])
         {
            if(int(ph.phase) >= 0)
            {
               phases.push(ph);
            }
         }
         var names:Array = [];
         var pick:int = 0;
         var choose:Function;
         if(phases.length > 1)
         {
            if(phasePickedFor != shownId || phasePicked < 0 || phasePicked >= phases.length)
            {
               phasePicked = livePhase(rounds,phases.length);
               phasePickedFor = shownId;
            }
            for each(ph in phases)
            {
               names.push(String(ph.name).toUpperCase());
            }
            pick = phasePicked;
            choose = function(i:int):void
            {
               phasePicked = i;
               phasePickedFor = shownId;
            };
            top = inPhase(top,int(phases[phasePicked].phase));
            low = inPhase(low,int(phases[phasePicked].phase));
         }
         else
         {
            var sides:int = top.length > 0 ? 2 * (top[0].matches as Array).length : 0;
            var offered:Array = [0];
            for(var sl:int = 1; sl < SLICES.length; sl++)
            {
               if(sides > int(SLICE_SIDES[sl]))
               {
                  offered.push(sl);
               }
            }
            if(offered.indexOf(slice) < 0)
            {
               slice = 0;
            }
            if(slice > 0)
            {
               top = sliced(top,int(SLICE_SIDES[slice]) / 2);
               low = sliced(low,int(SLICE_SIDES[slice]) / 4);
            }
            for each(var o:int in offered)
            {
               names.push(SLICES[o]);
            }
            pick = offered.indexOf(slice);
            choose = function(i:int):void
            {
               slice = int(offered[i]);
            };
         }
         bracketTop = top;
         bracketLow = low;
         var avail:Number = (area.width - 40);
         var most:int = Math.max(top.length,low.length);
         var fits:Boolean = most * MIN_COL_W <= avail;
         visCols = fits ? 0 : Math.max(2,int(avail / MIN_COL_W));
         topFrom = visCols > 0 ? Math.max(0,Math.min(topFrom,top.length - visCols)) : 0;
         lowFrom = visCols > 0 ? Math.max(0,Math.min(lowFrom,low.length - visCols)) : 0;
         var colW:Number = Math.min(250,avail / (visCols > 0 ? visCols : most));
         bracketColW = colW;
         var bx:Number = (area.width - 20);
         if(names.length > 1)
         {
            var chipRow:Sprite = new Sprite();
            p.addChild(chipRow);
            var cw:Number = UiKit.chips(chipRow,names,pick,false,function(i:int):void
            {
               choose(i);
               topFrom = lowFrom = 0;
               build();
            });
            chipRow.x = bx - cw;
            chipRow.y = 10;
            bx -= cw + 14;
            items.push({"w":"slice","sprite":chipRow,"parent":p,"width":cw,"height":24,"focusBox":[-12,-2,cw,28],
               "change":function(d:int):void
               {
                  choose(step(pick,d,names.length));
                  topFrom = lowFrom = 0;
                  pendingW = "slice";
               }});
         }
         bx = toolButton(p,bx,"FIND",function():void
         {
            typeText("FIND A PLAYER",findText,32,findPlayer);
         });
         if(v.my_side != null)
         {
            var side:int = int(v.my_side);
            bx = toolButton(p,bx,"MY MATCH",function():void
            {
               var mine:Object = findMatch(v,side,null);
               if(mine != null)
               {
                  message = "Your match: " + String(mine.name).toUpperCase() + ".";
                  showMatch(int(mine.round),int(mine.slot));
               }
            });
         }
         if(visCols > 0)
         {
            UiKit.arrow(p,bx - 22,11,1,function():void
            {
               stepColumns(1);
            });
            UiKit.arrow(p,bx - 50,11,-1,function():void
            {
               stepColumns(-1);
            });
            bx -= 60;
         }
         rtext(p,(int(v.losers) > 0 ? "DOUBLE ELIMINATION" : "SINGLE ELIMINATION") + (visCols > 0 ? "   ·   ROUNDS " +
            (topFrom + 1) + "-" + Math.min(top.length,topFrom + visCols) + " OF " + top.length + (low.length > 0 ?
            "   LOSERS " + (lowFrom + 1) + "-" + Math.min(low.length,lowFrom + visCols) + " OF " + low.length : "") +
            "   ·   THE ARROWS, DRAG, OR LEFT / RIGHT ON A MATCH MOVE" : ""),bx - 10,16,10,UiKit.GREY,UiKit.XBOLD);
         var boxH:Number = int(v.checkin) > 0 && v.state == "running" ? 64 : 52;
         var y:Number = top.length > 0 ? bracketRow(lane,top,topFrom,0,colW,boxH,v,me,creator,false) : 0;
         if(low.length > 0)
         {
            UiKit.text(lane,top.length > 0 ? "LOSERS BRACKET" : "LOSERS SIDE",20,y + 6,12,UiKit.TEAL,UiKit.XBOLD);
            bracketRow(lane,low,lowFrom,y + 28,colW,boxH,v,me,creator,true);
         }
      }

      private function dragPressed(e:MouseEvent) : void
      {
         var view:Sprite = bracketScroll != null ? bracketScroll.content.parent as Sprite : null;
         if(view == null || view.stage == null)
         {
            return;
         }
         dragBegin(view.mouseX,view.mouseY);
         view.stage.addEventListener(MouseEvent.MOUSE_MOVE,dragMoved);
         view.stage.addEventListener(MouseEvent.MOUSE_UP,dragReleased);
      }

      private function dragMoved(e:MouseEvent) : void
      {
         var view:Sprite = bracketScroll != null ? bracketScroll.content.parent as Sprite : null;
         if(view != null && drag != null)
         {
            dragMove(view.mouseX,view.mouseY);
         }
      }

      private function dragReleased(e:MouseEvent) : void
      {
         if(e.currentTarget != null)
         {
            e.currentTarget.removeEventListener(MouseEvent.MOUSE_MOVE,dragMoved);
            e.currentTarget.removeEventListener(MouseEvent.MOUSE_UP,dragReleased);
         }
         dragEnd();
      }

      public function dragBegin(x:Number, y:Number) : void
      {
         drag = {"x":x,"y":y,"scroll":bracketScroll != null ? -bracketScroll.content.y : 0,"top":topFrom,"low":lowFrom,
            "cols":0,"moving":false};
      }

      public function dragMove(x:Number, y:Number) : void
      {
         if(drag == null || bracketScroll == null)
         {
            return;
         }
         var dx:Number = x - drag.x;
         var dy:Number = y - drag.y;
         if(!drag.moving && Math.abs(dx) < DRAG_START && Math.abs(dy) < DRAG_START)
         {
            return;
         }
         drag.moving = true;
         bracketScroll.scrollTo(drag.scroll - dy);
         var want:int = visCols > 0 && bracketColW > 0 ? int(-dx / bracketColW) : 0;
         while(drag.cols != want)
         {
            var stepBy:int = want > drag.cols ? 1 : -1;
            if(!stepColumns(stepBy))
            {
               break;
            }
            drag.cols += stepBy;
         }
         var rest:Number = dx + drag.cols * bracketColW;
         var more:Boolean = rest < 0 ? canStep(1) : canStep(-1);
         bracketScroll.content.x = visCols > 0 && more ? rest : 0;
      }

      public function dragEnd() : void
      {
         if(bracketScroll != null)
         {
            bracketScroll.content.x = 0;
         }
         drag = null;
      }

      private function canStep(by:int) : Boolean
      {
         return visCols > 0 && (stepped(topFrom,by,bracketTop.length) != topFrom ||
            stepped(lowFrom,by,bracketLow.length) != lowFrom);
      }

      private function stepped(from:int, by:int, n:int) : int
      {
         return Math.max(0,Math.min(from + by,n - visCols));
      }

      private function stepColumns(by:int) : Boolean
      {
         if(!canStep(by))
         {
            return false;
         }
         var nextTop:int = stepped(topFrom,by,bracketTop.length);
         var nextLow:int = stepped(lowFrom,by,bracketLow.length);
         var mid:Number = -bracketScroll.content.y + bracketScroll.height / 2;
         var best:int = -1;
         var bestD:Number = Number.MAX_VALUE;
         for(var i:int = 0; i < items.length; i++)
         {
            var it:Object = items[i];
            if(it.col == null)
            {
               continue;
            }
            var from:int = it.low ? nextLow : nextTop;
            if(int(it.col) < from || int(it.col) >= from + visCols)
            {
               continue;
            }
            var d:Number = Math.abs(it.sprite.y + it.height / 2 - mid);
            if(d < bestD)
            {
               bestD = d;
               best = i;
            }
         }
         var keep:Number = -bracketScroll.content.y;
         var onScreen:Number = best >= 0 ? items[best].sprite.y - keep : 0;
         topFrom = nextTop;
         lowFrom = nextLow;
         if(best >= 0)
         {
            focus = best;
         }
         build();
         if(best >= 0 && focus < items.length)
         {
            bracketScroll.scrollTo(items[focus].sprite.y - onScreen);
            paintFocus();
            focused(items[focus]);
         }
         else
         {
            bracketScroll.scrollTo(keep);
         }
         if(drag != null)
         {
            drag.scroll += -bracketScroll.content.y - keep;
         }
         return true;
      }

      private function toolButton(p:Sprite, right:Number, label:String, act:Function) : Number
      {
         var w:Number = 30 + label.length * 9;
         var b:Sprite = button(p,label,right - w,8,w,act,28,12);
         items.push({"w":"b:" + label,"sprite":b,"parent":p,"width":w,"height":28,"use":act});
         return right - w - 10;
      }

      private function bracketRow(lane:Sprite, rounds:Array, from:int, y:Number, colW:Number, boxH:Number, v:Object,
                                  me:int, creator:Boolean, low:Boolean) : Number
      {
         var upto:int = visCols > 0 ? Math.min(rounds.length,from + visCols) : rounds.length;
         var first:int = (rounds[from].matches as Array).length;
         var h:Number = Math.max(first * (boxH + 10),boxH + 30);
         var lines:Shape = new Shape();
         lane.addChild(lines);
         for(var lr:int = from; lr + 1 < upto; lr++)
         {
            var here:Array = rounds[lr].matches as Array;
            var next:int = (rounds[lr + 1].matches as Array).length;
            var lx:Number = 20 + (lr - from) * colW + colW - 16;
            var mx:Number = lx + 8;
            var nx:Number = lx + 16;
            var hereH:Number = h / here.length;
            var nextH:Number = h / Math.max(1,next);
            for(var lk:int = 0; lk < here.length; lk++)
            {
               var cy:Number = y + HEAD_H + lk * hereH + hereH / 2;
               var to:int = next * 2 == here.length ? lk >> 1 : next == here.length ? lk : -1;
               if(to < 0)
               {
                  continue;
               }
               var ty:Number = y + HEAD_H + to * nextH + nextH / 2;
               lines.graphics.lineStyle(2,here[lk].winner != null ? LINE_DONE : LINE_OPEN);
               lines.graphics.moveTo(lx,cy);
               lines.graphics.lineTo(mx,cy);
               lines.graphics.lineTo(mx,ty);
               lines.graphics.lineTo(nx,ty);
            }
         }
         for(var r:int = from; r < upto; r++)
         {
            var x:Number = 20 + (r - from) * colW;
            var rnd:int = rounds[r].round != null ? int(rounds[r].round) : r;
            UiKit.fit(UiKit.text(lane,String(rounds[r].name).toUpperCase() + (rounds[r].best_of != null &&
               int(rounds[r].best_of) != int(v.best_of) ? "  BO" + int(rounds[r].best_of) : ""),x,y,12,UiKit.GREY,UiKit.XBOLD),
               colW - 16);
            UiKit.fit(UiKit.text(lane,columnNote(rounds[r]),x,y + 16,10,0x5C6E80,UiKit.XBOLD),colW - 16);
            var ms:Array = rounds[r].matches as Array;
            var slotH:Number = h / ms.length;
            for(var k:int = 0; k < ms.length; k++)
            {
               var mb:Object = matchBox(lane,x,y + HEAD_H + k * slotH + (slotH - boxH) / 2,colW - 16,boxH,ms[k],rnd,me,
                  creator,rnd == 0 || ms[k].note == "bye" || ms[k].note == "not played");
               mb.col = r;
               mb.k = k;
               mb.low = low;
            }
         }
         return y + HEAD_H + h;
      }

      private static function columnNote(r:Object) : String
      {
         var n:int = (r.matches as Array || []).length;
         return (r.phase_name != null ? String(r.phase_name).toUpperCase() + "  ·  " : "") +
            n + (n == 1 ? " MATCH" : " MATCHES") + (r.out_place != null ? "  ·  OUT " + ordinal(int(r.out_place)) : "");
      }

      private static function inPhase(rows:Array, phase:int) : Array
      {
         var out:Array = [];
         for each(var r:Object in rows)
         {
            if(r.phase != null && int(r.phase) == phase)
            {
               out.push(r);
            }
         }
         return out;
      }

      private static function livePhase(rounds:Array, count:int) : int
      {
         var live:int = count - 1;
         for each(var r:Object in rounds)
         {
            for each(var m:Object in r.matches as Array || [])
            {
               if(m.winner == null && m.note != "not played" && r.phase != null)
               {
                  live = Math.min(live,int(r.phase));
               }
            }
         }
         return Math.max(0,live);
      }

      private static function sliced(rows:Array, most:int) : Array
      {
         for(var i:int = 0; i < rows.length; i++)
         {
            if((rows[i].matches as Array).length <= most)
            {
               return rows.slice(i);
            }
         }
         return [];
      }

      private function matchBox(lane:Sprite, x:Number, y:Number, w:Number, h:Number, m:Object, rnd:int, me:int,
                                creator:Boolean, firstRound:Boolean) : Object
      {
         var tv:Object = ServerStats.get("tournament:" + shownId);
         var v_running:Boolean = tv != null && tv.state == "running";
         var s:Sprite = new Sprite();
         s.x = x;
         s.y = y;
         lane.addChild(s);
         var open:Boolean = m.winner == null && m.a != null && m.b != null;
         UiKit.rect(s,0,0,w,h,open ? UiKit.ROW_SELECTED : UiKit.BODY,4);
         var scores:Boolean = m.note != "bye" && m.note != "not played";
         var label:Boolean = m.note == "no-show" || m.note == "disqualified" || m.note == "reported";
         side(s,w,4,m.a,m.a_name,scores ? m.wins_a : null,m.winner,me,firstRound);
         side(s,w,26,m.b,m.b_name,scores ? m.wins_b : null,m.winner,me,firstRound);
         if(label)
         {
            UiKit.text(s,String(m.note).toUpperCase(),w - 6,h - 14,9,UiKit.GREY,UiKit.XBOLD).x = w - 60;
         }
         else if(open && m.checkin_left != null)
         {
            UiKit.text(s,"CHECK-IN " + minutesLeft(m).toUpperCase() + "  " + (m.checked as Array || []).length + " IN",8,
               h - 13,9,UiKit.TEAL,UiKit.XBOLD);
         }
         var it:Object = {"w":"m" + rnd + ":" + m.slot,"sprite":s,"parent":lane,"width":w,"height":h,"focusBox":[0,0,w,h],
            "tmatch":"tmatch:" + shownId + ":" + rnd + ":" + int(m.slot),"played":(m.results as Array || []).length > 0,
            "title":(m.a_name != null ? String(m.a_name) : "?") + " vs " + (m.b_name != null ? String(m.b_name) : "?")};
         var id:int = shownId;
         if(creator && (open && v_running || m.winner != null && m.note != "bye" && m.note != "not played"))
         {
            it.use = matchActions(m,rnd,open && v_running);
            it.menu = actionsEntry(it.use);
         }
         it.players = sidePlayers(m.a != null ? int(m.a) : 0,String(m.a_name || "")).concat(
            sidePlayers(m.b != null ? int(m.b) : 0,String(m.b_name || "")));
         it.menuTitle = String(it.title).toUpperCase();
         items.push(it);
         return it;
      }

      private static function actionsEntry(run:Function) : Function
      {
         return function():Array
         {
            return [["MATCH ACTIONS",run]];
         };
      }

      private function sidePlayers(account:int, name:String) : Array
      {
         if(account <= 0)
         {
            return [];
         }
         var tv:Object = ServerStats.get("tournament:" + shownId);
         for each(var e:Object in tv != null ? tv.entrants as Array || [] : [])
         {
            if(int(e.account) == account && e.partner != null && int(e.partner) > 0)
            {
               var names:Array = name.split(" & ");
               if(names.length == 2)
               {
                  return [{"account":account,"name":names[0]},{"account":int(e.partner),"name":names[1]}];
               }
            }
         }
         return [{"account":account,"name":name}];
      }

      private function drawInfo() : void
      {
         if(info == null)
         {
            return;
         }
         info.removeChildren();
         var w:Number = area.width - 40;
         UiKit.rect(info,20,0,w,INFO_H - 4,UiKit.BODY,6);
         if(infoQuery == null)
         {
            UiKit.text(info,"Select a match to see its games.",36,14,15,UiKit.GREY,UiKit.MEDIUM);
            return;
         }
         UiKit.fit(UiKit.text(info,infoTitle.toUpperCase(),36,8,15,UiKit.TEAL,UiKit.XBOLD),w - 32);
         var got:Object = ServerStats.get(infoQuery);
         var games:Array = got != null ? got.games as Array : null;
         if(games == null || games.length == 0)
         {
            UiKit.text(info,got == null ? "Loading..." : got.error != null ? String(got.error) :
               got.note ? String(got.note).toUpperCase() + ": no games played." : "No games played yet.",36,34,15,UiKit.LIGHT,
               UiKit.MEDIUM);
            return;
         }
         var n:int = Math.min(games.length,7);
         var gap:Number = 10;
         var cardW:Number = Math.min(300,(w - 32 - gap * (n - 1)) / n);
         var cardH:Number = INFO_H - 44;
         for(var i:int = 0; i < n; i++)
         {
            gameCard(info,36 + i * (cardW + gap),32,cardW,cardH,games[i],i + 1);
         }
      }

      private function gameCard(p:Sprite, x:Number, y:Number, w:Number, h:Number, g:Object, number:int) : void
      {
         var c:Sprite = new Sprite();
         c.x = x;
         c.y = y;
         p.addChild(c);
         UiKit.rect(c,0,0,w,h,UiKit.PANEL,6);
         var artH:Number = Math.round(h * 0.42);
         var art:Bitmap = LeaderboardWindow.mapThumb(g,int(w),int(artH));
         if(art != null)
         {
            c.addChild(art);
            var mask:Sprite = new Sprite();
            UiKit.rect(mask,0,0,w,artH,0,6);
            c.addChild(mask);
            art.mask = mask;
         }
         UiKit.rect(c,0,artH - 26,w,26,0x000000).alpha = 0.55;
         var secs:int = int(g.seconds);
         UiKit.text(c,"GAME " + number,10,artH - 23,14,UiKit.WHITE,UiKit.XBOLD);
         rtext(c,int(secs / 60) + ":" + (secs % 60 < 10 ? "0" : "") + secs % 60,w - 10,artH - 23,14,UiKit.LIGHT,UiKit.BOLD);
         UiKit.fit(UiKit.text(c,LeaderboardWindow.mapName(g).toUpperCase(),10,artH + 4,12,UiKit.GREY,UiKit.XBOLD),w - 20);
         var rowH:Number = (h - artH - 24) / 2;
         var first:String = g.won == "b" ? "b" : "a";
         sideCard(c,w,artH + 22,rowH,g[first] as Array,g.won != null);
         sideCard(c,w,artH + 22 + rowH,rowH,g[first == "a" ? "b" : "a"] as Array,false);
      }

      private function sideCard(c:Sprite, w:Number, y:Number, h:Number, ps:Array, won:Boolean) : void
      {
         if(won)
         {
            UiKit.rect(c,0,y + 2,4,h - 4,UiKit.TEAL);
         }
         var size:Number = Math.min(32,h - 6);
         var x:Number = 10;
         var names:Array = [];
         var kos:int = 0;
         var falls:int = 0;
         for each(var pl:Object in ps || [])
         {
            var bm:Bitmap = LeaderboardWindow.legendIcon(int(pl.legend_id),int(size));
            if(bm != null)
            {
               bm.x = x;
               bm.y = y + (h - size) / 2;
               c.addChild(bm);
            }
            x += size + 4;
            names.push(String(pl.name));
            kos += int(pl.kos);
            falls += int(pl.falls);
         }
         var right:Number = won ? w - 48 : w - 10;
         UiKit.fit(UiKit.text(c,names.length > 0 ? names.join(" & ") : "?",x + 4,y + h / 2 - 17,14,won ? UiKit.WHITE : UiKit.LIGHT,
            won ? UiKit.XBOLD : UiKit.BOLD),right - x - 8);
         UiKit.text(c,kos + " KO" + (kos == 1 ? "" : "s") + "  ·  " + falls + " FALL" + (falls == 1 ? "" : "S"),x + 4,y + h / 2,
            12,UiKit.GREY,UiKit.BOLD);
         if(won)
         {
            rtext(c,"WIN",w - 10,y + h / 2 - 9,14,UiKit.TEAL,UiKit.XBOLD);
         }
      }

      private static function rtext(p:Sprite, s:String, right:Number, y:Number, size:Number, color:uint, font:String) : TextField
      {
         var t:TextField = UiKit.text(p,s,right,y,size,color,font);
         t.x = right - t.width;
         return t;
      }

      private static function side(s:Sprite, w:Number, y:Number, acc:Object, name:Object, wins:Object, winner:Object,
                                   me:int, firstRound:Boolean) : void
      {
         if(acc == null)
         {
            UiKit.text(s,name != null ? String(name) : firstRound ? "bye" : "?",8,y,13,UiKit.GREY,UiKit.MEDIUM);
            return;
         }
         var won:Boolean = winner != null && int(winner) == int(acc);
         var lost:Boolean = winner != null && !won;
         UiKit.fit(UiKit.text(s,String(name),8,y,13,int(acc) == me ? UiKit.TEAL : (lost ? UiKit.GREY : UiKit.WHITE),
            won ? UiKit.XBOLD : UiKit.BOLD),w - 44);
         if(wins != null)
         {
            UiKit.text(s,String(int(wins)),w - 22,y,13,won ? UiKit.TEAL : UiKit.LIGHT,UiKit.XBOLD);
         }
      }

      private function buildCreate() : void
      {
         var page:Sprite = panel(area.x,area.y,area.width,area.height);
         var got:Object = PrivateServer.host != null ? ServerStats.get("tournaments") : null;
         if(got != null && got.may_create == false)
         {
            UiKit.text(page,got.signed_in == false ? "Sign in with Discord (Options > Account) to create a tournament." :
               "Only some accounts can create tournaments on this server.",24,14,16,UiKit.LIGHT,UiKit.MEDIUM,900);
            return;
         }
         if(editingId >= 0)
         {
            var head:Sprite = new Sprite();
            head.x = 12;
            head.y = 12;
            page.addChild(head);
            UiKit.rect(head,0,0,area.width - 24,48,UiKit.BODY,6);
            UiKit.rect(head,0,0,4,48,UiKit.TEAL);
            UiKit.fit(UiKit.text(head,"EDITING " + editingName.toUpperCase(),20,13,18,UiKit.WHITE,UiKit.XBOLD),area.width - 80);
         }
         else
         {
            presetRow(page);
         }
         var colW:Number = (area.width - 48) / 3;
         var colH:Number = area.height - 70 - 70;
         var cols:Array = [];
         for(var c:int = 0; c < 3; c++)
         {
            var col:Sprite = new Sprite();
            col.x = 12 + c * (colW + 12);
            col.y = 70;
            page.addChild(col);
            UiKit.rect(col,0,0,colW,colH,UiKit.BODY,6);
            UiKit.text(col,["TOURNAMENT","GAME RULES","MAPS & PICKS"][c],16,10,16,UiKit.TEAL,UiKit.XBOLD);
            cols.push(scroller(col,0,40,colW,colH - 44));
         }
         var w:Number = colW - 12;
         var p:Sprite = cols[0];
         var y:Number = 0;
         y = cText(p,y,w,"NAME",newName,"Type a name",40,"Shown in the list and on the invites.",function(v:String):void
         {
            newName = v;
         });
         y = cValue(p,y,w,"MODE",MODES[newMode].toUpperCase(),"1v1, or teams of two (sign up with your teammate in your party).",
            function(d:int):void
            {
               newMode = step(newMode,d,MODES.length);
               if(!scoringFits(newScoring))
               {
                  newScoring = 0;
               }
            });
         y = cValue(p,y,w,newMode == 1 ? "TEAMS" : "PLAYERS",String(LIMITS[newLimit]),"How many can sign up.",function(d:int):void
         {
            newLimit = step(newLimit,d,LIMITS.length);
         });
         y = cValue(p,y,w,"FORMAT",ELIMINATIONS[newLosers],newLosers == 0 ? "Lose once and you're out." :
            newLosers == 1 ? "Lose twice and you're out. The grand final resets if the losers' side wins it." :
            "Lose twice and you're out. One grand final, no reset.",function(d:int):void
         {
            newLosers = step(newLosers,d,ELIMINATIONS.length);
         });
         var top:int = POOL_TOPS[newPoolsTop];
         y = cValue(p,y,w,"POOLS",top == 0 ? "NONE" : "UNTIL TOP " + top,top == 0 ? "Straight into the bracket." :
            "Pools first; the pools' top " + top + " go on to the bracket.",
            function(d:int):void
            {
               newPoolsTop = step(newPoolsTop,d,POOL_TOPS.length);
            });
         if(top > 0)
         {
            y = cValue(p,y,w,"POOL TYPE",POOL_KIND_NAMES[newPoolKind],newPoolKind == 0 ?
               "Round robin: everyone in a pool plays everyone once." :
               "Bracket: each pool is a small single elimination bracket, played until its top go on.",function(d:int):void
               {
                  newPoolKind = step(newPoolKind,d,POOL_KINDS.length);
               });
            y = cValue(p,y,w,"FROM EACH POOL",String(POOL_SENDS[newPoolSend]),Math.max(1,top / POOL_SENDS[newPoolSend]) +
               " pools; each pool's top " + POOL_SENDS[newPoolSend] + " go on.",function(d:int):void
               {
                  newPoolSend = step(newPoolSend,d,POOL_SENDS.length);
               });
         }
         y = cValue(p,y,w,"PHASES",PHASE_NAMES[newPhaseSet],newPhaseSet == 0 ? "One bracket, played straight through." :
            "Each phase its own bracket, started once the one before is over (double elimination: seeded again, each " +
            "side kept).",function(d:int):void
            {
               newPhaseSet = step(newPhaseSet,d,PHASE_SETS.length);
            });
         y = cValue(p,y,w,"BEST OF",String(BEST_OF[newBestOf]),"Games per match.",function(d:int):void
         {
            newBestOf = step(newBestOf,d,BEST_OF.length);
         });
         y = cValue(p,y,w,"TOP 8",laterName(newTop8),"Games per match from the quarter-finals on.",function(d:int):void
         {
            newTop8 = step(newTop8,d,LATER_BEST_OF.length);
         });
         y = cValue(p,y,w,"FINAL",laterName(newFinal),"Games in the final.",function(d:int):void
         {
            newFinal = step(newFinal,d,LATER_BEST_OF.length);
         });
         y = cValue(p,y,w,"CHECK-IN",CHECKINS[newCheckin] == 0 ? "OFF" : CHECKINS[newCheckin] + " MIN",
            CHECKINS[newCheckin] == 0 ? "No check-in: the room opens as soon as a match is ready." :
            "Time to check in for each match. Miss it and you lose the match.",function(d:int):void
            {
               newCheckin = step(newCheckin,d,CHECKINS.length);
            });
         y = cValue(p,y,w,"SEEDING",SEEDING_NAMES[newSeeding],newSeeding == 0 ? "Best rated players are kept apart." :
            newSeeding == 1 ? "Random order." : newSeeding == 2 ? "First to sign up is seed 1." :
            "You set the seeds before it starts.",function(d:int):void
            {
               newSeeding = step(newSeeding,d,SEEDINGS.length);
            });
         y = cValue(p,y,w,"START",newStartAt == 0 ? "MANUAL" : when(newStartAt / 1000),newStartAt == 0 ? "You start it." :
            startPassed() ? "That time has passed: pick a later one." :
            "It starts by itself then (2 or more signed up). Your PC's time.",function(d:int):void
            {
               newStartAt = newStartAt == 0 ? nextHour() : 0;
               newPreset = -1;
            });
         if(newStartAt != 0)
         {
            y = cValue(p,y,w,"DATE",dayName(newStartAt),"The day it starts, up to a year ahead. Select opens the calendar.",
               function(d:int):void
               {
                  moveStart(d * 86400000);
               });
            var dateRow:Object = items[items.length - 1];
            dateRow.use = openCalendar;
            dateRow.sprite.buttonMode = true;
            dateRow.sprite.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
            {
               openCalendar();
            });
            var at:Date = new Date(newStartAt);
            y = cValue(p,y,w,"HOUR",(at.hours < 10 ? "0" : "") + at.hours + ":00","The hour (24-hour clock).",
               function(d:int):void
               {
                  var t:Date = new Date(newStartAt);
                  t.hours = (t.hours + d + 24) % 24;
                  moveStart(t.time - newStartAt);
               });
            y = cValue(p,y,w,"MINUTE",":" + (at.minutes < 10 ? "0" : "") + at.minutes,"Minutes past the hour, in fives.",
               function(d:int):void
               {
                  var t:Date = new Date(newStartAt);
                  t.minutes = (Math.round(t.minutes / 5) * 5 + d * 5 + 60) % 60;
                  moveStart(t.time - newStartAt);
               });
         }
         p = cols[1];
         y = 0;
         var ownMaps:Boolean = SCORINGS[newScoring][3] != "";
         y = cValue(p,y,w,"GAME MODE",String(SCORINGS[newScoring][1]),String(SCORINGS[newScoring][5]) + (ownMaps ?
            " Its own maps, time and score." : ""),function(d:int):void
            {
               do
               {
                  newScoring = step(newScoring,d == 0 ? 1 : d,SCORINGS.length);
               }
               while(!scoringFits(newScoring));
            },SCORINGS[newScoring][2]);
         if(SCORINGS[newScoring][4])
         {
            y = cValue(p,y,w,"STOCKS",String(STOCKS[newStocks]),"Lives per player.",function(d:int):void
            {
               newStocks = step(newStocks,d,STOCKS.length);
            });
         }
         if(!ownMaps)
         {
            y = cValue(p,y,w,"MATCH TIME",MINUTES[newMinutes] + " MIN","Time limit for each game.",function(d:int):void
            {
               newMinutes = step(newMinutes,d,MINUTES.length);
            });
         }
         y = cValue(p,y,w,"DAMAGE",newDamage + "%","Damage dealt (100% is normal).",function(d:int):void
         {
            newDamage = Math.max(50,Math.min(300,newDamage + d * 10));
         });
         if(!ownMaps)
         {
            y = cValue(p,y,w,"VARIATION",VARIATION_NAMES[newVariation],VARIATION_ABOUT[newVariation],function(d:int):void
            {
               newVariation = step(newVariation,d,VARIATION_NAMES.length);
            });
            y = cValue(p,y,w,"WEAPON SPAWNS",RATE_NAMES[newWeaponRate],"How often weapons drop.",function(d:int):void
            {
               newWeaponRate = step(newWeaponRate,d,WEAPON_RATES.length);
            });
            y = cValue(p,y,w,"GADGET SPAWNS",RATE_NAMES[newGadgetRate],"How often gadgets drop.",function(d:int):void
            {
               newGadgetRate = step(newGadgetRate,d,GADGET_RATES.length);
            });
         }
         if(newMode == 1)
         {
            y = cValue(p,y,w,"TEAM DAMAGE",newTeamDamage ? "ON" : "OFF","Whether you can hit your teammate.",function(d:int):void
            {
               newTeamDamage = !newTeamDamage;
            });
         }
         p = cols[2];
         y = 0;
         var pools:Array = MAP_POOLS[MODES[newMode]] as Array;
         newPool = Math.min(newPool,pools.length - 1);
         if(!ownMaps)
         {
            y = cValue(p,y,w,"MAP POOL",String(POOL_NAMES[String(pools[newPool])]),"Which maps can be played.",function(d:int):void
            {
               newPool = step(newPool,d,pools.length);
            });
         }
         y = cValue(p,y,w,"MAP PICK",MAP_PICK_NAMES[newMapPick],MAP_PICK_ABOUT[newMapPick],function(d:int):void
         {
            newMapPick = step(newMapPick,d,MAP_PICKS.length);
         });
         y = cValue(p,y,w,"LEGENDS",listValue(newLegendRule,newLegends.length),newLegendRule == 0 ?
            "Every legend. Press to ban some, or allow only some." : (newLegendRule == 1 ? "Banned legends." :
            "Only these legends.") + " Press to change the list.",function(d:int):void
            {
               newLegendRule = step(newLegendRule,d,LIST_RULES.length);
            });
         items[items.length - 1].use = function():void
         {
            pickLegends(0);
         };
         y = iconStrip(p,y,w,newLegendRule == 0 ? [] : newLegends,true);
         y = cValue(p,y,w,"WEAPONS",listValue(newWeaponRule,newWeapons.length),newWeaponRule == 0 ?
            "Every weapon. Press to ban some, or allow only some." : (newWeaponRule == 1 ?
            "Legends with a banned weapon can't be picked." : "Only legends with both weapons in the list.") +
            " Press to change the list.",function(d:int):void
            {
               newWeaponRule = step(newWeaponRule,d,LIST_RULES.length);
            });
         items[items.length - 1].use = function():void
         {
            pickWeapons(0);
         };
         y = iconStrip(p,y,w,newWeaponRule == 0 ? [] : newWeapons,false);
         y += 6;
         UiKit.text(p,"NOTES (OPTIONAL)",14,y,12,UiKit.GREY,UiKit.XBOLD);
         y += 22;
         y = cText(p,y,w,"ABOUT",newAbout,"",120,"A line about it.",function(v:String):void
         {
            newAbout = v;
         });
         y = cText(p,y,w,"RULES",newRules,"",300,"Anything else players should know.",function(v:String):void
         {
            newRules = v;
         });
         y = cText(p,y,w,"REGION",newRegion,"",40,"For example NA East.",function(v:String):void
         {
            newRegion = v;
         });
         y = cText(p,y,w,"STREAM",newStream,"",120,"A stream link.",function(v:String):void
         {
            newStream = v;
         });
         y = cText(p,y,w,"PRIZE",newPrize,"",100,"What the winner gets (just a note).",function(v:String):void
         {
            newPrize = v;
         });
         var create:Function = function():void
         {
            if(startPassed())
            {
               message = "That start time has passed: pick a later one.";
               build();
               return;
            }
            if(editingId >= 0)
            {
               saveEdit();
               return;
            }
            act("create",createArgs());
         };
         var by:Number = area.height - 56;
         var b:Sprite = button(page,editingId >= 0 ? "SAVE CHANGES" : "CREATE",12,by,240,create,44,18);
         items.push({"w":"create","sprite":b,"parent":page,"width":240,"height":44,"use":create,
            "about":editingId >= 0 ? "Save what you changed. Once it has started, only best-ofs, check-in, game rules " +
            "and notes can change." : "Create it. You run it: start it, award matches, add admins or cancel it."});
         var hintX:Number = 272;
         if(editingId >= 0)
         {
            var stop:Function = function():void
            {
               stopEditing();
               build();
            };
            var sb:Sprite = button(page,"STOP EDITING",262,by,200,stop,44,16);
            items.push({"w":"stopedit","sprite":sb,"parent":page,"width":200,"height":44,"use":stop,
               "about":"Leave the changes unsaved: CREATE makes a new tournament again."});
            hintX = 482;
         }
         createHint = UiKit.text(page,"",hintX,by + 12,16,UiKit.LIGHT,UiKit.MEDIUM,area.width - hintX - 18);
      }

      private function createArgs() : Object
      {
         return {"name":newName,"mode":MODES[newMode],"best_of":BEST_OF[newBestOf],"max_players":LIMITS[newLimit],
               "checkin":CHECKINS[newCheckin],"best_of_top8":LATER_BEST_OF[newTop8],"best_of_final":LATER_BEST_OF[newFinal],
               "losers":newLosers,"about":newAbout,"stocks":STOCKS[newStocks],"minutes":MINUTES[newMinutes],
               "seeding":SEEDINGS[newSeeding],"start_in":startIn(),"legend_rule":LIST_RULES[newLegendRule],
               "legends":newLegends.join(","),"weapon_rule":LIST_RULES[newWeaponRule],"weapons":newWeapons.join(","),
               "map_set":(MAP_POOLS[MODES[newMode]] as Array)[newPool],"map_pick":MAP_PICKS[newMapPick],
               "scoring":SCORINGS[newScoring][0],"damage":newDamage,"variation":newVariation,
               "weapon_rate":WEAPON_RATES[newWeaponRate],"gadget_rate":GADGET_RATES[newGadgetRate],
               "team_damage":newTeamDamage ? 1 : 0,"rules":newRules,"region":newRegion,"stream":newStream,
               "prize":newPrize,"pools_until":POOL_TOPS[newPoolsTop],"pool_advance":POOL_SENDS[newPoolSend],
               "pool_kind":POOL_KINDS[newPoolKind],"phases":PHASE_SETS[newPhaseSet]};
      }

      private function editTournament(v:Object) : void
      {
         var at:Function = function(list:Array, value:*, fallback:int):int
         {
            var i:int = list.indexOf(value);
            return i >= 0 ? i : fallback;
         };
         newName = String(v.name || "");
         newMode = at(MODES,String(v.mode),0);
         newLimit = at(LIMITS,int(v.max_players),1);
         newLosers = Math.max(0,Math.min(ELIMINATIONS.length - 1,int(v.losers)));
         newBestOf = at(BEST_OF,int(v.best_of),1);
         newTop8 = at(LATER_BEST_OF,int(v.best_of_top8),0);
         newFinal = at(LATER_BEST_OF,int(v.best_of_final),0);
         newCheckin = at(CHECKINS,int(v.checkin),0);
         newSeeding = at(SEEDINGS,String(v.seeding || "rating"),0);
         newStocks = at(STOCKS,int(v.stocks || 3),2);
         newMinutes = at(MINUTES,int(v.minutes || 8),5);
         newLegendRule = at(LIST_RULES,String(v.legend_rule || ""),0);
         newLegends = [];
         for each(var h:String in String(v.legends || "").split(","))
         {
            if(h.length > 0)
            {
               newLegends.push(int(h));
            }
         }
         newWeaponRule = at(LIST_RULES,String(v.weapon_rule || ""),0);
         newWeapons = [];
         for each(var wp:String in String(v.weapons || "").split(","))
         {
            if(wp.length > 0)
            {
               newWeapons.push(wp);
            }
         }
         newPool = at(MAP_POOLS[MODES[newMode]] as Array,int(v.map_set),0);
         newMapPick = at(MAP_PICKS,String(v.map_pick || "tournament"),0);
         newScoring = 0;
         for(var sc:int = 0; sc < SCORINGS.length; sc++)
         {
            if(SCORINGS[sc][0] == int(v.scoring || 2))
            {
               newScoring = sc;
            }
         }
         newDamage = v.damage != null ? int(v.damage) : 100;
         newVariation = int(v.variation);
         newWeaponRate = at(WEAPON_RATES,v.weapon_rate != null ? int(v.weapon_rate) : 2,2);
         newGadgetRate = at(GADGET_RATES,int(v.gadget_rate),0);
         newTeamDamage = v.team_damage == null || int(v.team_damage) != 0;
         newAbout = String(v.about || "");
         newRules = String(v.rules || "");
         newRegion = String(v.region || "");
         newStream = String(v.stream || "");
         newPrize = String(v.prize || "");
         newPoolsTop = at(POOL_TOPS,int(v.pools_until),0);
         newPoolSend = at(POOL_SENDS,int(v.pool_advance || 2),1);
         newPoolKind = at(POOL_KINDS,String(v.pool_kind || "robin"),0);
         newPhaseSet = at(PHASE_SETS,String(v.phases || ""),0);
         var now:Number = new Date().time;
         newStartAt = v.starts != null && Number(v.starts) > 0 ? now + (Number(v.starts) - Number(v.server_now || now / 1000)) * 1000 : 0;
         newPreset = -1;
         editingId = int(v.id);
         editingName = String(v.name || "");
         editingBefore = createArgs();
         editingStartAt = newStartAt;
         showTab(T_CREATE);
      }

      private function saveEdit() : void
      {
         var now:Object = createArgs();
         var changed:Object = {"id":editingId};
         var n:int = 0;
         for(var k:String in now)
         {
            if(k != "start_in" && k != "mode" && String(now[k]) != String(editingBefore[k]))
            {
               changed[k] = now[k];
               n++;
            }
         }
         if(newStartAt != editingStartAt)
         {
            changed["start_in"] = startIn();
            n++;
         }
         if(n == 0)
         {
            message = "Nothing changed.";
            build();
            return;
         }
         var id:int = editingId;
         stopEditing();
         shownId = id;
         act("settings",changed);
         showTab(T_OVERVIEW);
      }

      private function stopEditing() : void
      {
         editingId = -1;
         editingBefore = null;
         applyPreset(1);
         newName = newAbout = newRules = newRegion = newStream = newPrize = "";
      }

      private function scoringFits(i:int) : Boolean
      {
         return SCORINGS[i][3] == "" || SCORINGS[i][3] == MODES[newMode];
      }

      private static function nextHour() : Number
      {
         var t:Date = new Date();
         t.minutes = 0;
         t.seconds = 0;
         t.milliseconds = 0;
         return t.time + 3600000;
      }

      private function openCalendar() : void
      {
         var now:Number = new Date().time;
         pickDate("START DATE",newStartAt,now,now + START_DAYS * 86400000 - 60000,function(day:Number):void
         {
            var at:Date = new Date(newStartAt);
            var d:Date = new Date(day);
            newStartAt = new Date(d.fullYear,d.month,d.date,at.hours,at.minutes).time;
            newPreset = -1;
            build();
         });
      }

      private static function dayName(ms:Number) : String
      {
         var d:Date = new Date(ms);
         var today:Date = new Date();
         today.hours = 0;
         today.minutes = 0;
         today.seconds = 0;
         today.milliseconds = 0;
         var ahead:int = Math.round((new Date(d.fullYear,d.month,d.date).time - today.time) / 86400000);
         return ahead == 0 ? "TODAY" : ahead == 1 ? "TOMORROW" : DAYS[d.day] + " " + MONTHS[d.month] + " " + d.date +
            (d.fullYear != today.fullYear ? " " + d.fullYear : "");
      }

      private function moveStart(ms:Number) : void
      {
         newPreset = -1;
         var t:Number = newStartAt + ms;
         var last:Number = new Date().time + START_DAYS * 86400000 - 60000;
         if(t > last || t < new Date().time - 86400000)
         {
            return;
         }
         newStartAt = t;
      }

      private function startPassed() : Boolean
      {
         return newStartAt != 0 && newStartAt <= new Date().time;
      }

      private function startIn() : int
      {
         return newStartAt == 0 ? 0 : Math.min(START_DAYS * 1440,Math.max(1,Math.round((newStartAt - new Date().time) / 60000)));
      }

      private function step(i:int, d:int, n:int) : int
      {
         newPreset = -1;
         return (i + d + n) % n;
      }

      private function presetRow(page:Sprite) : void
      {
         var s:Sprite = new Sprite();
         s.x = 12;
         s.y = 12;
         page.addChild(s);
         var w:Number = area.width - 24;
         UiKit.rect(s,0,0,w,46,UiKit.BODY,6);
         UiKit.text(s,"PRESET",16,13,16,UiKit.GREY,UiKit.XBOLD);
         var x:Number = 120;
         var names:Array = [];
         for each(var pr:Object in PRESETS)
         {
            names.push(pr.name);
         }
         names.push("CUSTOM");
         var chosen:int = newPreset >= 0 ? newPreset : names.length - 1;
         for(var i:int = 0; i < names.length; i++)
         {
            var on:Boolean = i == chosen;
            var chip:Sprite = new Sprite();
            chip.x = x;
            chip.y = 7;
            s.addChild(chip);
            var cw:Number = Math.max(110,String(names[i]).length * 12 + 36);
            UiKit.rect(chip,0,0,cw,32,on ? UiKit.TEAL : UiKit.LINE,16);
            UiKit.text(chip,names[i],cw / 2,6,15,on ? UiKit.NAVY_TEXT : UiKit.WHITE,UiKit.XBOLD,0,true);
            if(i < PRESETS.length)
            {
               chip.buttonMode = true;
               chip.addEventListener(MouseEvent.CLICK,presetPicker(i));
            }
            x += cw + 10;
         }
         var change:Function = function(d:int):void
         {
            var at:int = newPreset >= 0 ? newPreset : (d > 0 ? -1 : 0);
            applyPreset((at + d + PRESETS.length) % PRESETS.length);
         };
         items.push({"w":"preset","sprite":s,"parent":page,"width":w,"height":46,"focusBox":[0,0,w,46],"change":change,
            "about":newPreset >= 0 ? PRESETS[newPreset].about : "Your own settings. Pick a preset to start from one."});
      }

      private function presetPicker(i:int) : Function
      {
         return function(e:MouseEvent):void
         {
            applyPreset(i);
            build();
         };
      }

      private function applyPreset(i:int) : void
      {
         var pr:Object = PRESETS[i];
         newPreset = i;
         newMode = MODES.indexOf(pr.mode);
         newLimit = LIMITS.indexOf(pr.limit);
         newLosers = pr.losers;
         newBestOf = BEST_OF.indexOf(pr.bestOf);
         newTop8 = LATER_BEST_OF.indexOf(pr.top8);
         newFinal = LATER_BEST_OF.indexOf(pr.final);
         newCheckin = CHECKINS.indexOf(pr.checkin);
         newSeeding = 0;
         newStartAt = 0;
         newScoring = pr.scoring == 1 ? 1 : 0;
         newStocks = STOCKS.indexOf(pr.stocks);
         newMinutes = MINUTES.indexOf(pr.minutes);
         newDamage = 100;
         newVariation = 0;
         newWeaponRate = WEAPON_RATES.indexOf(2);
         newGadgetRate = GADGET_RATES.indexOf(pr.gadgets);
         newTeamDamage = true;
         newPool = 0;
         newMapPick = MAP_PICKS.indexOf(pr.mapPick);
         newPoolsTop = 0;
         newPoolSend = 1;
         newPoolKind = 0;
         newPhaseSet = 0;
      }

      private function cValue(p:Sprite, y:Number, w:Number, label:String, value:String, about:String, change:Function,
                              icon:String = null) : Number
      {
         var s:Sprite = new Sprite();
         s.x = 6;
         s.y = y;
         p.addChild(s);
         UiKit.rect(s,0,0,w,40,UiKit.PANEL,4);
         UiKit.text(s,label,12,11,15,UiKit.LIGHT,UiKit.XBOLD);
         var vw:Number = Math.min(230,w * 0.55);
         var left:Number = w - vw - 6;
         UiKit.arrow(s,left,10,-1,function():void
         {
            change(-1);
            build();
         });
         if(icon != null)
         {
            var art:MovieClip = class_687.method_1714(icon,"UI_GameSettings");
            UiKit.gotoLabel(art,"Ready");
            UiKit.icon(s,art,left + 34,4,32);
         }
         var t:Object = UiKit.text(s,value,left + vw / 2 + (icon != null ? 14 : 0),10,value.length <= 12 ? 16 : 13,UiKit.WHITE,
            UiKit.XBOLD,0,true);
         UiKit.arrow(s,w - 34,10,1,function():void
         {
            change(1);
            build();
         });
         items.push({"w":"v:" + label,"sprite":s,"parent":p,"width":w,"height":40,"focusBox":[0,0,w,40],"change":change,
            "about":about});
         return y + 44;
      }

      private function cText(p:Sprite, y:Number, w:Number, label:String, value:String, empty:String, max:int, about:String,
                             done:Function) : Number
      {
         var s:Sprite = new Sprite();
         s.x = 6;
         s.y = y;
         p.addChild(s);
         UiKit.rect(s,0,0,w,40,UiKit.PANEL,4);
         UiKit.text(s,label,12,11,15,UiKit.LIGHT,UiKit.XBOLD);
         UiKit.rect(s,110,6,w - 116,28,UiKit.LINE,4);
         UiKit.fit(UiKit.text(s,value.length > 0 ? value : empty,118,10,15,value.length > 0 ? UiKit.WHITE : UiKit.GREY,
            UiKit.MEDIUM),w - 132);
         var it:Object = {"w":"f:" + label,"sprite":s,"parent":p,"width":w,"height":40,"focusBox":[0,0,w,40],"about":about,
            "use":function():void
            {
               typeText(label,value,max,function(v:String):void
               {
                  done(v);
                  build();
               });
            }};
         s.buttonMode = true;
         s.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            it.use();
         });
         items.push(it);
         return y + 44;
      }

      private function iconStrip(p:Sprite, y:Number, w:Number, list:Array, legends:Boolean) : Number
      {
         if(list.length == 0)
         {
            return y;
         }
         var size:Number = 34;
         var x:Number = 12;
         for(var i:int = 0; i < list.length; i++)
         {
            if(x + size > w)
            {
               UiKit.text(p,"+" + (list.length - i),x,y + 8,14,UiKit.GREY,UiKit.XBOLD);
               break;
            }
            if(legends)
            {
               var bm:Bitmap = LeaderboardWindow.legendIcon(int(list[i]),size);
               if(bm != null)
               {
                  bm.x = x;
                  bm.y = y;
                  p.addChild(bm);
               }
            }
            else
            {
               UiKit.icon(p,weaponIcon(String(list[i])),x,y,size);
            }
            x += size + 4;
         }
         return y + size + 6;
      }

      private static function weaponIcon(name:String) : MovieClip
      {
         return class_687.method_1714("a_WeaponIcon_" + name,"UI_Icons");
      }

      override protected function focused(it:Object) : void
      {
         if(tab == T_CREATE)
         {
            if(createHint != null)
            {
               createHint.text = it != null && it.about != null ? String(it.about) : "";
            }
            return;
         }
         focusedList(it);
      }

      private static function listValue(rule:int, n:int) : String
      {
         return rule == 0 ? "ANY" : RULE_NAMES[rule] + " " + n;
      }

      private static function legendNames(ids:Array) : String
      {
         var out:Array = [];
         for each(var id:Object in ids)
         {
            var hero:HeroType = HeroType.method_7110(uint(id));
            out.push(hero != null && hero.var_4421 ? String(hero.var_4421) : "Legend " + id);
         }
         return out.length > 0 ? out.join(", ") : "none yet";
      }

      private static function weaponNames(list:Array) : String
      {
         var out:Array = [];
         for each(var w:String in list)
         {
            var i:int = WEAPONS.indexOf(w);
            out.push(i >= 0 ? String(WEAPON_NAMES[i]).toLowerCase() : w);
         }
         return out.length > 0 ? out.join(", ") : "none yet";
      }

      private function pickLegends(at:int) : void
      {
         var heroes:Array = LeaderboardWindow.allLegends();
         var names:Array = ["DONE"];
         var mark:String = newLegendRule == 2 ? "+ " : "X ";
         for each(var h:HeroType in heroes)
         {
            names.push((newLegends.indexOf(int(h.var_12172)) >= 0 ? mark : "") + String(h.var_4421).toUpperCase());
         }
         pickFrom(newLegendRule == 2 ? "ALLOWED LEGENDS" : "BANNED LEGENDS",names,at,
            function(k:int):void
            {
               if(k == 0)
               {
                  build();
                  return;
               }
               var id:int = int(heroes[k - 1].var_12172);
               var i:int = newLegends.indexOf(id);
               if(i >= 0)
               {
                  newLegends.splice(i,1);
               }
               else
               {
                  newLegends.push(id);
               }
               if(newLegendRule == 0)
               {
                  newLegendRule = 1;
               }
               pickLegends(k);
            },function(k:int):Bitmap
            {
               if(k == 0)
               {
                  return null;
               }
               var bm:Bitmap = LeaderboardWindow.legendIcon(int(heroes[k - 1].var_12172),50);
               if(bm != null && (newLegends.indexOf(int(heroes[k - 1].var_12172)) >= 0) == (newLegendRule != 2))
               {
                  bm.alpha = 0.35;
               }
               return bm;
            });
      }

      private function pickWeapons(at:int) : void
      {
         var names:Array = ["DONE"];
         for(var i:int = 0; i < WEAPONS.length; i++)
         {
            names.push((newWeapons.indexOf(WEAPONS[i]) >= 0 ? (newWeaponRule == 2 ? "+ " : "X ") : "") + WEAPON_NAMES[i]);
         }
         pickFrom(newWeaponRule == 2 ? "ALLOWED WEAPONS" : "BANNED WEAPONS",names,at,
            function(k:int):void
            {
               if(k == 0)
               {
                  build();
                  return;
               }
               var j:int = newWeapons.indexOf(WEAPONS[k - 1]);
               if(j >= 0)
               {
                  newWeapons.splice(j,1);
               }
               else
               {
                  newWeapons.push(WEAPONS[k - 1]);
               }
               if(newWeaponRule == 0)
               {
                  newWeaponRule = 1;
               }
               pickWeapons(k);
            },function(k:int):Sprite
            {
               if(k == 0)
               {
                  return null;
               }
               var icon:Sprite = new Sprite();
               UiKit.icon(icon,weaponIcon(WEAPONS[k - 1]),0,0,50);
               if((newWeapons.indexOf(WEAPONS[k - 1]) >= 0) == (newWeaponRule != 2))
               {
                  icon.alpha = 0.35;
               }
               return icon;
            });
      }

      private static function ratingName(r:Array) : String
      {
         var low:int = int(r[0]);
         var high:int = int(r[1]);
         return low == 0 && high == 0 ? "ANY" : high == 0 ? low + "+" : low + "-" + high;
      }

      private static function laterName(i:int) : String
      {
         return LATER_BEST_OF[i] == 0 ? "SAME" : "BO" + LATER_BEST_OF[i];
      }

      private static function stateName(state:String) : String
      {
         return state == "open" ? "SIGN-UP OPEN" : state == "running" ? "LIVE" : state == "done" ? "FINISHED" : state.toUpperCase();
      }
   }
}
