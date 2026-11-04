package bh.platform
{
   import flash.desktop.Clipboard;
   import flash.desktop.ClipboardFormats;
   import flash.display.Bitmap;
   import flash.display.BitmapData;
   import flash.display.Shape;
   import flash.display.DisplayObject;
   import flash.display.MovieClip;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.KeyboardEvent;
   import flash.events.MouseEvent;
   import flash.geom.Rectangle;
   import flash.system.ApplicationDomain;
   import flash.text.TextField;
   import flash.text.TextFieldType;
   import flash.text.TextFormat;
   import flash.ui.Keyboard;
   import flash.utils.getDefinitionByName;
   import flash.utils.getTimer;

   public class LoadoutWindow extends BigWindow
   {
      private static const TABS:Array = ["LOOK","EXTRAS","SETUPS"];
      private static const GROUPS:Array = [[0,1,2,3],[4,5,6,7],null];
      private static const CAT_NAMES:Array = ["SKIN","COLOUR","WEAPON 1","WEAPON 2","SIDEKICK","COMPANION","EMITTER","STANCE"];
      private static const SETUPS_TAB:int = 2;
      override protected function get fullPage() : Boolean
      {
         return true;
      }

      private function get PREVIEW_W() : Number
      {
         return Math.max(360,Math.round(area.width * 0.3));
      }

      private function get LIST_X() : Number
      {
         return area.x + PREVIEW_W + 10;
      }

      private function get LIST_W() : Number
      {
         return area.right - LIST_X;
      }
      private static const DOLL_H:Number = 262;
      private static const STANCE_Y:Number = DOLL_H + 90;
      private static const STANCE_STATS:Array = ["STRENGTH","DEXTERITY","DEFENSE","SPEED"];

      private static var window:LoadoutWindow;
      private static var weaponPictures:Object = {};
      private static var weaponPictureCount:int = 0;

      private var screen:Object;
      private var slot:int = -1;
      private var device:int = -1;
      private var previewHolder:MovieClip;
      private var previewInfo:TextField;
      private var doll:PaperDoll;
      private var extraDolls:Array = [];
      private var dirty:Boolean = true;
      private var builtBare:Boolean = false;
      private var lastDraw:int = 0;
      private var note:String = "";
      private var deleteArmed:int = -1;
      private var focusCat:int = -1;
      private var extrasStrip:Sprite;
      private var stanceBox:Sprite;
      private var stanceFocus:Object = null;
      private var stanceKey:String = "";
      private var pendingPictures:Array = [];
      private var picturesFor:Object = null;

      public function LoadoutWindow(core:GameCore)
      {
         super(core);
      }

      public static function open(cs:Object, slot:int, device:int = -1) : void
      {
         if(window == null || ScreenManager.allScreens.indexOf(window) < 0)
         {
            window = new LoadoutWindow(ScreenManager.owner);
            ScreenManager.registerScreen(window);
            if(ScreenManager.var_14744 != null)
            {
               window.registrationIndex = ScreenManager.var_14744.registrationIndex;
            }
         }
         window.screen = cs;
         window.slot = slot;
         window.device = device;
         window.note = "";
         window.deleteArmed = -1;
         window.dirty = true;
         if(!window.isActive)
         {
            window.tab = 0;
            window.focus = 0;
            window.setSearch("",true,false);
            window.Display();
         }
         else
         {
            window.build();
         }
      }

      public static function get shown() : LoadoutWindow
      {
         return window != null && window.isActive ? window : null;
      }

      override protected function get title() : String
      {
         return "LOADOUT";
      }

      override protected function get tabNames() : Array
      {
         return TABS;
      }

      override protected function get tabLayout() : Array
      {
         return [-500,250,0.9];
      }

      override protected function get confirmLabel() : String
      {
         return "DONE";
      }

      override protected function statusText() : String
      {
         return note;
      }

      override protected function hintText() : String
      {
         var n:Object = Prompts.KEYS;
         return n.tabs + " TABS     " + n.page + " PAGE     " + n.select + " PICK     " + (tab == SETUPS_TAB ? n.option + (deleteArmed >= 0 ? " DELETE NOW     " : " DELETE     ") : "") +
            n.back + " BACK" + (tab != SETUPS_TAB ? "     {Alt} SEARCH" : "");
      }

      override protected function back() : void
      {
         clearDoll();
         Hide();
      }

      override public function HandleInput(input:int) : Boolean
      {
         if(device >= 0 && method_5588() && int(GameCore.var_10780) != device)
         {
            return true;
         }
         if(input == 20 && tab != SETUPS_TAB && method_5588() && !blockInput() && !keyboardOpen)
         {
            openSearch();
            return true;
         }
         return super.HandleInput(input);
      }

      private var search:String = "";
      private var searchBox:TextField;
      private var searchHint:TextField;
      private var searchHolder:Sprite;
      private static var keysHooked:Boolean = false;

      private function makeSearchBox() : void
      {
         if(!keysHooked)
         {
            keysHooked = true;
            Hooks.keyDown.add(function(event:Object):Boolean
            {
               return window != null && window.isActive && window.typing();
            });
         }
         searchHolder = new Sprite();
         searchHolder.x = area.right - 440;
         searchHolder.y = area.y - 92;
         searchHolder.buttonMode = true;
         body.addChild(searchHolder);
         UiKit.rect(searchHolder,0,0,220,26,UiKit.WHITE,5);
         searchBox = new TextField();
         searchBox.type = TextFieldType.INPUT;
         searchBox.defaultTextFormat = new TextFormat("_sans",14,UiKit.NAVY_TEXT);
         searchBox.x = 8;
         searchBox.y = 3;
         searchBox.width = 204;
         searchBox.height = 22;
         searchBox.maxChars = 30;
         searchHolder.addChild(searchBox);
         searchHint = UiKit.text(searchHolder,"SEARCH PICKS",10,4,13,UiKit.GREY,UiKit.MEDIUM);
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
         searchHolder.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
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
         typeText("SEARCH PICKS",search,30,function(v:String):void
         {
            setSearch(v);
         });
      }

      private function setSearch(q:String, toBox:Boolean = true, rebuild:Boolean = true) : void
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
         if(rebuild && isActive)
         {
            builtFresh = true;
            build();
         }
      }

      private function shownRows(x:Object, cat:int) : Array
      {
         var all:Array = rows(x,cat);
         if(search == "")
         {
            return all;
         }
         var q:String = search.toLowerCase();
         var out:Array = [];
         for each(var r:Object in all)
         {
            var owner:Object = r.owner;
            if(String(r.label).toLowerCase().indexOf(q) >= 0 ||
               owner != null && text(owner.mDisplayNameKey,owner.mCostumeName).toLowerCase().indexOf(q) >= 0)
            {
               out.push(r);
            }
         }
         return out;
      }

      private function context() : Object
      {
         if(screen == null || slot < 0)
         {
            return null;
         }
         try
         {
            var podium:Object = screen.method_8904(slot);
            var player:Object = podium != null ? screen.owner.var_6244.method_8549(slot) : null;
            if(player == null || !podium.var_5326 || player.var_5540 == null)
            {
               return null;
            }
            return {"podium":podium,"player":player,"owner":screen.owner};
         }
         catch(e:Error)
         {
         }
         return null;
      }

      override protected function tabOff(i:int) : Boolean
      {
         if(GROUPS[i] == null)
         {
            return false;
         }
         for each(var cat:int in GROUPS[i])
         {
            if(!catOff(cat))
            {
               return false;
            }
         }
         return true;
      }

      private function catOff(i:int) : Boolean
      {
         var x:Object = context();
         if(x == null)
         {
            return true;
         }
         try
         {
            var p:Object = x.podium;
            switch(i)
            {
               case 0:
                  return !p.method_2129(slot);
               case 1:
                  return !p.method_278(slot);
               case 2:
                  return p.var_12638 || p.mUsableWeapon1Skins == null;
               case 3:
                  return p.var_12638 || p.mUsableWeapon2Skins == null;
               case 4:
                  return !p.method_1928(slot);
               case 5:
                  return !p.method_4280(slot);
               case 6:
                  return !p.method_6422(slot);
               case 7:
                  return stances(x).length < 2;
            }
         }
         catch(e:Error)
         {
         }
         return false;
      }

      private static function text(key:String, fallback:String = null) : String
      {
         try
         {
            var s:String = key != null ? class_256.method_1351(key) : null;
            if(s != null && s != "" && s != key)
            {
               return s;
            }
         }
         catch(e:Error)
         {
         }
         return fallback != null ? fallback : key;
      }

      private function stances(x:Object) : Array
      {
         var hero:Object = x.player.var_5540.var_13881;
         var list:Object = x.owner.var_8329.method_842(hero);
         var out:Array = [];
         for(var i:int = 0; list != null && i < int(list.length); i++)
         {
            out.push(list[i]);
         }
         return out;
      }

      private function colours(x:Object) : Array
      {
         var list:Object = x.podium.var_5670;
         if(list == null)
         {
            var cs:Object = x.owner.var_6244;
            list = cs.method_1642(slot,x.player.var_2483,x.player.var_13724,cs.var_1751[slot].var_3540);
         }
         var out:Array = [];
         for(var i:int = 0; list != null && i < int(list.length); i++)
         {
            out.push(list[i]);
         }
         return out;
      }

      private static function weaponOrder(list:Object) : Array
      {
         var at:Array = [];
         for(var i:int = 0; i < int(list.length); i++)
         {
            at.push(i);
         }
         at.sort(function(a:int, b:int):int
         {
            var ca:Object = list[a].var_10030;
            var cb:Object = list[b].var_10030;
            if((ca == null) != (cb == null))
            {
               return ca == null ? -1 : 1;
            }
            if(ca != null)
            {
               var ha:int = list[a].var_10776 != null ? int(list[a].var_10776.var_12172) : 0;
               var hb:int = list[b].var_10776 != null ? int(list[b].var_10776.var_12172) : 0;
               if(ha != hb)
               {
                  return ha < hb ? -1 : 1;
               }
               if(int(ca.var_14823) != int(cb.var_14823))
               {
                  return int(ca.var_14823) < int(cb.var_14823) ? -1 : 1;
               }
            }
            return a < b ? -1 : a > b ? 1 : 0;
         });
         return at;
      }

      private function rows(x:Object, cat:int) : Array
      {
         var out:Array = [];
         var p:Object = x.podium;
         var player:Object = x.player;
         var data:Object = x.owner.var_8329;
         var list:Object;
         var i:int;
         var cur:int;
         switch(cat)
         {
            case 0:
               list = data.method_6632(player.var_5540,x.owner.var_6244.var_2390);
               cur = Setups.indexBy(list,function(c:Object):Boolean { return c == player.var_2483; });
               for(i = 0; i < int(list.length); i++)
               {
                  out.push({"label":text(list[i].mDisplayNameKey,list[i].mCostumeName),"current":i == cur,
                     "pick":stepper(x,0,cur,i,int(list.length)),"icon":list[i].var_12178});
               }
               break;
            case 1:
               var cl:Array = colours(x);
               for(i = 0; i < cl.length; i++)
               {
                  out.push({"label":text(cl[i].mDisplayNameKey,cl[i].mColorSchemeName),"current":cl[i] == player.var_13724,
                     "pick":colourPicker(x,cl[i]),"icon":cl[i].var_2697});
               }
               break;
            case 2:
            case 3:
               list = cat == 2 ? p.mUsableWeapon1Skins : p.mUsableWeapon2Skins;
               var w:Object = player.method_5489(cat == 2);
               cur = Setups.indexBy(list,function(o:Object):Boolean { return o == w; });
               for each(i in weaponOrder(list))
               {
                  out.push({"label":text(list[i].method_8192(p.var_5641),list[i].mWeaponSkinName),"current":i == cur,
                     "pick":stepper(x,cat,cur,i,int(list.length)),"icon":weaponIcon(list[i],player.var_2483,true),
                     "weapon":list[i],"owner":list[i].var_10030});
               }
               break;
            case 4:
               list = data.method_7796();
               var bots:Object = getClass("class_574").var_14155;
               cur = Setups.indexBy(list,function(id:uint):Boolean { return id == player.var_12740; });
               var botRows:Array = [];
               for(i = 0; i < int(list.length); i++)
               {
                  var bot:Object = bots[list[i]];
                  botRows.push({"label":text(bot != null ? bot.mDisplayNameKey : "UI_Random","Random"),"current":i == cur,
                     "pick":sidekickPicker(x,uint(list[i])),"icon":bot != null ? bot.var_2697 : "","id":uint(list[i])});
               }
               botRows.sortOn("id",Array.NUMERIC);
               out = out.concat(botRows);
               break;
            case 5:
               list = data.method_225(player.var_2483,player);
               var comp:Object = getClass("CompanionType").var_9851;
               var n:int = int(list.length) + 1;
               cur = player.var_5378 == 0 ? n - 1 : Setups.indexBy(list,function(id:uint):Boolean { return id == player.var_5378; });
               for(i = 0; i < n; i++)
               {
                  var t:Object = i < n - 1 ? comp.method_4935(list[i]) : null;
                  out.push({"label":text(t != null ? t.mDisplayNameKey : "CompanionType_NoCompanion_DisplayName","None"),
                     "current":i == cur,"pick":stepper(x,5,cur,i,n),"icon":t != null ? t.var_2697 : "a_Icon_Companion_NoCompanion"});
               }
               break;
            case 6:
               list = data.method_6850();
               var ems:Object = getClass("class_118").var_13975;
               cur = Setups.indexBy(list,function(id:uint):Boolean { return id == player.var_12121; });
               for(i = 0; i < int(list.length); i++)
               {
                  var em:Object = ems[list[i]];
                  out.push({"label":text(em != null ? em.mDisplayNameKey : null,"#" + list[i]),"current":i == cur,
                     "pick":stepper(x,6,cur,i,int(list.length)),"icon":em != null ? em.var_2697 : ""});
               }
               break;
            case 7:
               var st:Array = stances(x);
               for(i = 0; i < st.length; i++)
               {
                  out.push({"label":text(p.method_4038(st[i]),"Stance " + i),"current":uint(st[i].var_3173) == uint(player.var_5158),
                     "pick":stancePicker(x,uint(st[i].var_3173)),"icon":st[i].var_2697,"stance":st[i]});
               }
         }
         return out;
      }

      private function stepper(x:Object, cat:int, from:int, to:int, n:int) : Function
      {
         return function():void
         {
            var now:int = currentIndex(x,cat);
            Setups.step(x.podium,slot,x.player,cat,Setups.delta(now >= 0 ? now : from,to,n));
            done(x,cat);
         };
      }

      private function sidekickPicker(x:Object, id:uint) : Function
      {
         return function():void
         {
            var list:Object = x.owner.var_8329.method_7796();
            var to:int = Setups.indexBy(list,function(v:uint):Boolean { return v == id; });
            var now:int = currentIndex(x,4);
            if(to >= 0 && now >= 0)
            {
               Setups.step(x.podium,slot,x.player,4,Setups.delta(now,to,int(list.length)));
            }
            done(x,4);
         };
      }

      private function currentIndex(x:Object, cat:int) : int
      {
         var player:Object = x.player;
         var data:Object = x.owner.var_8329;
         var list:Object;
         switch(cat)
         {
            case 0:
               list = data.method_6632(player.var_5540,x.owner.var_6244.var_2390);
               return Setups.indexBy(list,function(c:Object):Boolean { return c == player.var_2483; });
            case 2:
            case 3:
               list = cat == 2 ? x.podium.mUsableWeapon1Skins : x.podium.mUsableWeapon2Skins;
               var w:Object = player.method_5489(cat == 2);
               return Setups.indexBy(list,function(o:Object):Boolean { return o == w; });
            case 4:
               return Setups.indexBy(data.method_7796(),function(id:uint):Boolean { return id == player.var_12740; });
            case 5:
               list = data.method_225(player.var_2483,player);
               return player.var_5378 == 0 ? int(list.length) :
                  Setups.indexBy(list,function(id:uint):Boolean { return id == player.var_5378; });
            case 6:
               return Setups.indexBy(data.method_6850(),function(id:uint):Boolean { return id == player.var_12121; });
         }
         return -1;
      }

      private function colourPicker(x:Object, target:Object) : Function
      {
         return function():void
         {
            var c0:Object = x.player.var_13724;
            var c:Object = c0;
            for(var k:int = 1; k <= 400 && c0 != target; k++)
            {
               c = x.owner.var_6244.method_1771(slot,x.player.var_2483,c,1,x.podium.var_5670);
               if(c == null || c == c0)
               {
                  break;
               }
               if(c == target)
               {
                  Setups.step(x.podium,slot,x.player,1,k);
                  break;
               }
            }
            done(x,1);
         };
      }

      private function stancePicker(x:Object, id:uint) : Function
      {
         return function():void
         {
            for(var k:int = 0; k < 12 && uint(x.player.var_5158) != id; k++)
            {
               Setups.step(x.podium,slot,x.player,7,1);
            }
            done(x,7);
         };
      }

      private function done(x:Object, cat:int) : void
      {
         x.podium.var_7434 = cat;
         x.podium.method_853(x.player,slot,false);
         screen.method_3789();
         dirty = true;
         note = "";
         deleteArmed = -1;
      }

      override public function OnCreateScreen() : void
      {
         super.OnCreateScreen();
         var box:Sprite = new Sprite();
         box.x = area.x;
         box.y = area.y;
         body.addChild(box);
         UiKit.rect(box,0,0,PREVIEW_W,area.height,UiKit.PANEL);
         UiKit.rect(box,10,10,PREVIEW_W - 20,DOLL_H,UiKit.BODY);
         previewHolder = new MovieClip();
         previewHolder.mouseEnabled = false;
         previewHolder.mouseChildren = false;
         box.addChild(previewHolder);
         previewHolder.mask = UiKit.rect(box,10,10,PREVIEW_W - 20,DOLL_H,0);
         extrasStrip = new Sprite();
         extrasStrip.x = 10;
         extrasStrip.y = 16 + DOLL_H;
         box.addChild(extrasStrip);
         stanceBox = new Sprite();
         stanceBox.x = 10;
         stanceBox.y = STANCE_Y;
         stanceBox.mouseEnabled = false;
         stanceBox.mouseChildren = false;
         box.addChild(stanceBox);
         stanceKey = "";
         previewInfo = UiKit.text(box,"",14,area.height - 60,12,UiKit.LIGHT,UiKit.MEDIUM,PREVIEW_W - 28);
         dirty = true;
         makeSearchBox();
      }

      private function clearDoll() : void
      {
         if(doll != null)
         {
            try
            {
               doll.method_5548();
            }
            catch(e:Error)
            {
            }
            doll = null;
         }
         for each(var d:PaperDoll in extraDolls)
         {
            try
            {
               d.method_5548();
            }
            catch(e2:Error)
            {
            }
         }
         extraDolls = [];
      }

      private function drawPreview() : void
      {
         var t0:int = getTimer();
         drawPreviewNow();
         if(getTimer() - t0 > 50)
         {
            Platform.log("loadout: slow preview: " + (getTimer() - t0) + " ms");
         }
      }

      private function drawPreviewNow() : void
      {
         dirty = false;
         lastDraw = getTimer();
         clearDoll();
         var x:Object = context();
         if(x == null || previewHolder == null)
         {
            if(previewInfo != null)
            {
               previewInfo.text = "The legend's picks are closed.";
            }
            drawStance(null);
            return;
         }
         var player:Object = x.player;
         var costume:CostumeType = player.var_2483 as CostumeType;
         try
         {
            if(costume != null)
            {
               var hero:HeroType = player.var_5540.var_13881 as HeroType;
               var holding:Boolean = focusCat == 2 || focusCat == 3;
               doll = new PaperDoll(owner,previewHolder,null,10 + (PREVIEW_W - 20) / 2 + (holding ? 40 : 0),DOLL_H - 8,null,
                  holding ? 0.8 : 0.95);
               var weapon:ItemType = holding && hero != null ?
                  ItemType.method_8638(focusCat == 2 ? hero.mBaseWeapon1 : hero.mBaseWeapon2) : null;
               var anim:String = weapon != null ? "Ready" : PaperDoll.method_637(costume.var_7289,costume);
               PaperDoll.method_5580(costume,player.var_13724,costume.var_7289,weapon != null ? uint(player.var_12551) :
                  costume.var_15258,doll,anim,null,null,weapon);
               doll.method_39(anim,true,true);
               doll.method_4082();
               if(!holding)
               {
                  drawBuddies(player);
               }
            }
         }
         catch(e:Error)
         {
            ErrorLog.write("loadout: preview failed: " + e + " " + e.getStackTrace());
         }
         drawExtras(x);
         drawStance(x);
         var w1:Object = player.method_5489(true);
         var w2:Object = player.method_5489(false);
         previewInfo.text = String(player.var_5540.var_13881.mDisplayName).toUpperCase() + "  ·  PLAYER " + (slot + 1) + "\n" +
            (costume != null ? text(costume.mDisplayNameKey,costume.mCostumeName) : "") + "  ·  " +
            (player.var_13724 != null ? text(player.var_13724.mDisplayNameKey,player.var_13724.mColorSchemeName) : "") + "\n" +
            (w1 != null ? text(w1.method_8192(x.podium.var_5641),w1.mWeaponSkinName) : "") + "  ·  " +
            (w2 != null ? text(w2.method_8192(x.podium.var_5641),w2.mWeaponSkinName) : "");
      }

      private function drawBuddies(player:Object) : void
      {
         var bot:class_574 = null;
         var comp:CompanionType = null;
         try
         {
            bot = class_574.var_14155[int(player.var_12740)] as class_574;
            comp = int(player.var_5378) != 0 ? CompanionType.var_9851.method_4935(uint(player.var_5378)) as CompanionType : null;
         }
         catch(e:Error)
         {
         }
         var picks:Array = [[bot,78,0.5],[comp,PREVIEW_W - 54,0.6]];
         for each(var pk:Array in picks)
         {
            if(pk[0] == null)
            {
               continue;
            }
            try
            {
               var d:PaperDoll = new PaperDoll(owner,previewHolder,null,pk[1],DOLL_H - 8,null,pk[2]);
               extraDolls.push(d);
               if(pk[0] is class_574)
               {
                  PaperDoll.method_8224(d,pk[0] as class_574,"Ready");
               }
               else
               {
                  PaperDoll.method_2757(d,pk[0] as CompanionType,"Ready");
               }
               d.method_39("Ready",true,true);
               d.method_4082();
            }
            catch(e2:Error)
            {
               ErrorLog.write("loadout: buddy preview failed: " + e2);
            }
         }
      }

      private function drawExtras(x:Object) : void
      {
         extrasStrip.removeChildren();
         var cats:Array = [4,5,6];
         var w:Number = (PREVIEW_W - 20) / cats.length;
         for(var k:int = 0; k < cats.length; k++)
         {
            var box:Sprite = new Sprite();
            box.x = k * w;
            extrasStrip.addChild(box);
            UiKit.rect(box,k > 0 ? 3 : 0,0,w - (k > 0 ? 3 : 0),66,UiKit.BODY,4);
            UiKit.text(box,CAT_NAMES[cats[k]],w / 2,2,9,UiKit.GREY,UiKit.XBOLD,0,true);
            if(catOff(cats[k]))
            {
               UiKit.text(box,"-",w / 2,26,12,UiKit.GREY,UiKit.MEDIUM,0,true);
               continue;
            }
            try
            {
               for each(var r:Object in rows(x,cats[k]))
               {
                  if(r.current)
                  {
                     var ic:DisplayObject = r.icon != null ? iconClip(r.icon) : null;
                     if(ic != null)
                     {
                        UiKit.icon(box,ic,w / 2 - 15,15,30);
                     }
                     var name:TextField = UiKit.fit(UiKit.text(box,r.label,0,48,10,UiKit.LIGHT,UiKit.MEDIUM),w - 8);
                     name.x = (w - name.width) / 2;
                     break;
                  }
               }
            }
            catch(e:Error)
            {
            }
         }
      }

      private function drawStance(x:Object) : void
      {
         if(stanceBox == null)
         {
            return;
         }
         var shown:Object = null;
         var equipped:Object = null;
         var base:Object = null;
         var name:String = "";
         try
         {
            if(x != null)
            {
               var hero:HeroType = x.player.var_5540.var_13881 as HeroType;
               var all:Object = hero != null ? class_356.method_285(hero.mHeroName) : null;
               equipped = hero != null ? class_356.method_4432(hero,uint(x.player.var_5158)) : null;
               base = all != null && int(all.length) > 0 ? all[0] : null;
               shown = stanceFocus != null && hero != null && stanceFocus.mHeroName == hero.mHeroName ? stanceFocus : equipped;
               if(shown != null)
               {
                  name = text(x.podium.method_4038(shown),"Stance " + shown.var_3173);
               }
            }
         }
         catch(e:Error)
         {
            shown = null;
         }
         var vals:Array = shown != null ? [int(shown.var_692),int(shown.var_202),int(shown.var_3217),int(shown.var_6905)] : [];
         var bases:Array = base != null ? [int(base.var_692),int(base.var_202),int(base.var_3217),int(base.var_6905)] : vals;
         var on:Boolean = shown != null && shown === equipped;
         var key:String = shown != null ? shown.mHeroName + "|" + shown.var_3173 + "|" + on + "|" + name + "|" + vals.join(",") + "|" +
            bases.join(",") : "";
         if(key == stanceKey)
         {
            return;
         }
         stanceKey = key;
         stanceBox.removeChildren();
         var room:Number = area.height - 66 - STANCE_Y;
         if(shown == null || room < 102)
         {
            return;
         }
         var w:Number = PREVIEW_W - 20;
         var rowH:Number = Math.min(22,Math.floor((room - 38) / 4));
         UiKit.rect(stanceBox,0,0,w,38 + rowH * 4,UiKit.BODY,4);
         var ic:DisplayObject = iconClip(shown.var_2697);
         if(ic != null)
         {
            UiKit.icon(stanceBox,ic,8,5,24);
         }
         var tag:TextField = UiKit.text(stanceBox,on ? "STANCE  ·  EQUIPPED" : "STANCE  ·  HIGHLIGHTED",0,11,9,on ? UiKit.TEAL : UiKit.GREY,
            UiKit.XBOLD);
         tag.x = w - 10 - tag.width;
         UiKit.fit(UiKit.text(stanceBox,name.toUpperCase(),40,8,13,on ? UiKit.TEAL : UiKit.WHITE,UiKit.BOLD),tag.x - 48);
         var barX:Number = 96;
         var slot:Number = (w - barX - 66) / 11;
         var pipH:Number = Math.min(10,rowH - 8);
         for(var k:int = 0; k < 4; k++)
         {
            var y:Number = 34 + k * rowH;
            var v:int = vals[k];
            var b:int = bases[k];
            UiKit.text(stanceBox,STANCE_STATS[k],10,y + (rowH - 15) / 2,10,UiKit.GREY,UiKit.XBOLD);
            var n:int = Math.min(11,Math.max(10,Math.max(v,b)));
            for(var p:int = 0; p < n; p++)
            {
               var c:uint = p < Math.min(v,b) ? UiKit.TEAL : (p < v ? UiKit.GOLD : (p < b ? UiKit.RED : UiKit.DIM));
               UiKit.rect(stanceBox,barX + p * slot,y + (rowH - pipH) / 2,slot - 3,pipH,c,2);
            }
            UiKit.text(stanceBox,String(v),w - 58,y + (rowH - 17) / 2,12,UiKit.WHITE,UiKit.BOLD);
            if(v != b)
            {
               UiKit.text(stanceBox,(v > b ? "+" : "-") + Math.abs(v - b),w - 34,y + (rowH - 17) / 2,12,v > b ? UiKit.GOLD : UiKit.RED,
                  UiKit.XBOLD);
            }
         }
      }

      override protected function everyFrame() : void
      {
         if(context() == null)
         {
            back();
            return;
         }
         if(builtBare)
         {
            builtBare = false;
            tab = 0;
            build();
         }
         if(dirty && getTimer() - lastDraw > 120)
         {
            drawPreview();
         }
         else if(pendingPictures.length > 0)
         {
            drawPendingPictures();
         }
      }

      override protected function buildTab(i:int) : void
      {
         var x:Object = context();
         pendingPictures = [];
         picturesFor = x != null ? x.player.var_2483 : null;
         stanceFocus = null;
         drawStance(x);
         var p:Sprite = panel(LIST_X,area.y,LIST_W,area.height);
         var list:Sprite = scroller(p,0,8,LIST_W,area.height - 16);
         builtBare = x == null;
         if(searchHolder != null)
         {
            searchHolder.visible = GROUPS[i] != null;
         }
         if(x == null)
         {
            UiKit.text(list,"Open your legend's picks on the podium first.",16,10,14,UiKit.GREY,UiKit.MEDIUM);
            return;
         }
         if(GROUPS[i] == null)
         {
            buildSetups(x,list);
            return;
         }
         list.parent.parent.removeChild(list.parent);
         scrollers.pop();
         var cats:Array = [];
         for each(var cat:int in GROUPS[i])
         {
            if(!catOff(cat))
            {
               cats.push(cat);
            }
         }
         var gap:Number = 6;
         var colW:Number = Math.floor((LIST_W - 12 - gap * (cats.length - 1)) / Math.max(1,cats.length));
         var curIndex:int = -1;
         for(var c:int = 0; c < cats.length; c++)
         {
            var cx:Number = 6 + c * (colW + gap);
            UiKit.text(p,CAT_NAMES[cats[c]],cx + 6,8,12,UiKit.GREY,UiKit.XBOLD);
            var col:Sprite = scroller(p,cx,30,colW,area.height - 38);
            var rs:Array = shownRows(x,cats[c]);
            if(rs.length == 0)
            {
               UiKit.text(col,"No match.",6,8,12,UiKit.GREY,UiKit.MEDIUM,colW - 14);
            }
            for(var r:int = 0; r < rs.length; r++)
            {
               cell(col,r,colW,rs[r].label,rs[r].current,rs[r].pick,rs[r].icon,c,cats[c],rs[r].weapon,rs[r].owner);
               if(rs[r].stance != null)
               {
                  items[items.length - 1].stance = rs[r].stance;
               }
               if(rs[r].current && builtFresh)
               {
                  scrollers[scrollers.length - 1].show = [r * 39 - 150,r * 39 + 186];
               }
               if(rs[r].current && (curIndex < 0 || cats[c] == focusCat))
               {
                  curIndex = items.length - 1;
               }
            }
         }
         if(builtFresh && curIndex >= 0)
         {
            focus = curIndex;
         }
         else if(builtFresh && search != "")
         {
            focus = 0;
         }
         builtFresh = false;
      }

      private function cell(parent:Sprite, index:int, w:Number, label:String, current:Boolean, pick:Function, icon:Object,
                            col:int, cat:int, weapon:Object = null, owner:Object = null) : void
      {
         var h:Number = 36;
         var line:Sprite = new Sprite();
         line.y = index * (h + 3);
         line.buttonMode = true;
         parent.addChild(line);
         var bg:Shape = UiKit.rect(line,0,0,w - 8,h,current ? UiKit.ROW_SELECTED : UiKit.BODY,5);
         var tx:Number = 10;
         var ic:DisplayObject = icon != null ? iconClip(icon) : null;
         var holder:Sprite = null;
         if(ic != null || weapon != null)
         {
            holder = UiKit.icon(line,ic,8,3,30);
            tx = 44;
         }
         if(weapon != null && !(icon is Bitmap))
         {
            pendingPictures.push({"holder":holder,"weapon":weapon});
         }
         var badge:Number = 0;
         var oc:DisplayObject = owner != null && owner.var_12178 != null ? iconClip(owner.var_12178) : null;
         if(oc != null)
         {
            badge = 30;
            UiKit.icon(line,oc,w - 8 - 30,5,26);
         }
         var name:TextField = UiKit.fit(UiKit.text(line,label,tx,(h - 18) / 2,12,current ? UiKit.TEAL : UiKit.LIGHT,UiKit.BOLD),
            w - 8 - tx - 6 - badge);
         var it:int = items.length;
         var act:Function = function():void
         {
            var t0:int = getTimer();
            try
            {
               if(pick != null)
               {
                  pick();
               }
            }
            catch(e:Error)
            {
               ErrorLog.write("loadout pick: " + e + " " + e.getStackTrace());
            }
            var t1:int = getTimer();
            var how:String = repaintCurrent() ? "repaint" : "rebuild";
            if(how == "rebuild")
            {
               build();
            }
            if(getTimer() - t0 > 50)
            {
               Platform.log("loadout: slow pick: " + (t1 - t0) + " ms the podium's own refresh, window " + how + " " + (getTimer() - t1) + " ms");
            }
         };
         line.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            focus = it;
            act();
         });
         items.push({"sprite":line,"parent":parent,"width":w - 8,"height":h,"use":act,"label":label,"col":col,"cat":cat,
            "bg":bg,"name":name,"current":current,"w":w - 8,
            "holder":holder,"weapon":weapon});
      }

      private function repaintCurrent() : Boolean
      {
         var x:Object = context();
         if(x == null || GROUPS[tab] == null)
         {
            return false;
         }
         var byCat:Object = {};
         for each(var it:Object in items)
         {
            if(it.bg != null)
            {
               (byCat[it.cat] = byCat[it.cat] || []).push(it);
            }
         }
         for(var catKey:String in byCat)
         {
            var cells:Array = byCat[catKey];
            var rs:Array = shownRows(x,int(catKey));
            if(rs.length != cells.length)
            {
               return false;
            }
            for(var r:int = 0; r < rs.length; r++)
            {
               var c:Object = cells[r];
               if(c.label != rs[r].label)
               {
                  return false;
               }
               if(Boolean(c.current) != Boolean(rs[r].current))
               {
                  c.current = rs[r].current;
                  c.bg.graphics.clear();
                  c.bg.graphics.beginFill(c.current ? UiKit.ROW_SELECTED : UiKit.BODY);
                  c.bg.graphics.drawRoundRect(0,0,c.w,36,5,5);
                  c.bg.graphics.endFill();
                  c.name.textColor = c.current ? UiKit.TEAL : UiKit.LIGHT;
               }
            }
         }
         var costume:Object = x.player.var_2483;
         if(costume !== picturesFor)
         {
            picturesFor = costume;
            pendingPictures = [];
            for each(var wc:Object in items)
            {
               if(wc.weapon != null && wc.holder != null)
               {
                  pendingPictures.push({"holder":wc.holder,"weapon":wc.weapon});
               }
            }
         }
         dirty = true;
         return true;
      }


      override protected function useItem(it:Object, dir:int) : void
      {
         if(dir == 0 || it.col == null)
         {
            super.useItem(it,dir);
            return;
         }
         var y:Number = it.sprite.y + it.parent.y;
         var best:int = -1;
         var bestD:Number = Number.MAX_VALUE;
         for(var i:int = 0; i < items.length; i++)
         {
            if(items[i].col == it.col + dir)
            {
               var d:Number = Math.abs(items[i].sprite.y + items[i].parent.y - y);
               if(d < bestD)
               {
                  bestD = d;
                  best = i;
               }
            }
         }
         if(best >= 0)
         {
            focus = best;
            paintFocus();
         }
      }

      override protected function moveIn(it:Object, dir:int) : Boolean
      {
         if(it.col == null)
         {
            return false;
         }
         var n:int = focus + dir;
         return n < 0 || n >= items.length || items[n].col != it.col;
      }

      override protected function focused(it:Object) : void
      {
         var cat:int = it.cat != null ? int(it.cat) : -1;
         if(cat != focusCat)
         {
            var wasWeapon:Boolean = focusCat == 2 || focusCat == 3;
            focusCat = cat;
            if(wasWeapon || cat == 2 || cat == 3)
            {
               dirty = true;
            }
         }
         var st:Object = it.stance != null ? it.stance : null;
         if(st !== stanceFocus)
         {
            stanceFocus = st;
            drawStance(context());
         }
      }

      private var builtFresh:Boolean = true;

      override protected function showTab(i:int) : void
      {
         builtFresh = true;
         super.showTab(i);
      }

      override public function Display() : void
      {
         builtFresh = true;
         super.Display();
      }

      private function row(parent:Sprite, index:int, label:String, current:Boolean, pick:Function, option:Function = null,
                           color:uint = 0xFFFFFF, icon:Object = null) : void
      {
         var w:Number = LIST_W - 24;
         var h:Number = icon != null ? 38 : 30;
         var line:Sprite = new Sprite();
         line.x = 10;
         line.y = index * (h + 4);
         line.buttonMode = true;
         parent.addChild(line);
         UiKit.rect(line,0,0,w,h,current ? UiKit.ROW_SELECTED : UiKit.BODY,6);
         var tx:Number = 16;
         if(icon != null)
         {
            UiKit.icon(line,iconClip(icon),12,3,32);
            tx = 56;
         }
         UiKit.fit(UiKit.text(line,label,tx,(h - 20) / 2,14,current ? UiKit.WHITE : (color != 0xFFFFFF ? color : UiKit.LIGHT),UiKit.BOLD),w - 140);
         if(current)
         {
            var t:TextField = UiKit.text(line,"EQUIPPED",w - 14,(h - 18) / 2,12,UiKit.TEAL,UiKit.XBOLD);
            t.x = w - 14 - t.width;
         }
         var it:int = items.length;
         var act:Function = function():void
         {
            var t0:int = getTimer();
            try
            {
               if(pick != null)
               {
                  pick();
               }
            }
            catch(e:Error)
            {
               ErrorLog.write("loadout pick: " + e + " " + e.getStackTrace());
            }
            var t1:int = getTimer();
            build();
            Platform.log("loadout: pick " + (t1 - t0) + " ms (the podium's own refresh), window rebuild " + (getTimer() - t1) + " ms");
         };
         line.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            focus = it;
            act();
         });
         items.push({"sprite":line,"parent":parent,"width":w,"height":h,"use":act,"option":option,"label":label});
      }

      private function buildSetups(x:Object, list:Sprite) : void
      {
         var legend:String = String(x.player.var_5540.var_13881.mHeroName);
         var setups:Array = Setups.forLegend(legend);
         var r:int = 0;
         for(var i:int = 0; i < setups.length; i++)
         {
            row(list,r++,setups[i].name + (deleteArmed == i ? "   (press DELETE again)" : ""),
               false,setupPicker(x,setups[i]),setupDeleter(legend,i));
         }
         row(list,r++,"+ SAVE AS NEW",false,function():void
         {
            Setups.saveNew(x.player);
            note = "Saved as " + Setups.forLegend(legend)[Setups.forLegend(legend).length - 1].name + ".";
         },null,UiKit.TEAL);
         row(list,r++,"COPY CODE",false,function():void
         {
            try
            {
               Clipboard.generalClipboard.setData(ClipboardFormats.TEXT_FORMAT,Setups.code(x.player,legend.toUpperCase() + " SETUP"));
               note = "Code for this look copied. Send it to a friend, who picks IMPORT CODE.";
            }
            catch(e:Error)
            {
               note = "Couldn't copy the code.";
            }
         },null,UiKit.TEAL);
         row(list,r++,"IMPORT CODE",false,function():void
         {
            var text:String = null;
            try
            {
               text = Clipboard.generalClipboard.getData(ClipboardFormats.TEXT_FORMAT) as String;
            }
            catch(e:Error)
            {
            }
            var got:Object = Setups.importCode(text);
            note = got == null ? "No setup code on the clipboard. Copy one first." :
               got.legend == legend ? "Imported " + got.name + "." : "Imported " + got.name + " for " + got.legend + ".";
         },null,UiKit.TEAL);
      }

      private function setupPicker(x:Object, s:Object) : Function
      {
         return function():void
         {
            Setups.apply(x.podium,slot,x.player,s);
            screen.method_3789();
            dirty = true;
            deleteArmed = -1;
            note = s.name + " put on.";
         };
      }

      private function setupDeleter(legend:String, i:int) : Function
      {
         return function():void
         {
            if(deleteArmed != i)
            {
               deleteArmed = i;
               build();
               return;
            }
            var list:Array = Setups.forLegend(legend);
            note = "Deleted " + list[i].name + ".";
            list.splice(i,1);
            Setups.storeList(legend,list);
            deleteArmed = -1;
            build();
         };
      }

      private static function iconClip(icon:Object) : DisplayObject
      {
         if(icon is DisplayObject)
         {
            return icon as DisplayObject;
         }
         var name:String = icon as String;
         try
         {
            if(name != null && name != "")
            {
               var clip:MovieClip = class_687.method_1714(name,"UI_Icons");
               if(clip != null)
               {
                  clip.stopAllMovieClips();
               }
               return clip;
            }
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private static function weaponIcon(w:Object, costume:Object, cachedOnly:Boolean = false) : Object
      {
         var key:String = String(w.mWeaponSkinName) + "|" + (costume != null ? String(costume.mCostumeName) : "");
         var kept:BitmapData = weaponPictures[key] as BitmapData;
         if(kept != null)
         {
            var again:Bitmap = new Bitmap(kept);
            again.smoothing = true;
            return again;
         }
         if(cachedOnly)
         {
            return fallbackIcon(w);
         }
         try
         {
            var bmp:Bitmap = class_51.method_7309(ScreenManager.owner,w as class_725,costume as CostumeType,64).method_7455();
            if(bmp != null && bmp.bitmapData != null)
            {
               var data:BitmapData = bmp.bitmapData.clone();
               if(++weaponPictureCount > 600)
               {
                  weaponPictures = {};
                  weaponPictureCount = 1;
               }
               weaponPictures[key] = data;
               var copy:Bitmap = new Bitmap(data);
               copy.smoothing = true;
               return copy;
            }
         }
         catch(e:Error)
         {
         }
         return fallbackIcon(w);
      }

      private static function fallbackIcon(w:Object) : Object
      {
         try
         {
            return w.var_2697 && ApplicationDomain.currentDomain.hasDefinition(w.var_2697) ? w.var_2697 :
               "a_WeaponIcon_" + w.var_12803;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private function drawPendingPictures() : void
      {
         var x:Object = context();
         var t0:int = getTimer();
         while(pendingPictures.length > 0 && getTimer() - t0 < 4)
         {
            var p:Object = pendingPictures.shift();
            var pic:Bitmap = x != null ? weaponIcon(p.weapon,x.player.var_2483) as Bitmap : null;
            if(pic == null || p.holder == null)
            {
               continue;
            }
            var h:Sprite = p.holder;
            h.removeChildren();
            h.addChild(pic);
            var b:Rectangle = pic.getBounds(h);
            if(b.width > 0 && b.height > 0)
            {
               pic.scaleX = pic.scaleY = Math.min(30 / b.width,30 / b.height);
               b = pic.getBounds(h);
               pic.x -= b.x + b.width / 2 - 15;
               pic.y -= b.y + b.height / 2 - 15;
            }
         }
      }

      private static function getClass(name:String) : Object
      {
         return Object(getDefinitionByName(name));
      }
   }
}
