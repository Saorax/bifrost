package bh.platform
{
   import flash.display.MovieClip;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.events.MouseEvent;
   import flash.text.TextField;

   public class SettingsWindow extends BigWindow
   {
      protected var game:Object;
      private var refreshIn:int = 0;
      private var lastValues:String = "";
      private var closingNow:Boolean = false;

      public function SettingsWindow(core:GameCore)
      {
         super(core);
      }

      protected function optionTabs() : Array
      {
         return [];
      }

      protected function tick() : Boolean
      {
         return false;
      }

      override protected function get fullPage() : Boolean
      {
         return true;
      }

      protected function get COL_W() : Number
      {
         return Math.floor((area.width - 10) / 2);
      }

      protected function get LIST_W() : Number
      {
         return Math.round(area.width * 0.4);
      }

      protected function get DX() : Number
      {
         return area.x + LIST_W + 14;
      }

      protected function get DW() : Number
      {
         return area.right - DX;
      }

      protected function get logName() : String
      {
         return title.toLowerCase();
      }

      protected function canEdit() : Boolean
      {
         try
         {
            return Boolean(game.method_8786());
         }
         catch(e:Error)
         {
         }
         return true;
      }

      override protected function tabOff(i:int) : Boolean
      {
         if(optionTabs().indexOf(i) < 0)
         {
            return false;
         }
         try
         {
            var t:Object = tabEnum(i);
            return t != null && Boolean(game.method_2191(t));
         }
         catch(e:Error)
         {
         }
         return false;
      }

      public function attach(screen:Object) : void
      {
         game = screen;
         hideGame(true);
         if(body != null)
         {
            build();
         }
      }

      protected function hideGame(hidden:Boolean) : void
      {
         try
         {
            if(game != null && game.panelClip != null && game.panelClip.parent != null)
            {
               game.panelClip.parent.visible = !hidden;
            }
         }
         catch(e:Error)
         {
         }
      }

      protected function tabEnum(i:int) : Object
      {
         var tabs:Array = game != null ? game.var_6777 as Array : null;
         return tabs != null && i < tabs.length ? tabs[i] : null;
      }

      protected function widgets(i:int) : Array
      {
         var out:Array = [];
         var t:Object = tabEnum(i);
         if(t == null)
         {
            return out;
         }
         var list:Object = Object(game.var_12155).method_4935(t);
         for(var k:int = 0; list != null && k < int(list.length); k++)
         {
            try
            {
               game.method_7359(list[k]);
               game.method_610(list[k]);
            }
            catch(e:Error)
            {
            }
            out.push(list[k]);
         }
         return out;
      }

      protected static function textOf(lt:Object) : String
      {
         try
         {
            return lt != null && lt.var_2544 != null ? String(lt.var_2544.text) : "";
         }
         catch(e:Error)
         {
         }
         return "";
      }

      protected static function kindOf(w:Object) : String
      {
         return String(w.var_987);
      }

      protected static function optionName(w:Object) : String
      {
         return String(w.var_5108);
      }

      protected static function isIcons(w:Object) : Boolean
      {
         var k:String = kindOf(w);
         return k == "IconGroup" || k == "IconGroupFull";
      }

      protected static function labelOf(w:Object) : String
      {
         var s:String = textOf(w.var_8347);
         if(s == "" || s == "DESCRIPTION" || s == "-")
         {
            var name:String = optionName(w).replace(/^(Game|Lobby|Player|Bot)_/,"");
            name = name.replace(/Selections.*$/,"").replace(/([a-z])([A-Z])/g,"$1 $2");
            s = name.toUpperCase();
         }
         return s;
      }

      protected static function valueOf(w:Object) : String
      {
         if(kindOf(w) == "InputText")
         {
            return w.var_1544 != null ? String(w.var_1544) : "";
         }
         if(w.var_6220)
         {
            return textOf(w.var_3587);
         }
         return w.var_1421 != null ? textOf(w.var_1421) : "";
      }

      protected static function localized(key:String) : String
      {
         try
         {
            var s:String = class_256.method_1351(key);
            return s != null && s != "" ? s : key;
         }
         catch(e:Error)
         {
         }
         return key;
      }

      protected static function iconSelected(w:Object, icon:Object) : Boolean
      {
         if(w.var_15084)
         {
            return (uint(w.var_11019) & (1 << uint(icon.var_6750))) == 0;
         }
         return uint(icon.var_12730) == uint(w.var_11419);
      }

      protected function editable(w:Object) : Boolean
      {
         return w != null && canEdit() && !w.var_3019 && w.var_3713;
      }

      protected function change(w:Object, dir:int) : void
      {
         if(!editable(w))
         {
            return;
         }
         try
         {
            w.method_3428(null,dir);
         }
         catch(e:Error)
         {
            Platform.log(logName + ": changing " + optionName(w) + " failed: " + e.message);
         }
         refresh(true);
      }

      protected function pickIcon(w:Object, icon:Object) : void
      {
         if(!editable(w))
         {
            return;
         }
         try
         {
            w.method_3941(null,icon);
         }
         catch(e:Error)
         {
            Platform.log(logName + ": picking in " + optionName(w) + " failed: " + e.message);
         }
         refresh(true);
      }

      protected function select(w:Object) : void
      {
         if(!editable(w) || !w.var_11986)
         {
            return;
         }
         try
         {
            game.method_591(w);
            w.method_5698();
         }
         catch(e:Error)
         {
            Platform.log(logName + ": " + optionName(w) + " failed: " + e.message);
         }
         refresh(true);
      }

      protected function editText(w:Object) : void
      {
         if(w == null || !canEdit() || w.var_3019)
         {
            return;
         }
         try
         {
            ScreenManager.var_11000.method_6837(game,w.var_11333,w.var_9809,w.var_3050);
         }
         catch(e:Error)
         {
            Platform.log(logName + ": text input failed: " + e.message);
         }
      }

      protected function itemAction(it:Object, dir:int) : Boolean
      {
         return false;
      }

      override protected function back() : void
      {
         close(true);
      }

      override protected function useItem(it:Object, dir:int) : void
      {
         if(itemAction(it,dir))
         {
            return;
         }
         if(dir != 0)
         {
            if(it.w != null)
            {
               change(it.w,dir);
            }
         }
         else if(it.kind == "button")
         {
            it.act();
         }
         else if(it.kind == "InputText")
         {
            editText(it.w);
         }
         else if(it.w != null && it.w.var_11986)
         {
            select(it.w);
         }
         else if(it.w != null && isIcons(it.w) && it.w.var_15084)
         {
            change(it.w,0);
         }
         else if(it.w != null)
         {
            change(it.w,1);
         }
      }

      override protected function optionItem(it:Object) : void
      {
         if(it.w != null && isIcons(it.w) && it.w.var_15084)
         {
            change(it.w,0);
         }
         else
         {
            super.optionItem(it);
         }
      }

      protected function close(apply:Boolean) : void
      {
         if(closingNow)
         {
            return;
         }
         closingNow = true;
         try
         {
            Hide();
            hideGame(false);
            if(apply && game != null && game.isActive)
            {
               game.method_6245();
            }
         }
         catch(e:Error)
         {
            Platform.log(logName + ": closing failed: " + e.getStackTrace());
         }
         closingNow = false;
      }

      public function get isClosing() : Boolean
      {
         return closingNow;
      }

      protected function get gameMenu() : String
      {
         return null;
      }

      override protected function get pageAction() : Array
      {
         return gameMenu != null ? ["GAME'S MENU",useGameMenu] : null;
      }

      protected function useGameMenu() : void
      {
         if(closingNow || game == null)
         {
            return;
         }
         var screen:Object = game;
         GameMenus.setOwn(gameMenu,true);
         closingNow = true;
         try
         {
            Hide();
            hideGame(false);
         }
         catch(e:Error)
         {
            Platform.log(logName + ": switching to the game's menu failed: " + e.getStackTrace());
         }
         closingNow = false;
         GameMenus.offer(screen,gameMenu);
      }

      override protected function everyFrame() : void
      {
         if(game == null)
         {
            return;
         }
         if(!game.isActive)
         {
            close(false);
            return;
         }
         hideGame(true);
         if(tick())
         {
            return;
         }
         if(++refreshIn >= 20)
         {
            refreshIn = 0;
            refresh(false);
         }
      }

      protected function refresh(always:Boolean) : void
      {
         if(always || signature() != lastValues)
         {
            build();
         }
      }

      protected function signature() : String
      {
         var parts:Array = [canEdit(),tab];
         if(optionTabs().indexOf(tab) < 0)
         {
            return parts.join("|") + extraSignature();
         }
         for each(var i:int in optionTabs())
         {
            for each(var w:Object in widgets(i))
            {
               parts.push(optionName(w) + w.var_3713 + w.var_3019 + w.var_11419 + w.var_11019 + valueOf(w));
            }
         }
         return parts.join("|") + extraSignature();
      }

      protected function extraSignature() : String
      {
         return "";
      }

      override protected function build() : void
      {
         if(game != null)
         {
            super.build();
         }
      }

      override protected function built() : void
      {
         lastValues = signature();
      }

      protected static function rowHeight(w:Object, about:String = null, width:Number = 0) : Number
      {
         return (isIcons(w) ? (wraps(w,width) ? 70 : 46) : 30) + (about != null && about != "" ? 16 : 0);
      }

      private static function wraps(w:Object, width:Number) : Boolean
      {
         var list:Object = w.var_11509;
         return width > 0 && list != null && width * 0.44 + int(list.length) * 38 > width;
      }

      protected function row(parent:Sprite, w:Object, x:Number, y:Number, width:Number, about:String = null, label:String = null) : Number
      {
         var k:String = kindOf(w);
         var line:Sprite = new Sprite();
         line.x = x;
         line.y = y;
         parent.addChild(line);
         var canChange:Boolean = canEdit() && !w.var_3019;
         var icons:Boolean = isIcons(w);
         var wrapped:Boolean = icons && wraps(w,width);
         var h:Number = icons ? (wrapped ? 70 : 46) : 30;
         var extra:Number = about != null && about != "" ? 16 : 0;
         var indent:Number = w.var_475 ? 18 : 0;
         var bg:Shape = UiKit.rect(line,0,0,width,h + extra - 3,UiKit.BODY,6);
         UiKit.fit(UiKit.text(line,label != null ? label : labelOf(w),10 + indent,icons && !wrapped ? 12 : 5,14,canChange ? UiKit.WHITE : UiKit.GREY,
            UiKit.BOLD),width * 0.42 - indent);
         if(extra > 0)
         {
            UiKit.fit(UiKit.text(line,about,10 + indent,h - 6,11,UiKit.GREY,UiKit.MEDIUM),width - 20 - indent);
         }
         var cursor:Shape = null;
         if(icons)
         {
            var list:Object = w.var_11509;
            var ix:Number = wrapped ? 10 + indent : width * 0.44;
            var iy:Number = wrapped ? 28 : 4;
            var multi:Boolean = Boolean(w.var_15084);
            for(var i:int = 0; list != null && i < int(list.length); i++)
            {
               var icon:Object = list[i];
               var on:Boolean = iconSelected(w,icon);
               var cell:Sprite = new Sprite();
               cell.x = ix + i * 38;
               cell.y = iy;
               cell.buttonMode = canChange;
               line.addChild(cell);
               UiKit.rect(cell,0,0,34,34,on ? UiKit.TEAL : UiKit.LINE,6);
               UiKit.rect(cell,2,2,30,30,on ? UiKit.ROW_SELECTED : UiKit.BODY,6);
               var art:MovieClip = class_687.method_1714(icon.var_2697,"UI_GameSettings") ||
                  class_687.method_1714(ScoringType.TIMED.var_2697,"UI_GameSettings");
               if(art != null)
               {
                  UiKit.gotoLabel(art,on ? "Ready" : "Inactive");
               }
               UiKit.icon(cell,art,4,4,26);
               cell.addEventListener(MouseEvent.CLICK,iconPicker(w,icon));
               if(multi && i == int(w.var_11419))
               {
                  cursor = new Shape();
                  cursor.graphics.lineStyle(2,UiKit.WHITE);
                  cursor.graphics.drawRoundRect(cell.x - 3,iy - 3,40,40,10,10);
                  cursor.visible = items.length == focus;
                  line.addChild(cursor);
               }
            }
         }
         else if(k == "InputText")
         {
            UiKit.fit(UiKit.text(line,valueOf(w) || "(none)",width * 0.44,5,14,UiKit.TEAL,UiKit.MEDIUM),width * 0.4);
            if(canChange)
            {
               smallButton(line,"EDIT",width - 64,3,56,function():void
               {
                  editText(w);
               });
            }
         }
         else
         {
            var value:TextField = UiKit.text(line,valueOf(w),width * 0.72,5,14,UiKit.TEAL,UiKit.BOLD,0,true);
            UiKit.fit(value,width * 0.36);
            value.x = width * 0.72 - value.width / 2;
            if(canChange)
            {
               UiKit.arrow(line,width * 0.5,3,-1,function():void
               {
                  change(w,-1);
               });
               UiKit.arrow(line,width - 30,3,1,function():void
               {
                  change(w,1);
               });
               if(w.var_11986)
               {
                  smallButton(line,"DO",width * 0.5 - 56,3,48,function():void
                  {
                     select(w);
                  });
               }
            }
         }
         var item:Object = {"kind":k,"w":w,"sprite":line,"bg":bg,"width":width,"height":h + extra - 3,"parent":parent,
            "cursor":cursor};
         line.addEventListener(MouseEvent.CLICK,itemFocuser(items.length));
         items.push(item);
         return h + extra;
      }

      private function smallButton(parent:Sprite, label:String, x:Number, y:Number, w:Number, act:Function) : Sprite
      {
         return button(parent,label,x,y,w,act,21,13);
      }

      protected function iconPicker(w:Object, icon:Object) : Function
      {
         return function(e:MouseEvent):void
         {
            e.stopPropagation();
            pickIcon(w,icon);
         };
      }

   }
}
