package bh.mods.lobbyscreen
{
   import bh.platform.GameMenus;
   import bh.platform.LeaderboardWindow;
   import bh.platform.ModSettings;
   import bh.platform.OnlineTraining;
   import bh.platform.SettingsWindow;
   import bh.platform.UiKit;
   import bh.platform.net.PrivateServer;
   import bh.platform.net.RoomNet;
   import flash.display.Bitmap;
   import flash.display.MovieClip;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.events.MouseEvent;
   import flash.text.TextField;
   import flash.utils.Dictionary;

   public class LobbySettingsScreen extends SettingsWindow
   {
      private static const TABS:Array = ["GAME RULES","LOBBY","PRESETS","NETWORK"];

      public static var current:LobbySettingsScreen;
      public static var closing:Boolean = false;

      private var presetAt:int = 0;
      private static const COLS:int = 3;
      private static const GRID_W:Number = 14 + COLS * 106;
      private var modeCursor:int = -1;

      public function LobbySettingsScreen(core:GameCore)
      {
         super(core);
      }

      override protected function get title() : String
      {
         return "LOBBY SETTINGS";
      }

      override protected function get gameMenu() : String
      {
         return GameMenus.LOBBY;
      }

      override protected function get tabNames() : Array
      {
         return TABS;
      }

      override protected function optionTabs() : Array
      {
         return [0,1];
      }

      override protected function statusText() : String
      {
         return tab == 3 ? (canEdit() ? "The room's settings apply to everyone from the next match. Connection is just yours." :
            "Only the host can change the room's settings. Connection is just yours.") :
            (canEdit() ? "Changes apply when you confirm." : "Only the room's host can change these.");
      }

      override public function OnCreateScreen() : void
      {
         current = this;
         var locked:Boolean = rankedLobby();
         if(locked && (tab == 0 || tab == 2))
         {
            tab = 1;
         }
         super.OnCreateScreen();
         if(locked)
         {
            var layout:Array = tabLayout;
            var k:int = 0;
            for(var i:int = 0; i < tabClips.length; i++)
            {
               tabClips[i].visible = i != 0 && i != 2;
               if(tabClips[i].visible)
               {
                  tabClips[i].x = layout[0] + k * layout[1];
                  k++;
               }
            }
         }
      }

      private function banThumb(list:Sprite, w:Object, width:Number, y:Number) : void
      {
         var name:String = optionName(w);
         if(name != "Lobby_BanLevel" && name != "Lobby_BanLevel2")
         {
            return;
         }
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var pl:Object = core.var_6244.var_2390;
            var ev:Object = pl != null ? core.method_7678(pl.var_8356) : null;
            var level:Object = ev != null ? LevelType.var_3683[name == "Lobby_BanLevel" ? ev.var_1343 : ev.var_9762] : null;
            if(level == null)
            {
               return;
            }
            var pic:Bitmap = LeaderboardWindow.mapThumb({"map":level.var_5173},48,27);
            if(pic != null)
            {
               pic.x = width - 56;
               pic.y = y + 1;
               list.addChild(pic);
            }
         }
         catch(e:Error)
         {
         }
      }

      private static function rankedLobby() : Boolean
      {
         try
         {
            var pl:Object = Object(GameApp.mainInstance).var_13259.var_6244.var_2390;
            return pl != null && Boolean(pl.var_9135);
         }
         catch(e:Error)
         {
         }
         return false;
      }

      override protected function tabOff(i:int) : Boolean
      {
         if((i == 0 || i == 2) && rankedLobby())
         {
            return true;
         }
         return super.tabOff(i);
      }

      override protected function close(apply:Boolean) : void
      {
         closing = true;
         super.close(apply);
         closing = false;
      }

      override protected function tick() : Boolean
      {
         if(applying != null)
         {
            stepApply();
            return true;
         }
         return false;
      }

      override protected function buildTab(i:int) : void
      {
         switch(i)
         {
            case 0:
               buildRules();
               break;
            case 1:
               buildLobby();
               break;
            case 2:
               buildPresets();
               break;
            default:
               buildNetwork();
         }
      }

      override protected function showTab(i:int) : void
      {
         if(i != tab)
         {
            modeCursor = -1;
         }
         super.showTab(i);
      }

      override protected function backKey() : void
      {
         if(tab == 0 && focus > 0 && items.length > 0 && items[0].kind == "modes")
         {
            focus = 0;
            paintFocus();
            return;
         }
         super.backKey();
      }

      override protected function itemAction(it:Object, dir:int) : Boolean
      {
         if(it.kind == "modes")
         {
            if(dir == 0)
            {
               var icons:Object = it.w.var_11509;
               if(icons != null && modeCursor >= 0 && modeCursor < int(icons.length))
               {
                  pickIcon(it.w,icons[modeCursor]);
               }
            }
            else
            {
               moveModeCursor(it,modeCursor + dir);
            }
            return true;
         }
         if(it.kind == "network")
         {
            it.act(dir == 0 ? 1 : dir);
            build();
            return true;
         }
         if(it.kind == "preset")
         {
            if(dir == 0)
            {
               apply(presets()[it.index]);
            }
            else
            {
               presetAt = Math.max(0,presetAt + dir);
               build();
            }
            return true;
         }
         return false;
      }

      override protected function moveIn(it:Object, dir:int) : Boolean
      {
         if(it.kind != "modes" || it.tiles == null)
         {
            return false;
         }
         var to:int = modeCursor + dir * COLS;
         if(dir > 0 && to >= it.tiles.length && int(modeCursor / COLS) < int((it.tiles.length - 1) / COLS))
         {
            to = it.tiles.length - 1;
         }
         if(to < 0 || to >= it.tiles.length)
         {
            return false;
         }
         moveModeCursor(it,to);
         return true;
      }

      private function tilePicker(w:Object, icon:Object, index:int) : Function
      {
         var pick:Function = iconPicker(w,icon);
         return function(e:MouseEvent):void
         {
            modeCursor = index;
            pick(e);
         };
      }

      private function moveModeCursor(it:Object, to:int) : void
      {
         var tiles:Array = it.tiles as Array;
         if(tiles == null || tiles.length == 0)
         {
            return;
         }
         modeCursor = Math.max(0,Math.min(tiles.length - 1,to));
         var tile:Sprite = tiles[modeCursor];
         describeCursorMode(it);
         it.cursor.x = tile.x;
         it.cursor.y = tile.y;
         var sc:Object = it.gridScroller;
         if(sc != null)
         {
            if(tile.y - 4 < -sc.content.y)
            {
               sc.scrollTo(tile.y - 4);
            }
            else if(tile.y + 72 > -sc.content.y + sc.height)
            {
               sc.scrollTo(tile.y + 72 - sc.height);
            }
         }
      }

      private function modeWidget() : Object
      {
         var scoring:Object = null;
         for each(var w:Object in widgets(0))
         {
            if(optionName(w) == "Game_TrainingGameModeType" && w.var_3713)
            {
               trainingModes = true;
               return w;
            }
            if(optionName(w) == "Game_ScoringType")
            {
               scoring = w;
            }
         }
         trainingModes = false;
         return scoring;
      }

      private static var trainingModes:Boolean = false;

      private function instruction() : Object
      {
         for each(var w:Object in widgets(0))
         {
            if(kindOf(w) == "Instruction")
            {
               return w;
            }
         }
         return null;
      }

      private static function scoringFor(modeIcon:Object) : Object
      {
         try
         {
            if(trainingModes && !(modeIcon is String))
            {
               var gm:Object = class_163.var_13378[uint(modeIcon.var_6750)];
               if(gm != null)
               {
                  return gm;
               }
            }
            var iconName:String = modeIcon is String ? String(modeIcon) : String(modeIcon.var_2697);
            var byId:Object = modeIcon is String ? null : ScoringType.var_11920[uint(modeIcon.var_6750)];
            if(byId != null && byId.var_2697 == iconName)
            {
               return byId;
            }
            for each(var st:Object in ScoringType.var_11790)
            {
               if(st != null && st.var_2697 == iconName)
               {
                  return st;
               }
            }
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private static const RULE_SECTIONS:Array = [
         [["MODE",["Game_Variation","Game_AltMode","Game_CrewBattleCycle"]],
          ["MATCH",["Game_NumLives","Game_GameDuration","Game_RoundDuration","Game_ScoreToWin","Game_DamageMult"]],
          ["TEAMS",["Game_TeamsToggle","Game_TeamDamage","Game_MaxPlayers"]]],
         [["UI_GameSettings_Gadgets_And_Weapons",["Game_AlwaysHaveItemSelect","Game_GadgetsSelectionsAlwaysEquipRandom",
            "Game_GadgetsSelectionsAlwaysEquipSingle","Game_WeaponSpawnRate","Game_GadgetSpawnRate","Game_GadgetsSelections"]],
          ["MAPS",["Game_MapSet","Game_TestMapsToggle"]],
          ["TESTING",["Game_TestFeaturesToggle"]]]];

      private static const LOBBY_SECTIONS:Array = [
         [["ROOM",["Lobby_Mode","Lobby_CustomGameType","Lobby_Playlist","Lobby_BotMatch"]],
          ["WHO CAN JOIN",["Lobby_Privacy","Lobby_FriendsToggle","Lobby_ClanmateToggle","Lobby_PasswordToggle",
             "Lobby_Description"]]],
         [["MAPS",["Lobby_MapSelectionMode","Lobby_CompetitiveLevels","Lobby_BanLevel","Lobby_BanLevel2"]],
          ["PICKS",["Lobby_BlindPickToggle","Lobby_BanGadgets","Lobby_Handicaps"]]]];

      private static const HIDDEN:Array = ["Lobby_Region"];

      private static const LABELS:Object = {"Game_WeaponSpawnRate":"WEAPON SPAWNS","Game_GadgetSpawnRate":"GADGET SPAWNS"};

      private static const ABOUT:Object = {
         "Game_Variation":"A twist on the mode, picked from its icons.",
         "Game_AltMode":"The mode's rule set.",
         "Game_CrewBattleCycle":"Crew Battle: whether the next crew member comes in after each stock lost or after each player is out.",
         "Game_NumLives":"Stocks each player (or team) starts with.",
         "Game_GameDuration":"How long the match lasts at most.",
         "Game_RoundDuration":"How long each round lasts.",
         "Game_ScoreToWin":"The score that wins the match.",
         "Game_DamageMult":"How much damage every hit does, compared to normal.",
         "Game_TeamsToggle":"Play in teams instead of everyone for themselves.",
         "Game_TeamDamage":"Whether hits hurt your own teammates.",
         "Game_MaxPlayers":"How many players the room takes.",
         "Game_AlwaysHaveItemSelect":"The item everyone has equipped.",
         "Game_GadgetsSelectionsAlwaysEquipRandom":"The gadgets handed out at random.",
         "Game_GadgetsSelectionsAlwaysEquipSingle":"The gadget everyone has.",
         "Game_WeaponSpawnRate":"How often weapons drop onto the map.",
         "Game_GadgetSpawnRate":"How often gadgets drop onto the map.",
         "Game_GadgetsSelections":"Which gadgets can drop. {Select} turns the focused one on or off.",
         "Game_MapSet":"Which maps can be played.",
         "Game_TestMapsToggle":"Adds the test maps to the maps that can be played.",
         "Game_TestFeaturesToggle":"Plays with the game's test features on.",
         "Lobby_Mode":"What kind of room this is.",
         "Lobby_CustomGameType":"Custom rules, or the Tournament 1v1 / 2v2 rules.",
         "Lobby_Playlist":"The room's playlist.",
         "Lobby_BotMatch":"A match against bots.",
         "Lobby_Privacy":"Public rooms show up in Browse Rooms. Private rooms need an invite or the room number.",
         "Lobby_FriendsToggle":"Your friends can join without an invite.",
         "Lobby_ClanmateToggle":"Your guildmates can join without an invite.",
         "Lobby_PasswordToggle":"Anyone with the room number can join.",
         "Lobby_Description":"The text shown with the room in Browse Rooms.",
         "Lobby_MapSelectionMode":"How the map of each match is picked.",
         "Lobby_CompetitiveLevels":"Only the tournament maps can be picked.",
         "Lobby_BanLevel":"A map that is never picked.",
         "Lobby_BanLevel2":"A second map that is never picked.",
         "Lobby_BlindPickToggle":"Players don't see each other's legends until the match starts.",
         "Lobby_BanGadgets":"Gadget bans before the match.",
         "Lobby_Handicaps":"Players may give themselves a handicap."};

      private var describe:TextField;
      private var describeLabel:TextField;

      private static function heading(key:String) : String
      {
         return key.indexOf("UI_") == 0 ? localized(key).toUpperCase() : key;
      }

      private function sectioned(tabIndex:int, layout:Array, skip:Function) : Array
      {
         var byName:Object = {};
         var shown:Array = [];
         for each(var w:Object in widgets(tabIndex))
         {
            if(w.var_3713 && !skip(w))
            {
               shown.push(w);
               byName[optionName(w)] = w;
            }
         }
         var out:Array = [];
         var placed:Dictionary = new Dictionary();
         for each(var sec:Array in layout)
         {
            var rows:Array = [];
            for each(var name:String in sec[1])
            {
               if(byName[name] != null)
               {
                  rows.push(byName[name]);
                  placed[byName[name]] = true;
               }
            }
            out.push([heading(sec[0]),rows]);
         }
         var more:Array = [];
         for each(var m:Object in shown)
         {
            if(!placed[m])
            {
               more.push(m);
            }
         }
         out.push(["MORE",more]);
         return out;
      }

      private function twoColumns(tabIndex:int, layout:Array, skip:Function) : Array
      {
         var left:Array = sectioned(tabIndex,layout[0],skip);
         left.pop();
         var right:Array = sectioned(tabIndex,layout[1],skip);
         right.pop();
         right.push(sectioned(tabIndex,layout[0].concat(layout[1]),skip).pop());
         return [left,right];
      }

      private function drawSections(list:Sprite, sections:Array, width:Number) : void
      {
         var y:Number = 0;
         for each(var s:Array in sections)
         {
            if(s[1].length == 0)
            {
               continue;
            }
            UiKit.text(list,s[0],6,y + 2,13,UiKit.GREY,UiKit.XBOLD);
            y += 24;
            for each(var r:Object in s[1])
            {
               var rowY:Number = y;
               y += row(list,r,0,y,width,null,LABELS[optionName(r)]) + 2;
               banThumb(list,r,width,rowY);
            }
            y += 6;
         }
      }

      private function describeBar(listHeight:Number) : void
      {
         var bar:Sprite = panel(area.x,area.y + listHeight + 6,area.width,42);
         describeLabel = UiKit.text(bar,"",14,4,14,UiKit.WHITE,UiKit.XBOLD);
         describe = UiKit.text(bar,"",14,22,13,UiKit.LIGHT,UiKit.MEDIUM);
      }

      private function showDescription(label:String, about:String) : void
      {
         if(describe == null)
         {
            return;
         }
         describeLabel.text = label != null ? label.toUpperCase() : "";
         describeText(describe,about != null ? about.replace(/\s+/g," ") : "");
         if(describe.visible)
         {
            UiKit.fit(describe,1030);
         }
      }

      override protected function focused(it:Object) : void
      {
         if(it.kind == "modes")
         {
            describeCursorMode(it);
         }
         else if(it.w != null)
         {
            showDescription(LABELS[optionName(it.w)] || labelOf(it.w),ABOUT[optionName(it.w)]);
         }
         else
         {
            showDescription("","");
         }
      }

      private function describeCursorMode(it:Object) : void
      {
         var icons:Object = it.w != null ? it.w.var_11509 : null;
         var st:Object = icons != null && modeCursor >= 0 && modeCursor < int(icons.length) ? scoringFor(icons[modeCursor]) : null;
         showDescription(st != null ? localized(st.mDisplayNameKey) : "",st != null && st.var_13223 ? localized(st.var_13223) : "");
      }

      private function buildRules() : void
      {
         describe = null;
         var listHeight:Number = area.height - 48;
         var mode:Object = modeWidget();
         var left:Sprite = panel(area.x,area.y,GRID_W,listHeight);
         var info:Object = instruction();
         var st2:Object = mode != null && mode.var_11509 != null && mode.var_11419 < mode.var_11509.length ?
            scoringFor(mode.var_11509[mode.var_11419]) : null;
         var picked:String = info != null ? textOf(info.var_8515) : (st2 != null ? localized(st2.mDisplayNameKey) : "");
         UiKit.fit(UiKit.text(left,"GAME MODE" + (picked != "" ? "  ·  " + picked.toUpperCase() : ""),12,8,14,UiKit.GREY,
            UiKit.XBOLD),GRID_W - 24);
         if(mode != null && mode.var_11509 != null)
         {
            var icons:Object = mode.var_11509;
            var tiles:Array = [];
            var grid:Sprite = 34 + Math.ceil(int(icons.length) / COLS) * 74 > listHeight ? scroller(left,0,30,GRID_W,listHeight - 34) : left;
            var gridY:Number = grid == left ? 34 : 4;
            for(var i:int = 0; i < int(icons.length); i++)
            {
               var icon:Object = icons[i];
               var tile:Sprite = new Sprite();
               tile.x = 10 + (i % COLS) * 106;
               tile.y = gridY + int(i / COLS) * 74;
               tile.buttonMode = canEdit();
               grid.addChild(tile);
               var on:Boolean = iconSelected(mode,icon);
               UiKit.rect(tile,0,0,100,68,on ? UiKit.TEAL : UiKit.LINE,8);
               UiKit.rect(tile,2,2,96,64,on ? UiKit.ROW_SELECTED : UiKit.BODY,8);
               var art:MovieClip = class_687.method_1714(icon.var_2697,"UI_GameSettings") ||
                  class_687.method_1714(ScoringType.TIMED.var_2697,"UI_GameSettings");
               if(art != null)
               {
                  UiKit.gotoLabel(art,on ? "Ready" : "Inactive");
               }
               UiKit.icon(tile,art,32,4,36);
               var st:Object = scoringFor(icon);
               UiKit.fit(UiKit.text(tile,st != null ? localized(st.mDisplayNameKey) : "",50,44,11,on ? UiKit.WHITE : UiKit.LIGHT,
                  UiKit.BOLD,0,true),94);
               tile.addEventListener(MouseEvent.CLICK,tilePicker(mode,icon,i));
               tiles.push(tile);
            }
            if(modeCursor < 0 || modeCursor >= tiles.length)
            {
               modeCursor = Math.min(tiles.length - 1,int(mode.var_11419));
            }
            var cursor:Shape = new Shape();
            cursor.graphics.lineStyle(3,UiKit.WHITE);
            cursor.graphics.drawRoundRect(-3,-3,106,74,12,12);
            cursor.visible = items.length == focus;
            grid.addChild(cursor);
            if(tiles.length > 0)
            {
               cursor.x = tiles[modeCursor].x;
               cursor.y = tiles[modeCursor].y;
            }
            if(grid != left)
            {
               scrollers[scrollers.length - 1].show = [gridY + int(modeCursor / COLS) * 74 - 4,
                                                       gridY + int(modeCursor / COLS) * 74 + 72];
            }
            items.push({"kind":"modes","w":mode,"sprite":left,"focusBox":[0,0,GRID_W,listHeight],"tiles":tiles,"cursor":cursor,
               "gridScroller":grid != left ? scrollers[scrollers.length - 1] : null});
         }
         var skip:Function = function(w:Object):Boolean
         {
            return kindOf(w) == "Instruction" || optionName(w) == "Game_ScoringType" || optionName(w) == "Game_TrainingGameModeType";
         };
         var colW:Number = (area.width - GRID_W - 20) / 2;
         var cols:Array = twoColumns(0,RULE_SECTIONS,skip);
         for(var c:int = 0; c < 2; c++)
         {
            var col:Sprite = panel(area.x + GRID_W + 10 + c * (colW + 10),area.y,colW,listHeight);
            drawSections(scroller(col,8,8,colW - 16,listHeight - 14),cols[c],colW - 16);
         }
         describeBar(listHeight);
      }

      private function buildLobby() : void
      {
         describe = null;
         var listHeight:Number = area.height - 48;
         var skip:Function = function(w:Object):Boolean
         {
            return kindOf(w) == "Instruction" || HIDDEN.indexOf(optionName(w)) >= 0;
         };
         var cols:Array = twoColumns(1,LOBBY_SECTIONS,skip);
         var before:int = items.length;
         for(var c:int = 0; c < 2; c++)
         {
            var col:Sprite = panel(area.x + c * (COL_W + 10),area.y,COL_W,listHeight);
            drawSections(scroller(col,10,8,COL_W - 20,listHeight - 14),cols[c],COL_W - 30);
         }
         if(items.length == before)
         {
            UiKit.text(tabBody,"No lobby settings here.",area.x + COL_W / 2,area.y + 180,16,UiKit.GREY,UiKit.BOLD,0,true);
         }
         describeBar(listHeight);
      }

      private function presets() : Array
      {
         var list:* = ModSettings.value("lobbyPresets");
         return list is Array ? list as Array : [];
      }

      private function presetIcons(parent:Sprite, v:Object, x:Number, y:Number) : Boolean
      {
         var on:Array = v.icons as Array;
         if(on.length == 0)
         {
            return false;
         }
         var row:Object = null;
         for each(var w:Object in widgets(int(v.tab)))
         {
            if(optionName(w) == v.option)
            {
               row = w;
            }
         }
         if(row == null || row.var_11509 == null)
         {
            return false;
         }
         var n:int = 0;
         for each(var icon:Object in row.var_11509)
         {
            if(on.indexOf(uint(icon.var_12730)) >= 0 && n < 12)
            {
               var art:MovieClip = class_687.method_1714(icon.var_2697,"UI_GameSettings") ||
                  class_687.method_1714(ScoringType.TIMED.var_2697,"UI_GameSettings");
               if(art != null)
               {
                  UiKit.gotoLabel(art,"Ready");
               }
               UiKit.icon(parent,art,x + n * 22,y,18);
               n++;
            }
         }
         return n > 0;
      }

      private function capture() : Object
      {
         var mode:Object = modeWidget();
         var picked:Object = mode != null && mode.var_11509 != null && mode.var_11419 < mode.var_11509.length ?
            mode.var_11509[mode.var_11419] : null;
         var modeIcon:String = picked != null ? String(picked.var_2697) : null;
         var values:Array = [];
         var summary:Array = [];
         for each(var i:int in [0,1])
         {
            for each(var w:Object in widgets(i))
            {
               var k:String = kindOf(w);
               if(!w.var_3713 || k == "Instruction" || k == "InputText" || optionName(w) == "Game_ScoringType")
               {
                  continue;
               }
               var v:Object = {"tab":i,"option":optionName(w),"label":labelOf(w),"kind":k};
               if(k == "IconGroup" || k == "IconGroupFull")
               {
                  var on:Array = [];
                  for each(var icon:Object in w.var_11509)
                  {
                     if(iconSelected(w,icon))
                     {
                        on.push(uint(icon.var_12730));
                     }
                  }
                  v.icons = on;
               }
               else
               {
                  v.value = valueOf(w);
                  if(summary.length < 3 && i == 0)
                  {
                     summary.push(v.label.charAt(0) + v.label.substr(1).toLowerCase() + " " + v.value);
                  }
               }
               values.push(v);
            }
         }
         var st:Object = picked != null ? scoringFor(picked) : null;
         return {"name":(st != null ? localized(st.mDisplayNameKey) : "Mode") + " · " + summary.join(" · "),"mode":modeIcon,
                 "modeId":picked != null ? uint(picked.var_6750) : null,"values":values};
      }

      private var applying:Object = null;

      private function apply(p:Object) : void
      {
         if(!canEdit() || p == null)
         {
            return;
         }
         applying = {"p":p,"i":-1,"steps":0,"start":null,"wait":0,"missed":[]};
         status.text = "Loading the preset...";
      }

      private function findWidget(tabIndex:int, option:String) : Object
      {
         for each(var w:Object in widgets(tabIndex))
         {
            if(optionName(w) == option)
            {
               return w;
            }
         }
         return null;
      }

      private function stepApply() : void
      {
         var a:Object = applying;
         if(a.wait > 0)
         {
            a.wait--;
            return;
         }
         var values:Array = a.p.values as Array;
         if(a.i < 0)
         {
            var mode:Object = modeWidget();
            if(mode != null && a.p.mode != null)
            {
               for each(var icon:Object in mode.var_11509)
               {
                  if((a.p.modeId != null ? uint(icon.var_6750) == uint(a.p.modeId) : icon.var_2697 == a.p.mode) &&
                     !iconSelected(mode,icon))
                  {
                     mode.method_3941(null,icon);
                     a.wait = 6;
                  }
               }
            }
            a.i = 0;
            return;
         }
         if(a.i >= values.length)
         {
            applying = null;
            build();
            status.text = a.missed.length == 0 ? "Preset loaded." : "Preset loaded, except: " + a.missed.join(", ");
            return;
         }
         var v:Object = values[a.i];
         var w:Object = findWidget(int(v.tab),String(v.option));
         if(w == null || !w.var_3713 || w.var_3019)
         {
            a.missed.push(v.label);
            next(a);
            return;
         }
         try
         {
            if(v.icons is Array)
            {
               var changed:Boolean = false;
               for each(var ic:Object in w.var_11509)
               {
                  var want:Boolean = (v.icons as Array).indexOf(uint(ic.var_12730)) >= 0;
                  if(want != iconSelected(w,ic) && (want || w.var_15084))
                  {
                     w.method_3941(null,ic);
                     changed = true;
                     if(!w.var_15084)
                     {
                        break;
                     }
                  }
               }
               next(a);
               a.wait = changed ? 3 : 0;
               return;
            }
            var now:String = valueOf(w);
            if(now == v.value)
            {
               next(a);
               return;
            }
            if(a.steps > 0 && now == a.start || a.steps > 60)
            {
               a.missed.push(v.label);
               next(a);
               return;
            }
            if(a.steps == 0)
            {
               a.start = now;
            }
            w.method_3428(null,1);
            a.steps++;
            a.wait = 2;
         }
         catch(e:Error)
         {
            a.missed.push(v.label);
            next(a);
         }
      }

      private static function next(a:Object) : void
      {
         a.i++;
         a.steps = 0;
         a.start = null;
      }

      private function buildPresets() : void
      {
         describe = null;
         var list:Array = presets();
         var left:Sprite = new Sprite();
         left.x = area.x;
         left.y = area.y;
         tabBody.addChild(left);
         UiKit.rect(left,0,0,LIST_W,area.height,UiKit.PANEL);
         var save:Sprite = button(left,"SAVE CURRENT AS A PRESET",10,10,LIST_W - 20,function():void
         {
            var all:Array = presets();
            all.push(capture());
            ModSettings.setValue("lobbyPresets",all);
            presetAt = all.length - 1;
            build();
         });
         items.push({"kind":"button","act":function():void
         {
            var all:Array = presets();
            all.push(capture());
            ModSettings.setValue("lobbyPresets",all);
            presetAt = all.length - 1;
            build();
         },"sprite":save,"width":LIST_W - 20,"height":30});
         presetAt = Math.max(0,Math.min(presetAt,list.length - 1));
         for(var i:int = 0; i < list.length && i < 9; i++)
         {
            var line:Sprite = new Sprite();
            line.x = 10;
            line.y = 52 + i * 38;
            line.buttonMode = true;
            left.addChild(line);
            UiKit.rect(line,0,0,LIST_W - 20,34,i == presetAt ? UiKit.ROW_SELECTED : UiKit.BODY,6);
            UiKit.fit(UiKit.text(line,String(list[i].name),12,7,14,UiKit.WHITE,UiKit.BOLD),396);
            line.addEventListener(MouseEvent.CLICK,presetPicker(i));
            items.push({"kind":"preset","index":i,"sprite":line,"width":LIST_W - 20,"height":34});
         }
         if(list.length == 0)
         {
            UiKit.text(left,"No presets yet. Set up the rules, then save them here.",LIST_W / 2,200,14,UiKit.GREY,UiKit.MEDIUM,380,true);
            return;
         }
         var right:Sprite = new Sprite();
         right.x = DX;
         right.y = area.y;
         tabBody.addChild(right);
         UiKit.rect(right,0,0,DW,area.height,UiKit.PANEL);
         var p:Object = list[presetAt];
         UiKit.fit(UiKit.text(right,String(p.name),12,8,20,UiKit.WHITE,UiKit.XBOLD),DW - 26);
         var y:Number = 42;
         for each(var v:Object in p.values as Array)
         {
            if(y > area.height - 60)
            {
               break;
            }
            UiKit.fit(UiKit.text(right,String(v.label),14,y,13,UiKit.LIGHT,UiKit.BOLD),250);
            if(!(v.icons is Array) || !presetIcons(right,v,280,y - 1))
            {
               UiKit.fit(UiKit.text(right,v.icons is Array ? (v.icons as Array).length + " selected" : String(v.value),280,y,13,
                  UiKit.TEAL,UiKit.MEDIUM),300);
            }
            y += 20;
         }
         var at:int = presetAt;
         var load:Sprite = button(right,"LOAD",12,area.height - 42,180,function():void
         {
            apply(presets()[at]);
         });
         var over:Sprite = button(right,"OVERWRITE",212,area.height - 42,180,function():void
         {
            var all:Array = presets();
            all[at] = capture();
            ModSettings.setValue("lobbyPresets",all);
            build();
         });
         var del:Sprite = button(right,"DELETE",412,area.height - 42,180,function():void
         {
            var all:Array = presets();
            all.splice(at,1);
            ModSettings.setValue("lobbyPresets",all);
            build();
         });
      }

      private function presetPicker(i:int) : Function
      {
         return function(e:MouseEvent):void
         {
            presetAt = i;
            build();
         };
      }

      private static const DELAYS:Array = [null,16,32,48,64,80,96,112,128,160];
      private static const SMOOTHING:Array = [50,75,100,125,150,200,250,300];

      private function buildNetwork() : void
      {
         describe = null;
         PrivateServer.readP2PSettings();
         var panel:Sprite = new Sprite();
         panel.x = area.x;
         panel.y = area.y;
         tabBody.addChild(panel);
         UiKit.rect(panel,0,0,area.width,area.height,UiKit.PANEL);
         var net:Object = roomNet();
         var host:Boolean = canEdit();
         var rows:Array = [
            ["MATCH TYPE",OnlineTraining.requested ? "Training" : "Normal","Training: rooms you host start their match as Training for everyone. Online, a Training setting anyone changes changes for everyone; saved states, legend changes and frame step are off.",function(dir:int):void
            {
               OnlineTraining.requested = !OnlineTraining.requested;
            }],
            ["ROLLBACK",net.rollback ? "On" : "Off","Late inputs are corrected by going back and simulating again, so your own controls react at once. Off: lockstep (everyone waits for the slowest).",function(dir:int):void
            {
               net.rollback = !net.rollback;
               sendNet(net,host);
            }],
            ["INPUT DELAY",uint(net.delay) != 0 ? net.delay + " ms" : "Auto","How far ahead inputs are sent. Auto picks it from the ping (at most 48 ms with rollback); more delay means fewer corrections, less delay snappier controls.",function(dir:int):void
            {
               var at:int = uint(net.delay) != 0 ? DELAYS.indexOf(uint(net.delay)) : 0;
               var next:* = DELAYS[(Math.max(0,at) + dir + DELAYS.length) % DELAYS.length];
               net.delay = next == null ? 0 : uint(next);
               sendNet(net,host);
            }],
            ["SMOOTHING",net.smoothing ? "On" : "Off","When a correction moves the other legend, slide it there instead of jumping.",function(dir:int):void
            {
               net.smoothing = !net.smoothing;
               sendNet(net,host);
            }],
            ["SMOOTHING TIME",int(net.smoothingMs) + " ms","How long a correction takes to slide (about 90% of the way).",function(dir:int):void
            {
               var at:int = SMOOTHING.indexOf(int(net.smoothingMs));
               net.smoothingMs = SMOOTHING[(Math.max(0,at) + dir + SMOOTHING.length) % SMOOTHING.length];
               sendNet(net,host);
            }],
            ["CONNECTION",PrivateServer.p2pRelayOnly ? "Relay only" : "Direct when possible","Relay only sends everything through the server (when a direct path doesn't work on your network).",function(dir:int):void
            {
               PrivateServer.writeP2PSetting("p2p",PrivateServer.p2pRelayOnly ? null : "relay");
            }]];
         var y:Number = 14;
         for each(var r:Array in rows)
         {
            var line:Sprite = new Sprite();
            line.x = 10;
            line.y = y;
            panel.addChild(line);
            UiKit.rect(line,0,0,area.width - 20,60,UiKit.BODY,6);
            UiKit.text(line,r[0],12,6,15,UiKit.WHITE,UiKit.BOLD);
            UiKit.text(line,r[2],12,26,12,UiKit.LIGHT,UiKit.MEDIUM,area.width - 420);
            var value:TextField = UiKit.text(line,r[1],area.width - 190,18,15,UiKit.TEAL,UiKit.BOLD,0,true);
            var act:Function = r[3];
            UiKit.arrow(line,area.width - 300,18,-1,stepper(act,-1));
            UiKit.arrow(line,area.width - 80,18,1,stepper(act,1));
            items.push({"kind":"network","act":act,"sprite":line,"width":area.width - 20,"height":60});
            y += 64;
         }
      }

      private function roomNet() : Object
      {
         var room:uint = 0;
         try
         {
            room = uint(Object(GameApp.mainInstance).var_13259.var_6244.var_13482);
         }
         catch(e:Error)
         {
         }
         var s:Object = RoomNet.of(room);
         return {"room":room,"rollback":s != null ? s.rollback : PrivateServer.p2pRollback,
            "delay":s != null ? uint(s.delay) : (PrivateServer.p2pDelaySet ? PrivateServer.p2pDelay : 0),
            "smoothing":s != null ? s.smoothing : PrivateServer.p2pSmoothing,
            "smoothingMs":s != null ? uint(s.smoothingMs) : uint(PrivateServer.p2pSmoothingMs)};
      }

      private function sendNet(net:Object, host:Boolean) : void
      {
         if(!host)
         {
            return;
         }
         PrivateServer.writeP2PSetting("p2p_rollback",net.rollback);
         PrivateServer.writeP2PSetting("p2p_delay_ms",uint(net.delay) != 0 ? uint(net.delay) : null);
         PrivateServer.writeP2PSetting("p2p_smoothing",net.smoothing);
         PrivateServer.writeP2PSetting("p2p_smoothing_ms",uint(net.smoothingMs));
         RoomNet.send(net.rollback,uint(net.delay),net.smoothing,uint(net.smoothingMs));
         RoomNet.settings = {"room":net.room,"host":0,"rollback":net.rollback,"delay":uint(net.delay),
            "smoothing":net.smoothing,"smoothingMs":uint(net.smoothingMs)};
      }

      private function stepper(act:Function, dir:int) : Function
      {
         return function():void
         {
            act(dir);
            build();
         };
      }

      override public function OnDestroyScreen() : void
      {
         current = null;
         super.OnDestroyScreen();
      }
   }
}
