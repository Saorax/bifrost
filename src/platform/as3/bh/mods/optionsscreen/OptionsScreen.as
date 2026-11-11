package bh.mods.optionsscreen
{
   import bh.platform.AchievementsWindow;
   import bh.platform.BugReport;
   import bh.platform.Moderation;
   import bh.platform.ModerationWindow;
   import bh.platform.CloudSave;
   import bh.platform.SaveEditorWindow;
   import bh.platform.SaveCopy;
   import bh.platform.BigWindow;
   import bh.platform.ErrorLog;
   import bh.platform.Prompts;
   import bh.platform.FramePacing;
   import bh.platform.GameMenus;
   import bh.platform.LaunchOptions;
   import bh.platform.ModSettings;
   import bh.platform.MenuThemes;
   import bh.platform.ReplayKeep;
   import bh.platform.ReplaysWindow;
   import bh.platform.Platform;
   import bh.platform.StatsOverlay;
   import bh.platform.Vsync;
   import bh.platform.EngineDisplay;
   import bh.platform.InputDisplay;
   import bh.platform.ClassicEffects;
   import bh.platform.SkinEffectsWindow;
   import bh.platform.ReducedFlashes;
   import bh.platform.PostMatchStats;
   import bh.platform.RatingExtras;
   import bh.platform.ScreenShake;
   import bh.platform.Profiles;
   import bh.platform.UiKit;
   import bh.platform.net.DiscordLogin;
   import bh.platform.net.PlayerName;
   import bh.platform.net.PrivateServer;
   import flash.display.MovieClip;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.events.KeyboardEvent;
   import flash.events.MouseEvent;
   import flash.events.SecurityErrorEvent;
   import flash.net.Socket;
   import flash.net.URLLoader;
   import flash.net.URLRequest;
   import flash.text.TextField;
   import flash.text.TextFieldType;
   import flash.text.TextFormat;
   import flash.ui.Keyboard;
   import haxe.IMap;
   import flash.utils.getTimer;
   import flash.utils.setTimeout;

   public class OptionsScreen extends BigWindow
   {
      private static const TABS:Array = ["SYSTEM","PREFERENCES","GRAPHICS","SERVERS","PROFILES","CONTROLS","MORE"];
      private static const RATES:Array = [0,60,75,120,144,165,180,240,-1];
      private static const MONITORS:Array = [-1,0,1,2,3];

      public static var current:OptionsScreen;
      public static var regionPicker:Boolean = false;
      public var hub:Object;

      public var focusBefore:ScreenBase;

      private var describe:TextField;
      private var describeLabel:TextField;
      private var serverStatus:Object = {};
      private var serversRefreshing:Boolean = false;
      private var addHost:TextField;
      private var addName:TextField;
      private var addProfile:TextField;
      private var deleting:String = null;
      private var restartNote:String = null;

      private var importArmed:Boolean = false;
      private var capturing:Object = null;
      private var keyCol:int = 0;
      private var resetting:Boolean = false;
      private var controlsDevice:int = -1;
      private var swallowUp:Object = {};

      public function OptionsScreen(core:GameCore)
      {
         super(core);
      }

      override protected function get title() : String
      {
         return "OPTIONS";
      }

      override protected function get tabNames() : Array
      {
         return TABS;
      }

      override protected function get tabLayout() : Array
      {
         return [-518,170,0.8];
      }

      override protected function get confirmLabel() : String
      {
         return "DONE";
      }

      override public function OnCreateScreen() : void
      {
         current = this;
         super.OnCreateScreen();
         var exit:MovieClip = UiKit.tabButton(body,"EXIT GAME",screen.right - 246,screen.bottom - 50,0.85,function():void
         {
            close();
            ScreenManager.owner.method_8303();
         });
         makeSearchBox();
      }

      override protected function back() : void
      {
         close();
      }

      public function close() : void
      {
         query = "";
         controlsDevice = -1;
         found = [];
         index = null;
         if(searchBox != null)
         {
            searchBox.text = "";
            searchHint.visible = true;
         }
         try
         {
            GameApp.method_3078();
         }
         catch(e:Error)
         {
         }
         Hide();
         try
         {
            if(hub != null)
            {
               hub.panelClip.visible = true;
               if(hub.isActive)
               {
                  var bar:Object = hub.var_6263;
                  if(focusBefore != null && focusBefore !== this && focusBefore !== hub && focusBefore !== bar)
                  {
                     ScreenBase.previousFocusedScreen = focusBefore;
                  }
                  if(bar != null && bar.var_3094 == 7 && bar.isActive)
                  {
                     bar.method_4483();
                     bar.method_3789();
                  }
                  if(hub.isActive)
                  {
                     hub.method_905();
                  }
               }
            }
            focusBefore = null;
         }
         catch(e2:Error)
         {
         }
      }

      override protected function buildTab(i:int) : void
      {
         describe = null;
         describeLabel = null;
         addHost = addName = addProfile = null;
         if(query != "" && !indexing)
         {
            buildResults();
            return;
         }
         switch(i)
         {
            case 0:
               buildGameRows(ScreenManager.var_15094);
               break;
            case 1:
               buildGameRows(ScreenManager.var_7197);
               break;
            case 2:
               buildGraphics();
               break;
            case 3:
               buildServers();
               break;
            case 4:
               buildProfiles();
               break;
            case 5:
               buildControls();
               break;
            default:
               buildMore();
         }
      }

      override protected function statusText() : String
      {
         if(query != "")
         {
            return found.length == 0 ? "No setting matches \"" + query + "\"." : "Select a result to go to that setting.";
         }
         return restartNote != null ? restartNote : (tab <= 2 || tab == 4 ? "Changes apply at once." : "");
      }

      private function row(parent:Sprite, y:Number, width:Number, label:String, value:String, about:String,
                           change:Function, enabled:Boolean = true) : Sprite
      {
         var line:Sprite = new Sprite();
         line.x = 10;
         line.y = y;
         parent.addChild(line);
         UiKit.rect(line,0,0,width,30,UiKit.BODY,6);
         UiKit.fit(UiKit.text(line,label,12,5,14,enabled ? UiKit.WHITE : UiKit.GREY,UiKit.BOLD),width * 0.5);
         var v:TextField = UiKit.text(line,value,width * 0.76,5,14,UiKit.TEAL,UiKit.BOLD,0,true);
         UiKit.fit(v,width * 0.3);
         v.x = width * 0.76 - v.width / 2;
         if(change != null && enabled)
         {
            UiKit.arrow(line,width * 0.56,4,-1,function():void
            {
               change(-1);
               rebuildKeepFocus();
            });
            UiKit.arrow(line,width - 30,4,1,function():void
            {
               change(1);
               rebuildKeepFocus();
            });
         }
         var index:int = items.length;
         line.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            focus = index;
            paintFocus();
         });
         items.push({"sprite":line,"parent":parent,"width":width,"height":30,"change":enabled ? change : null,"about":about,
            "label":label});
         return line;
      }

      private function rebuildKeepFocus() : void
      {
         build();
      }

      override protected function focused(it:Object) : void
      {
         if(describe != null)
         {
            describeText(describe,it.about ? String(it.about) : "");
         }
         if(describeLabel != null)
         {
            describeLabel.text = it.label ? String(it.label) : "";
         }
         paintKeyBoxes();
      }

      private function get COLUMN_W() : Number
      {
         return Math.floor((area.width - 10) / 2);
      }


      private static const BAR_H:Number = 66;
      private var colLists:Array;
      private var colY:Array;
      private var colAt:int;

      private function columns() : void
      {
         colLists = [];
         colY = [0,0];
         colAt = 0;
         var listHeight:Number = area.height - BAR_H - 6;
         for(var c:int = 0; c < 2; c++)
         {
            var col:Sprite = panel(area.x + c * (COLUMN_W + 10),area.y,COLUMN_W,listHeight);
            colLists.push(scroller(col,0,6,COLUMN_W,listHeight - 10));
         }
         var bar:Sprite = panel(area.x,area.y + listHeight + 6,COLUMN_W * 2 + 10,BAR_H);
         describeLabel = UiKit.text(bar,"",14,4,14,UiKit.WHITE,UiKit.XBOLD);
         describe = UiKit.text(bar,"",14,22,12,UiKit.LIGHT,UiKit.MEDIUM,COLUMN_W * 2 - 18);
      }

      private function section(c:int, title:String) : void
      {
         colAt = c;
         UiKit.text(colLists[c],title,14,colY[c],13,UiKit.GREY,UiKit.XBOLD);
         colY[c] += 21;
      }

      private function colRow(label:String, value:String, about:String, change:Function, enabled:Boolean = true) : Sprite
      {
         var line:Sprite = row(colLists[colAt],colY[colAt],COLUMN_W - 20,label,value,about,change,enabled);
         colY[colAt] += 31;
         return line;
      }

      private function sectionEnd() : void
      {
         colY[colAt] += 4;
      }

      override protected function get fullPage() : Boolean
      {
         return true;
      }

      private function get LW() : Number
      {
         return Math.round(area.width * 0.6);
      }

      private function get RW() : Number
      {
         return LW - 20;
      }

      private function get RX() : Number
      {
         return area.x + LW + 10;
      }

      private function get RPW() : Number
      {
         return area.width - LW - 10;
      }

      private function side(x:Number, w:Number) : Sprite
      {
         return panel(x,area.y,w,area.height);
      }

      private function aboutPanel(title:String) : void
      {
         var right:Sprite = side(RX,RPW);
         UiKit.text(right,title,14,10,14,UiKit.GREY,UiKit.XBOLD);
         describe = UiKit.text(right,"",14,36,14,UiKit.LIGHT,UiKit.MEDIUM,RPW - 30);
      }

      private static function textOf(lt:Object) : String
      {
         if(lt == null)
         {
            return "";
         }
         try
         {
            if(lt.hasOwnProperty("var_3517") && lt.var_3517 != null)
            {
               var s:String = class_256.method_1351(String(lt.var_3517));
               if(lt.var_2348 != null)
               {
                  s = lt.var_2348 + s;
               }
               if(lt.var_9020 != null)
               {
                  s += lt.var_9020;
               }
               if(lt.var_5462 != null)
               {
                  s = class_593.method_1974(s,(lt.var_5462 as Array).map(function(a:*, ...rest):String
                  {
                     return class_256.method_1351(String(a));
                  }));
               }
               return s;
            }
            return lt.var_2544 != null ? String(lt.var_2544.text) : "";
         }
         catch(e:Error)
         {
         }
         return "";
      }

      private static function localized(key:String) : String
      {
         try
         {
            var s:String = class_256.method_1351(key);
            return s != null && s != key ? s : "";
         }
         catch(e:Error)
         {
         }
         return "";
      }

      private function gameRows(screen:Object) : Array
      {
         if(screen == null)
         {
            return [];
         }
         try
         {
            if(screen.var_4818 == null)
            {
               screen.createClip();
               if(screen.panelClip != null && screen.panelClip.parent != null)
               {
                  screen.panelClip.parent.visible = false;
               }
            }
            var list:Object = screen.var_4818;
            var out:Array = [];
            for(var i:int = 0; list != null && list.var_15010 != null && i < int(list.var_15010.length); i++)
            {
               out.push(list.var_15010[i]);
            }
            return out;
         }
         catch(e:Error)
         {
            Platform.log("options window: the game's settings rows: " + e.getStackTrace());
         }
         return [];
      }

      private static const GAME_SECTIONS:Array = [
         [0,"AUDIO",["UI_System_Settings_Music","UI_System_Settings_Sound"]],
         [0,"SCREEN",["UI_System_Settings_Display","UI_System_Settings_Language","UI_System_Settings_Streamer_Mode"]],
         [0,"NAMES AND ICONS",["UI_System_Settings_Names","UI_System_Settings_HudIcons","UI_System_Settings_HudSize"]],
         [0,"MENUS",["UI_System_Settings_Crossovers","UI_System_Settings_Upgrades","UI_System_Settings_Accessibility",
            "UI_System_Settings_QueueMode"]],
         [1,"PLAYING",["UI_System_SettingsHoldToPause","UI_System_Settings_Chat","UI_System_Settings_Spectate_Delay",
            "UI_System_Settings_Delete_Outdated_Replays"]],
         [1,"DISCORD",["UI_Bifrost_DiscordPresence","UI_Bifrost_DiscordJoin"]],
         [1,"IN MATCHES",["UI_System_Settings_Camera","UI_System_Settings_Timer","UI_System_Settings_Damage_Numbers",
            "UI_System_Settings_CombatBroadcast"]]];

      private function buildGameRows(screen:Object) : void
      {
         var rows:Array = gameRows(screen);
         if(EngineDisplay.available)
         {
            rows = rows.filter(function(r:Object, ... rest):Boolean
            {
               return String(r.var_10161) != "UI_System_Settings_Display";
            });
         }
         columns();
         var byKey:Object = {};
         for each(var r0:Object in rows)
         {
            byKey[String(r0.var_10161)] = r0;
         }
         var placed:Array = [];
         for(var c:int = 0; c < 2; c++)
         {
            for each(var sec:Array in GAME_SECTIONS)
            {
               var mine:Array = [];
               for each(var key:String in sec[2])
               {
                  if(sec[0] == c && byKey[key] != null)
                  {
                     mine.push(byKey[key]);
                  }
               }
               if(mine.length > 0)
               {
                  section(c,sec[1]);
                  for each(var r1:Object in mine)
                  {
                     gameRow(r1);
                     placed.push(r1);
                  }
                  sectionEnd();
               }
            }
         }
         var more:Array = rows.filter(function(r2:Object, ... rest):Boolean
         {
            return placed.indexOf(r2) < 0;
         });
         if(more.length > 0)
         {
            section(colY[0] <= colY[1] ? 0 : 1,"MORE");
            for each(var r3:Object in more)
            {
               gameRow(r3);
            }
         }
         if(rows.length == 0)
         {
            UiKit.text(colLists[0],"These settings aren't available right now.",262,160,15,UiKit.GREY,UiKit.BOLD,0,true);
         }
         if(tab == 0)
         {
            section(colY[0] <= colY[1] ? 0 : 1,"LEGAL");
            var legal:Sprite = new Sprite();
            legal.y = colY[colAt];
            colLists[colAt].addChild(legal);
            var openLegal:Function = function():void
            {
               close();
               ScreenManager.var_10749.Display();
            };
            button(legal,"LEGAL NOTICES",14,0,240,openLegal,30,14);
            items.push({"sprite":legal,"parent":legal.parent,"width":240,"height":30,"focusBox":[14,0,240,30],"use":openLegal,
               "about":"The game's legal notices."});
            colY[colAt] += 38;
            sectionEnd();
            if(regionPicker && hub != null)
            {
               section(colY[0] <= colY[1] ? 0 : 1,"ONLINE");
               var region:Sprite = new Sprite();
               region.y = colY[colAt];
               colLists[colAt].addChild(region);
               var openRegion:Function = function():void
               {
                  var menu:Object = hub;
                  Hide();
                  try
                  {
                     menu.panelClip.visible = true;
                     menu.method_3541(2);
                  }
                  catch(e:Error)
                  {
                     Platform.log("options: the region page didn't open: " + e);
                  }
               };
               button(region,"SERVER REGION",14,0,240,openRegion,30,14);
               items.push({"sprite":region,"parent":region.parent,"width":240,"height":30,"focusBox":[14,0,240,30],"use":openRegion,
                  "about":"Pick which server regions the game connects you to."});
               colY[colAt] += 38;
               sectionEnd();
            }
         }
         else if(tab == 1)
         {
            launchRows();
         }
      }

      private function gameRow(r:Object) : void
      {
         try
         {
            r.Update();
         }
         catch(e:Error)
         {
         }
         var label:String = textOf(r.var_279);
         if(label == "")
         {
            label = localized(String(r.var_10161));
         }
         var value:String = textOf(r.var_9950);
         if(r.var_6119 != null && r.var_9950 == null)
         {
            value = String(int(Math.round(Number(r.var_6119.var_8050) * 100)));
         }
         else if(value == "" && r.var_14490 != null)
         {
            value = textOf(r.var_14490);
         }
         colRow(label.toUpperCase(),value,localized(String(r.var_10161) + "_Tooltip"),rowChanger(r),!r.var_8623);
      }

      private function rowChanger(r:Object) : Function
      {
         return function(dir:int):void
         {
            try
            {
               r.method_4688(null,dir);
            }
            catch(e:Error)
            {
               Platform.log("options window: changing a setting failed: " + e.message);
            }
         };
      }

      private function buildGraphics() : void
      {
         columns();
         section(0,"DISPLAY");
         colRow("FRAME PACING",FramePacing.on ? "On" : "Off","Smooths movement between the game's 16 ms steps, so " +
            "everything moves evenly at any refresh rate. It can add up to 16 ms of display delay. F11 also turns it on or off.",function(dir:int):void
         {
            FramePacing.on = !FramePacing.on;
            ModSettings.setFlag("framePacing",FramePacing.on);
         });
         var rate:int = LaunchOptions.frameRate();
         colRow("FRAME RATE",rate == 0 ? "Monitor" : (rate < 0 ? "Unlimited" : rate + " fps"),"How many frames the game draws " +
            "each second. Monitor matches your screen's refresh rate. With VSYNC on, the game can't go faster than your " +
            "monitor, so turn VSYNC off for higher caps or Unlimited. Select it to type your own number.",function(dir:int):void
         {
            var at:int = RATES.indexOf(LaunchOptions.frameRate());
            applyFrameRate(RATES[(Math.max(0,at) + dir + RATES.length) % RATES.length]);
         });
         items[items.length - 1].use = function():void
         {
            var current:int = LaunchOptions.frameRate();
            typeText("FRAME RATE (25 TO 1000, 0 FOR THE MONITOR)",current > 0 ? String(current) : "",4,function(v:String):void
            {
               if(v != null && /^\d+$/.test(v))
               {
                  var n:int = int(v);
                  applyFrameRate(n == 0 ? 0 : int(Math.max(25,Math.min(1000,n))));
                  build();
               }
            });
         };
         colRow("VSYNC",!Vsync.available ? "Not available" : (Vsync.on ? "On" : "Off"),"On stops screen tearing by " +
            "waiting for your monitor. Off shows each frame right away for the lowest delay, but the picture may tear. " +
            "Turn it off to use a FRAME RATE above your refresh rate.",function(dir:int):void
         {
            Vsync.on = !Vsync.on;
         });
         if(EngineDisplay.available)
         {
            var next:String = EngineDisplay.renderer;
            colRow("RENDERER",EngineDisplay.nameOf(EngineDisplay.RENDERERS,EngineDisplay.RENDERER_NAMES,next) +
               (next != EngineDisplay.running ? " (next start)" : ""),"The graphics API the game draws with. Changes take effect the next time the game starts. Right now it's using " +
               EngineDisplay.nameOf(EngineDisplay.RENDERERS,EngineDisplay.RENDERER_NAMES,EngineDisplay.running) + ". " +
               "If Vulkan fails to start, the game goes back to DirectX 11.",
               function(dir:int):void
            {
               EngineDisplay.setRenderer(EngineDisplay.step(EngineDisplay.RENDERERS,EngineDisplay.renderer,dir));
            });
            colRow("DISPLAY MODE",EngineDisplay.nameOf(EngineDisplay.MODES,EngineDisplay.MODE_NAMES,EngineDisplay.mode),
               "Game's Setting follows the game's own window or full screen choice. " +
               "Exclusive fullscreen gives the game the whole monitor for the lowest delay.",
               function(dir:int):void
            {
               EngineDisplay.setMode(EngineDisplay.step(EngineDisplay.MODES,EngineDisplay.mode,dir));
            });
            var screen:int = EngineDisplay.monitor;
            colRow("MONITOR",screen < 0 ? "Current" : "Monitor " + (screen + 1),"Which monitor the game uses in " +
               "Borderless and Exclusive fullscreen. Current keeps the one the window is on.",
               function(dir:int):void
            {
               EngineDisplay.setMonitor(EngineDisplay.step(MONITORS,EngineDisplay.monitor,dir));
            });
         }
         else
         {
            var driver:String = "unknown";
            try
            {
               driver = String(body.stage.stage3Ds[0].context3D.driverInfo) + " (" + String(body.stage.stage3Ds[0].context3D.profile) + ")";
            }
            catch(e:Error)
            {
            }
            colRow("RENDERER",driver.length > 40 ? driver.substr(0,37) + "..." : driver,"The game draws through AIR's " +
               "Stage3D, which is DirectX 11 on Windows. \"Software\" means no GPU is used. To fix that, pick a GPU for " +
               "Brawlhalla.exe in Windows Settings > Display > Graphics.",null);
         }
         sectionEnd();
         section(0,"IN MATCHES");
         colRow("INPUT DISPLAY",InputDisplay.POSITIONS[InputDisplay.position],
            "Shows the keys or buttons each player on this PC presses, in matches and Training. " +
            "Keyboard players see their own key bindings.",function(dir:int):void
         {
            InputDisplay.position = (InputDisplay.position + dir + InputDisplay.POSITIONS.length) % InputDisplay.POSITIONS.length;
         });
         colRow("INPUT DISPLAY SIZE",InputDisplay.size + "%","How big the input display is. \"Bottom, by side\" " +
            "puts player 1 (or team 1) on the left and player 2 (or team 2) on the right. A panel fades when a legend " +
            "is behind it.",function(dir:int):void
         {
            var sizes:Array = InputDisplay.SIZES;
            InputDisplay.size = sizes[(Math.max(0,sizes.indexOf(InputDisplay.size)) + dir + sizes.length) % sizes.length];
         });
         colRow("OTHER PLAYERS' INPUTS",InputDisplay.OTHERS[InputDisplay.others],
            "Also shows other players' inputs while INPUT DISPLAY is on. " +
            "Pick just your teammates in team matches, or everyone, including bots, online players and replays (up to three).",function(dir:int):void
         {
            InputDisplay.others = (InputDisplay.others + dir + 3) % 3;
         });
         colRow("SCREEN SHAKE",ScreenShake.label(ScreenShake.strength),
            "How much the camera shakes on big hits and some powers. " +
            "100% is the game's normal shake. This only changes what you see.",function(dir:int):void
         {
            var levels:Array = ScreenShake.LEVELS;
            ScreenShake.strength = levels[(levels.indexOf(ScreenShake.strength) + dir + levels.length) % levels.length];
         });
         colRow("BLINKING LEGENDS",ReducedFlashes.on ? "Steady" : "Game",
            "Legends blink white after respawning or while they can't be hit. " +
            "Steady shows an even tint instead, so you still see the state without the flicker.",function(dir:int):void
         {
            ReducedFlashes.on = !ReducedFlashes.on;
         });
         colRow("KO EFFECTS",ReducedFlashes.koStrength + "%",
            "How strong the KO effects look, both the burst at the edge of the screen and the effect on the legend. " +
            "100% is the game's normal look.",function(dir:int):void
         {
            var levels:Array = ReducedFlashes.KO_LEVELS;
            ReducedFlashes.koStrength = levels[(levels.indexOf(ReducedFlashes.koStrength) + dir + levels.length) % levels.length];
         });
         colRow("SKIN EFFECTS",ClassicEffects.on ? "Parent Effects" : "Unchanged",
            "Crossovers, Ascended skins and some weapon skins (like Mega Man's Blasters) have their own attack effects " +
            "and sounds. Parent Effects uses the base legend's and weapon's effects instead, and the skins still look the same. " +
            "Use CHOOSE SKINS to keep some skins Unchanged. Starts from the next match.",function(dir:int):void
         {
            ClassicEffects.on = !ClassicEffects.on;
         });
         colRow("CHOOSE SKINS",ClassicEffects.on ? "Open" : "-",
            "Pick which skins and weapon skins keep their own effects.",
            function(dir:int):void
         {
            if(ClassicEffects.on)
            {
               SkinEffectsWindow.open();
            }
         },ClassicEffects.on);
         sectionEnd();
         var at:int = StatsOverlay.position;
         section(1,"STATS OVERLAY (F12)");
         colRow("STATS OVERLAY",StatsOverlay.POSITIONS[at],"A small box with your frame rate, ping and the other " +
            "lines below. F12 shows or hides it.",function(dir:int):void
         {
            StatsOverlay.position = (StatsOverlay.position + dir + StatsOverlay.POSITIONS.length) % StatsOverlay.POSITIONS.length;
         });
         colRow("OVERLAY SIZE",StatsOverlay.SIZES[StatsOverlay.size],"The overlay's text size.",function(dir:int):void
         {
            StatsOverlay.size = (StatsOverlay.size + dir + StatsOverlay.SIZES.length) % StatsOverlay.SIZES.length;
         });
         colRow("OVERLAY LAYOUT",StatsOverlay.LAYOUTS[StatsOverlay.arrangement],"Side by side puts everything in one row. " +
            "Stacked gives each line its own row.",function(dir:int):void
         {
            StatsOverlay.arrangement = (StatsOverlay.arrangement + dir + StatsOverlay.LAYOUTS.length) % StatsOverlay.LAYOUTS.length;
         });
         for(var i:int = 0; i < StatsOverlay.LINES.length; i++)
         {
            colRow(StatsOverlay.LINES[i][1],StatsOverlay.lineOn(i) ? "Shown" : "Hidden",
               StatsOverlay.LINES[i][3],lineToggler(i));
         }
         sectionEnd();
         section(1,"AFTER A MATCH");
         colRow("MATCH STATS",PostMatchStats.on ? "On" : "Off",
            "Adds a MATCH STATS button (Tab) to the scoreboard and to replays. It shows damage, KOs, falls, dodges and " +
            "jumps for each player, a damage graph, and the attacks that did the most damage. Starts from the next match.",function(dir:int):void
         {
            PostMatchStats.on = !PostMatchStats.on;
         });
         colRow("RANKED OVERLAYS",RatingExtras.on ? "On" : "Off",
            "Bifrost's ranked panels: rating tags and side panels before a ranked match, the ranked lobby panel, and your " +
            "rating change after the match. Off shows only the game's own screens.",
            function(dir:int):void
         {
            RatingExtras.on = !RatingExtras.on;
         });
         colRow("KEEP RECENT",ReplayKeep.keepLabel(ReplayKeep.keepRecent),
            "How many of your newest replays stay in the Replays list. Older ones move to the Older folder, and nothing " +
            "is deleted. Replays you add to Favorites stay in Favorites.",function(dir:int):void
         {
            ReplayKeep.stepKeep(dir);
         });
         sectionEnd();
         section(1,"MAIN MENU");
         colRow("MENU THEME",MenuThemes.label(),MenuThemes.about(),function(dir:int):void
         {
            MenuThemes.step(dir);
         });
         sectionEnd();
         section(1,"SETTINGS PAGES");
         colRow("TRAINING SETTINGS",GameMenus.label(GameMenus.TRAINING),
            "Which page Training's settings open: Bifrost's or the game's own. Each page has a button to switch to the other.",
            function(dir:int):void
         {
            GameMenus.setOwn(GameMenus.TRAINING,!GameMenus.own(GameMenus.TRAINING));
         });
         colRow("REPLAYS",ReplaysWindow.label(),
            "Which page Social > Replays opens: Bifrost's (folders, filters, KO timeline, notes, tags and saved match stats) " +
            "or the game's own list. Each page has a button to switch to the other.",function(dir:int):void
         {
            ReplaysWindow.enabled = !ReplaysWindow.enabled;
         });
         colRow("LOBBY SETTINGS",GameMenus.label(GameMenus.LOBBY),
            "Which page a custom lobby's settings open: Bifrost's or the game's own. Each page has a button to switch to the other.",
            function(dir:int):void
         {
            GameMenus.setOwn(GameMenus.LOBBY,!GameMenus.own(GameMenus.LOBBY));
         });
      }

      private function applyFrameRate(next:int) : void
      {
         LaunchOptions.setFrameRate(next);
         try
         {
            var fps:Number = next > 0 ? next : (next < 0 ? 1000 : monitorRate());
            Main.targetFrameRate = fps;
            body.stage.frameRate = Math.max(25,Math.min(1000,fps));
         }
         catch(e:Error)
         {
         }
      }

      private static function monitorRate() : Number
      {
         try
         {
            var hz:Number = Number(GameApp.windowsExtension.ASGetRefreshRate());
            if(hz >= 25)
            {
               return hz;
            }
         }
         catch(e:Error)
         {
         }
         return 60;
      }

      private function lineToggler(i:int) : Function
      {
         return function(dir:int):void
         {
            StatsOverlay.setLine(i,!StatsOverlay.lineOn(i));
         };
      }

      private function servers() : Array
      {
         var list:* = ModSettings.value("servers");
         var out:Array = list is Array ? (list as Array).concat() : [];
         if(PrivateServer.host != null)
         {
            var known:Boolean = false;
            for each(var s:Object in out)
            {
               known = known || s.host == PrivateServer.host && int(s.port) == int(PrivateServer.port);
            }
            if(!known)
            {
               out.unshift({"name":"Current server","host":PrivateServer.host,"port":PrivateServer.port});
            }
         }
         var main:Object = mainServer();
         if(main != null)
         {
            var listed:Boolean = false;
            for each(var t:Object in out)
            {
               listed = listed || t.host == main.host && int(t.port) == int(main.port);
            }
            if(!listed)
            {
               out.unshift({"name":"Main server","host":main.host,"port":int(main.port)});
            }
         }
         return out;
      }

      private function mainServer() : Object
      {
         var m:* = ModSettings.value("mainServer");
         var release:Object = PrivateServer.main;
         if(release != null)
         {
            if(m == null || typeof m != "object" || m.host != release.host || int(m.port) != int(release.port))
            {
               ModSettings.setValue("mainServer",release);
            }
            return release;
         }
         if((m == null || typeof m != "object" || !m.host) && PrivateServer.host != null)
         {
            m = {"host":PrivateServer.host,"port":int(PrivateServer.port)};
            ModSettings.setValue("mainServer",m);
         }
         return m != null && typeof m == "object" && m.host ? m : null;
      }

      private function isMain(s:Object) : Boolean
      {
         var m:Object = mainServer();
         return m != null && s.host == m.host && int(s.port) == int(m.port);
      }

      private function saveServers(list:Array) : void
      {
         ModSettings.setValue("servers",list);
      }

      private function isCurrent(s:Object) : Boolean
      {
         return PrivateServer.host != null && s.host == PrivateServer.host && int(s.port) == int(PrivateServer.port);
      }

      private function probe(s:Object) : void
      {
         var key:String = s.host + ":" + s.port;
         var old:Object = serverStatus[key];
         if(old != null && (old.busy > 0 || getTimer() - old.at < 15000))
         {
            return;
         }
         var st:Object = {"at":getTimer(),"state":old != null ? old.state : "checking...","ping":old != null ? old.ping : -1,
            "info":old != null ? old.info : null,"busy":2};
         serverStatus[key] = st;
         var settled:Function = function():void
         {
            st.busy--;
            st.at = getTimer();
            refreshServers();
         };
         try
         {
            var sock:Socket = new Socket();
            var started:int = getTimer();
            var answered:Boolean = false;
            sock.timeout = 4000;
            sock.addEventListener(Event.CONNECT,function(e:Event):void
            {
               if(answered)
               {
                  return;
               }
               answered = true;
               st.state = "online";
               st.ping = getTimer() - started;
               try
               {
                  sock.close();
               }
               catch(err:Error)
               {
               }
               settled();
            });
            var down:Function = function(e:Event):void
            {
               if(answered)
               {
                  return;
               }
               answered = true;
               st.state = "offline";
               settled();
            };
            sock.addEventListener(IOErrorEvent.IO_ERROR,down);
            sock.addEventListener(SecurityErrorEvent.SECURITY_ERROR,down);
            sock.connect(String(s.host),int(s.port));
            var web:int = s.web ? int(s.web) : int(s.port) + 1;
            var ask:Function = function(scheme:String):void
            {
               var loader:URLLoader = new URLLoader();
               var heard:Boolean = false;
               loader.addEventListener(Event.COMPLETE,function(e:Event):void
               {
                  if(heard)
                  {
                     return;
                  }
                  heard = true;
                  try
                  {
                     st.info = JSON.parse(String(loader.data));
                     st.info.https = scheme == "https";
                  }
                  catch(err:Error)
                  {
                  }
                  settled();
               });
               var failed:Function = function(e:Event):void
               {
                  if(heard)
                  {
                     return;
                  }
                  heard = true;
                  if(scheme == "https")
                  {
                     ask("http");
                     return;
                  }
                  st.info = null;
                  settled();
               };
               loader.addEventListener(IOErrorEvent.IO_ERROR,failed);
               loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR,failed);
               loader.load(new URLRequest(scheme + "://" + s.host + ":" + web + "/info"));
            };
            ask("https");
         }
         catch(e:Error)
         {
            st.state = "offline";
            st.busy = 0;
         }
      }

      private function refreshServers() : void
      {
         if(serversRefreshing)
         {
            return;
         }
         serversRefreshing = true;
         setTimeout(function():void
         {
            serversRefreshing = false;
            if(tab == 3 && isActive && !typing())
            {
               rebuildKeepFocus();
            }
         },100);
      }

      private function buildServers() : void
      {
         var left:Sprite = side(area.x,LW);
         UiKit.text(left,"SERVERS",12,8,14,UiKit.GREY,UiKit.XBOLD);
         var list:Array = servers();
         var y:Number = 32;
         for(var i:int = 0; i < list.length && y < area.height - 60; i++)
         {
            var s:Object = list[i];
            probe(s);
            var st:Object = serverStatus[s.host + ":" + s.port];
            var line:Sprite = new Sprite();
            line.x = 10;
            line.y = y;
            left.addChild(line);
            UiKit.rect(line,0,0,RW,54,isCurrent(s) ? UiKit.ROW_SELECTED : UiKit.BODY,6);
            var info:Object = st != null ? st.info : null;
            var title:String = (info != null && info.name ? String(info.name) : String(s.name || s.host)) + (isMain(s) ? "  (main)" : "") +
               (isCurrent(s) ? "  (in use)" : "");
            UiKit.fit(UiKit.text(line,title,12,5,15,UiKit.WHITE,UiKit.BOLD),380);
            var bits:Array = [s.host + ":" + s.port];
            if(st != null)
            {
               bits.push(st.state == "online" ? "online, " + st.ping + " ms" : st.state);
            }
            if(info != null)
            {
               if(info.players is Number)
               {
                  bits.push(int(info.players) == 1 ? "1 player on" : int(info.players) + " players on");
               }
               bits.push(info.whitelist ? "whitelisted (Discord)" : "open to everyone");
               if(!info.sign_in)
               {
                  bits.push("no Discord sign-in");
               }
            }
            UiKit.fit(UiKit.text(line,bits.join(" · "),12,29,12,st != null && st.state == "online" ? UiKit.TEAL : UiKit.GREY,
               UiKit.MEDIUM),400);
            if(!isCurrent(s))
            {
               smallButton(line,"USE",RW - 200,13,serverUser(s));
            }
            var removable:Boolean = !isMain(s) && !isCurrent(s);
            if(removable)
            {
               smallButton(line,"REMOVE",RW - 100,13,serverRemover(s));
            }
            items.push({"sprite":line,"width":RW,"height":54,"use":serverUser(s),"option":removable ? serverRemover(s) : null,
               "about":"Use this server (" + Prompts.KEYS.select + "): the game connects to it at once " +
               "(no restart). " + (removable ? Prompts.KEYS.option + " removes it. " : isMain(s) ? "The main server can't be removed. " :
               "The server in use can't be removed (use another one first). ") + "Your Discord sign-in is kept per server, " +
               "so one server never gets another's token."});
            y += 60;
         }
         var add:Sprite = new Sprite();
         add.x = 10;
         add.y = area.height - 52;
         left.addChild(add);
         UiKit.rect(add,0,0,RW,44,UiKit.BODY,6);
         addHost = input(add,12,10,240,"address:port");
         addName = input(add,262,10,220,"name (optional)");
         actionButton(add,"ADD",500,10,function():void
         {
            var text:String = addHost.text.replace(/^\s+|\s+$/g,"");
            var m:Array = /^([A-Za-z0-9.\-]+)(?::(\d+))?$/.exec(text);
            if(m == null)
            {
               restartNote = "That isn't an address (host or IP, and :port).";
               build();
               return;
            }
            var port:int = m[2] ? int(m[2]) : 7910;
            var why:String = PrivateServer.refuse(m[1],port);
            if(why != null)
            {
               restartNote = "Refused: " + why;
               build();
               return;
            }
            var all:Array = servers();
            all.push({"name":addName.text.replace(/^\s+|\s+$/g,"") || m[1],"host":m[1],"port":port});
            saveServers(all);
            restartNote = null;
            delete typed["address:port"];
            delete typed["name (optional)"];
            build();
         });
         var right:Sprite = side(RX,RPW);
         var y2:Number = account(right);
         UiKit.rect(right,12,y2,RPW - 24,1,UiKit.LINE);
         UiKit.text(right,"ABOUT SERVERS",14,y2 + 10,14,UiKit.GREY,UiKit.XBOLD);
         UiKit.text(right,"Bifrost servers are run by players. Add one by its address (ask its owner), then Use it; the " +
            "game connects there at once, and only there: never to official servers.\n\nA whitelisted server " +
            "lets in only the Discord accounts its owner listed. It checks that itself, from its own Discord sign-in, so " +
            "nobody can pretend to be on the list.\n\nAccounts are the server's own (Discord sign-in, no passwords). " +
            "Nothing is bought: everything is unlocked for everyone.",14,y2 + 36,13,UiKit.LIGHT,UiKit.MEDIUM,RPW - 30);
      }

      private function account(right:Sprite) : Number
      {
         UiKit.text(right,"DISCORD ACCOUNT",14,10,14,UiKit.GREY,UiKit.XBOLD);
         var signedIn:Boolean = PrivateServer.account != null || PrivateServer.token != null;
         UiKit.fit(UiKit.text(right,PrivateServer.host == null ? "No server in use (offline)" : PrivateServer.account != null ?
            "Signed in as " + PrivateServer.account : (PrivateServer.token != null ? "Signed in (this server keeps your account)" :
            "Not signed in on this server"),14,36,15,signedIn ? UiKit.TEAL : UiKit.GREY,UiKit.BOLD),RPW - 30);
         var bw:int = signedIn ? 150 : 120;
         var signIn:Function = function():void
         {
            close();
            DiscordLogin.start();
         };
         var b:Sprite = button(right,signedIn ? "SIGN IN AGAIN" : "SIGN IN",14,64,bw,signIn,26,13);
         items.push({"sprite":b,"width":bw,"height":26,"use":signIn,
            "about":"Sign in with Discord on the server in use: your browser opens Discord's page, and this server gets " +
            "your account (again: to use another Discord account). It is how whitelisted servers know you."});
         if(PrivateServer.host == null)
         {
            return 104;
         }
         UiKit.text(right,"YOUR NAME",14,104,14,UiKit.GREY,UiKit.XBOLD);
         UiKit.fit(UiKit.text(right,PlayerName.current() || "(not logged in)",14,128,15,UiKit.WHITE,UiKit.BOLD),RPW - 200);
         var rename:Function = function():void
         {
            typeText("YOUR NAME (3-16 LETTERS, DIGITS, SPACES, _ OR -)",PlayerName.current(),16,function(v:String):void
            {
               var why:String = PlayerName.change(v.replace(/^\s+|\s+$/g,""));
               restartNote = why != null ? "Name not changed: " + why + "." : "Name sent to the server: " + v + ".";
               build();
            });
         };
         var nb:Sprite = button(right,"CHANGE NAME",RPW - 170,124,156,rename,26,13);
         items.push({"sprite":nb,"width":156,"height":26,"use":rename,
            "about":"Your name in the game on this server. Names are unique and can be changed any time; old matches " +
            "keep the name you had then. A Discord sign-in names you after your Discord name the first time only."});
         UiKit.text(right,"SAVE ON THE SERVER",14,166,14,UiKit.GREY,UiKit.XBOLD);
         if(!CloudSave.ENABLED)
         {
            UiKit.fit(UiKit.text(right,"Off for now. To bring the official game's save over, use MORE > IMPORT " +
               "OFFICIAL SAVE.",14,190,13,UiKit.LIGHT,UiKit.MEDIUM),RPW - 30);
            return moderation(right,bugReport(right,226));
         }
         UiKit.fit(UiKit.text(right,CloudSave.describe(),14,190,13,UiKit.LIGHT,UiKit.MEDIUM),RPW - 230);
         var off:Boolean = ModSettings.flag(CloudSave.OFF);
         var saveAct:Function = function():void
         {
            if(off)
            {
               CloudSave.keep();
               restartNote = "Your save goes to the server again (in a few seconds).";
            }
            else if(!deleteArmed)
            {
               deleteArmed = true;
               restartNote = "Press DELETE FROM SERVER again: the server deletes your save for good (this PC keeps it).";
            }
            else
            {
               deleteArmed = false;
               restartNote = CloudSave.deleteFromServer() ? "Deleted from the server. Nothing more is sent until KEEP ON SERVER." :
                  "Not connected to the server.";
            }
            build();
         };
         var label:String = off ? "KEEP ON SERVER" : deleteArmed ? "SURE? DELETE" : "DELETE FROM SERVER";
         var sb:Sprite = button(right,label,RPW - 210,186,196,saveAct,26,13);
         items.push({"sprite":sb,"width":196,"height":26,"use":saveAct,
            "about":"Your settings, key binds, legend setups and colours are kept by the server for your Discord " +
            "account, so another PC gets them when you sign in there. Delete from server removes them for good."});
         return moderation(right,bugReport(right,226));
      }

      private function moderation(right:Sprite, y:Number) : Number
      {
         if(!Moderation.admin)
         {
            return y;
         }
         UiKit.text(right,"MODERATION",14,y,14,UiKit.GREY,UiKit.XBOLD);
         UiKit.fit(UiKit.text(right,"You are an admin of this server: reports, mutes, bans, ratings, announcements.",14,
            y + 24,13,UiKit.LIGHT,UiKit.MEDIUM),RPW - 200);
         var open:Function = function():void
         {
            ModerationWindow.open();
         };
         var mb:Sprite = button(right,"MODERATION",RPW - 170,y + 20,156,open,26,13);
         items.push({"sprite":mb,"width":156,"height":26,"use":open,
            "about":"The server's admin page: the players' reports, mute or ban a player, reset a rating, and " +
            "announcements shown in every game's notification list."});
         return y + 60;
      }

      private function bugReport(right:Sprite, y:Number) : Number
      {
         UiKit.text(right,"REPORT A BUG",14,y,14,UiKit.GREY,UiKit.XBOLD);
         UiKit.fit(UiKit.text(right,BugReport.status || "Sends your note and the game's logs (this and the last " +
            "session) to this server.",14,y + 24,13,UiKit.LIGHT,UiKit.MEDIUM),RPW - 200);
         var report:Function = function():void
         {
            typeText("WHAT WENT WRONG? (OPTIONAL)","",200,function(v:String):void
            {
               BugReport.onAnswer = function(text:String):void
               {
                  restartNote = text;
                  if(body != null && body.stage != null)
                  {
                     build();
                  }
               };
               var why:String = BugReport.send(v.replace(/^\s+|\s+$/g,""));
               restartNote = why != null ? "Bug report not sent: " + why + "." : "Sending the bug report...";
               build();
            },true);
         };
         var rb:Sprite = button(right,"REPORT A BUG",RPW - 170,y + 20,156,report,26,13);
         items.push({"sprite":rb,"width":156,"height":26,"use":report,
            "about":"Something went wrong? Type what happened (or nothing) and the game sends it with its logs " +
            "(this session's and the last one's, so a crash's too) to this server's owner. Your sign-in is never sent."});
         return y + 60;
      }

      private var deleteArmed:Boolean = false;

      private function serverUser(s:Object) : Function
      {
         return function():void
         {
            var why:String = PrivateServer.switchTo(String(s.host),int(s.port));
            restartNote = why != null ? "Couldn't switch: " + why : "Connecting to " + (s.name || s.host) + "...";
            var all:Array = servers();
            saveServers(all);
            build();
         };
      }

      private function serverRemover(s:Object) : Function
      {
         return function():void
         {
            if(isMain(s) || isCurrent(s))
            {
               return;
            }
            var all:Array = servers();
            for(var i:int = all.length - 1; i >= 0; i--)
            {
               if(all[i].host == s.host && int(all[i].port) == int(s.port))
               {
                  all.splice(i,1);
               }
            }
            saveServers(all);
            build();
         };
      }

      private var typed:Object = {};

      private function input(parent:Sprite, x:Number, y:Number, w:Number, hint:String) : TextField
      {
         UiKit.rect(parent,x,y,w,24,UiKit.WHITE,4);
         var t:TextField = new TextField();
         t.type = TextFieldType.INPUT;
         t.defaultTextFormat = new TextFormat("_sans",14,UiKit.NAVY_TEXT);
         t.x = x + 6;
         t.y = y + 2;
         t.width = w - 12;
         t.height = 22;
         t.maxChars = 60;
         t.text = typed[hint] != null ? typed[hint] : "";
         parent.addChild(t);
         var label:TextField = UiKit.text(parent,hint,x + 8,y + 3,13,UiKit.GREY,UiKit.MEDIUM);
         label.visible = t.text.length == 0;
         t.addEventListener(Event.CHANGE,function(e:Event):void
         {
            typed[hint] = t.text;
            label.visible = t.text.length == 0;
         });
         items.push({"sprite":parent,"parent":parent.parent,"width":w,"height":24,"focusBox":[x - 8,y,w,24],
            "about":Prompts.KEYS.select + " to type with the on-screen keyboard (or click the box and use the keyboard).",
            "use":function():void
            {
               typeText(hint.toUpperCase(),t.text,t.maxChars,function(v:String):void
               {
                  typed[hint] = v;
                  build();
               });
            }});
         t.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            e.stopPropagation();
            if(body.stage != null)
            {
               body.stage.focus = t;
            }
         });
         return t;
      }

      public function typing() : Boolean
      {
         return body != null && body.stage != null && body.stage.focus != null && (body.stage.focus == addHost || body.stage.focus == addName || body.stage.focus == addProfile ||
            body.stage.focus == searchBox);
      }

      private function smallButton(parent:Sprite, label:String, x:Number, y:Number, act:Function) : Sprite
      {
         return button(parent,label,x,y,90,act,26,13);
      }

      private function actionButton(parent:Sprite, label:String, x:Number, y:Number, act:Function) : Sprite
      {
         var b:Sprite = smallButton(parent,label,x,y,act);
         items.push({"sprite":parent,"parent":parent.parent,"width":90,"height":26,"focusBox":[x - 8,y,90,26],"use":act});
         return b;
      }

      private function buildProfiles() : void
      {
         var mgr:class_310 = owner.var_261;
         var left:Sprite = scroller(side(area.x,LW),0,0,LW,area.height);
         UiKit.text(left,"WHO USES WHICH PROFILE",12,8,14,UiKit.GREY,UiKit.XBOLD);
         var y:Number = 32;
         for each(var d:Object in Profiles.devices())
         {
            row(left,y,RW,String(d.name).toUpperCase(),Profiles.deviceProfile(mgr,uint(d.id)),d.id == 0 ?
               "The profile keyboard players use. Set its key bindings in the game's Controls settings. " +
               "A new profile is used from the next start." :
               "The profile this controller uses. Set its button mappings in the game's Controls settings " +
               "while this profile is picked.",deviceChanger(mgr,uint(d.id)));
            y += 31;
         }
         y += 14;
         UiKit.text(left,"PROFILES",12,y,14,UiKit.GREY,UiKit.XBOLD);
         y += 24;
         for each(var name:String in Profiles.names(mgr))
         {
            var line:Sprite = new Sprite();
            line.x = 10;
            line.y = y;
            left.addChild(line);
            UiKit.rect(line,0,0,RW,30,UiKit.BODY,6);
            UiKit.fit(UiKit.text(line,name,12,5,14,UiKit.WHITE,UiKit.BOLD),400);
            if(name != Profiles.DEFAULT)
            {
               button(line,deleting == name ? "SURE?" : "DELETE",RW - 100,2,90,profileDeleter(mgr,name),26,13);
            }
            items.push({"sprite":line,"parent":left,"width":RW,"height":30,
               "use":name != Profiles.DEFAULT ? profileDeleter(mgr,name) : null,
               "about":name == Profiles.DEFAULT ? "The game's own profile: what everyone used before. It can't be deleted." :
               "Delete this profile and everything it remembers (press DELETE twice). Players using it go back to Default."});
            y += 31;
         }
         var add:Sprite = new Sprite();
         add.x = 10;
         add.y = y + 8;
         left.addChild(add);
         UiKit.rect(add,0,0,RW,44,UiKit.BODY,6);
         addProfile = input(add,12,10,300,"new profile name");
         addProfile.maxChars = 16;
         actionButton(add,"CREATE",330,9,function():void
         {
            var n:String = addProfile.text.replace(/^\s+|\s+$/g,"");
            var made:Boolean = Profiles.create(mgr,n);
            if(made)
            {
               delete typed["new profile name"];
            }
            restartNote = made ? "Created " + n + ". Pick it for a keyboard or controller above." :
               "A profile name is 1-16 letters, digits, spaces, - or _, and not one that exists.";
            build();
         });
         UiKit.rect(left,0,y + 60,10,10,UiKit.BODY,0).alpha = 0;
         aboutPanel("ABOUT PROFILES");
         if(describe != null && describe.text == "")
         {
            describe.text = "Profiles hold your controls: key bindings for the keyboard and button mappings for each controller. " +
               "Legend looks are shared by every profile. Save different looks as setups on character select.";
         }
      }

      private function deviceChanger(mgr:class_310, id:uint) : Function
      {
         return function(dir:int):void
         {
            Profiles.cycleDevice(mgr,id,dir);
         };
      }

      private function profileDeleter(mgr:class_310, name:String) : Function
      {
         return function():void
         {
            if(deleting != name)
            {
               deleting = name;
               restartNote = "Press DELETE again to delete " + name + ".";
            }
            else
            {
               deleting = null;
               restartNote = Profiles.remove(mgr,name) ? "Deleted " + name + "." : "Couldn't delete " + name + ".";
            }
            build();
         };
      }

      private static const KEY_ACTIONS:Array = [1,2,4,29,3,5,6,9,8,7,13,14,15,16,51,52,53,54,10,30];
      private static const KEY_SECTIONS:Array = ["MOVEMENT",null,null,null,null,null,"ATTACKS",null,null,null,
         "EMOTES",null,null,null,null,null,null,null,"OTHER",null];

      private function buildControls() : void
      {
         var mapper:class_230 = owner.var_7206;
         var dev:int = int(owner.var_12133);
         var multi:Boolean = Main.useMultiKeyboard;
         var left:Sprite = scroller(side(area.x,LW),0,0,LW,area.height);
         var pads:Array = connectedPads();
         if(controlsDevice < 0 || controlsDevice > pads.length)
         {
            controlsDevice = usingController() && pads.length > 0 ? 1 : 0;
         }
         var deviceNames:Array = ["Keyboard"];
         for each(var pd:class_87 in pads)
         {
            deviceNames.push(String(pd.var_12619.var_5585.var_15259));
         }
         row(left,8,RW,"DEVICE",deviceNames[controlsDevice] + (deviceNames.length > 1 ? "  (" + (controlsDevice + 1) + "/" +
            deviceNames.length + ")" : ""),"Which device's keys or buttons this tab shows. Left/right switch between the " +
            "keyboard and each connected controller.",function(dir:int):void
            {
               controlsDevice = (controlsDevice + dir + deviceNames.length) % deviceNames.length;
            },deviceNames.length > 1);
         var y:Number = 48;
         if(controlsDevice > 0)
         {
            y = buildPads(left,y,pads[controlsDevice - 1]);
            buildMappingRow(left,y);
            aboutPanel("ABOUT THIS BUTTON");
            return;
         }
         UiKit.text(left,"KEYBOARD  (profile " + Profiles.deviceProfile(owner.var_261,0) + ")",12,y,14,UiKit.GREY,UiKit.XBOLD);
         y += 24;
         row(left,y,RW,localizedKey("UI_Keybind_Prioritize").toUpperCase(),mapper.var_7146 ? "On" : "Off",
            "The game's own option from its keyboard Controls screen. Saved at once.",function(dir:int):void
            {
               mapper.var_7146 = !mapper.var_7146;
               saveKeys();
            },!multi);
         y += 31;
         row(left,y,RW,localizedKey("UI_ControllerDevices_PickUpWithQuick").toUpperCase(),!mapper.var_7262 ? "On" : "Off",
            "Light attack also picks up weapons and items, as the throw key does. The game's own keyboard option from its " +
            "old controller settings. Saved at once.",function(dir:int):void
            {
               mapper.var_7262 = !mapper.var_7262;
               saveKeys();
            },!multi);
         y += 31;
         for(var i:int = 0; i < KEY_ACTIONS.length; i++)
         {
            var section:String = KEY_SECTIONS[i];
            if(section != null)
            {
               y += 8;
               UiKit.text(left,section,12,y,13,UiKit.GREY,UiKit.XBOLD);
               if(i == 0)
               {
                  UiKit.text(left,"PRIMARY",RW - 230,y,13,UiKit.GREY,UiKit.XBOLD,0,true);
                  UiKit.text(left,"SECONDARY",RW - 75,y,13,UiKit.GREY,UiKit.XBOLD,0,true);
               }
               y += 22;
            }
            var action:int = KEY_ACTIONS[i];
            var label:String = localizedKey(class_458.var_3962[i]);
            var line:Sprite = new Sprite();
            line.x = 10;
            line.y = y;
            left.addChild(line);
            UiKit.rect(line,0,0,RW,30,UiKit.BODY,6);
            UiKit.fit(UiKit.text(line,label,12,5,14,UiKit.WHITE,UiKit.BOLD),300);
            var boxes:Array = [];
            for(var c:int = 0; c < 2; c++)
            {
               var box:Sprite = new Sprite();
               box.x = c == 0 ? RW - 310 : RW - 155;
               box.y = 3;
               box.buttonMode = true;
               line.addChild(box);
               var caught:Boolean = capturing != null && capturing.action == action && capturing.secondary == (c == 1);
               box.addEventListener(MouseEvent.CLICK,keyBoxClick(items.length,action,c,label));
               boxes.push({"sprite":box,"name":caught ? "??" : keyName(mapper,action,dev,c == 1)});
            }
            items.push({"sprite":line,"parent":left,"width":RW,"height":30,"boxes":boxes,"label":label,
               "change":keyColumn,
               "use":keyCatcher(action,label),
               "option":keyEraser(action),
               "about":label + ". Press " + Prompts.KEYS.select + " (or click a key), then press the new key. Esc clears it. " +
               "Left and right switch between the primary and secondary key, and " + Prompts.KEYS.option + " clears the " +
               "selected one."});
            y += 31;
         }
         var reset:Sprite = new Sprite();
         reset.x = 10;
         reset.y = y + 6;
         left.addChild(reset);
         UiKit.rect(reset,0,0,RW,40,UiKit.BODY,6);
         var resetAct:Function = function():void
         {
            if(!resetting)
            {
               resetting = true;
               restartNote = "Press RESET again to put every key back to the game's defaults.";
            }
            else
            {
               resetting = false;
               mapper.method_2477(dev);
               mapper.method_4618(dev);
               mapper.var_7146 = false;
               applyKeys(mapper,dev);
               restartNote = "Keys reset to the game's defaults and saved.";
            }
            build();
         };
         button(reset,resetting ? "SURE?" : "RESET ALL KEYS",12,6,240,resetAct,28,13);
         items.push({"sprite":reset,"parent":left,"width":RW,"height":40,"use":multi ? null : resetAct,"label":"RESET ALL KEYS",
            "about":"Every key back to the game's defaults (press twice)."});
         y += 56;
         if(pads.length == 0)
         {
            UiKit.text(left,"CONTROLLERS: none connected",12,y,14,UiKit.GREY,UiKit.XBOLD);
            y += 26;
         }
         UiKit.rect(left,0,y + 10,10,10,UiKit.BODY,0).alpha = 0;
         aboutPanel(multi ? "SEVERAL KEYBOARDS" : "ABOUT THIS COMMAND");
         if(multi && describe != null)
         {
            describe.text = "Several keyboards is on: each keyboard has its own keys. Set them from the game's Controls " +
               "screen (More > CONTROLS) with that keyboard.";
         }
      }

      private static function connectedPads() : Array
      {
         var out:Array = [];
         for each(var dev:class_87 in class_112.var_9206)
         {
            if(dev != null && dev.mID != 0 && dev.var_12619 != null && dev.var_12619.var_5585 != null && dev.method_4184())
            {
               out.push(dev);
            }
         }
         return out;
      }

      private function buildMappingRow(left:Sprite, y:Number) : void
      {
         var pad:Sprite = new Sprite();
         pad.x = 10;
         pad.y = y;
         left.addChild(pad);
         UiKit.rect(pad,0,0,RW,40,UiKit.BODY,6);
         UiKit.text(pad,"THE GAME'S MAPPING SCREEN",12,10,14,UiKit.WHITE,UiKit.BOLD);
         var padAct:Function = function():void
         {
            close();
            if(hub != null)
            {
               hub.method_3541(4);
            }
         };
         button(pad,"BUTTON MAPPING",380,6,240,padAct,28,13);
         items.push({"sprite":pad,"parent":left,"width":RW,"height":40,"use":padAct,"label":"BUTTON MAPPING",
            "about":"The game's own controller mapping screen (per controller, saved to that controller's profile)."});
         UiKit.rect(left,0,y + 50,10,10,UiKit.BODY,0).alpha = 0;
      }

      private static function buttonIcon(line:Sprite, hk:HotkeyType, input:String) : void
      {
         var art:MovieClip = null;
         try
         {
            var clipName:Object = hk.var_13723.method_4935(input);
            if(clipName != null)
            {
               art = class_687.method_1714(String(clipName),hk.clipLibrary);
            }
            if(art != null && hk.var_11561 != null && hk.var_11561.exists(input))
            {
               art.rotation = Number(hk.var_11561.method_4935(input));
            }
         }
         catch(e:Error)
         {
            art = null;
         }
         if(art == null)
         {
            return;
         }
         UiKit.icon(line,art,10,3,24);
         line.getChildAt(1).x += 30;
      }

      private function buildPads(left:Sprite, y:Number, only:class_87) : Number
      {
         var mgr:class_310 = owner.var_261;
         for each(var dev:class_87 in [only])
         {
            var type:ControllerType = dev.var_12619.var_5585;
            var mapping:ControllerMappingType = dev.var_12619.var_10840;
            UiKit.text(left,String(type.var_15259).toUpperCase() + "  (profile " + Profiles.deviceProfile(mgr,dev.mID) + ")",12,y,
               14,UiKit.GREY,UiKit.XBOLD);
            y += 24;
            for(var t:int = 0; t < PAD_TOGGLES.length; t++)
            {
               row(left,y,RW,localizedKey(PAD_TOGGLES[t]).toUpperCase(),mapping != null && padFlag(mapping,t) ? "On" : "Off","The game's own mapping " +
                  "option. Saved at once to this controller's profile.",padToggle(dev,t));
               y += 31;
            }
            var hk:HotkeyType = type.var_11260;
            for each(var input:String in hk.var_10910)
            {
               if(Commands.var_9815.method_4935(input) || type.buttons.method_4935(input) == null)
               {
                  continue;
               }
               var shown:String = input.toUpperCase();
               if(String(type.var_15259).indexOf("PS") == 0 && PS_NAMES[shown] != null)
               {
                  shown = PS_NAMES[shown];
               }
               var line0:Sprite = row(left,y,RW,shown,padCommandLabel(mapping,input),
                  "What this button does. Press " + Prompts.KEYS.select + " to pick from the list, or use left and right " +
                  "to go through the commands.",padChanger(dev,input));
               items[items.length - 1].use = padPicker(dev,input,shown);
               line0.addEventListener(MouseEvent.CLICK,padPicker(dev,input,shown));
               buttonIcon(line0,hk,input);
               y += 31;
            }
            var reset:Function = padReset(dev);
            var line:Sprite = new Sprite();
            line.x = 10;
            line.y = y + 4;
            left.addChild(line);
            UiKit.rect(line,0,0,RW,40,UiKit.BODY,6);
            button(line,"DEFAULT BUTTONS",12,6,240,reset,28,13);
            items.push({"sprite":line,"parent":left,"width":RW,"height":40,"use":reset,"label":"DEFAULT BUTTONS",
               "about":"This controller's buttons back to the game's defaults for its type."});
            y += 56;
         }
         return y;
      }

      private static const PAD_TOGGLES:Array = ["UI_ControllerKeybinds_UpToJump","UI_ControllerKeybinds_RightStickTaunts",
         "UI_ControllerKeybinds_QuickPicksUp","UI_ControllerKeybinds_RadialStickInterpretation"];

      private static function padFlag(m:ControllerMappingType, i:int) : Boolean
      {
         return i == 0 ? m.var_14864 : (i == 1 ? !m.var_948 : (i == 2 ? !m.var_7262 : !m.var_15264));
      }

      private static function setPadFlag(m:ControllerMappingType, i:int, on:Boolean) : void
      {
         if(i == 0)
         {
            m.var_14864 = on;
         }
         else if(i == 1)
         {
            m.var_948 = !on;
         }
         else if(i == 2)
         {
            m.var_7262 = !on;
         }
         else
         {
            m.var_15264 = !on;
         }
      }

      private static const PS_NAMES:Object = {"A":"CROSS","B":"CIRCLE","X":"SQUARE","Y":"TRIANGLE","LB":"L1","RB":"R1","LT":"L2",
         "RT":"R2","BACK":"CREATE / SHARE","START":"OPTIONS"};

      private static function padCommand(mapping:ControllerMappingType, input:String) : String
      {
         if(mapping != null)
         {
            for each(var id:uint in Commands.var_13267)
            {
               var on:Array = mapping.method_5841(false,id);
               if(on != null && on.indexOf(input) >= 0)
               {
                  return String(Commands.var_10028.method_4935(id));
               }
            }
         }
         return "Disabled";
      }

      private static function padCommandLabel(mapping:ControllerMappingType, input:String) : String
      {
         var command:String = padCommand(mapping,input);
         var key:Object = Commands.var_12002.method_4935(command == "Disabled" ? "Disable" : command);
         return key != null ? localizedKey(String(key)) : "Disabled";
      }

      private static function padCopy(dev:class_87) : ControllerMappingType
      {
         var copy:ControllerMappingType = new ControllerMappingType();
         ControllerMappingType.method_2641("Custom",copy,dev.var_12619.var_10840);
         return copy;
      }

      private function padSave(dev:class_87, copy:ControllerMappingType) : void
      {
         var name:String = Profiles.deviceProfile(owner.var_261,dev.mID);
         var standard:ControllerMappingType = ControllerMappingType.method_7051(dev.var_12619.var_5585);
         if(ControllerMappingType.method_8682(copy,standard))
         {
            owner.var_261.method_4659(dev.var_10827,name,copy);
         }
         else
         {
            owner.var_261.method_4659(dev.var_10827,name);
         }
         dev.var_12619.method_2657(copy);
         restartNote = "Saved to profile " + name + ".";
      }

      private function padChanger(dev:class_87, input:String) : Function
      {
         return function(dir:int):void
         {
            if(!dev.method_4184())
            {
               return;
            }
            var names:Array = padCommandNames();
            var at:int = names.indexOf(padCommandName(dev,input));
            padSet(dev,input,names[(Math.max(0,at) + dir + names.length) % names.length]);
         };
      }

      private static function padCommandNames() : Array
      {
         var names:Array = [];
         for each(var n:String in Commands.var_9358)
         {
            if(!Commands.var_4773.method_4935(n))
            {
               names.push(n);
            }
         }
         return names;
      }

      private static function padCommandName(dev:class_87, input:String) : String
      {
         var current:String = padCommand(dev.var_12619.var_10840,input);
         return current == "Disabled" ? "Disable" : current;
      }

      private function padSet(dev:class_87, input:String, command:String) : void
      {
         var copy:ControllerMappingType = padCopy(dev);
         copy.method_4012(false,input);
         copy.method_5498(false,uint(Commands.var_6823.method_4935(command)),input);
         padSave(dev,copy);
      }

      private function padPicker(dev:class_87, input:String, shown:String) : Function
      {
         return function(e:MouseEvent = null):void
         {
            if(!dev.method_4184())
            {
               return;
            }
            var names:Array = padCommandNames();
            var labels:Array = [];
            for each(var n:String in names)
            {
               var key:Object = Commands.var_12002.method_4935(n);
               labels.push(key != null ? localizedKey(String(key)) : n);
            }
            pickFrom(shown + ": WHAT IT DOES",labels,names.indexOf(padCommandName(dev,input)),function(i:int):void
            {
               padSet(dev,input,names[i]);
               rebuildKeepFocus();
            });
         };
      }

      private function padToggle(dev:class_87, i:int) : Function
      {
         return function(dir:int):void
         {
            if(!dev.method_4184())
            {
               return;
            }
            var copy:ControllerMappingType = padCopy(dev);
            setPadFlag(copy,i,!padFlag(copy,i));
            padSave(dev,copy);
         };
      }

      private function padReset(dev:class_87) : Function
      {
         return function():void
         {
            if(!dev.method_4184())
            {
               return;
            }
            var copy:ControllerMappingType = new ControllerMappingType();
            ControllerMappingType.method_2641("Custom",copy,ControllerMappingType.method_7051(dev.var_12619.var_5585));
            padSave(dev,copy);
            build();
         };
      }

      private function keyColumn(dir:int) : void
      {
         keyCol = dir < 0 ? 0 : 1;
      }

      private static function localizedKey(key:String) : String
      {
         try
         {
            var s:String = class_256.method_1351(key);
            if(s != null && s != "")
            {
               return s;
            }
         }
         catch(e:Error)
         {
         }
         return key;
      }

      private static function keyName(mapper:class_230, action:int, dev:int, secondary:Boolean) : String
      {
         var s:String = mapper.method_7962(mapper.method_932(action,dev,false,secondary,false));
         return s == null || s == "" ? class_458.var_8162 : s;
      }

      private function paintKeyBoxes() : void
      {
         for(var i:int = 0; i < items.length; i++)
         {
            var it:Object = items[i];
            if(it.boxes == null)
            {
               continue;
            }
            for(var c:int = 0; c < 2; c++)
            {
               var b:Object = it.boxes[c];
               var sp:Sprite = b.sprite;
               while(sp.numChildren > 0)
               {
                  sp.removeChildAt(0);
               }
               var picked:Boolean = i == focus && c == keyCol;
               UiKit.rect(sp,0,0,140,24,picked ? UiKit.TEAL : UiKit.PANEL,5);
               UiKit.fit(UiKit.text(sp,b.name,70,2,14,picked ? UiKit.NAVY_TEXT : UiKit.TEAL,UiKit.BOLD,0,true),130);
            }
         }
      }

      private function keyBoxClick(index:int, action:int, col:int, label:String) : Function
      {
         return function(e:MouseEvent):void
         {
            e.stopPropagation();
            focus = index;
            keyCol = col;
            keyCatcher(action,label)();
         };
      }

      private function keyCatcher(action:int, label:String) : Function
      {
         return function():void
         {
            if(Main.useMultiKeyboard || capturing != null)
            {
               return;
            }
            capturing = {"action":action,"secondary":keyCol == 1,"label":label};
            restartNote = "Press a key for " + label + (keyCol == 1 ? " (secondary)" : "") + ". Esc erases it.";
            build();
         };
      }

      private function keyEraser(action:int) : Function
      {
         return function():void
         {
            if(Main.useMultiKeyboard || capturing != null)
            {
               return;
            }
            bindKeyNow(action,255,keyCol == 1);
            restartNote = "Key erased. Saved.";
            build();
         };
      }

      public function keyDownHook(e:Object) : Boolean
      {
         if(eatKey >= 0 && int(e.keyCode) == eatKey)
         {
            eatKey = -1;
            swallowUp[int(e.keyCode)] = true;
            return true;
         }
         if(capturing == null || !isActive)
         {
            return false;
         }
         var code:int = int(e.keyCode);
         swallowUp[code] = true;
         catchKey(code == Keyboard.ESCAPE ? 255 : code);
         return true;
      }

      public function keyUpHook(e:Object) : Boolean
      {
         var code:int = int(e.keyCode);
         if(swallowUp[code])
         {
            delete swallowUp[code];
            return true;
         }
         return false;
      }

      private function catchKey(key:int) : void
      {
         var mapper:class_230 = owner.var_7206;
         if(!mapper.method_4054(key))
         {
            restartNote = "That key can't be used. Pick another key for " + capturing.label + ".";
            build();
            return;
         }
         var c:Object = capturing;
         stopCatching();
         bindKeyNow(int(c.action),key,Boolean(c.secondary));
         restartNote = key == 255 ? c.label + ": key erased. Saved." : c.label + ": " + mapper.method_7962(key) + ". Saved.";
         build();
      }

      private function stopCatching() : void
      {
         capturing = null;
      }

      private function bindKeyNow(action:int, key:int, secondary:Boolean) : void
      {
         var mapper:class_230 = owner.var_7206;
         var dev:int = int(owner.var_12133);
         mapper.method_2477(dev);
         var twins:IMap = class_458.var_10202;
         if(key != 255 && !GameApp.isMac && twins != null && twins.exists(key))
         {
            bindInCopy(mapper,dev,action,int(twins.method_4935(key)),!secondary);
         }
         bindInCopy(mapper,dev,action,key,secondary);
         applyKeys(mapper,dev);
      }

      private static function bindInCopy(mapper:class_230, dev:int, action:int, key:int, secondary:Boolean) : void
      {
         var old:uint = uint(mapper.method_932(action,dev,true,secondary));
         mapper.method_3104(old,dev,true,false);
         mapper.method_3104(old,dev,true,true);
         mapper.method_3104(key,dev,true,false);
         mapper.method_3104(key,dev,true,true);
         if(!secondary)
         {
            mapper.bindKey(action,key,dev,true,true);
         }
         else
         {
            mapper.method_5455(action,key,dev,true,true);
         }
      }

      private function applyKeys(mapper:class_230, dev:int) : void
      {
         mapper.method_2683(dev);
         saveKeys();
         mapper.method_6846();
      }

      private function saveKeys() : void
      {
         ScreenManager.var_12001.method_3987();
      }

      override public function HandleInput(input:int) : Boolean
      {
         if(capturing != null)
         {
            if(input == 18 || input == 19)
            {
               stopCatching();
               restartNote = "Cancelled.";
               build();
            }
            return true;
         }
         if(input == 20 && method_5588() && !blockInput() && !keyboardOpen)
         {
            searchWithKeyboard();
            return true;
         }
         if((input == 18 || input == 19) && query != "" && method_5588() && !blockInput() && !keyboardOpen)
         {
            setQuery("");
            return true;
         }
         return super.HandleInput(input);
      }

      override public function OnClearScreen() : void
      {
         stopCatching();
         super.OnClearScreen();
      }

      private static const LAUNCH_SECTIONS:Array = [
         [0,"LOOK",["-noskulls","-showversion"]],
         [0,"INPUT",["-steamdeck"]],
         [1,"STREAMING",["-broadcaster","-spectatedelay"]]];

      private function launchRows() : void
      {
         var saved:Object = LaunchOptions.saved();
         var placed:Object = {};
         for each(var sec:Array in LAUNCH_SECTIONS.concat([[1,"MORE",null]]))
         {
            var mine:Array = [];
            for each(var opt:Array in LaunchOptions.ALL)
            {
               if(sec[2] != null ? (sec[2] as Array).indexOf(opt[0]) >= 0 : !placed[opt[0]])
               {
                  mine.push(opt);
               }
            }
            if(mine.length == 0)
            {
               continue;
            }
            section(colY[0] <= colY[1] ? 0 : 1,sec[1]);
            for each(opt in mine)
            {
               placed[opt[0]] = true;
               var flag:String = opt[0];
               var value:* = saved[flag];
               var shown:String = opt[3] == "toggle" ? (value ? "On" : "Off") : (value ? launchNumber(flag,int(value)) : "Off");
               colRow(String(opt[1]).toUpperCase(),shown,opt[2] + " (" + flag + ") " + opt[5],launchChanger(opt));
            }
            sectionEnd();
         }
      }

      private function launchChanger(opt:Array) : Function
      {
         return function(dir:int):void
         {
            var flag:String = opt[0];
            var value:* = LaunchOptions.saved()[flag];
            if(opt[3] == "toggle")
            {
               LaunchOptions.set(flag,!value);
            }
            else
            {
               var values:Array = opt[4];
               var at:int = values.indexOf(int(value || 0));
               LaunchOptions.set(flag,values[(Math.max(0,at) + dir + values.length) % values.length]);
            }
            restartNote = opt[1] + ": " + opt[5];
         };
      }

      private static function launchNumber(flag:String, value:int) : String
      {
         return flag == "-spectatedelay" ? (value < 1000 ? value + " ms" : value / 1000 + " s") : String(value);
      }

      private function buildMore() : void
      {
         var left:Sprite = side(area.x,LW);
         var entries:Array = [
            ["IMAGE RENDER TOOL","The game's tool for rendering legends and items to images.",function():void
            {
               close();
               ScreenManager.var_7811.Display();
            }],
            ["UNLOCK ACHIEVEMENTS","Your Steam achievements: see which you have and unlock any of them (owner, 2026-10-12).",
            function():void
            {
               close();
               AchievementsWindow.open();
            }],
            ["SAVE FILE EDITOR","See and change what the game saved: settings, profile picks, key bindings (owner, 2026-10-12). " +
            "Some changes show after a restart.",
            function():void
            {
               close();
               SaveEditorWindow.open();
            }],
            ["IMPORT OFFICIAL SAVE","Copy the official game's save (settings, key bindings, profile picks) over this game's " +
            "the next time it starts. Values only this game has stay. Press twice.",
            function():void
            {
               if(SaveCopy.importPending())
               {
                  restartNote = "The official save is imported the next time the game starts: close it and start it again.";
               }
               else if(!importArmed)
               {
                  importArmed = true;
                  restartNote = "Press IMPORT OFFICIAL SAVE again: your settings, key bindings and picks are replaced by " +
                     "the official game's at the next start.";
               }
               else
               {
                  importArmed = false;
                  restartNote = SaveCopy.requestImport() ? "Done: close the game and start it again to import the official save." :
                     "Couldn't set up the import (see bh-errors.txt).";
               }
            }]];
         var y:Number = 10;
         for each(var en:Array in entries)
         {
            var line:Sprite = new Sprite();
            line.x = 10;
            line.y = y;
            line.buttonMode = true;
            left.addChild(line);
            UiKit.rect(line,0,0,RW,40,UiKit.BODY,6);
            UiKit.text(line,en[0],14,10,15,UiKit.WHITE,UiKit.BOLD);
            var act:Function = en[2];
            line.addEventListener(MouseEvent.CLICK,clicker(act));
            items.push({"sprite":line,"width":RW,"height":40,"use":act,"about":en[1],"label":en[0]});
            y += 46;
         }
         aboutPanel("ABOUT");
      }

      private function clicker(act:Function) : Function
      {
         return function(e:MouseEvent):void
         {
            act();
         };
      }

      override protected function blockInput() : Boolean
      {
         return typing();
      }

      override protected function hintText() : String
      {
         return defaultHint() + "     {Alt} SEARCH";
      }

      private var query:String = "";
      private var found:Array = [];
      private var index:Array = null;
      private var indexing:Boolean = false;
      private var searchBox:TextField;
      private var searchHint:TextField;
      private var eatKey:int = -1;
      private static const SEARCHED:Array = [0,1,2,5,6,7,8];

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
         searchHint = UiKit.text(box,"SEARCH SETTINGS",10,4,13,UiKit.GREY,UiKit.MEDIUM);
         searchBox.addEventListener(Event.CHANGE,function(e:Event):void
         {
            setQuery(searchBox.text,false);
         });
         searchBox.addEventListener(KeyboardEvent.KEY_DOWN,function(e:KeyboardEvent):void
         {
            if(e.keyCode == Keyboard.ENTER || e.keyCode == Keyboard.DOWN || e.keyCode == Keyboard.ESCAPE)
            {
               eatKey = e.keyCode;
               if(body.stage != null)
               {
                  body.stage.focus = null;
               }
               if(e.keyCode == Keyboard.ESCAPE)
               {
                  setQuery("");
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

      private function searchWithKeyboard() : void
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
         typeText("SEARCH SETTINGS",query,30,function(v:String):void
         {
            setQuery(v);
         });
      }

      private function setQuery(q:String, toBox:Boolean = true) : void
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
         if(q == query)
         {
            return;
         }
         query = q;
         if(q == "")
         {
            index = null;
         }
         else if(index == null)
         {
            index = buildIndex();
         }
         found = q == "" ? [] : match(q);
         focus = 0;
         build();
      }

      private function buildIndex() : Array
      {
         var out:Array = [];
         var keepBody:Sprite = tabBody;
         var keepItems:Array = items;
         var keepScrollers:Array = scrollers;
         var keepTab:int = tab;
         indexing = true;
         try
         {
            for each(var t:int in SEARCHED)
            {
               tabBody = new Sprite();
               items = [];
               scrollers = [];
               tab = t;
               try
               {
                  buildTab(t);
               }
               catch(e:Error)
               {
                  ErrorLog.write("options search: tab " + t + ": " + e);
               }
               for(var i:int = 0; i < items.length; i++)
               {
                  var it:Object = items[i];
                  if(it.label != null && String(it.label) != "")
                  {
                     out.push({"tab":t,"item":i,"label":String(it.label),"about":it.about != null ? String(it.about) : "","plain":it.about != null ? Prompts.plain(String(it.about)) : ""});
                  }
               }
            }
         }
         finally
         {
            indexing = false;
            tabBody = keepBody;
            items = keepItems;
            scrollers = keepScrollers;
            tab = keepTab;
            describe = null;
            addHost = addName = addProfile = null;
         }
         return out;
      }

      private function match(q:String) : Array
      {
         var words:Array = q.toLowerCase().split(/\s+/);
         var byName:Array = [];
         var byAbout:Array = [];
         for each(var e:Object in index)
         {
            var name:String = e.label.toLowerCase();
            var about:String = e.plain.toLowerCase();
            var inName:Boolean = true;
            var inAbout:Boolean = true;
            for each(var w:String in words)
            {
               inName = inName && name.indexOf(w) >= 0;
               inAbout = inAbout && (name.indexOf(w) >= 0 || about.indexOf(w) >= 0);
            }
            if(inName)
            {
               byName.push(e);
            }
            else if(inAbout)
            {
               byAbout.push(e);
            }
         }
         return byName.concat(byAbout).slice(0,60);
      }

      private function buildResults() : void
      {
         var left:Sprite = scroller(side(area.x,LW),0,0,LW,area.height);
         UiKit.text(left,"RESULTS FOR \"" + query.toUpperCase() + "\"",12,8,14,UiKit.GREY,UiKit.XBOLD);
         var y:Number = 32;
         for each(var e:Object in found)
         {
            var line:Sprite = new Sprite();
            line.x = 10;
            line.y = y;
            line.buttonMode = true;
            left.addChild(line);
            UiKit.rect(line,0,0,RW,30,UiKit.BODY,6);
            UiKit.fit(UiKit.text(line,e.label.toUpperCase(),12,5,14,UiKit.WHITE,UiKit.BOLD),440);
            var where:TextField = UiKit.text(line,TABS[e.tab],618,6,12,UiKit.TEAL,UiKit.XBOLD);
            where.x = 618 - where.width;
            var go:Function = goTo(e.tab,e.item);
            line.addEventListener(MouseEvent.CLICK,clicker(go));
            items.push({"sprite":line,"parent":left,"width":RW,"height":30,"use":go,
               "about":(e.about != "" ? e.about + "\n\n" : "") + "On the " + TABS[e.tab] + " tab."});
            y += 34;
         }
         if(found.length == 0)
         {
            UiKit.text(left,"Nothing found. Try another word.",12,y,14,UiKit.LIGHT,UiKit.MEDIUM);
         }
         UiKit.rect(left,0,y + 10,10,10,UiKit.BODY,0).alpha = 0;
         aboutPanel("ABOUT THIS SETTING");
      }

      private function goTo(t:int, item:int) : Function
      {
         return function():void
         {
            setQuery("");
            if(t != tab)
            {
               showTab(t);
            }
            focus = Math.max(0,Math.min(item,items.length - 1));
            paintFocus();
         };
      }

      override public function OnDestroyScreen() : void
      {
         current = null;
         super.OnDestroyScreen();
      }
   }
}
