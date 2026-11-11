package bh.platform
{
   import flash.display.Bitmap;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.events.MouseEvent;
   import flash.filesystem.File;
   import flash.utils.getTimer;

   public class ReplaysWindow extends BigWindow
   {
      private static const TABS:Array = ["RECENT","FAVORITES","OLDER"];
      private static const QUICK:Array = ["ALL","WINS","LOSSES","1V1","2V2","RANKED","NOTED"];
      private static const PER_PAGE:int = 40;
      private static const ROW_H:Number = 58;
      private static const THUMB_W:int = 104;
      private static const ICON:int = 22;
      private static const ICONS:int = 4;
      private static const KEY:String = "gameReplayList";

      private static var window:ReplaysWindow;
      private static var tabScreen:Object = null;
      private static const FORWARD:Array = [2,6,17,23];
      private static var wantAfterMatch:Boolean = false;
      private static var openName:String = null;
      private static var settledAt:int = 0;
      private static var settledOn:Object = null;
      private static const SETTLE_MS:int = 1500;
      private static var ticking:Boolean = false;
      private static var leftScreen:Object = null;
      private static var lastSaved:String = null;
      private static var lastSavedAt:int = 0;
      private static var leftAt:int = 0;

      public static var picked:Object = {};
      public static var filters:Object = {"legend":"","map":"","opponent":"","mode":"","tag":""};

      private var entries:Array = null;
      private var files:Array = null;
      private var nextFile:int = 0;
      private var keepCount:int = 0;
      private var loadedKeys:Object = {};
      private var selectFound:Boolean = true;
      private var shown:Array = [];
      private var loadedTab:int = -1;
      private var loading:Boolean = false;
      private var page:int = 0;
      private var select:String = null;
      private var favNames:Object = {};
      private var thumbsMissing:Boolean = false;
      private var thumbRebuilds:int = 0;
      private var thumbFrames:int = 0;
      private var detail:Sprite;
      private var detailFor:Object = null;
      private var thumbTries:int = 0;
      private var message:String = "";
      private var pendingFocus:int = -1;

      public function ReplaysWindow(core:GameCore)
      {
         super(core);
      }

      public static function get enabled() : Boolean
      {
         return !ModSettings.flag(KEY,false);
      }

      public static function set enabled(on:Boolean) : void
      {
         ModSettings.setFlag(KEY,!on);
      }

      public static function label() : String
      {
         return enabled ? "Bifrost's" : "The game's";
      }

      public static function get shownWindow() : ReplaysWindow
      {
         return window != null && window.isActive ? window : null;
      }

      public static function open(name:String = null, over:Object = null) : ReplaysWindow
      {
         if(window == null || ScreenManager.allScreens.indexOf(window) < 0)
         {
            window = new ReplaysWindow(ScreenManager.owner);
            ScreenManager.registerScreen(window);
         }
         if(over != null)
         {
            window.registrationIndex = over.registrationIndex;
         }
         else if(ScreenManager.var_14744 != null)
         {
            window.registrationIndex = ScreenManager.var_14744.registrationIndex;
         }
         tabScreen = over;
         if(name != null)
         {
            window.select = name;
            window.tab = 0;
            window.entries = null;
         }
         if(!window.isActive)
         {
            window.Display();
         }
         else if(name != null)
         {
            window.reload();
         }
         return window;
      }

      public static function pressed(screen:Object, input:int) : Boolean
      {
         if(!enabled || class_687.var_11971 != 2 || FORWARD.indexOf(input) < 0 || screen == null || !screen.isActive ||
            window != null && window.isActive)
         {
            return false;
         }
         over(screen,true);
         return true;
      }

      public static function over(screen:Object, forwarded:Boolean = false) : void
      {
         if(!enabled)
         {
            if(!GameMenus.offered(screen))
            {
               GameMenus.offer(screen,GameMenus.REPLAYS,function(s:Object):void
               {
                  over(s);
               });
            }
            return;
         }
         if(window != null && window.isActive || screen == null || !screen.isActive ||
            !forwarded && screen === leftScreen && getTimer() - leftAt < 2000 ||
            !forwarded && class_687.var_11971 == 2)
         {
            return;
         }
         Platform.log("replays: Bifrost's page over the game's Replays tab");
         open(null,screen);
      }

      public static function afterMatch() : void
      {
         if(lastSaved != null && getTimer() - lastSavedAt < 600000)
         {
            openName = lastSaved;
            settledOn = null;
         }
         else
         {
            wantAfterMatch = true;
         }
         DummyDrift.show("The replay opens in Replays once the match closes.",3000);
         tick();
      }

      public static function matchStarted() : void
      {
         lastSaved = null;
         wantAfterMatch = false;
      }

      public static function matchSaved(name:String) : void
      {
         lastSaved = name;
         lastSavedAt = getTimer();
         if(wantAfterMatch)
         {
            wantAfterMatch = false;
            openName = name;
            settledOn = null;
            tick();
         }
      }

      private static function tick() : void
      {
         if(!ticking)
         {
            ticking = true;
            Hooks.frameStarting.add(afterMatchFrame);
         }
      }

      private static function afterMatchFrame() : void
      {
         if(openName == null)
         {
            if(!wantAfterMatch)
            {
               ticking = false;
               Hooks.frameStarting.remove(afterMatchFrame);
            }
            return;
         }
         var settled:Boolean = false;
         try
         {
            var board:Object = ScreenManager.var_6219;
            settled = !Platform.matchRunning && !PostMatchStats.replaying && !(board != null && board.isActive) &&
               ScreenBase.focusedScreen != null;
         }
         catch(e:Error)
         {
         }
         if(!settled || ScreenBase.focusedScreen !== settledOn)
         {
            settledOn = settled ? ScreenBase.focusedScreen : null;
            settledAt = getTimer();
            return;
         }
         if(getTimer() - settledAt < SETTLE_MS)
         {
            return;
         }
         var name:String = openName;
         openName = null;
         Platform.log("replays: opening the page at the last match's replay " + name);
         open(name);
      }

      override protected function get title() : String
      {
         return "REPLAYS";
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

      override protected function get pageAction() : Array
      {
         return ["GAME'S LIST",function():void
         {
            useGameList();
         }];
      }

      override public function get trailName() : String
      {
         return "REPLAYS";
      }

      private function useGameList() : void
      {
         enabled = false;
         var screen:Object = tabScreen;
         Hide();
         if(screen != null && screen.isActive)
         {
            ScreenBase.setFocus(screen as ScreenBase);
            GameMenus.offer(screen,GameMenus.REPLAYS,function(s:Object):void
            {
               over(s);
            });
         }
         else
         {
            DummyDrift.show("The game's own Replays list is back (Social > Replays).",3000);
         }
      }

      override protected function back() : void
      {
         var screen:Object = tabScreen;
         tabScreen = null;
         leftScreen = screen;
         leftAt = getTimer();
         Hide();
         if(screen != null && screen.isActive)
         {
            try
            {
               ScreenBase.setFocus(screen as ScreenBase);
               screen.HandleInput(18);
            }
            catch(e:Error)
            {
               Platform.log("replays: the game's tab didn't go back: " + e.message);
            }
         }
      }

      private function folderOf(t:int) : File
      {
         var main:File = class_51.method_3608();
         return t == 0 ? main : t == 1 ? ReplayKeep.favorites() : main.resolvePath(ReplayKeep.OLDER);
      }

      private function reload() : void
      {
         keepCount = loadedTab == tab ? nextFile : 0;
         entries = null;
         files = null;
         loadedTab = -1;
         build();
      }

      private function load() : void
      {
         if(loadedTab != tab)
         {
            entries = null;
         }
         if(loading || loadedTab == tab && entries != null)
         {
            return;
         }
         loading = true;
         var want:int = tab;
         var dir:File = folderOf(want);
         favNames = {};
         try
         {
            var best:File = folderOf(1);
            if(best.exists)
            {
               for each(var b:File in best.getDirectoryListing())
               {
                  favNames[b.name] = true;
               }
            }
         }
         catch(e:Error)
         {
         }
         files = ReplayIndex.newestFirst(dir);
         nextFile = 0;
         loadedKeys = {};
         entries = null;
         if(files.length == 0)
         {
            loading = false;
            entries = [];
            loadedTab = want;
            return;
         }
         readMore(Math.max((1 + ReplayIndex.PAGES_AHEAD) * PER_PAGE,keepCount));
         keepCount = 0;
      }

      private function readMore(count:int) : void
      {
         var want:int = tab;
         var from:Array = files;
         var batch:Array = files.slice(nextFile,nextFile + count);
         nextFile += batch.length;
         loading = true;
         ReplayIndex.scanThen(folderOf(want),function(list:Array):void
         {
            loading = false;
            if(tab != want || files !== from)
            {
               if(isActive)
               {
                  build();
               }
               return;
            }
            var first:Boolean = entries == null;
            var all:Array = first ? [] : entries;
            for each(var e:Object in list)
            {
               if(!loadedKeys[e.key])
               {
                  loadedKeys[e.key] = true;
                  all.push(e);
               }
            }
            all.sortOn("time",Array.DESCENDING | Array.NUMERIC);
            entries = all;
            loadedTab = want;
            if(first)
            {
               page = 0;
               firstRows = true;
               thumbRebuilds = 0;
            }
            build();
         },false,batch);
      }

      private function moreToRead() : Boolean
      {
         return files != null && nextFile < files.length;
      }

      private function readAhead() : void
      {
         if(loading || entries == null || loadedTab != tab || !moreToRead())
         {
            return;
         }
         if(!selectFound || shown.length < (page + 1 + ReplayIndex.PAGES_AHEAD) * PER_PAGE)
         {
            readMore(PER_PAGE);
         }
      }

      private function matches(e:Object) : Boolean
      {
         var n:int = e.players ? e.players.length : 0;
         if((isPicked("WINS") || isPicked("LOSSES")) && !(isPicked("WINS") && e.result == "win" || isPicked("LOSSES") && e.result == "loss"))
         {
            return false;
         }
         if((isPicked("1V1") || isPicked("2V2")) && !(isPicked("1V1") && !e.teams && n == 2 || isPicked("2V2") && e.teams && n == 4))
         {
            return false;
         }
         if(isPicked("RANKED") && !e.ranked)
         {
            return false;
         }
         if(isPicked("NOTED") && ReplayStore.note(e.file) == "" && ReplayStore.tags(e.file).length == 0)
         {
            return false;
         }
         if(filters.mode && String(e.mode || e.playlist) != filters.mode)
         {
            return false;
         }
         if(filters.tag && ReplayStore.tags(e.file).indexOf(filters.tag) < 0)
         {
            return false;
         }
         return true;
      }

      private function applyFilters() : void
      {
         shown = [];
         if(entries == null)
         {
            return;
         }
         for each(var e:Object in ReplayIndex.filter(entries,filters.legend,filters.map,filters.opponent,null))
         {
            if(matches(e))
            {
               shown.push(e);
            }
         }
         selectFound = select == null;
         if(select != null)
         {
            for(var i:int = 0; i < shown.length; i++)
            {
               if(shown[i].file == select)
               {
                  page = int(i / PER_PAGE);
                  selectFound = true;
                  break;
               }
            }
         }
         page = Math.max(0,Math.min(page,pages() - 1));
      }

      private static var chipAt:int = 0;

      private static function isPicked(name:String) : Boolean
      {
         return !!Object(picked)[name];
      }

      private static function setPicked(name:String, on:Boolean) : void
      {
         var o:Object = picked;
         o[name] = on;
      }

      private static function anyPicked() : Boolean
      {
         for each(var on:* in picked)
         {
            if(on)
            {
               return true;
            }
         }
         return false;
      }

      private function toggleChip(n:int) : void
      {
         if(n <= 0)
         {
            picked = {};
         }
         else
         {
            var name:String = QUICK[n];
            setPicked(name,!isPicked(name));
         }
         chipAt = n;
         page = 0;
         build();
      }

      private function drawChips(parent:Sprite, focusedNow:Boolean) : void
      {
         parent.removeChildren();
         var x:Number = 0;
         for(var i:int = 0; i < QUICK.length; i++)
         {
            var chip:Sprite = new Sprite();
            chip.x = x;
            chip.buttonMode = true;
            parent.addChild(chip);
            var on:Boolean = i == 0 ? !anyPicked() : isPicked(QUICK[i]);
            var label:Object = UiKit.text(chip,QUICK[i],12,3,13,on ? UiKit.NAVY_TEXT : UiKit.LIGHT,UiKit.XBOLD);
            var back:Object = UiKit.rect(chip,0,0,label.width + 24,24,on ? UiKit.TEAL : UiKit.LINE,24);
            chip.setChildIndex(back as Shape,0);
            if(focusedNow && i == chipAt)
            {
               UiKit.rect(chip,6,27,label.width + 12,3,UiKit.WHITE);
            }
            chip.addEventListener(MouseEvent.CLICK,chipClick(i));
            x += label.width + 30;
         }
      }

      private function chipClick(i:int) : Function
      {
         return function(e:MouseEvent):void
         {
            toggleChip(i);
         };
      }

      private function pages() : int
      {
         return Math.max(1,Math.ceil(shown.length / PER_PAGE));
      }

      private function filterText() : String
      {
         var out:Array = [];
         for each(var k:String in ["legend","map","opponent","mode","tag"])
         {
            if(filterOf(k) != "")
            {
               out.push(k.toUpperCase() + " " + filterOf(k));
            }
         }
         return out.join("  ·  ");
      }

      private function get LEFT_W() : Number
      {
         return Math.round(area.width * 0.5);
      }

      private function get RIGHT_X() : Number
      {
         return area.x + LEFT_W + 16;
      }

      private function get RIGHT_W() : Number
      {
         return area.width - LEFT_W - 16;
      }

      override protected function buildTab(i:int) : void
      {
         load();
         applyFilters();
         readAhead();
         var left:Sprite = panel(area.x,area.y,LEFT_W,area.height);
         var right:Sprite = panel(RIGHT_X,area.y,RIGHT_W,area.height);
         detail = new Sprite();
         right.addChild(detail);
         detailFor = null;
         var chipRow:Sprite = new Sprite();
         chipRow.x = 14;
         chipRow.y = 12;
         left.addChild(chipRow);
         var chips:Sprite = new Sprite();
         chipRow.addChild(chips);
         var paintChips:Function = function(focusedNow:Boolean):void
         {
            drawChips(chips,focusedNow);
         };
         paintChips(false);
         items.push({"w":"chips","sprite":chipRow,"parent":left,"width":LEFT_W - 28,"height":30,"focusBox":[-8,-4,LEFT_W - 12,34],
            "change":function(dir:int):void
            {
               chipAt = (chipAt + dir + QUICK.length) % QUICK.length;
            },"use":function():void
            {
               toggleChip(chipAt);
            },"paint":paintChips});
         var ft:String = filterText();
         if(ft != "")
         {
            UiKit.fit(UiKit.text(left,"FILTERS  " + ft.toUpperCase(),14,46,12,UiKit.GOLD,UiKit.XBOLD),LEFT_W - 28);
         }
         else
         {
            describeText(UiKit.text(left,"",14,44,12,UiKit.GREY,UiKit.XBOLD),"NO FILTERS  ·  {Alt} FILTERS");
         }
         var list:Sprite = scroller(left,0,70,LEFT_W,area.height - 74);
         if(entries == null)
         {
            UiKit.text(list,"Reading replays...",14,8,14,UiKit.LIGHT,UiKit.MEDIUM);
            drawDetail(null);
            return;
         }
         if(shown.length == 0)
         {
            UiKit.text(list,entries.length == 0 ? (tab == 0 ? "No replays yet. The game saves every match you play here." :
               tab == 1 ? "No favorites yet. Add a replay with its menu: ADD TO FAVORITES." :
               "Nothing in Older. With Options > KEEP RECENT set, replays past the newest ones move here.") :
               moreToRead() ? "Reading more replays..." : "No replay matches these filters.",14,8,13,UiKit.LIGHT,UiKit.MEDIUM,LEFT_W - 40);
         }
         var y:Number = 0;
         if(page > 0)
         {
            y = pageRow(list,y,-1);
         }
         var first:int = page * PER_PAGE;
         var focusAt:int = -1;
         for(var k:int = first; k < shown.length && k < first + PER_PAGE; k++)
         {
            if(select != null && shown[k].file == select)
            {
               focusAt = items.length;
            }
            row(list,y,shown[k]);
            y += ROW_H + 4;
         }
         if(page < pages() - 1)
         {
            pageRow(list,y,1);
         }
         if(focusAt >= 0)
         {
            pendingFocus = focusAt;
            select = null;
         }
         else if(firstRows && items.length > 1)
         {
            pendingFocus = page > 0 ? 2 : 1;
         }
         firstRows = false;
      }

      private var firstRows:Boolean = true;

      override public function Display() : void
      {
         if(!isActive)
         {
            entries = null;
            files = null;
            loadedTab = -1;
            loading = false;
         }
         super.Display();
      }

      override protected function build() : void
      {
         super.build();
         if(pendingFocus >= 0 && pendingFocus < items.length)
         {
            focus = pendingFocus;
            paintFocus();
         }
         pendingFocus = -1;
      }

      override protected function built() : void
      {
         var it:Object = focus < items.length ? items[focus] : null;
         if(it == null || it.entry == null)
         {
            drawDetail(null);
         }
      }

      private function pageRow(list:Sprite, y:Number, dir:int) : Number
      {
         var r:Sprite = new Sprite();
         r.y = y;
         list.addChild(r);
         var w:Number = LEFT_W - 20;
         UiKit.rect(r,10,0,w,32,UiKit.LINE,4);
         UiKit.text(r,dir < 0 ? "PREVIOUS " + PER_PAGE : "NEXT " + Math.min(PER_PAGE,shown.length - (page + 1) * PER_PAGE),
            w / 2 + 10,7,13,UiKit.LIGHT,UiKit.XBOLD,0,true);
         var go:Function = function():void
         {
            turnPage(dir);
         };
         r.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            go();
         });
         items.push({"w":"page " + dir,"sprite":r,"parent":list,"width":w,"height":32,"focusBox":[10,0,w,32],"use":go});
         return y + 36;
      }

      private function turnPage(dir:int) : void
      {
         var next:int = Math.max(0,Math.min(pages() - 1,page + dir));
         if(next == page)
         {
            return;
         }
         page = next;
         pendingFocus = page > 0 ? 2 : 1;
         build();
      }

      override protected function pageFocus(dir:int) : void
      {
         turnPage(dir);
      }

      private function row(list:Sprite, y:Number, e:Object) : void
      {
         var r:Sprite = new Sprite();
         r.y = y;
         list.addChild(r);
         var w:Number = LEFT_W - 20;
         UiKit.rect(r,10,0,w,ROW_H,UiKit.BODY,4);
         var thumb:Bitmap = LeaderboardWindow.mapThumb({"map":mapKey(e)},THUMB_W,int(ROW_H));
         if(thumb != null)
         {
            thumb.x = 10;
            r.addChild(thumb);
         }
         else
         {
            UiKit.rect(r,10,0,THUMB_W,ROW_H,UiKit.LINE,4);
            thumbsMissing = true;
         }
         var tx:Number = 10 + THUMB_W + 12;
         var right:Number = w + 4;
         var when:Object = UiKit.text(r,ago(Number(e.time)),0,6,12,UiKit.LIGHT,UiKit.MEDIUM);
         when.x = right - when.width;
         var marks:Array = [];
         if(favNames[e.file] && tab != 1)
         {
            marks.push("FAV");
         }
         if(ReplayStore.hasStats(e.file))
         {
            marks.push("STATS");
         }
         if(ReplayStore.note(e.file) != "" || ReplayStore.tags(e.file).length > 0)
         {
            marks.push("NOTE");
         }
         var topRight:Number = when.x;
         if(marks.length > 0)
         {
            var mt:Object = UiKit.text(r,marks.join(" · "),0,7,11,UiKit.TEAL,UiKit.XBOLD);
            mt.x = when.x - 12 - mt.width;
            topRight = mt.x;
         }
         var icons:Number = legendIcons(r,e,right,31);
         var res:String = !e.ok ? (e.why == "version" ? "OLD VERSION" : e.why == "mode" ? "MODE NOT LOADED" : "UNREADABLE") :
            e.result == "win" ? "WIN" : e.result == "loss" ? "LOSS" : "";
         var tag:Number = 0;
         if(res != "")
         {
            var rt:Object = UiKit.text(r,res,tx,6,13,!e.ok ? UiKit.GREY : e.result == "win" ? UiKit.GOLD : UiKit.RED,UiKit.XBOLD);
            tag = rt.width + 10;
         }
         UiKit.fit(UiKit.text(r,titleOf(e),tx + tag,5,15,e.ok ? UiKit.WHITE : UiKit.GREY,UiKit.BOLD),topRight - tx - tag - 12);
         var mode:String = modeText(e);
         var mx:Number = tx;
         if(mode != "")
         {
            var mo:Object = UiKit.fit(UiKit.text(r,mode.toUpperCase(),tx,31,12,UiKit.TEAL,UiKit.XBOLD),Math.max(60,
               (right - icons - tx) * 0.5));
            mx = tx + mo.width + 10;
         }
         UiKit.fit(UiKit.text(r,joined(mapOf(e),clock(Number(e.length))),mx,31,12,UiKit.GREY,UiKit.MEDIUM),
            Math.max(20,right - icons - mx - 12));
         var it:Object = {"w":"replay " + e.key,"sprite":r,"parent":list,"width":w,"height":ROW_H,
            "focusBox":[10,0,w,ROW_H],"entry":e,"menuTitle":String(e.file).replace(/\.replay$/,"").toUpperCase(),
            "use":function():void
            {
               watch(e,-1);
            },"menu":function():Array
            {
               return menuOf(e);
            }};
         items.push(it);
      }

      private static function joined(... parts) : String
      {
         var out:Array = [];
         for each(var p:String in parts)
         {
            if(p != null && p != "")
            {
               out.push(p);
            }
         }
         return out.join("  ·  ");
      }

      private static function filterOf(key:String) : String
      {
         var v:* = Object(filters)[key];
         return v ? String(v) : "";
      }

      private static function setFilter(key:String, value:String) : void
      {
         var f:Object = filters;
         f[key] = value;
      }

      private function legendIcons(r:Sprite, e:Object, right:Number, y:Number) : Number
      {
         var order:Array = [];
         if(e.me >= 0 && e.players != null && e.players[e.me] != null)
         {
            order.push(e.players[e.me]);
         }
         for(var i:int = 0; e.players != null && i < e.players.length; i++)
         {
            if(i != e.me)
            {
               order.push(e.players[i]);
            }
         }
         var n:int = Math.min(order.length,ICONS);
         var x:Number = right - n * (ICON + 3) + 3;
         for(var k:int = 0; k < n; k++)
         {
            var p:Object = order[k];
            UiKit.rect(r,x,y,ICON,ICON,UiKit.LINE,4);
            var b:Bitmap = p != null && p.ids != null && p.ids.length > 0 ? LeaderboardWindow.legendIcon(int(p.ids[0]),ICON) : null;
            if(b != null)
            {
               b.x = x;
               b.y = y;
               b.width = b.height = ICON;
               r.addChild(b);
            }
            x += ICON + 3;
         }
         return n > 0 ? n * (ICON + 3) : 0;
      }

      private static function titleOf(e:Object) : String
      {
         return String(e.file).replace(/\.replay$/,"");
      }

      private static function mapKey(e:Object) : String
      {
         if(e.map)
         {
            return String(e.map);
         }
         var m:Array = /^\[[^\]]*\] (.*?)( \(\d+\))?( \((shared|code) [^)]*\))?\.replay$/.exec(String(e.file));
         return m != null ? levelNamed(String(m[1])) : "";
      }

      private static var levelNames:Object = {};

      private static function levelNamed(name:String) : String
      {
         var known:* = Object(levelNames)[name];
         if(known != null)
         {
            return String(known);
         }
         var found:String = name;
         try
         {
            for each(var level:Object in LevelType.var_3683)
            {
               if(level == null || !level.mDisplayName)
               {
                  continue;
               }
               var shown:String = String(level.mDisplayName).replace(/[^A-Za-z0-9]/g,"");
               if(shown == name || name.length >= 12 && shown.indexOf(name) == 0)
               {
                  found = String(level.var_5173);
                  break;
               }
            }
         }
         catch(err:Error)
         {
         }
         var names:Object = levelNames;
         names[name] = found;
         return found;
      }

      public static function modeText(e:Object) : String
      {
         var rule:String = "";
         var scoring:String = String(e.scoring || "");
         if(scoring.indexOf("Timed") >= 0 && uint(e.duration) > 0)
         {
            var secs:uint = uint(e.duration);
            rule = secs % 60 == 0 ? String(secs / 60) + " MIN" : clock(secs * 1000);
         }
         else if(scoring.indexOf("Timed") < 0 && uint(e.lives) > 0)
         {
            var lives:uint = uint(e.lives);
            rule = String(lives) + (lives == 1 ? " LIFE" : " LIVES");
         }
         var playlist:String = String(e.playlist || "");
         var ranked:String = e.ranked && playlist.toUpperCase().indexOf("RANKED") < 0 ? "RANKED" : "";
         return joined(ranked,playlist != String(e.mode || "") ? playlist : "",String(e.mode || ""),rule);
      }

      private static function mapOf(e:Object) : String
      {
         return e.mapName ? String(e.mapName) : e.map ? String(e.map).replace(/([a-z])([A-Z])/g,"$1 $2") : "";
      }

      public static function clock(ms:Number) : String
      {
         if(!(ms > 0))
         {
            return "";
         }
         var s:int = Math.round(ms / 1000);
         return int(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + s % 60;
      }

      private static function ago(t:Number) : String
      {
         var s:Number = (new Date().time - t) / 1000;
         if(isNaN(s) || s < 3600)
         {
            return Math.max(1,Math.floor((isNaN(s) ? 0 : s) / 60)) + " MIN AGO";
         }
         if(s < 86400)
         {
            return Math.floor(s / 3600) + " H AGO";
         }
         var d:int = Math.floor(s / 86400);
         if(d < 30)
         {
            return d + (d == 1 ? " DAY AGO" : " DAYS AGO");
         }
         var at:Date = new Date(t);
         return at.fullYear + "-" + (at.month < 9 ? "0" : "") + (at.month + 1) + "-" + (at.date < 10 ? "0" : "") + at.date;
      }

      override protected function focused(it:Object) : void
      {
         if(it != null && it.paint != null)
         {
            it.paint(true);
         }
         for each(var other:Object in items)
         {
            if(other !== it && other.paint != null)
            {
               other.paint(false);
            }
         }
         if(it != null && it.entry != null && it.entry !== detailFor)
         {
            drawDetail(it.entry);
         }
      }

      override protected function everyFrame() : void
      {
         if(thumbsMissing && thumbRebuilds < 10 && ++thumbFrames % 60 == 0)
         {
            thumbRebuilds++;
            thumbsMissing = false;
            build();
         }
         if(detailFor != null && thumbTries > 0 && --thumbTries % 30 == 0)
         {
            var e:Object = detailFor;
            detailFor = null;
            drawDetail(e,false);
         }
      }

      private function fileOf(e:Object) : File
      {
         return e.path ? new File(String(e.path)) : folderOf(tab).resolvePath(String(e.file));
      }

      private function drawDetail(e:Object, fresh:Boolean = true) : void
      {
         if(detail == null)
         {
            return;
         }
         detail.removeChildren();
         detailFor = e;
         var w:Number = RIGHT_W;
         if(e == null)
         {
            UiKit.text(detail,message != "" ? message : "Pick a replay on the left.",20,20,14,UiKit.GREY,UiKit.MEDIUM,w - 40);
            return;
         }
         var thumbH:Number = Math.min(150,Math.round(w * 0.32));
         var thumb:Bitmap = mapKey(e) ? LeaderboardWindow.mapThumb({"map":mapKey(e)},int(w),int(thumbH)) : null;
         if(thumb != null)
         {
            detail.addChild(thumb);
            thumbTries = 0;
         }
         else
         {
            UiKit.rect(detail,0,0,w,thumbH,UiKit.LINE);
            if(fresh)
            {
               thumbTries = 300;
            }
         }
         var shade:Sprite = new Sprite();
         shade.graphics.beginFill(0,0.55);
         shade.graphics.drawRect(0,thumbH - 58,w,58);
         shade.graphics.endFill();
         detail.addChild(shade);
         UiKit.fit(UiKit.text(detail,titleOf(e),18,thumbH - 54,24,UiKit.WHITE,UiKit.XBOLD),w - 36);
         UiKit.fit(UiKit.text(detail,joined(modeText(e),mapOf(e),clock(Number(e.length)),dateText(Number(e.time))),
            18,thumbH - 22,13,UiKit.LIGHT,UiKit.MEDIUM),w - 36);
         var y:Number = thumbH + 12;
         if(!e.ok)
         {
            UiKit.text(detail,e.why == "version" ? "This replay is from another version of the game (" + versionOf(e.file) +
               "), so it can't be played here." : e.why == "mode" ? "Its game mode isn't loaded now (a mod's mode). Switch " +
               "that mod on in Mods to watch it." : "This file couldn't be read.",18,y,13,UiKit.LIGHT,UiKit.MEDIUM,w - 36);
            y += 44;
         }
         for(var i:int = 0; e.players != null && i < e.players.length; i++)
         {
            y = playerLine(detail,e,i,y,w);
         }
         if(e.ok && e.kos != null && e.kos.length > 0)
         {
            y = timeline(detail,e,y + 8,w);
         }
         var note:String = ReplayStore.note(e.file);
         var tags:Array = ReplayStore.tags(e.file);
         if(note != "" || tags.length > 0)
         {
            var nt:Object = UiKit.text(detail,(tags.length > 0 ? tags.join(", ").toUpperCase() + (note != "" ? "  ·  " : "") : "") +
               note,18,y + 6,13,UiKit.GOLD,UiKit.MEDIUM,w - 36);
            y += nt.height + 10;
         }
         var buttons:Array = [["WATCH",function():void
         {
            watch(e,-1);
         }]];
         if(e.ok)
         {
            buttons.push([ReplayStore.hasStats(e.file) ? "MATCH STATS" : "GET STATS",function():void
            {
               statsOf(e);
            }]);
            buttons.push(["EXPORT",function():void
            {
               exportVideo(e);
            }]);
         }
         buttons.push(["TAGS",function():void
         {
            pickTag(e);
         }]);
         buttons.push(["MORE",function():void
         {
            var it:Object = items[focus];
            if(it != null && it.entry === e)
            {
               openContext(it);
            }
         }]);
         var bw:Number = Math.floor((w - 36 - (buttons.length - 1) * 8) / buttons.length);
         var by:Number = area.height - 46;
         for(var b:int = 0; b < buttons.length; b++)
         {
            button(detail,buttons[b][0],18 + b * (bw + 8),by,bw,buttons[b][1],30,13);
         }
      }

      private static function versionOf(file:String) : String
      {
         var m:Array = /^\[([^\]]+)\]/.exec(file);
         return m != null ? m[1] : "unknown";
      }

      private static function dateText(t:Number) : String
      {
         if(isNaN(t) || t <= 0)
         {
            return "";
         }
         var d:Date = new Date(t);
         return d.fullYear + "-" + (d.month < 9 ? "0" : "") + (d.month + 1) + "-" + (d.date < 10 ? "0" : "") + d.date + " " +
            (d.hours < 10 ? "0" : "") + d.hours + ":" + (d.minutes < 10 ? "0" : "") + d.minutes;
      }

      private function playerLine(s:Sprite, e:Object, i:int, y:Number, w:Number) : Number
      {
         var p:Object = e.players[i];
         var colour:uint = PostMatchStats.COLORS[i % PostMatchStats.COLORS.length];
         var line:Sprite = new Sprite();
         line.y = y;
         s.addChild(line);
         UiKit.rect(line,18,0,4,46,colour);
         var av:Bitmap = uint(p.avatar) != 0 ? LeaderboardWindow.avatar(int(p.avatar),40) : null;
         if(av != null)
         {
            av.x = 28;
            av.y = 3;
            av.width = av.height = 40;
            line.addChild(av);
         }
         var b:Bitmap = p.ids != null && p.ids.length > 0 ? LeaderboardWindow.legendIcon(int(p.ids[0]),40) : null;
         if(b != null)
         {
            b.x = 72;
            b.y = 3;
            b.width = b.height = 40;
            line.addChild(b);
         }
         var tx:Number = 120;
         var place:uint = uint(p.place);
         var named:Object = UiKit.fit(UiKit.text(line,String(p.name || "?") + (i == e.me ? "  (YOU)" : ""),tx,0,15,
            i == e.me ? UiKit.TEAL : UiKit.WHITE,UiKit.BOLD),w - 360);
         var extra:Array = [];
         if(uint(p.pid) != 0)
         {
            extra.push("ID " + uint(p.pid));
         }
         if(extra.length > 0)
         {
            UiKit.text(line,extra.join("  ·  "),tx + named.width + 10,3,11,UiKit.GREY,UiKit.MEDIUM);
         }
         UiKit.fit(UiKit.text(line,(p.legends != null ? p.legends.join(" / ") : "") + (e.teams ? "  ·  TEAM " + p.team : ""),tx,17,
            12,UiKit.GREY,UiKit.MEDIUM),w - tx - 80);
         var inputs:String = inputsText(p.inputs,Number(e.length));
         if(inputs != "")
         {
            UiKit.fit(UiKit.text(line,inputs,tx,31,11,UiKit.LIGHT,UiKit.MEDIUM),w - tx - 80);
         }
         if(place > 0)
         {
            var pt:Object = UiKit.text(line,place == 1 ? "1ST" : place == 2 ? "2ND" : place == 3 ? "3RD" : place + "TH",0,12,15,
               UiKit.placeColour(place,UiKit.LIGHT),UiKit.XBOLD);
            pt.x = w - 18 - pt.width;
         }
         return y + 52;
      }

      public static function inputsText(n:Object, length:Number) : String
      {
         if(n == null)
         {
            return "";
         }
         var actions:int = int(n.jump) + int(n.light) + int(n.heavy) + int(n.dodge) + int(n["throw"]);
         if(actions == 0)
         {
            return "";
         }
         var minutes:Number = Math.max(1 / 60,length / 60000);
         return "APM " + Math.round(actions / minutes) + "  ·  LIGHT " + int(n.light) + "  ·  HEAVY " + int(n.heavy) +
            "  ·  DODGE " + int(n.dodge) + "  ·  JUMP " + int(n.jump) + "  ·  THROW " + int(n["throw"]);
      }

      private function timeline(s:Sprite, e:Object, y:Number, w:Number) : Number
      {
         UiKit.text(s,"KOS  ·  CLICK ONE TO WATCH FROM IT",18,y,11,UiKit.GREY,UiKit.XBOLD);
         var bar:Sprite = new Sprite();
         bar.x = 18;
         bar.y = y + 20;
         s.addChild(bar);
         var bw:Number = w - 36;
         UiKit.rect(bar,0,8,bw,4,UiKit.LINE,4);
         var total:Number = Math.max(1,Number(e.length) + 2500);
         for each(var ko:Array in e.kos)
         {
            var who:int = int(ko[0]);
            var t:Number = Number(ko[1]);
            var dot:Sprite = new Sprite();
            dot.buttonMode = true;
            dot.x = Math.round(Math.min(1,t / total) * bw);
            dot.y = 10;
            dot.graphics.beginFill(who >= 0 ? PostMatchStats.COLORS[who % PostMatchStats.COLORS.length] : UiKit.LIGHT);
            dot.graphics.drawCircle(0,0,7);
            dot.graphics.endFill();
            dot.graphics.lineStyle(2,UiKit.BODY);
            dot.graphics.drawCircle(0,0,7);
            dot.addEventListener(MouseEvent.CLICK,koClick(e,t));
            bar.addChild(dot);
         }
         UiKit.text(bar,"0:00",0,22,11,UiKit.GREY,UiKit.MEDIUM);
         var end:Object = UiKit.text(bar,clock(e.length),0,22,11,UiKit.GREY,UiKit.MEDIUM);
         end.x = bw - end.width;
         return y + 62;
      }

      private function koClick(e:Object, t:Number) : Function
      {
         return function(ev:MouseEvent):void
         {
            ev.stopPropagation();
            watch(e,t);
         };
      }

      private function menuOf(e:Object) : Array
      {
         var out:Array = [["WATCH",function():void
         {
            watch(e,-1);
         }]];
         if(e.ok && e.kos != null && e.kos.length > 0)
         {
            out.push(["WATCH FROM A KO  >",function():void
            {
               pickKo(e);
            }]);
         }
         if(e.ok)
         {
            out.push([ReplayStore.hasStats(e.file) ? "MATCH STATS" : "GET MATCH STATS",function():void
            {
               statsOf(e);
            }]);
            out.push(["EXPORT VIDEO",function():void
            {
               exportVideo(e);
            }]);
         }
         var f:File = fileOf(e);
         if(tab == 1)
         {
            out.push(["REMOVE FROM FAVORITES",function():void
            {
               if(ReplayKeep.unstar(f))
               {
                  say("Taken out of Favorites.");
                  reload();
               }
            }]);
         }
         else if(!favNames[e.file])
         {
            out.push(["ADD TO FAVORITES",function():void
            {
               if(ReplayKeep.star(f,"starred"))
               {
                  favNames[e.file] = true;
                  say("Added to Favorites.");
                  build();
               }
            }]);
         }
         else
         {
            out.push(["REMOVE FROM FAVORITES",function():void
            {
               if(ReplayKeep.unstar(f))
               {
                  delete favNames[e.file];
                  say("Taken out of Favorites.");
                  build();
               }
            }]);
         }
         out.push([ReplayStore.note(e.file) != "" ? "EDIT NOTE" : "ADD A NOTE",function():void
         {
            typeText("NOTE",ReplayStore.note(e.file),120,function(v:String):void
            {
               ReplayStore.setNote(e.file,v);
               build();
            },true);
         }]);
         out.push(["TAGS  >",function():void
         {
            pickTag(e);
         }]);
         if(ReplayIndex.sharing != null && e.ok)
         {
            out.push(["SHARE CODE",function():void
            {
               share(e);
            }]);
         }
         out.push(["DELETE",function():void
         {
            confirmDelete(e);
         }]);
         return out;
      }

      private function say(text:String) : void
      {
         message = text;
         if(status != null)
         {
            status.text = text;
         }
      }

      override protected function statusText() : String
      {
         if(message != "")
         {
            var m:String = message;
            message = "";
            return m;
         }
         if(entries == null)
         {
            return ReplayIndex.reading ? "Reading replays..." : "";
         }
         var wins:int = 0;
         var losses:int = 0;
         for each(var e:Object in shown)
         {
            wins += e.result == "win" ? 1 : 0;
            losses += e.result == "loss" ? 1 : 0;
         }
         return shown.length + (shown.length == 1 ? " replay" : " replays") + (shown.length != entries.length ? " of " +
            entries.length : "") + (wins + losses > 0 ? "  ·  " + wins + "-" + losses + " (" + Math.round(wins * 100 /
            (wins + losses)) + "% wins)" : "") + (pages() > 1 ? "  ·  page " + (page + 1) + " of " + pages() : "") +
            (moreToRead() ? "  ·  newest " + nextFile + " of " + files.length + " read" : "");
      }

      override protected function hintText() : String
      {
         var n:Object = Prompts.KEYS;
         return n.tabs + " FOLDERS     " + n.page + " PAGE     " + n.select + " WATCH     " + n.option + " MENU     {Alt} FILTERS     " +
            n.back + " BACK";
      }

      override public function HandleInput(input:int) : Boolean
      {
         if(input == 20 && method_5588() && !covered() && !pickerOpen && !keyboardOpen)
         {
            openFilters();
            return true;
         }
         return super.HandleInput(input);
      }

      private function watch(e:Object, at:Number) : void
      {
         if(!e.ok)
         {
            say(e.why == "version" ? "This replay is from another version of the game." : "This replay can't be played.");
            return;
         }
         if(ReplayExport.active || ReplayPlayer.busy)
         {
            return;
         }
         select = e.file;
         ReplayPlayer.watch(fileOf(e),at);
      }

      private function pickKo(e:Object) : void
      {
         var names:Array = [];
         for each(var ko:Array in e.kos)
         {
            var p:Object = int(ko[0]) >= 0 && e.players != null ? e.players[int(ko[0])] : null;
            names.push(clock(Number(ko[1])) + "  " + (p != null ? String(p.name).toUpperCase() + " LOSES A STOCK" : "KO"));
         }
         pickFrom("WATCH FROM A KO",names,0,function(n:int):void
         {
            if(n >= 0 && n < e.kos.length)
            {
               watch(e,Number(e.kos[n][1]));
            }
         });
      }

      private function statsOf(e:Object) : void
      {
         var saved:Object = ReplayStore.stats(e.file);
         if(saved != null)
         {
            PostMatchStats.openWith(saved);
            return;
         }
         if(!e.ok || ReplayExport.active || ReplayPlayer.busy)
         {
            return;
         }
         select = e.file;
         ReplayPlayer.watch(fileOf(e),-1,true);
      }

      private function exportVideo(e:Object) : void
      {
         if(!e.ok || ReplayExport.active || ReplayPlayer.busy)
         {
            return;
         }
         select = e.file;
         ReplayExport.startWithNext(String(e.file).replace(/\.replay$/,""));
         ReplayPlayer.watch(fileOf(e),-1);
      }

      private function pickTag(e:Object) : void
      {
         var all:Array = ReplayStore.allTags();
         var have:Array = ReplayStore.tags(e.file);
         var names:Array = [];
         for each(var t:String in all)
         {
            names.push((have.indexOf(t) >= 0 ? "ON  ·  " : "") + t.toUpperCase());
         }
         names.push("NEW TAG...");
         pickFrom("TAGS",names,0,function(n:int):void
         {
            if(n == all.length)
            {
               newTag(e);
               return;
            }
            if(n >= 0 && n < all.length)
            {
               ReplayStore.toggleTag(e.file,all[n]);
               build();
            }
         });
      }

      private function share(e:Object) : void
      {
         say("Sending the replay to the server...");
         ReplayIndex.sharing.share(fileOf(e),function(code:String, error:String):void
         {
            if(code)
            {
               Modal.show("Share code","Code: " + code + "\n\nAnyone on this server can open this replay with the code (Replays > " +
                  "ENTER A CODE).");
               say("Share code " + code);
            }
            else
            {
               say("Not shared: " + (error || "no answer"));
            }
            build();
         });
      }

      public function enterCode() : void
      {
         if(ReplayIndex.sharing == null)
         {
            return;
         }
         typeText("SHARE CODE",null,12,function(v:String):void
         {
            v = v.replace(/\s+/g,"").toUpperCase();
            if(v == "")
            {
               return;
            }
            say("Asking the server for " + v + "...");
            ReplayIndex.sharing.fetch(v,function(name:String, error:String):void
            {
               if(name)
               {
                  select = name;
                  tab = 0;
                  say("Saved " + name + ".");
                  reload();
               }
               else
               {
                  say("Not found: " + (error || "no answer"));
               }
            });
         });
      }

      private function confirmDelete(e:Object) : void
      {
         var f:File = fileOf(e);
         Modal.show("Delete replay","Delete " + String(e.file).replace(/\.replay$/,"") + " for good? A copy in Favorites stays.",
            [{"label":"Delete","action":function():void
            {
               deleteNow(e,f);
            }},{"label":"Keep"}]);
      }

      private function deleteNow(e:Object, f:File) : void
      {
         try
         {
            f.deleteFile();
            ReplayIndex.forget(f);
            var still:Boolean = false;
            for each(var t:int in [0,1,2])
            {
               still = still || folderOf(t).resolvePath(String(e.file)).exists;
            }
            if(!still)
            {
               ReplayStore.forget(String(e.file));
            }
            if(entries != null)
            {
               var at:int = entries.indexOf(e);
               if(at >= 0)
               {
                  entries.splice(at,1);
               }
            }
            if(tab == 1 || f.parent != null && f.parent.name == ReplayKeep.FAVORITES)
            {
               delete favNames[e.file];
            }
            Platform.log("replays: deleted " + ReplayIndex.keyOf(f));
            say("Deleted.");
         }
         catch(err:Error)
         {
            say("Not deleted: " + err.message);
         }
         build();
      }

      private function openFilters() : void
      {
         var entry:Function = function(key:String, label:String, values:Array, icon:Function = null, wide:Boolean = false):Array
         {
            return [label + ": " + (filterOf(key) != "" ? filterOf(key).toUpperCase() : "ANY") + "  >",function():void
            {
               var names:Array = ["ANY"].concat(values);
               var at:int = Math.max(0,names.indexOf(filterOf(key)));
               var choose:Function = function(n:int):void
               {
                  setFilter(key,n <= 0 ? "" : String(names[n]));
                  page = 0;
                  build();
               };
               if(icon == null)
               {
                  pickFrom(label,names,at,choose);
                  return;
               }
               pickFrom(label,names,at,choose,function(n:int):Bitmap
               {
                  return n > 0 ? icon(String(names[n])) as Bitmap : null;
               },wide);
            }];
         };
         var list:Array = entries != null ? entries : [];
         var legendIds:Object = {};
         var mapKeys:Object = {};
         for each(var le:Object in list)
         {
            for each(var lp:Object in le.players)
            {
               for(var li:int = 0; lp.legends != null && lp.ids != null && li < lp.legends.length; li++)
               {
                  legendIds[String(lp.legends[li])] = int(lp.ids[li]);
               }
            }
            if(le.mapName || le.map)
            {
               mapKeys[String(le.mapName || le.map)] = String(le.map || mapKey(le));
            }
         }
         var bots:Object = botNames();
         var seen:Object = {};
         var players:Array = [];
         for each(var oe:Object in list)
         {
            for(var oi:int = 0; oe.players != null && oi < oe.players.length; oi++)
            {
               var op:Object = oe.players[oi];
               var on:String = String(op.name || "");
               if(oi == oe.me || on == "" || bots[on.toUpperCase()] || seen[on])
               {
                  continue;
               }
               seen[on] = true;
               players.push(on);
            }
         }
         players.sort(Array.CASEINSENSITIVE);
         var modes:Object = {};
         var modeList:Array = [];
         for each(var e:Object in list)
         {
            var m:String = String(e.mode || e.playlist || "");
            if(m != "" && !modes[m])
            {
               modes[m] = true;
               modeList.push(m);
            }
         }
         modeList.sort(Array.CASEINSENSITIVE);
         var rows:Array = [entry("legend","LEGEND",ReplayIndex.values(list,"legend"),function(name:String):Bitmap
            {
               return legendIds[name] != null ? LeaderboardWindow.legendIcon(int(legendIds[name]),50) : null;
            }),
            entry("map","MAP",ReplayIndex.values(list,"map"),function(name:String):Bitmap
            {
               return mapKeys[name] != null ? LeaderboardWindow.mapThumb({"map":mapKeys[name]},140,74) : null;
            },true),
            entry("opponent","OPPONENT",players),
            entry("mode","MODE",modeList),
            tagEntry()];
         rows.push(["CLEAR FILTERS",function():void
         {
            filters = {"legend":"","map":"","opponent":"","mode":"","tag":""};
            picked = {};
            page = 0;
            build();
         }]);
         if(ReplayIndex.sharing != null)
         {
            rows.push(["ENTER A SHARE CODE",function():void
            {
               enterCode();
            }]);
         }
         openContext({"menu":function():Array
         {
            return rows;
         },"menuTitle":"FILTERS"},area.x + 40,area.y + 60);
      }

      private function tagEntry() : Array
      {
         var tags:Array = ReplayStore.allTags();
         return ["TAG: " + (filterOf("tag") != "" ? filterOf("tag").toUpperCase() : "ANY") + "  >",function():void
         {
            var names:Array = ["ANY"].concat(tags);
            names.push("NEW TAG...");
            pickFrom("TAG",names,Math.max(0,names.indexOf(filterOf("tag"))),function(n:int):void
            {
               if(n == names.length - 1)
               {
                  var it:Object = items[focus];
                  if(it == null || it.entry == null)
                  {
                     say("Pick a replay first: the new tag goes on it.");
                     return;
                  }
                  newTag(it.entry);
                  return;
               }
               setFilter("tag",n <= 0 ? "" : String(names[n]));
               page = 0;
               build();
            });
         }];
      }

      private function newTag(e:Object) : void
      {
         typeText("NEW TAG",null,24,function(v:String):void
         {
            v = v.replace(/^\s+|\s+$/g,"");
            if(v != "")
            {
               ReplayStore.toggleTag(e.file,v);
            }
            build();
         });
      }

      private static var bots:Object = null;

      private static function botNames() : Object
      {
         if(bots != null)
         {
            return bots;
         }
         var out:Object = {};
         for each(var h:Object in LeaderboardWindow.allLegends())
         {
            if(h != null && h.var_4421)
            {
               out[String(h.var_4421).toUpperCase()] = true;
            }
         }
         bots = out;
         return out;
      }

   }
}
