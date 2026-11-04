package bh.platform
{
   import bh.platform.net.PrivateServer;
   import bh.platform.net.ReplayShare;
   import bh.platform.net.ServerStats;
   import flash.display.Bitmap;
   import flash.display.GraphicsBitmapFill;
   import flash.display.GraphicsEndFill;
   import flash.display.GraphicsGradientFill;
   import flash.display.GraphicsPath;
   import flash.display.GraphicsSolidFill;
   import flash.display.IGraphicsData;
   import flash.utils.Dictionary;
   import flash.display.BitmapData;
   import flash.display.DisplayObject;
   import flash.display.MovieClip;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.KeyboardEvent;
   import flash.events.MouseEvent;
   import flash.geom.Matrix;
   import flash.geom.Rectangle;
   import flash.system.ApplicationDomain;
   import flash.text.TextField;
   import flash.text.TextFieldType;
   import flash.text.TextFormat;
   import flash.ui.Keyboard;
   import flash.utils.setTimeout;

   public class LeaderboardWindow extends BigWindow
   {
      private static const TABS:Array = ["1V1","2V2 SOLO","2V2 TEAM","3V3","LEGENDS","CLANS","RECENT"];
      private static const LADDER_OF_TAB:Array = ["1v1","2v2","2v2team","3v3",null,null,null];
      private static const T_TEAM:int = 2;
      private static const T_LEGENDS:int = 4;
      private static const T_CLANS:int = 5;
      private static const T_RECENT:int = 6;
      private static const COL_W:Number = 280;
      private static const SHOWCASE_REF:Number = 260;
      private static const ROW_H:Number = 34;
      private static const TEAM_ROW_H:Number = 54;
      private static const X_RATING:Number = 330;
      private static const X_RECORD:Number = 412;
      private static const X_PERCENT:Number = 478;

      private static const TIER_COLOURS:Object = {"Unranked":0x7F8C99,"Tin":0x8C8F95,"Bronze":0xC0814D,"Silver":0xB9C3CF,
         "Gold":0xE8C14A,"Platinum":0x5FD0C6,"Diamond":0x7AA8FF,"Valhallan":0xD38BFF};
      private static const PLACEMENT_GAMES:int = 10;

      private function isPlaced(rt:Object) : Boolean
      {
         if(rt == null)
         {
            return false;
         }
         var need:int = rt.placement != null ? int(rt.placement) : tab == T_LEGENDS ? 0 : PLACEMENT_GAMES;
         return int(rt.games) >= need;
      }

      private static var window:LeaderboardWindow;
      private static var listening:Boolean = false;
      private static var boxHooked:Dictionary = new Dictionary(true);

      private static var art:Object = {};
      private static var waitingArt:Boolean = false;
      private var artRetries:int = 0;

      private var detail:Sprite;
      private var shownKey:String = "";
      private var shownRow:Object = null;
      private var dolls:Array = [];
      private var toFit:Array = [];
      private var season:int = 0;
      private var filterIndex:int = 0;
      private var legendId:int = 0;
      private var rowItems:Array = [];

      public function LeaderboardWindow(core:GameCore)
      {
         super(core);
      }

      public static const BUTTON:uint = 2;
      public static const KEY_BUTTON:String = "BH_Leaderboard_Button";
      public static const KEY_BUTTON_DESC:String = "BH_Leaderboard_Button_Desc";
      private static const STRINGS:Object = {
         "BH_Leaderboard_Button":"Leaderboard",
         "BH_Leaderboard_Button_Desc":"Rankings on this server"
      };

      private static var menu:ScreenMainMenu;

      private static var stripped:Dictionary = new Dictionary(true);
      private static var stripLogged:Boolean = false;

      private static function stripBox(shape:Shape) : void
      {
         try
         {
            var data:Vector.<IGraphicsData> = shape.graphics.readGraphicsData(false);
            var whole:Rectangle = shape.getBounds(shape);
            var keep:Vector.<IGraphicsData> = new Vector.<IGraphicsData>();
            var log:Array = [];
            var i:int = 0;
            while(i < data.length)
            {
               var d:IGraphicsData = data[i];
               if(d is GraphicsSolidFill || d is GraphicsGradientFill || d is GraphicsBitmapFill)
               {
                  var group:Vector.<IGraphicsData> = new Vector.<IGraphicsData>();
                  group.push(d);
                  var box:Rectangle = new Rectangle();
                  var j:int = i + 1;
                  while(j < data.length && !(data[j] is GraphicsSolidFill || data[j] is GraphicsGradientFill ||
                     data[j] is GraphicsBitmapFill))
                  {
                     group.push(data[j]);
                     if(data[j] is GraphicsPath)
                     {
                        box = box.union(pathBounds(data[j] as GraphicsPath));
                     }
                     if(data[j] is GraphicsEndFill)
                     {
                        j++;
                        break;
                     }
                     j++;
                  }
                  var big:Boolean = d is GraphicsGradientFill && box.width * box.height > 0;
                  log.push((d is GraphicsGradientFill ? "gradient" : (d is GraphicsSolidFill ? "solid " +
                     GraphicsSolidFill(d).color.toString(16) : "bitmap")) + " " + Math.round(box.width) + "x" +
                     Math.round(box.height) + (big ? " dropped" : ""));
                  if(!big)
                  {
                     for each(var k:IGraphicsData in group)
                     {
                        keep.push(k);
                     }
                  }
                  i = j;
                  continue;
               }
               keep.push(d);
               i++;
            }
            shape.graphics.clear();
            shape.graphics.drawGraphicsData(keep);
            if(!stripLogged)
            {
               stripLogged = true;
               PrivateServer.log("leaderboard button: its box shape " + Math.round(whole.width) + "x" +
                  Math.round(whole.height) + ": " + log.join(", "));
            }
         }
         catch(e:Error)
         {
            shape.visible = false;
            PrivateServer.log("leaderboard button: box not stripped (" + e.message + "), hidden");
         }
      }

      private static function pathBounds(p:GraphicsPath) : Rectangle
      {
         var minX:Number = Number.MAX_VALUE;
         var minY:Number = Number.MAX_VALUE;
         var maxX:Number = -Number.MAX_VALUE;
         var maxY:Number = -Number.MAX_VALUE;
         for(var i:int = 0; i + 1 < p.data.length; i += 2)
         {
            minX = Math.min(minX,p.data[i]);
            maxX = Math.max(maxX,p.data[i]);
            minY = Math.min(minY,p.data[i + 1]);
            maxY = Math.max(maxY,p.data[i + 1]);
         }
         return maxX >= minX ? new Rectangle(minX,minY,maxX - minX,maxY - minY) : new Rectangle();
      }

      public static function init() : void
      {
         Hooks.mainMenuButtonsBuilt.add(onButtonsBuilt);
         Hooks.mainMenuInput.add(onMenuInput);
         Hooks.keyDown.add(function(event:Object):Boolean
         {
            return window != null && window.isActive && window.typing();
         });
      }

      private static function onButtonsBuilt(m:ScreenMainMenu) : void
      {
         if(Localization.var_14676 != null)
         {
            for(var key:String in STRINGS)
            {
               if(!Localization.var_14676.var_15061.exists(key))
               {
                  Localization.var_14676.var_15061.method_65(key,STRINGS[key]);
               }
            }
         }
         ServerStats.sendProfile();
         menu = m;
         if(m.var_9668 != null && m.var_5281 != null && m.var_9668[BUTTON] != KEY_BUTTON)
         {
            m.var_9668[BUTTON] = KEY_BUTTON;
            m.var_5281[BUTTON] = KEY_BUTTON_DESC;
            m.rebuildButtons();
            return;
         }
         var b:UiClip = m.buttons[BUTTON];
         if(b != null)
         {
            var ribbon:DisplayObject = b.clip != null ? b.clip.getChildByName("am_WrapperNew") : null;
            if(ribbon != null)
            {
               ribbon.visible = false;
               var clip:MovieClip = b.clip;
               var rb:Rectangle = ribbon.getBounds(clip);
               var lastFrame:int = -1;
               var hideBox:Function = function(e:Event = null):void
               {
                  if(e != null && (clip.stage == null || clip.currentFrame == lastFrame))
                  {
                     return;
                  }
                  lastFrame = clip.currentFrame;
                  var full:Rectangle = clip.getBounds(clip);
                  for(var c:int = 0; c < clip.numChildren; c++)
                  {
                     var child:DisplayObject = clip.getChildAt(c);
                     if(child is Shape && !stripped[child] && child.getBounds(clip).intersects(rb) &&
                        child.width < full.width / 2)
                     {
                        stripped[child] = true;
                        stripBox(child as Shape);
                     }
                  }
                  var r:DisplayObject = clip.getChildByName("am_WrapperNew");
                  if(r != null)
                  {
                     r.visible = false;
                  }
               };
               hideBox();
               if(!boxHooked[clip])
               {
                  boxHooked[clip] = true;
                  clip.addEventListener(Event.ENTER_FRAME,hideBox);
               }
            }
            b.var_15122 = function(e:MouseEvent, id:uint):void
            {
               if(menu != null)
               {
                  ScreenBase.setFocus(menu);
               }
               open();
            };
         }
      }

      private static function onMenuInput(m:ScreenMainMenu, input:int, device:class_223) : Boolean
      {
         if((input == 11 || input == 17 || input == 23) && m.method_688() == BUTTON && device != null)
         {
            class_112.method_3429();
            if(class_112.method_8187(device.mType,device.mControllerID) != null)
            {
               open();
            }
            return true;
         }
         return false;
      }

      public static function open() : void
      {
         if(window == null || ScreenManager.allScreens.indexOf(window) < 0)
         {
            window = new LeaderboardWindow(ScreenManager.owner);
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
            ServerStats.sendProfile(true);
            ServerStats.ask("seasons");
            ServerStats.ask(window.boardQuery(window.tab));
            ServerStats.ask("recent");
         }
         if(!window.isActive)
         {
            window.shownKey = "";
            window.artRetries = 0;
            window.detailRetryKey = "";
            window.Display();
         }
      }

      public static function get shown() : LeaderboardWindow
      {
         return window != null && window.isActive ? window : null;
      }

      private static var tierArtState:String = "not asked";

      override protected function get fullPage() : Boolean
      {
         return true;
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

      private function get SHOW_X() : Number
      {
         return COL_W + 16;
      }

      private function get SHOW_W() : Number
      {
         return RIGHT_W - SHOW_X - 10;
      }

      override protected function get title() : String
      {
         return "LEADERBOARD";
      }

      override protected function get tabNames() : Array
      {
         return TABS;
      }

      override protected function get tabLayout() : Array
      {
         return [-505,147,0.66];
      }

      override protected function get confirmLabel() : String
      {
         return "DONE";
      }

      override protected function hintText() : String
      {
         var n:Object = Prompts.KEYS;
         if(tab == T_RECENT)
         {
            return n.tabs + " TABS     " + n.page + " PAGE     " + n.select + " WATCH REPLAY     " + n.back + " BACK     {Alt} SEARCH";
         }
         if(regionNames().length > 1 && filterIndex >= 2)
         {
            return n.tabs + " TABS     " + n.page + " PAGE     " + n.option + " SET AS MY REGION     " + n.back + " BACK";
         }
         if(tab != T_CLANS && tab != T_TEAM)
         {
            return n.tabs + " TABS     " + n.page + " PAGE     " + n.select + " VIEW PROFILE     " + n.option + " MENU     " + n.back +
               " BACK     {Alt} SEARCH";
         }
         return defaultHint() + "     {Alt} SEARCH";
      }

      private var search:String = "";
      private var searchBox:TextField;
      private var searchHint:TextField;

      override public function OnCreateScreen() : void
      {
         super.OnCreateScreen();
         makeSearchBox();
      }

      private function makeSearchBox() : void
      {
         var box:Sprite = new Sprite();
         box.x = area.right - 440;
         box.y = area.y - 92;
         box.buttonMode = true;
         body.addChild(box);
         UiKit.rect(box,0,0,220,26,UiKit.WHITE,5);
         searchBox = new TextField();
         searchBox.type = TextFieldType.INPUT;
         searchBox.defaultTextFormat = new TextFormat("_sans",14,UiKit.NAVY_TEXT);
         searchBox.x = 8;
         searchBox.y = 3;
         searchBox.width = 204;
         searchBox.height = 22;
         searchBox.maxChars = 30;
         box.addChild(searchBox);
         searchHint = UiKit.text(box,"SEARCH PLAYERS",10,4,13,UiKit.GREY,UiKit.MEDIUM);
         searchBox.addEventListener(Event.CHANGE,function(e:Event):void
         {
            setSearch(searchBox.text,false);
         });
         searchBox.addEventListener(KeyboardEvent.KEY_DOWN,function(e:KeyboardEvent):void
         {
            if(e.keyCode == Keyboard.ENTER || e.keyCode == Keyboard.DOWN || e.keyCode == Keyboard.ESCAPE)
            {
               if(body.stage != null)
               {
                  body.stage.focus = null;
               }
               if(e.keyCode == Keyboard.ESCAPE)
               {
                  setSearch("");
               }
            }
         });
         box.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            e.stopPropagation();
            if(body.stage != null)
            {
               body.stage.focus = searchBox;
            }
         });
      }

      public function typing() : Boolean
      {
         return searchBox != null && searchBox.stage != null && searchBox.stage.focus === searchBox;
      }

      override protected function blockInput() : Boolean
      {
         return typing();
      }

      override public function HandleInput(input:int) : Boolean
      {
         if(input == 20 && method_5588() && !covered() && !blockInput() && !keyboardOpen)
         {
            openSearch();
            return true;
         }
         return super.HandleInput(input);
      }

      private function openSearch() : void
      {
         if(class_687.var_11971 != 2 && searchBox != null)
         {
            var box:TextField = searchBox;
            var once:Function = function(e:Event):void
            {
               box.removeEventListener(Event.ENTER_FRAME,once);
               if(box.stage != null && isActive)
               {
                  box.stage.focus = box;
                  box.setSelection(box.length,box.length);
               }
            };
            box.addEventListener(Event.ENTER_FRAME,once);
            return;
         }
         typeText("SEARCH PLAYERS",search,30,function(v:String):void
         {
            setSearch(v);
         });
      }

      private function setSearch(q:String, toBox:Boolean = true) : void
      {
         q = q == null ? "" : q.replace(/^\s+|\s+$/g,"");
         if(toBox && searchBox != null)
         {
            searchBox.text = q;
         }
         if(searchHint != null)
         {
            searchHint.visible = searchBox == null || searchBox.text.length == 0;
         }
         if(q == search)
         {
            return;
         }
         search = q;
         shownKey = "";
         if(PrivateServer.host != null && tab != T_CLANS)
         {
            ServerStats.ask(boardQuery(tab));
         }
         build();
      }

      private function nameMatches(name:Object) : Boolean
      {
         return search == "" || String(name).toLowerCase().indexOf(search.toLowerCase()) >= 0;
      }

      override protected function statusText() : String
      {
         if(PrivateServer.host == null)
         {
            return "Offline: the leaderboard lives on the project's server.";
         }
         switch(tab)
         {
            case T_RECENT:
               return "The server's latest matches, newest first.";
            case T_CLANS:
               return "Clans by their members' rated wins this season, then their average 1v1 rating.";
            case T_LEGENDS:
               return "Each legend's own 1v1 rating, from rated 1v1 matches played with it.";
            case T_TEAM:
               return "A rating per pair of players, from rated 2v2 matches they played together.";
            default:
               return "";
         }
      }

      private function recentQuery() : String
      {
         return search != "" ? "recent:" + encodeURIComponent(search) : "recent";
      }

      private function searchPart() : String
      {
         return search != "" ? ":" + encodeURIComponent(search) : "";
      }

      private function filterKey() : String
      {
         return filterIndex == 0 ? "all" : (filterIndex == 1 ? "friends" : "r" + (filterIndex - 2));
      }

      private function boardQuery(t:int) : String
      {
         if(t == T_CLANS)
         {
            return "clans:" + season;
         }
         if(t == T_LEGENDS)
         {
            var id:int = currentLegend();
            return id > 0 ? "leaderboard:L" + id + ":" + season + ":" + filterKey() + searchPart() : "legends:" + season;
         }
         if(t == T_RECENT)
         {
            return recentQuery();
         }
         return "leaderboard:" + LADDER_OF_TAB[t] + ":" + season + ":" + filterKey() + searchPart();
      }

      private function detailQuery() : String
      {
         if(shownKey.charAt(0) == "p")
         {
            return "player:" + shownKey.substr(1) + ":" + season + ":" + (tab == T_LEGENDS ? "L" + currentLegend() :
               detailLadder());
         }
         if(shownKey.charAt(0) == "t")
         {
            return "team:" + shownKey.substr(1) + ":" + season;
         }
         return "";
      }

      private function arrived(query:String) : void
      {
         if(query == "seasons" || query == boardQuery(tab) || query == "legends:" + season && tab == T_LEGENDS)
         {
            build();
         }
         else if(query == detailQuery() && detail != null)
         {
            drawDetail();
         }
      }

      private function seasonsAnswer() : Object
      {
         return PrivateServer.host != null ? ServerStats.get("seasons") : null;
      }

      private function seasonList() : Array
      {
         var got:Object = seasonsAnswer();
         return got != null && got.seasons is Array ? got.seasons as Array : [];
      }

      private function regionNames() : Array
      {
         var got:Object = seasonsAnswer();
         return got != null && got.regions is Array ? got.regions as Array : ["Global"];
      }

      private function you() : int
      {
         var got:Object = seasonsAnswer();
         return got != null ? int(got.you) : 0;
      }

      private function shownSeason() : Object
      {
         for each(var z:Object in seasonList())
         {
            if(season == 0 ? z.current : int(z.id) == season)
            {
               return z;
            }
         }
         return null;
      }

      private function stepSeason(dir:int) : void
      {
         var list:Array = seasonList();
         if(list.length < 2)
         {
            return;
         }
         var at:int = 0;
         for(var i:int = 0; i < list.length; i++)
         {
            if(season == 0 ? list[i].current : int(list[i].id) == season)
            {
               at = i;
            }
         }
         at = (at + (dir > 0 ? 1 : -1) + list.length) % list.length;
         season = list[at].current ? 0 : int(list[at].id);
         shownKey = "";
         legendId = 0;
      }

      private function filterNames() : Array
      {
         var names:Array = ["EVERYONE","FRIENDS"];
         var regions:Array = regionNames();
         if(regions.length > 1)
         {
            for each(var r:String in regions)
            {
               names.push(r.toUpperCase());
            }
         }
         return names;
      }

      public static function allLegends() : Array
      {
         var out:Array = [];
         try
         {
            for each(var h:HeroType in HeroType.var_12147)
            {
               if(h != null && h.var_10527 != null && h.var_12172 > 0 && h.var_4421)
               {
                  out.push(h);
               }
            }
            out.sortOn("var_4421",Array.CASEINSENSITIVE);
         }
         catch(e:Error)
         {
         }
         return out;
      }

      private function pickLegend() : void
      {
         var heroes:Array = allLegends();
         if(heroes.length == 0 || pickerOpen)
         {
            return;
         }
         var names:Array = [];
         var at:int = 0;
         for(var i:int = 0; i < heroes.length; i++)
         {
            names.push(String(heroes[i].var_4421).toUpperCase());
            if(int(heroes[i].var_12172) == legendId)
            {
               at = i;
            }
         }
         pickFrom("PICK A LEGEND",names,at,function(k:int):void
         {
            legendId = int(heroes[k].var_12172);
            shownKey = "";
            ServerStats.get(boardQuery(tab));
            build();
         },function(k:int):Bitmap
         {
            return legendIcon(int(heroes[k].var_12172),50);
         });
      }

      private function legendList() : Array
      {
         var got:Object = PrivateServer.host != null ? ServerStats.get("legends:" + season) : null;
         return got != null && got.legends is Array ? got.legends as Array : [];
      }

      private function currentLegend() : int
      {
         var list:Array = legendList();
         if(legendId == 0 && list.length > 0)
         {
            legendId = int(list[0].legend);
         }
         return legendId;
      }

      private function stepLegend(dir:int) : void
      {
         var list:Array = legendList();
         if(list.length == 0)
         {
            return;
         }
         var at:int = 0;
         for(var i:int = 0; i < list.length; i++)
         {
            if(int(list[i].legend) == legendId)
            {
               at = i;
            }
         }
         legendId = int(list[(at + dir + list.length) % list.length].legend);
         shownKey = "";
      }

      override protected function built() : void
      {
         if(waitingArt && artRetries < 5)
         {
            artRetries++;
            var self:LeaderboardWindow = this;
            setTimeout(function():void
            {
               if(self.isActive)
               {
                  self.build();
               }
            },800);
         }
         waitingArt = false;
      }

      override public function Hide() : void
      {
         clearDolls();
         super.Hide();
      }

      override public function returnTo() : void
      {
         open();
      }

      private var builtTab:int = -1;

      override protected function buildTab(i:int) : void
      {
         detail = null;
         rowItems = [];
         if(i != builtTab)
         {
            builtTab = i;
            shownKey = "";
            shownRow = null;
         }
         if(i == T_RECENT)
         {
            buildRecent();
            return;
         }
         var left:Sprite = panel(area.x,area.y,LEFT_W,area.height);
         var right:Sprite = panel(RIGHT_X,area.y,RIGHT_W,area.height);
         detail = right;
         var y:Number = 6;
         y = seasonRow(left,y);
         if(i != T_CLANS)
         {
            y = filterRow(left,y);
         }
         if(i == T_LEGENDS)
         {
            y = legendRow(left,y);
            if(currentLegend() == 0)
            {
               UiKit.text(left,legendList().length == 0 && ServerStats.get("legends:" + season) == null ? "Asking the server..." :
                  "No rated 1v1 match " + (season == 0 ? "this season yet." : "in that season."),24,y + 10,14,UiKit.LIGHT,
                  UiKit.MEDIUM,LEFT_W - 48);
               drawDetail();
               return;
            }
         }
         var board:Object = PrivateServer.host != null ? ServerStats.get(boardQuery(i)) : null;
         var rows:Array = board == null ? null : (i == T_CLANS ? board.clans as Array : board.rows as Array);
         if(rows != null && i == T_CLANS && search != "")
         {
            rows = rows.filter(function(r:Object, k:int, all:Array):Boolean { return nameMatches(r.name); });
         }
         header(left,y,i);
         y += 20;
         if(board != null && board.error != null && (rows == null || rows.length == 0))
         {
            UiKit.text(left,String(board.error),24,y + 8,14,UiKit.LIGHT,UiKit.MEDIUM,LEFT_W - 48);
            drawDetail();
            return;
         }
         if(rows != null && rows.length == 0 && search != "")
         {
            UiKit.text(left,"Nobody named like \"" + search + "\" here.",24,y + 8,14,UiKit.LIGHT,UiKit.MEDIUM,LEFT_W - 48);
            shownKey = "";
            drawDetail();
            return;
         }
         if(rows == null || rows.length == 0)
         {
            UiKit.text(left,board == null ? (PrivateServer.host == null ? "Offline." : "Asking the server...") :
               (i == T_CLANS ? "No clan yet." : "Nobody here " + (season == 0 ? "this season yet" : "in that season") +
               ". An online match counts when every player's game reports the same result."),24,y + 8,14,UiKit.LIGHT,
               UiKit.MEDIUM,LEFT_W - 48);
            shownKey = "";
            drawDetail();
            return;
         }
         var mine:int = -1;
         var me:int = you();
         for(var n:int = 0; n < rows.length && me > 0 && i != T_CLANS; n++)
         {
            if(i == T_TEAM ? rows[n].accounts is Array && rows[n].accounts.indexOf(me) >= 0 : int(rows[n].id) == me)
            {
               mine = n;
               break;
            }
         }
         var rh:Number = rowHeight(i);
         var listH:Number = area.height - y - 6 - (mine >= 0 ? rh + 8 : 0);
         var list:Sprite = scroller(left,0,y,LEFT_W,listH);
         for(n = 0; n < rows.length; n++)
         {
            row(list,n * (rh + 4),rows[n],i);
         }
         if(mine >= 0)
         {
            pinned(left,area.height - rh - 8,rows[mine],i,mine);
         }
         if(shownKey == "")
         {
            select(rows[0],i);
         }
         drawDetail();
      }

      private function keyOf(r:Object, t:int) : String
      {
         return t == T_CLANS ? "c" + r.id : (t == T_TEAM ? "t" + r.id : "p" + r.id);
      }

      private function select(r:Object, t:int) : void
      {
         shownKey = keyOf(r,t);
         shownRow = r;
      }

      private function seasonRow(left:Sprite, y:Number) : Number
      {
         var s:Sprite = new Sprite();
         left.addChild(s);
         var w:Number = LEFT_W - 20;
         UiKit.rect(s,10,y,w,30,UiKit.BODY,4);
         var z:Object = shownSeason();
         var label:String = z == null ? "THIS SEASON" : String(z.name).toUpperCase() + (z.current ? "  (CURRENT)" : "  " +
            day(Number(z.started)) + " - " + day(Number(z.ended)));
         UiKit.text(s,"SEASON",24,y + 6,12,UiKit.GREY,UiKit.XBOLD);
         UiKit.fit(UiKit.text(s,label,100,y + 4,15,z != null && !z.current ? UiKit.TEAL : UiKit.WHITE,UiKit.BOLD),w - 200);
         var change:Function = function(dir:int):void
         {
            stepSeason(dir);
            ServerStats.get(boardQuery(tab));
         };
         if(seasonList().length > 1)
         {
            UiKit.arrow(s,w - 76,y + 4,-1,function():void { change(-1); build(); });
            UiKit.arrow(s,w - 24,y + 4,1,function():void { change(1); build(); });
         }
         items.push({"w":"season","sprite":s,"parent":left,"width":w,"height":30,"focusBox":[10,y,w,30],"change":change});
         return y + 34;
      }

      private function filterRow(left:Sprite, y:Number) : Number
      {
         var s:Sprite = new Sprite();
         left.addChild(s);
         var w:Number = LEFT_W - 20;
         var names:Array = filterNames();
         if(filterIndex >= names.length)
         {
            filterIndex = 0;
         }
         UiKit.rect(s,10,y,w,28,UiKit.BODY,4);
         UiKit.text(s,"SHOW",24,y + 6,12,UiKit.GREY,UiKit.XBOLD);
         var x:Number = 100;
         for(var k:int = 0; k < names.length; k++)
         {
            x += filterButton(s,x,y,k,names[k]) + 26;
         }
         var regions:Array = regionNames();
         var got:Object = seasonsAnswer();
         if(regions.length > 1 && got != null && int(got.you) > 0)
         {
            var mineName:String = String(regions[Math.min(int(got.your_region),regions.length - 1)]).toUpperCase();
            var mt:Object = UiKit.text(s,"YOU: " + mineName,0,y + 6,11,UiKit.GREY,UiKit.XBOLD);
            mt.x = w - 4 - mt.width;
         }
         var change:Function = function(dir:int):void
         {
            filterIndex = (filterIndex + dir + names.length) % names.length;
            shownKey = "";
            ServerStats.get(boardQuery(tab));
         };
         var item:Object = {"w":"filter","sprite":s,"parent":left,"width":w,"height":28,"focusBox":[10,y,w,28],"change":change};
         if(regions.length > 1)
         {
            item.option = function():void
            {
               if(filterIndex >= 2)
               {
                  ServerStats.setRegion(uint(filterIndex - 2));
                  DummyDrift.show("Your region: " + regions[filterIndex - 2],2500);
                  ServerStats.ask("seasons");
                  ServerStats.ask(boardQuery(tab));
               }
            };
         }
         items.push(item);
         return y + 32;
      }

      private function filterButton(s:Sprite, x:Number, y:Number, k:int, name:String) : Number
      {
         var on:Boolean = k == filterIndex;
         var b:Sprite = new Sprite();
         b.buttonMode = true;
         s.addChild(b);
         var t:Object = UiKit.text(b,name,x,y + 5,13,on ? UiKit.TEAL : UiKit.LIGHT,on ? UiKit.XBOLD : UiKit.BOLD);
         UiKit.rect(b,x - 8,y,t.width + 16,28,0).alpha = 0;
         b.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            e.stopPropagation();
            if(filterIndex != k)
            {
               filterIndex = k;
               shownKey = "";
               ServerStats.get(boardQuery(tab));
               build();
            }
         });
         return t.width;
      }

      private function legendRow(left:Sprite, y:Number) : Number
      {
         var s:Sprite = new Sprite();
         left.addChild(s);
         var w:Number = LEFT_W - 20;
         UiKit.rect(s,10,y,w,34,UiKit.BODY,4);
         UiKit.text(s,"LEGEND",24,y + 9,12,UiKit.GREY,UiKit.XBOLD);
         var id:int = currentLegend();
         if(id > 0)
         {
            put(s,legendIcon(id,30),100,y + 2);
            var mine:Object = null;
            for each(var l:Object in legendList())
            {
               if(int(l.legend) == id)
               {
                  mine = l;
               }
            }
            var players:int = mine != null ? int(mine.players) : 0;
            UiKit.fit(UiKit.text(s,legendName(id).toUpperCase(),138,y + 7,16,UiKit.WHITE,UiKit.XBOLD),118);
            UiKit.text(s,"W-L",262,y + 1,10,UiKit.GREY,UiKit.XBOLD);
            UiKit.text(s,"WIN %",322,y + 1,10,UiKit.GREY,UiKit.XBOLD);
            UiKit.text(s,"PLAYERS",374,y + 1,10,UiKit.GREY,UiKit.XBOLD);
            if(mine != null && mine.matches != null)
            {
               record(s,mine,262,y + 14,13,true);
               UiKit.text(s,percent(mine),322,y + 14,13,UiKit.WHITE,UiKit.BOLD);
            }
            UiKit.text(s,String(players),374,y + 14,13,UiKit.WHITE,UiKit.BOLD);
         }
         var change:Function = function(dir:int):void
         {
            stepLegend(dir);
            ServerStats.get(boardQuery(tab));
         };
         if(legendList().length > 1)
         {
            UiKit.arrow(s,w - 76,y + 6,-1,function():void { change(-1); build(); });
            UiKit.arrow(s,w - 24,y + 6,1,function():void { change(1); build(); });
         }
         var item:Object = {"w":"legend","sprite":s,"parent":left,"width":w,"height":34,"focusBox":[10,y,w,34],
            "change":change,"use":pickLegend};
         s.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            pickLegend();
         });
         items.push(item);
         return y + 38;
      }

      private function header(left:Sprite, y:Number, t:int) : void
      {
         UiKit.text(left,"#",20,y,12,UiKit.GREY,UiKit.XBOLD);
         if(t == T_CLANS)
         {
            UiKit.text(left,"CLAN",82,y,12,UiKit.GREY,UiKit.XBOLD);
            UiKit.text(left,"MEMBERS",290,y,12,UiKit.GREY,UiKit.XBOLD);
            UiKit.text(left,"RATED WINS",372,y,12,UiKit.GREY,UiKit.XBOLD);
            UiKit.text(left,"AVG",476,y,12,UiKit.GREY,UiKit.XBOLD);
            return;
         }
         UiKit.text(left,t == T_TEAM ? "TEAM" : "PLAYER",112,y,12,UiKit.GREY,UiKit.XBOLD);
         UiKit.text(left,"RATING",X_RATING,y,12,UiKit.GREY,UiKit.XBOLD);
         UiKit.text(left,"W-L",X_RECORD,y,12,UiKit.GREY,UiKit.XBOLD);
         UiKit.text(left,"WIN %",X_PERCENT,y,12,UiKit.GREY,UiKit.XBOLD);
      }

      private static function rowHeight(t:int) : Number
      {
         return t == T_TEAM ? TEAM_ROW_H : ROW_H;
      }

      private function drawRow(s:Sprite, r:Object, t:int, pin:Boolean = false) : void
      {
         var w:Number = LEFT_W - 20;
         var h:Number = rowHeight(t);
         var mid:Number = h / 2;
         var rt:Object = r.rating;
         var placed:Boolean = isPlaced(rt);
         var tier:String = rt != null && rt.tier ? String(rt.tier) : "Unranked";
         var colour:uint = TIER_COLOURS[tier] != null ? uint(TIER_COLOURS[tier]) : UiKit.GREY;
         UiKit.rect(s,10,0,w,h,pin ? UiKit.ROW_SELECTED : UiKit.BODY,4);
         if(placed)
         {
            UiKit.rect(s,10,0,w,h,colour,4).alpha = int(r.rank) <= 3 ? 0.24 : 0.12;
            UiKit.rect(s,10,0,4,h,colour);
         }
         UiKit.text(s,String(r.rank),20,mid - 9,14,UiKit.placeColour(int(r.rank),UiKit.GREY),UiKit.XBOLD);
         if(t == T_CLANS)
         {
            put(s,avatar(int(r.emblem),30),44,2);
            UiKit.fit(UiKit.text(s,String(r.name),82,7,15,UiKit.WHITE,UiKit.BOLD),200);
            UiKit.text(s,String(int(r.members)),290,8,14,UiKit.LIGHT,UiKit.MEDIUM);
            UiKit.text(s,String(int(r.rated_wins)),372,8,14,UiKit.WHITE,UiKit.BOLD);
            UiKit.text(s,r.average != null ? String(r.average) : "-",476,8,14,UiKit.LIGHT,UiKit.MEDIUM);
            return;
         }
         if(tab == T_LEGENDS)
         {
            putIcon(s,RatingExtras.rankIcon(placed ? int(rt.rating) : 0,!placed,30),44,mid - 15);
         }
         else
         {
            put(s,tierBanner(tier,30,placed ? int(rt.rating) : 0),44,mid - 15);
         }
         if(t == T_TEAM && r.members is Array)
         {
            for(var k:int = 0; k < 2 && k < r.members.length; k++)
            {
               put(s,legendIcon(int(r.members[k].top_legend),22),80,4 + k * 25);
               UiKit.fit(UiKit.text(s,String(r.members[k].name),110,3 + k * 25,14,UiKit.WHITE,UiKit.BOLD),X_RATING - 118);
            }
         }
         else
         {
            put(s,legendIcon(int(r.top_legend),30),76,2);
            UiKit.fit(UiKit.text(s,String(r.name),112,7,15,UiKit.WHITE,UiKit.BOLD),X_RATING - 120);
         }
         UiKit.text(s,rt != null ? String(rt.rating) : "-",X_RATING,mid - 9,14,placed ? colour : UiKit.LIGHT,UiKit.BOLD);
         if(rt != null && !placed)
         {
            UiKit.text(s,int(rt.games) + "/" + PLACEMENT_GAMES,X_RATING + 40,mid - 7,10,UiKit.GREY,UiKit.MEDIUM);
         }
         record(s,r,X_RECORD,mid - 9,14);
         UiKit.text(s,percent(r),X_PERCENT,mid - 9,14,UiKit.LIGHT,UiKit.MEDIUM);
      }

      private function row(list:Sprite, y:Number, r:Object, t:int) : void
      {
         var s:Sprite = new Sprite();
         s.y = y;
         list.addChild(s);
         drawRow(s,r,t);
         var w:Number = LEFT_W - 20;
         var h:Number = rowHeight(t);
         var it:Object = {"w":keyOf(r,t),"key":keyOf(r,t),"row":r,"tabOf":t,"sprite":s,"parent":list,"width":w,"height":h,
            "focusBox":[10,0,w,h],"focusOutline":true};
         if(keyOf(r,t).charAt(0) == "p")
         {
            it.player = {"account":int(r.id),"name":String(r.name || "")};
            it.use = function():void
            {
               ProfileWindow.openAccount(int(r.id),String(r.name || ""));
            };
         }
         else if(t == T_TEAM && r.members is Array)
         {
            it.players = [];
            for each(var mem:Object in r.members)
            {
               it.players.push({"account":int(mem.id),"name":String(mem.name || "")});
            }
         }
         s.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            focused(it);
         });
         items.push(it);
         rowItems.push(it);
      }

      private function pinned(left:Sprite, y:Number, r:Object, t:int, index:int) : void
      {
         var s:Sprite = new Sprite();
         s.y = y;
         left.addChild(s);
         drawRow(s,r,t,true);
         var tag:Object = UiKit.text(s,"YOU",0,-1,9,UiKit.TEAL,UiKit.XBOLD);
         tag.x = LEFT_W - 14 - tag.width;
         var w:Number = LEFT_W - 20;
         var jump:Function = function():void
         {
            var target:Object = rowItems[index];
            var at:int = items.indexOf(target);
            if(at >= 0)
            {
               focus = at;
               paintFocus();
            }
         };
         s.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            jump();
         });
         var h:Number = rowHeight(t);
         items.push({"w":"you","sprite":s,"parent":left,"width":w,"height":h,"focusBox":[10,0,w,h],"use":jump});
      }

      override protected function focused(it:Object) : void
      {
         if(it != null && it.key != null && it.key != shownKey)
         {
            shownKey = it.key;
            shownRow = it.row;
            drawDetail();
         }
      }

      private function drawDetail() : void
      {
         var tabWaiting:Boolean = waitingArt;
         waitingArt = false;
         drawDetailNow();
         var waiting:Boolean = waitingArt;
         waitingArt = tabWaiting;
         if(!waiting || shownKey == "")
         {
            return;
         }
         if(detailRetryKey != shownKey)
         {
            detailRetryKey = shownKey;
            detailRetries = 0;
         }
         if(detailRetries < 5)
         {
            detailRetries++;
            var self:LeaderboardWindow = this;
            var key:String = shownKey;
            setTimeout(function():void
            {
               if(self.isActive && self.shownKey == key)
               {
                  self.drawDetail();
               }
            },800);
         }
      }

      private var detailRetryKey:String = "";
      private var detailRetries:int = 0;

      private function drawDetailNow() : void
      {
         try
         {
            clearDolls();
            if(detail == null)
            {
               return;
            }
            while(detail.numChildren > 1)
            {
               detail.removeChildAt(1);
            }
            if(shownKey == "")
            {
               return;
            }
            if(shownKey.charAt(0) == "c")
            {
               drawClan(shownRow);
               return;
            }
            var p:Object = ServerStats.get(detailQuery());
            if(p == null)
            {
               UiKit.text(detail,"Asking the server...",20,14,14,UiKit.LIGHT,UiKit.MEDIUM);
               return;
            }
            if(p.error != null)
            {
               UiKit.text(detail,String(p.error),20,14,14,UiKit.LIGHT,UiKit.MEDIUM,RIGHT_W - 40);
               return;
            }
            if(shownKey.charAt(0) == "t")
            {
               drawTeam(p);
            }
            else
            {
               drawPlayer(p);
            }
         }
         catch(e:Error)
         {
            ErrorLog.write("leaderboard: right side not fully drawn: " + e + " " + e.getStackTrace());
         }
      }

      private function detailLadder() : String
      {
         var l:String = LADDER_OF_TAB[tab];
         return l == null || l == "2v2team" ? (l == "2v2team" ? "2v2" : "1v1") : l;
      }

      private function drawPlayer(p:Object) : void
      {
         var prof:Object = p.profile || {};
         var ladder:String = detailLadder();
         var rt:Object = p.ratings != null ? p.ratings[ladder] : null;
         if(tab == T_LEGENDS && shownRow != null && shownRow.rating != null)
         {
            rt = shownRow.rating;
         }
         nameplate(detail,14,12,prof,String(p.name),232);
         ratingBlock(detail,248,12,rt,p.streak,null,44,100);
         var t:Object = p.totals || {};
         var nums:Array = [["GAMES",String(int(t.matches)),null],["W-L",null,t],["WIN %",percent(t),null]];
         if(p.vs_you != null && int(p.vs_you.matches) > 0)
         {
            nums.push(["VS YOU",null,p.vs_you]);
         }
         miniStats(detail,404,12,nums);
         var y:Number = 88;
         var history:Array = p.history != null && tab != T_LEGENDS ? p.history[ladder] as Array : null;
         if(history != null && history.length > 1)
         {
            graph(detail,20,y,COL_W - 34,40,history);
            y += 52;
         }
         var legends:Array = p.legends as Array || [];
         var showY:Number = 88;
         if(legends.length > 0 && tab != T_LEGENDS)
         {
            UiKit.text(detail,"LEGENDS",SHOW_X,showY - 2,11,UiKit.GREY,UiKit.XBOLD);
            UiKit.text(detail,"W-L",SHOW_X + 114,showY - 2,11,UiKit.GREY,UiKit.XBOLD);
            UiKit.text(detail,"WIN %",SHOW_X + 156,showY - 2,11,UiKit.GREY,UiKit.XBOLD);
            var ly:Number = showY + 14;
            var lw:Number = SHOW_W >= 380 ? SHOW_W / 2 : SHOW_W;
            var perCol:int = lw < SHOW_W ? 3 : 4;
            if(lw < SHOW_W && legends.length > 3)
            {
               UiKit.text(detail,"W-L",SHOW_X + lw + 114,showY - 2,11,UiKit.GREY,UiKit.XBOLD);
               UiKit.text(detail,"WIN %",SHOW_X + lw + 156,showY - 2,11,UiKit.GREY,UiKit.XBOLD);
            }
            for(var i:int = 0; i < legends.length && i < perCol * (lw < SHOW_W ? 2 : 1); i++)
            {
               var l:Object = legends[i];
               var lx:Number = SHOW_X + int(i / perCol) * lw;
               var ry:Number = ly + (i % perCol) * 24;
               put(detail,legendIcon(int(l.legend),22),lx,ry);
               UiKit.fit(UiKit.text(detail,legendName(int(l.legend),String(l.legend_name)),lx + 28,ry + 2,13,UiKit.WHITE,
                  UiKit.BOLD),82);
               record(detail,l,lx + 114,ry + 3,12);
               UiKit.text(detail,percent(l),lx + 156,ry + 3,12,UiKit.LIGHT,UiKit.MEDIUM);
            }
            showY = ly + Math.min(legends.length,perCol) * 24 + 4;
         }
         showY = moreNumbers(detail,SHOW_X,showY,p,ladder);
         lastMatches(detail,y,area.height - 10,p.recent as Array || [],int(shownKey.substr(1)));
         showcase(prof,SHOW_X,showY,SHOW_W,area.height - showY - 10);
      }

      private function drawTeam(p:Object) : void
      {
         var members:Array = p.members as Array || [];
         var y:Number = 10;
         var half:Number = (RIGHT_W - 28) / 2;
         for(var k:int = 0; k < members.length && k < 2; k++)
         {
            var m:Object = members[k];
            var mx:Number = 14 + k * half;
            put(detail,avatar(int(m.profile != null ? m.profile.avatar : 0),40),mx,y);
            UiKit.fit(UiKit.text(detail,String(m.name),mx + 48,y + 1,16,UiKit.WHITE,UiKit.XBOLD),half - 54);
            var tn:String = monikerName(int(m.profile != null ? m.profile.title : 0));
            if(tn)
            {
               UiKit.fit(UiKit.text(detail,tn,mx + 48,y + 22,11,monikerColour(int(m.profile.title)),UiKit.BOLD),half - 54);
            }
         }
         y += 52;
         ratingBlock(detail,14,y,p.rating,null,"TEAM",48,170);
         miniStats(detail,248,y,[["GAMES",String(int(p.matches)),null],["W-L",null,p],["WIN %",percent(p),null]]);
         y += 70;
         lastMatches(detail,y,area.height - 10,p.recent as Array || [],int(p.accounts != null ? p.accounts[0] : 0));
         for(k = 0; k < members.length && k < 2; k++)
         {
            showcase(members[k].profile || {},SHOW_X + k * SHOW_W / 2,y,SHOW_W / 2,area.height - y - 10);
         }
      }

      private function drawClan(c:Object) : void
      {
         if(c == null)
         {
            return;
         }
         put(detail,avatar(int(c.emblem),58),17,15);
         UiKit.fit(UiKit.text(detail,String(c.name),88,16,20,UiKit.WHITE,UiKit.XBOLD),RIGHT_W - 110);
         UiKit.text(detail,"RANK " + c.rank + (season == 0 ? " THIS SEASON" : ""),88,44,13,UiKit.TEAL,UiKit.XBOLD);
         var y:Number = 92;
         stat(detail,20,y,"MEMBERS",String(int(c.members)));
         stat(detail,120,y,"RATED WINS",String(int(c.rated_wins)));
         stat(detail,240,y,"RATED GAMES",String(int(c.rated_matches)));
         stat(detail,370,y,"AVG 1V1",c.average != null ? String(c.average) : "-");
         y += 56;
         var best:Array = c.best as Array || [];
         if(best.length > 0)
         {
            UiKit.text(detail,"BEST 1V1 PLAYERS",20,y,11,UiKit.GREY,UiKit.XBOLD);
            y += 18;
            for each(var b:Object in best)
            {
               UiKit.fit(UiKit.text(detail,String(b.name),20,y,14,UiKit.WHITE,UiKit.BOLD),300);
               UiKit.text(detail,String(b.rating),340,y,14,UiKit.TEAL,UiKit.BOLD);
               y += 22;
            }
         }
      }

      private function nameplate(p:Sprite, x:Number, y:Number, prof:Object, name:String, w:Number) : void
      {
         put(p,avatar(int(prof.avatar),58),x,y);
         UiKit.fit(UiKit.text(p,name,x + 66,y + 4,20,UiKit.WHITE,UiKit.XBOLD),w - 66);
         var titleName:String = monikerName(int(prof.title));
         if(titleName)
         {
            UiKit.fit(UiKit.text(p,titleName,x + 66,y + 32,13,monikerColour(int(prof.title)),UiKit.BOLD),w - 66);
         }
      }

      private function ratingBlock(p:Sprite, x:Number, y:Number, rt:Object, streak:Object, label:String, size:int,
                                   w:Number) : void
      {
         var tier:String = rt != null && rt.tier ? String(rt.tier) : "Unranked";
         var colour:uint = TIER_COLOURS[tier] != null ? uint(TIER_COLOURS[tier]) : UiKit.GREY;
         if(tab == T_LEGENDS)
         {
            putIcon(p,RatingExtras.rankIcon(rt != null ? int(rt.rating) : 0,!isPlaced(rt),size),x,y);
         }
         else
         {
            put(p,tierBanner(tier,size,isPlaced(rt) ? int(rt.rating) : 0),x,y);
         }
         var tx:Number = x + size + 6;
         var shownTier:String = isPlaced(rt) ? rankName(tier,int(rt.rating)) : tier;
         UiKit.fit(UiKit.text(p,(label != null ? label + "  " : "") + shownTier.toUpperCase(),tx,y - 2,12,colour,UiKit.XBOLD),w);
         if(rt != null)
         {
            var placed:Boolean = isPlaced(rt);
            UiKit.text(p,rt.rating + (int(rt.rank) > 0 ? "  #" + rt.rank : ""),tx,y + 11,20,placed ? colour : UiKit.WHITE,
               UiKit.XBOLD);
            UiKit.text(p,placed ? "PEAK " + rt.peak : "PLACEMENT " + rt.games + "/" + PLACEMENT_GAMES,tx,y + 36,11,UiKit.GREY,
               UiKit.XBOLD);
            if(streak != null && streak.kind != null && int(streak.count) >= 2)
            {
               var win:Boolean = streak.kind == "win";
               UiKit.text(p,(win ? "WIN" : "LOSS") + " STREAK " + streak.count,tx,y + 50,11,win ? UiKit.TEAL : UiKit.RED,
                  UiKit.XBOLD);
            }
         }
         else
         {
            UiKit.text(p,"No rated games" + (season == 0 ? " this season." : " that season."),tx,y + 16,12,UiKit.GREY,
               UiKit.BOLD,w);
         }
      }

      private static function miniStats(p:Sprite, x:Number, y:Number, nums:Array) : void
      {
         for each(var n:Array in nums)
         {
            UiKit.text(p,n[0],x,y,MINI,UiKit.GREY,UiKit.XBOLD);
            if(n[2] != null)
            {
               record(p,n[2],x + 54,y,MINI,true);
            }
            else
            {
               UiKit.text(p,n[1],x + 54,y,MINI,UiKit.WHITE,UiKit.BOLD);
            }
            y += 18;
         }
      }

      private static const MINI:int = 13;

      private function moreNumbers(p:Sprite, x:Number, y:Number, data:Object, ladder:String) : Number
      {
         var t:Object = data.totals || {};
         var n:int = int(t.matches);
         var colW:Number = SHOW_W / 4;
         if(n > 0)
         {
            UiKit.text(p,"PER GAME",x,y,11,UiKit.GREY,UiKit.XBOLD);
            var per:Array = [["KOS",Number(t.kos) / n,1],["FALLS",Number(t.falls) / n,1],["DAMAGE",Number(t.damage_dealt) / n,0],
               ["TAKEN",Number(t.damage_taken) / n,0]];
            for(var k:int = 0; k < per.length; k++)
            {
               UiKit.text(p,per[k][0],x + k * colW,y + 14,10,UiKit.GREY,UiKit.BOLD);
               UiKit.text(p,Number(per[k][1]).toFixed(per[k][2]),x + k * colW,y + 26,14,UiKit.WHITE,UiKit.BOLD);
            }
            y += 50;
         }
         var others:Array = [];
         for each(var l:String in ["1v1","2v2","3v3"])
         {
            if(l != ladder && data.ratings != null && data.ratings[l] != null)
            {
               others.push(l);
            }
         }
         if(others.length > 0)
         {
            UiKit.text(p,"OTHER LADDERS",x,y,11,UiKit.GREY,UiKit.XBOLD);
            for(k = 0; k < others.length; k++)
            {
               var rt:Object = data.ratings[others[k]];
               var placed:Boolean = int(rt.games) >= PLACEMENT_GAMES;
               var tier:String = rt.tier ? String(rt.tier) : "Unranked";
               var colour:uint = placed && TIER_COLOURS[tier] != null ? uint(TIER_COLOURS[tier]) : UiKit.LIGHT;
               var ox:Number = x + k * (SHOW_W / 3);
               put(p,tierBanner(tier,24,placed ? int(rt.rating) : 0),ox,y + 15);
               UiKit.text(p,String(others[k]).toUpperCase(),ox + 28,y + 14,10,UiKit.GREY,UiKit.BOLD);
               UiKit.text(p,placed ? String(rt.rating) : int(rt.games) + "/" + PLACEMENT_GAMES,ox + 28,y + 26,14,colour,UiKit.BOLD);
            }
            y += 50;
         }
         return y;
      }

      private function lastMatches(p:Sprite, y:Number, bottom:Number, recent:Array, account:int) : Number
      {
         if(y > bottom - 34)
         {
            return y;
         }
         UiKit.text(p,"LAST MATCHES",20,y,11,UiKit.GREY,UiKit.XBOLD);
         y += 16;
         if(recent.length == 0)
         {
            UiKit.text(p,"No ranked match" + (season == 0 ? " this season yet." : " that season."),20,y,12,UiKit.LIGHT,
               UiKit.MEDIUM);
            return y + 18;
         }
         for(var i:int = 0; i < recent.length && y < bottom - 20; i++)
         {
            var m:Object = recent[i];
            var me:Object = null;
            for each(var pl:Object in m.players)
            {
               if(int(pl.account) == account)
               {
                  me = pl;
               }
            }
            var outcome:String = me != null && me.outcome != null ? String(me.outcome).toUpperCase() : "-";
            var colour:uint = outcome == "WIN" ? UiKit.TEAL : (outcome == "LOSS" ? UiKit.RED : UiKit.LIGHT);
            if(me != null && me.legend)
            {
               put(p,legendIcon(int(me.legend),18),20,y);
            }
            UiKit.text(p,outcome,42,y,12,colour,UiKit.XBOLD);
            UiKit.text(p,delta(m.team_rating != null ? m.team_rating : me),80,y,12,colour,UiKit.XBOLD);
            var ago:Object = UiKit.text(p,since(Number(m.time)),0,y,12,UiKit.GREY,UiKit.MEDIUM);
            ago.x = COL_W + 4 - ago.width;
            if(opponents(m,me,account).length > 1)
            {
               var lastY:Number = opponentsAt(p,m,me,account,42,y + 17,COL_W - 42,2);
               y = lastY + 23;
            }
            else
            {
               opponentsAt(p,m,me,account,116,y,COL_W - 116 - ago.width - 6);
               y += 21;
            }
         }
         return y;
      }

      private function opponentsAt(p:Sprite, m:Object, me:Object, account:int, x:Number, y:Number, w:Number,
                                   perLine:int = 0) : Number
      {
         var others:Array = opponents(m,me,account);
         var left:Number = x;
         var end:Number = x + w;
         var vs:TextField = UiKit.text(p,"vs",x,y,12,UiKit.GREY,UiKit.MEDIUM);
         x += vs.textWidth + 8;
         left = x;
         if(others.length == 0)
         {
            UiKit.text(p,"?",x,y,12,UiKit.LIGHT,UiKit.MEDIUM);
            return y;
         }
         var cols:int = perLine > 0 ? perLine : others.length;
         var room:Number = (end - left) / cols;
         for(var i:int = 0; i < others.length; i++)
         {
            if(i > 0 && i % cols == 0)
            {
               x = left;
               y += 19;
            }
            var start:Number = x;
            if(int(others[i].legend) > 0)
            {
               put(p,legendIcon(int(others[i].legend),16),x,y + 1);
               x += 19;
            }
            var t:TextField = UiKit.fit(UiKit.text(p,String(others[i].name) + (i < others.length - 1 ? " &" : ""),x,y,12,
               UiKit.LIGHT,UiKit.MEDIUM),Math.max(30,room - (x - start) - 4));
            x += t.width + 6;
         }
         return y;
      }

      private static function opponents(m:Object, me:Object, account:int) : Array
      {
         var others:Array = [];
         for each(var pl:Object in m.players)
         {
            var other:Boolean = me != null && me.team != null && int(me.team) != 0 ? int(pl.team) != int(me.team) :
               int(pl.account) != account;
            if(other)
            {
               others.push(pl);
            }
         }
         return others;
      }

      private function graph(p:Sprite, x:Number, y:Number, w:Number, h:Number, points:Array) : void
      {
         var lo:Number = Number.MAX_VALUE;
         var hi:Number = -Number.MAX_VALUE;
         for each(var v:Number in points)
         {
            lo = Math.min(lo,v);
            hi = Math.max(hi,v);
         }
         if(hi - lo < 20)
         {
            hi = lo + 20;
         }
         UiKit.rect(p,x,y,w,h,UiKit.BODY,4);
         var line:Shape = new Shape();
         line.graphics.lineStyle(2,points[points.length - 1] >= points[0] ? UiKit.TEAL : UiKit.RED);
         for(var i:int = 0; i < points.length; i++)
         {
            var px:Number = x + 4 + (w - 8) * i / (points.length - 1);
            var py:Number = y + h - 4 - (h - 8) * (Number(points[i]) - lo) / (hi - lo);
            if(i == 0)
            {
               line.graphics.moveTo(px,py);
            }
            else
            {
               line.graphics.lineTo(px,py);
            }
         }
         p.addChild(line);
         UiKit.text(p,String(Math.round(hi)),x + w + 2,y - 2,9,UiKit.GREY,UiKit.BOLD);
         UiKit.text(p,String(Math.round(lo)),x + w + 2,y + h - 12,9,UiKit.GREY,UiKit.BOLD);
      }

      private function buildRecent() : void
      {
         var left:Sprite = panel(area.x,area.y,area.width,area.height);
         var got:Object = PrivateServer.host != null ? ServerStats.get(recentQuery()) : null;
         var matches:Array = got != null ? got.matches as Array : null;
         if(matches == null || matches.length == 0)
         {
            UiKit.text(left,got == null ? (PrivateServer.host == null ? "Offline." : "Asking the server...") :
               (search != "" ? "No ranked match with a player named like \"" + search + "\"." : "No ranked matches yet."),
               24,14,14,UiKit.LIGHT,UiKit.MEDIUM);
            return;
         }
         var list:Sprite = scroller(left,0,8,area.width,area.height - 14);
         var w:Number = area.width - 20;
         var rh:Number = 92;
         for(var n:int = 0; n < matches.length; n++)
         {
            var m:Object = matches[n];
            var s:Sprite = new Sprite();
            s.y = n * (rh + 6);
            list.addChild(s);
            UiKit.rect(s,10,0,w,rh,UiKit.BODY,4);
            var thumb:Bitmap = mapThumb(m,140,79);
            if(thumb != null)
            {
               put(s,thumb,16,6);
            }
            else
            {
               UiKit.rect(s,16,6,140,79,UiKit.PANEL,4);
            }
            var head:Object = UiKit.fit(UiKit.text(s,mapName(m),170,6,15,UiKit.WHITE,UiKit.BOLD),380);
            var when:String = since(Number(m.time)) + " ago" + (Number(m.duration) > 0 ? "   " + clock(Number(m.duration)) : "");
            UiKit.text(s,when.toUpperCase(),head.x + head.width + 18,9,12,UiKit.GREY,UiKit.XBOLD);
            if(m.replay)
            {
               UiKit.rect(s,w - 112,6,108,20,UiKit.TEAL,4);
               UiKit.text(s,"WATCH REPLAY",w - 58,8,11,UiKit.NAVY_TEXT,UiKit.XBOLD,0,true);
            }
            else
            {
               UiKit.text(s,"NO REPLAY",w - 58,8,11,UiKit.GREY,UiKit.XBOLD,0,true);
            }
            var players:Array = (m.players as Array || []).concat();
            players.sortOn(["team","place"],[Array.NUMERIC,Array.NUMERIC]);
            var sides:int = 0;
            var last:Object = null;
            for each(var pl:Object in players)
            {
               if(last == null || pl.team != last.team)
               {
                  sides++;
               }
               last = pl;
            }
            var gap:Number = 34;
            var cell:Number = Math.min(330,(w - 174 - gap * Math.max(0,sides - 1)) / Math.max(2,players.length));
            var x:Number = 170;
            last = null;
            for each(pl in players)
            {
               if(last != null && pl.team != last.team)
               {
                  UiKit.text(s,"VS",x + gap / 2 - 18,52,12,UiKit.GREY,UiKit.XBOLD,0,true);
                  x += gap;
               }
               last = pl;
               var colour:uint = pl.outcome == "win" ? UiKit.TEAL : (pl.outcome == "loss" ? UiKit.RED : UiKit.WHITE);
               put(s,legendIcon(int(pl.legend),44),x,36);
               UiKit.fit(UiKit.text(s,String(pl.name),x + 50,32,13,UiKit.WHITE,UiKit.BOLD),cell - 58);
               var d:Object = UiKit.text(s,delta(pl),x + 50,50,12,colour,UiKit.XBOLD);
               if(pl.rating_after != null)
               {
                  var tier:String = pl.tier_after ? String(pl.tier_after) : null;
                  var tx:Number = d.x + d.width + 6;
                  if(tier != null)
                  {
                     put(s,tierBanner(tier,16,tier != "Unranked" ? int(pl.rating_after) : 0),tx,49);
                     tx += 18;
                  }
                  var ra:Object = UiKit.text(s,String(pl.rating_after),tx,50,12,UiKit.WHITE,UiKit.BOLD);
                  if(tier != null)
                  {
                     var changed:Boolean = pl.tier_before && String(pl.tier_before) != tier;
                     var up:Boolean = changed && int(pl.rating_after) > int(pl.rating_before);
                     var tierColour:uint = TIER_COLOURS[tier] != null ? uint(TIER_COLOURS[tier]) : UiKit.GREY;
                     UiKit.fit(UiKit.text(s,rankName(tier,int(pl.rating_after)),ra.x + ra.width + 5,50,12,
                        changed ? (up ? UiKit.TEAL : UiKit.RED) : tierColour,UiKit.XBOLD),
                        Math.max(20,x + cell - 8 - ra.x - ra.width - 5));
                  }
               }
               UiKit.fit(UiKit.text(s,int(pl.kos) + " KO  " + int(pl.falls) + " FALLS  " + int(pl.damage_dealt) + " DMG",x + 50,68,
                  10,UiKit.GREY,UiKit.XBOLD),cell - 58);
               x += cell;
            }
            items.push({"w":"match " + m.id,"sprite":s,"parent":list,"width":w,"height":rh,"focusBox":[10,0,w,rh],
               "use":watcher(m)});
         }
      }

      private function watcher(m:Object) : Function
      {
         var self:LeaderboardWindow = this;
         return function():void
         {
            if(!m.replay)
            {
               DummyDrift.show("The server keeps no replay of that match.",2500);
               return;
            }
            BackTrail.leaving("replay");
            ReplayShare.fetch(uint(m.room),uint(m.seed),true);
         };
      }

      private function clearDolls() : void
      {
         for each(var d:Object in dolls)
         {
            try
            {
               d.method_5548();
            }
            catch(e:Error)
            {
            }
         }
         dolls = [];
         toFit = [];
      }

      private function doll(parent:Sprite) : PaperDoll
      {
         var d:PaperDoll = new PaperDoll(owner != null ? owner : ScreenManager.owner,new MovieClip(),null,0,0,null,1);
         parent.addChild(d.var_219);
         dolls.push(d);
         return d;
      }

      override protected function everyFrame() : void
      {
         for(var i:int = toFit.length - 1; i >= 0; i--)
         {
            var f:Object = toFit[i];
            var group:Sprite = f.group;
            var hb:Rectangle = DisplayObject(f.hero).getBounds(group);
            if(hb.height <= 0 || hb.width <= 0)
            {
               continue;
            }
            var w:Number = Number(f.width);
            var h:Number = Number(f.height);
            var sc:Number = Math.min((h - 6) / SHOWCASE_REF,(w - 8) / hb.width,(h - 6) / hb.height);
            group.scaleX = group.scaleY = sc;
            group.x = w / 2 - (hb.x + hb.width / 2) * sc;
            group.y = h - (hb.y + hb.height) * sc;
            group.visible = true;
            toFit.splice(i,1);
         }
      }

      private function showcase(prof:Object, x:Number, y:Number, w:Number, h:Number) : void
      {
         var hero:HeroType = int(prof.legend) > 0 ? HeroType.method_7110(uint(prof.legend)) : null;
         if(hero == null || h < 40)
         {
            return;
         }
         var stage:Sprite = new Sprite();
         stage.x = x;
         stage.y = y;
         detail.addChild(stage);
         var clipMask:Shape = new Shape();
         clipMask.graphics.beginFill(0);
         clipMask.graphics.drawRect(0,0,w,h);
         clipMask.graphics.endFill();
         stage.addChild(clipMask);
         var group:Sprite = new Sprite();
         group.mask = clipMask;
         group.visible = false;
         stage.addChild(group);
         try
         {
            var costume:CostumeType = int(prof.costume) > 0 && CostumeType.var_12721 != null ?
               CostumeType.var_12721[int(prof.costume)] as CostumeType : null;
            if(costume == null || costume.var_7289 != hero)
            {
               costume = hero.var_10527;
            }
            var colour:class_76 = int(prof.colour) > 0 && class_76.var_12696 != null ? class_76.var_12696[int(prof.colour)] as
               class_76 : null;
            if(colour == null)
            {
               colour = class_76.NO_COLOR_SCHEME;
            }
            var heroHolder:Sprite = new Sprite();
            group.addChild(heroHolder);
            var hd:PaperDoll = doll(heroHolder);
            hd.method_5191(0,0,1);
            hd.method_4082();
            PaperDoll.method_5580(costume,colour,hero,costume.var_15258,hd,PaperDoll.method_4400(hero,costume),null,null);
            hd.method_4082();
            hd.method_9137();
            toFit.push({"group":group,"hero":heroHolder,"width":w,"height":h});
         }
         catch(e:Error)
         {
            PrivateServer.log("leaderboard: showcase not drawn (" + e.message + ")");
         }
      }

      private static function putIcon(parent:Sprite, icon:Sprite, x:Number, y:Number) : void
      {
         if(icon != null)
         {
            icon.x = x;
            icon.y = y;
            parent.addChild(icon);
         }
      }

      private static function put(parent:Sprite, bm:Bitmap, x:Number, y:Number) : void
      {
         if(bm != null)
         {
            bm.x = x;
            bm.y = y;
            parent.addChild(bm);
         }
      }

      private static function picture(key:String, size:int, make:Function) : Bitmap
      {
         var k:String = key + "@" + size;
         if(art[k] == null)
         {
            try
            {
               var clip:DisplayObject = make() as DisplayObject;
               if(clip != null)
               {
                  var holder:Sprite = new Sprite();
                  holder.addChild(clip);
                  var b:Rectangle = clip.getBounds(holder);
                  var first:DisplayObject = clip is MovieClip && MovieClip(clip).numChildren > 0 ?
                     MovieClip(clip).getChildAt(0) : null;
                  if(b.width > 0 && b.height > 0 && !(first is Bitmap && class_687.method_3680(Bitmap(first))))
                  {
                     var px:int = size * 2;
                     var sc:Number = Math.min(px / b.width,px / b.height);
                     var m:Matrix = new Matrix(sc,0,0,sc,-b.x * sc + (px - b.width * sc) / 2,-b.y * sc + (px - b.height * sc) / 2);
                     var bd:BitmapData = new BitmapData(px,px,true,0);
                     bd.draw(clip,m,null,null,null,true);
                     art[k] = bd;
                  }
               }
               if(art[k] == null)
               {
                  waitingArt = true;
               }
            }
            catch(e:Error)
            {
               PrivateServer.log("leaderboard: no picture for " + key + " (" + e.message + ")");
            }
         }
         if(art[k] == null)
         {
            return null;
         }
         var bm:Bitmap = new Bitmap(art[k] as BitmapData);
         bm.smoothing = true;
         bm.scaleX = bm.scaleY = 0.5;
         return bm;
      }

      public static function tierBanner(tier:String, size:int, rating:int = 0) : Bitmap
      {
         var path:String = "images/UI/RankedBanner" + tier + ".png";
         var notch:int = notchOf(tier,rating);
         return picture("tier " + tier + (notch >= 0 ? " notch " + notch : ""),size,function():DisplayObject
         {
            var bm:Bitmap = class_51.method_782(path,true);
            if(bm == null && !(path in asked))
            {
               asked[path] = true;
               ArchiveLoader.method_7065("LevelArt");
               ArchiveLoader.method_21(path,"LevelArt");
            }
            tierArtState = path + (bm != null ? " loaded" : " loading");
            return bm != null && notch >= 0 ? withNotches(bm,notch) : bm;
         });
      }

      public static function rankName(tier:String, rating:int) : String
      {
         var n:int = tier == "Valhallan" || tier == "Unranked" ? 0 : Ranks.tierNumber(rating);
         return n > 0 ? tier + " " + n : tier;
      }

      private static const NOTCHED:Object = {"Tin":true,"Bronze":true,"Silver":true,"Gold":true,"Platinum":true};

      private static function notchOf(tier:String, rating:int) : int
      {
         if(rating < 0 || !NOTCHED[tier])
         {
            return -1;
         }
         rating = Math.max(1,rating);
         try
         {
            var stars:uint = class_189.method_5563(uint(rating));
            return class_700.method_6508(stars) ? -1 : int(class_189.method_1542(stars));
         }
         catch(e:Error)
         {
         }
         return -1;
      }

      private static function withNotches(banner:Bitmap, notch:int) : DisplayObject
      {
         var holder:Sprite = new Sprite();
         var b:Bitmap = new Bitmap(banner.bitmapData);
         b.smoothing = true;
         b.scaleX = b.scaleY = 149 / banner.bitmapData.width;
         holder.addChild(b);
         if(!ApplicationDomain.currentDomain.hasDefinition("a_UIRank2"))
         {
            class_687.method_1714("a_UIRank2","UI_1");
            return null;
         }
         try
         {
            var rank:MovieClip = class_687.method_1714("a_UIRank2","UI_1");
            var inner:MovieClip = rank != null ? rank.getChildByName("am_PanelInternal") as MovieClip : null;
            var notches:MovieClip = inner != null ? inner.getChildByName("am_Notches") as MovieClip : null;
            if(notches != null)
            {
               notches.gotoAndStop("Notch" + notch);
               notches.stopAllMovieClips();
               notches.visible = true;
               notches.x = 80.9 - 7.2;
               notches.y = 99.6 + 4.3;
               holder.addChild(notches);
            }
         }
         catch(e:Error)
         {
            PrivateServer.log("leaderboard: no notches (" + e.message + ")");
         }
         return holder;
      }

      private static var asked:Object = {};

      public static function legendIcon(id:int, size:int) : Bitmap
      {
         var hero:HeroType = id > 0 ? HeroType.method_7110(uint(id)) : null;
         if(hero == null || !hero.var_12260)
         {
            return null;
         }
         var name:String = hero.var_12260 + "M";
         var file:String = hero.var_6330;
         return picture("roster " + name,size,function():DisplayObject
         {
            var clip:MovieClip = class_687.method_1714(name,file);
            if(clip != null)
            {
               clip.gotoAndStop(1);
               clip.stopAllMovieClips();
            }
            return clip;
         });
      }

      internal static function avatar(id:int, size:int) : Bitmap
      {
         var type:Object = id > 0 && class_16.var_3275 != null ? class_16.var_3275[id] : null;
         if(type == null)
         {
            type = class_16.var_13871;
         }
         if(type == null)
         {
            return null;
         }
         return picture("avatar " + type.var_9656,size,function():DisplayObject
         {
            var clip:MovieClip = type.method_7036() as MovieClip;
            UiKit.gotoLabel(clip,"Ready");
            if(clip != null)
            {
               clip.stopAllMovieClips();
            }
            return clip;
         });
      }

      public static function legendName(id:int, fallback:Object = null) : String
      {
         var hero:HeroType = id > 0 ? HeroType.method_7110(uint(id)) : null;
         if(hero != null && hero.var_4421)
         {
            return String(hero.var_4421);
         }
         return fallback ? String(fallback).replace(/([a-z])([A-Z])/g,"$1 $2") : "Legend " + id;
      }

      private static function localized(key:Object) : String
      {
         try
         {
            return key ? class_256.method_2800(String(key)) : null;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private static function moniker(id:int) : Object
      {
         try
         {
            return id > 0 && class_279.var_369 != null ? class_279.var_369.method_4935(id) : null;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      internal static function monikerName(id:int) : String
      {
         var t:Object = moniker(id);
         return t != null ? localized(t.mDisplayNameKey) : null;
      }

      internal static function monikerColour(id:int) : uint
      {
         var t:Object = moniker(id);
         return t != null && uint(t.var_11356) != 0 ? uint(t.var_11356) : UiKit.TEAL;
      }

      private static function day(t:Number) : String
      {
         if(!(t > 0))
         {
            return "";
         }
         var d:Date = new Date(t * 1000);
         return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
      }

      private static function pad(n:int) : String
      {
         return n < 10 ? "0" + n : String(n);
      }

      public static function mapName(m:Object) : String
      {
         var level:LevelType = mapLevel(m);
         if(level != null && level.mDisplayName)
         {
            return level.mDisplayName;
         }
         return m.map ? String(m.map).replace(/([a-z])([A-Z])/g,"$1 $2") : "Unknown map";
      }

      private static function mapLevel(m:Object) : LevelType
      {
         try
         {
            return m.map ? LevelType.method_2845(String(m.map)) : null;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      public static function mapThumb(m:Object, w:int, h:int) : Bitmap
      {
         var path:String = null;
         var name:String = m.map ? String(m.map) : "";
         var base:String = name.replace(/^(Small|Big)/,"");
         for each(var n:String in [name,base,"Big" + base,"Small" + base])
         {
            var level:LevelType = mapLevel({"map":n});
            if(level != null && level.var_14988 && level.var_14988.indexOf("testmap") < 0)
            {
               path = level.var_14988;
               break;
            }
         }
         if(!path)
         {
            return null;
         }
         var k:String = "map " + path + "@" + w + "x" + h;
         if(art[k] == null)
         {
            try
            {
               var src:Bitmap = class_51.method_782(path,true);
               if(src == null || src.bitmapData == null)
               {
                  if(!(path in asked))
                  {
                     asked[path] = true;
                     ArchiveLoader.method_7065("LevelArt");
                     ArchiveLoader.method_21(path,"LevelArt");
                  }
                  waitingArt = true;
                  return null;
               }
               var sc:Number = Math.max(w * 2 / src.bitmapData.width,h * 2 / src.bitmapData.height);
               var bd:BitmapData = new BitmapData(w * 2,h * 2,false,0);
               bd.draw(src.bitmapData,new Matrix(sc,0,0,sc,(w * 2 - src.bitmapData.width * sc) / 2,
                  (h * 2 - src.bitmapData.height * sc) / 2),null,null,null,true);
               art[k] = bd;
            }
            catch(e:Error)
            {
               PrivateServer.log("leaderboard: no thumbnail for " + path + " (" + e.message + ")");
               return null;
            }
         }
         var bm:Bitmap = new Bitmap(art[k] as BitmapData);
         bm.smoothing = true;
         bm.scaleX = bm.scaleY = 0.5;
         return bm;
      }

      private static function delta(pl:Object) : String
      {
         if(pl == null || pl.rating_before == null || pl.rating_after == null)
         {
            return "";
         }
         var d:int = int(pl.rating_after) - int(pl.rating_before);
         return (d >= 0 ? "+" : "") + d;
      }

      private static function since(t:Number) : String
      {
         if(!(t > 0))
         {
            return "";
         }
         var s:Number = Math.max(0,new Date().time / 1000 - t);
         if(s < 3600)
         {
            return Math.max(1,Math.floor(s / 60)) + "m";
         }
         if(s < 86400)
         {
            return Math.floor(s / 3600) + "h";
         }
         return s < 86400 * 14 ? Math.floor(s / 86400) + "d" : Math.floor(s / (86400 * 7)) + "w";
      }

      private static function clock(ms:Number) : String
      {
         var sec:int = int(ms / 1000);
         return int(sec / 60) + ":" + pad(sec % 60);
      }

      private static function stat(p:Sprite, x:Number, y:Number, label:String, value:String) : void
      {
         UiKit.text(p,label,x,y,11,UiKit.GREY,UiKit.XBOLD);
         UiKit.text(p,value,x,y + 14,18,UiKit.WHITE,UiKit.BOLD);
      }

      private static function record(p:Sprite, r:Object, x:Number, y:Number, size:int, strong:Boolean = false) : void
      {
         if(size >= 18)
         {
            strong = true;
         }
         var wins:Object = UiKit.text(p,int(r.wins) + "-",x,y,size,strong ? UiKit.WHITE : UiKit.LIGHT,strong ? UiKit.BOLD :
            UiKit.MEDIUM);
         UiKit.text(p,String(int(r.losses)) + (int(r.draws) > 0 ? "-" + int(r.draws) : ""),x + wins.width - 4,y,size,UiKit.RED,
            strong ? UiKit.BOLD : UiKit.MEDIUM);
      }

      private static function percent(r:Object) : String
      {
         return int(r.matches) > 0 ? Math.round(Number(r.wins) * 100 / int(r.matches)) + "%" : "-";
      }
   }
}
