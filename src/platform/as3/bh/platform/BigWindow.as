package bh.platform
{
   import flash.utils.getTimer;
   import flash.desktop.Clipboard;
   import flash.desktop.ClipboardFormats;
   import flash.display.MovieClip;
   import flash.display.Shape;
   import flash.display.DisplayObject;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.MouseEvent;
   import flash.events.KeyboardEvent;
   import flash.geom.Point;
   import flash.geom.Rectangle;
   import flash.text.TextField;
   import flash.text.TextFieldType;
   import flash.text.TextFormat;
   import flash.utils.Dictionary;

   public class BigWindow extends ScreenBase
   {
      protected static const HALF:Number = 540;
      protected static const LEFT:Number = -530;
      protected static const TOP:Number = -86;
      protected static const HEIGHT:Number = 408;
      protected static const SCREEN:Rectangle = new Rectangle(-683,-287,1366,768);

      protected var area:Rectangle = new Rectangle(LEFT,TOP,HALF * 2 - 20,HEIGHT);
      protected var screen:Rectangle = SCREEN.clone();

      protected var body:Sprite;
      protected var tabBody:Sprite;
      protected var tabClips:Array = [];
      protected var tab:int = 0;
      protected var status:TextField;
      protected var items:Array = [];
      protected var focus:int = 0;
      protected var scrollers:Array = [];
      private var builtTab:int = -1;
      private var hint:Sprite;
      private var hintShown:String;

      private static const OSK_ROWS:Array = ["1234567890","QWERTYUIOP","ASDFGHJKL-","ZXCVBNM_.:"];
      private static const OSK_SYMBOLS:String = "&~@,!#+*()";
      private var oskRows:Array = OSK_ROWS;
      private static const OSK_BOTTOM:Array = [["abc",0,2],["SPACE",2,2],["PASTE",4,2],["DEL",6,2],["DONE",8,2]];
      private var osk:Sprite;

      private var picker:Sprite;
      private var pickerHint:Sprite;
      private var pickNames:Array;
      private var pickTitle:String;
      private var pickAt:int = 0;
      private var pickDone:Function;
      private var pickCells:Array;
      private var dateBox:Sprite;
      private var dateHint:Sprite;
      private var dateTitle:String;
      private var dateAt:Date;
      private var dateMin:Number;
      private var dateMax:Number;
      private var dateDone:Function;
      private static const PICK_COLS:int = 3;
      private static const DOUBLE_MS:int = 400;
      private var oskHint:Sprite;
      private var oskTitle:String;
      private var oskText:String;
      private var oskMax:int;
      private var oskDone:Function;
      private var oskRow:int;
      private var oskCol:int;
      private var oskLower:Boolean;
      private var typedBox:TextField;
      private static var typingIn:BigWindow;
      private static var keyHook:Boolean = false;

      public static function anyOpen() : Boolean
      {
         try
         {
            for each(var screen:ScreenBase in ScreenManager.allScreens)
            {
               if(screen is BigWindow && screen.isActive)
               {
                  return true;
               }
            }
         }
         catch(e:Error)
         {
         }
         return false;
      }

      public function BigWindow(core:GameCore)
      {
         super(core,"a_ScreenNews","am_PanelInternal","UI_NewsPage");
         var_3798 = "FadeIn";
         var_14711 = "FadeOut";
         var_5327 = true;
      }

      protected function get title() : String
      {
         return "SETTINGS";
      }

      protected function get tabNames() : Array
      {
         return [];
      }

      protected function get tabLayout() : Array
      {
         return [-500,190,0.85];
      }

      protected function get confirmLabel() : String
      {
         return "CONFIRM";
      }

      protected function get pageAction() : Array
      {
         return null;
      }

      protected function get fullPage() : Boolean
      {
         return false;
      }

      protected function buildTab(i:int) : void
      {
      }

      protected function built() : void
      {
      }

      protected function statusText() : String
      {
         return "";
      }

      protected function tabOff(i:int) : Boolean
      {
         return false;
      }

      protected function back() : void
      {
         Hide();
      }

      protected function backKey() : void
      {
         back();
      }

      protected function everyFrame() : void
      {
      }

      protected function blockInput() : Boolean
      {
         return false;
      }

      protected function useItem(it:Object, dir:int) : void
      {
         if(dir == 0 && it.use != null)
         {
            it.use();
         }
         else if(it.change != null)
         {
            it.change(dir == 0 ? 1 : dir);
            build();
         }
      }

      protected function moveIn(it:Object, dir:int) : Boolean
      {
         return false;
      }

      protected function optionItem(it:Object) : void
      {
         if(it.option != null)
         {
            it.option();
         }
         else if(it.rightUse != null)
         {
            it.rightUse();
         }
         else
         {
            openContext(it);
         }
      }

      protected function hintText() : String
      {
         return null;
      }

      protected function focused(it:Object) : void
      {
      }

      private var openedFrom:ScreenBase;

      private static var opened:Array = [];

      public static function openWindows() : Array
      {
         return opened.filter(function(w:BigWindow, ... rest):Boolean
         {
            return w.isActive;
         });
      }

      override public function Display() : void
      {
         if(!isActive && ScreenBase.focusedScreen !== this)
         {
            openedFrom = ScreenBase.focusedScreen;
         }
         var at:int = opened.indexOf(this);
         if(at >= 0)
         {
            opened.splice(at,1);
         }
         opened.push(this);
         var reused:Boolean = body != null;
         super.Display();
         if(reused && body != null)
         {
            build();
         }
      }

      protected function covered() : Boolean
      {
         for(var i:int = opened.indexOf(this) + 1; i > 0 && i < opened.length; i++)
         {
            if(opened[i].isActive)
            {
               return true;
            }
         }
         return false;
      }

      public function returnTo() : void
      {
         if(!isActive)
         {
            Display();
         }
      }

      public function get trailName() : String
      {
         return title;
      }

      override public function Hide() : void
      {
         closeContext();
         closePicker();
         closeOsk();
         super.Hide();
         var at:int = opened.indexOf(this);
         if(at >= 0)
         {
            opened.splice(at,1);
         }
         handFocusBack(this,openedFrom);
         openedFrom = null;
      }

      public static function handFocusBack(window:ScreenBase, to:ScreenBase) : void
      {
         try
         {
            var clip:MovieClip = window.panelClip;
            if(clip != null && clip.stage != null && clip.stage.focus != null && clip.contains(clip.stage.focus))
            {
               clip.stage.focus = null;
            }
         }
         catch(e0:Error)
         {
         }
         try
         {
            if(ScreenBase.focusedScreen !== window)
            {
               return;
            }
            if(to != null && to !== window && to.isActive && to.method_336())
            {
               ScreenBase.setFocus(to);
            }
            else if(ScreenBase.previousFocusedScreen != null && ScreenBase.previousFocusedScreen !== window &&
                    ScreenBase.previousFocusedScreen.isActive)
            {
               ScreenBase.restorePreviousFocus();
            }
         }
         catch(e:Error)
         {
            ErrorLog.write("window: focus not handed back: " + e);
         }
      }

      override public function OnCreateScreen() : void
      {
         if(fullPage)
         {
            pageFrame();
         }
         else
         {
            body = UiKit.frame(this,title,HALF,function(e:MouseEvent = null, id:uint = 0):void
            {
               back();
            });
            var names:Array = tabNames;
            var layout:Array = tabLayout;
            for(var i:int = 0; i < names.length; i++)
            {
               tabClips.push(UiKit.tabButton(body,names[i],layout[0] + i * layout[1],-133,layout[2],tabPicker(i)));
            }
            var confirm:MovieClip = UiKit.tabButton(body,confirmLabel,-495,352,0.95,function():void
            {
               back();
            });
            confirm.scaleY = 0.9;
            status = UiKit.text(body,"",-110,360,15,UiKit.TEAL,UiKit.MEDIUM);
            hint = new Sprite();
            hint.y = 331;
            body.addChild(hint);
         }
         hintShown = null;
         body.addEventListener(Event.ENTER_FRAME,function(e:Event):void
         {
            if(isActive)
            {
               everyFrame();
            }
         });
         body.addEventListener(MouseEvent.MOUSE_DOWN,focusPressed);
         body.addEventListener(MouseEvent.RIGHT_CLICK,rightClicked);
         build();
      }

      private function pageScreen() : Rectangle
      {
         try
         {
            var clip:MovieClip = panelClip;
            if(clip != null && clip.stage != null)
            {
               var tl:Point = clip.globalToLocal(new Point(0,0));
               var br:Point = clip.globalToLocal(new Point(clip.stage.stageWidth,clip.stage.stageHeight));
               if(br.x - tl.x > 600 && br.y - tl.y > 300)
               {
                  return new Rectangle(tl.x,tl.y,br.x - tl.x,br.y - tl.y);
               }
            }
         }
         catch(e:Error)
         {
         }
         return SCREEN.clone();
      }

      private var pageTitle:Object;

      private function pageFrame() : void
      {
         var panel:MovieClip = panelClip;
         for(var i:int = 0; i < panel.numChildren; i++)
         {
            panel.getChildAt(i).visible = false;
         }
         screen = pageScreen();
         ErrorLog.write("page " + title + ": screen " + screen + (panel.stage == null ? " (not on the stage yet)" : ""));
         var r:Rectangle = screen;
         body = new Sprite();
         panel.addChild(body);
         UiKit.rect(body,r.x,r.y,r.width,r.height,UiKit.BODY);
         UiKit.rect(body,r.x,r.y,r.width,104,UiKit.PANEL);
         UiKit.rect(body,r.x,r.y + 104,r.width,3,UiKit.TEAL);
         UiKit.rect(body,r.x,r.bottom - 64,r.width,64,UiKit.PANEL);
         pageTitle = UiKit.text(body,title,r.x + 36,r.y + 14,30,UiKit.WHITE,UiKit.XBOLD);
         var names:Array = tabNames;
         var gap:Number = Math.min(200,(r.width - 72) / Math.max(1,names.length));
         for(var t:int = 0; t < names.length; t++)
         {
            tabClips.push(UiKit.tabButton(body,names[t],r.x + 36 + t * gap,r.y + 60,0.85 * gap / 200,tabPicker(t)));
         }
         var close:MovieClip = UiKit.tabButton(body,"BACK",r.right - 210,r.y + 18,0.85,function():void
         {
            back();
         });
         var extra:Array = pageAction;
         if(extra != null)
         {
            UiKit.tabButton(body,extra[0],r.right - 430,r.y + 18,0.85,function():void
            {
               extra[1]();
            });
         }
         var confirm:MovieClip = UiKit.tabButton(body,confirmLabel,r.x + 36,r.bottom - 50,0.85,function():void
         {
            back();
         });
         status = UiKit.text(body,"",r.x + 260,r.bottom - 42,15,UiKit.TEAL,UiKit.MEDIUM);
         hint = new Sprite();
         hint.y = r.bottom - 92;
         body.addChild(hint);
         area = new Rectangle(r.x + 30,r.y + 122,r.width - 60,r.height - 122 - 100);
      }

      private function get hintRight() : Number
      {
         return fullPage ? screen.right - 36 : HALF - 15;
      }

      private function dimAll(g:Object) : void
      {
         var r:Rectangle = fullPage ? screen : new Rectangle(-HALF - 200,-220,HALF * 2 + 400,640);
         g.graphics.beginFill(0,0.6);
         g.graphics.drawRect(r.x,r.y,r.width,r.height);
         g.graphics.endFill();
      }

      private var pressedW:Object = null;
      private var pressedAt:int = 0;

      private function focusPressed(e:MouseEvent) : void
      {
         var i:int = itemAt(e.target);
         var it:Object = i >= 0 ? items[i] : null;
         var again:Boolean = it != null && it.dbl && it.w != null && it.w === pressedW && getTimer() - pressedAt < DOUBLE_MS;
         pressedW = it != null ? it.w : null;
         pressedAt = getTimer();
         if(i >= 0 && i != focus)
         {
            focus = i;
            paintFocus();
         }
         if(again)
         {
            pressedW = null;
            useItem(it,0);
         }
      }

      private function itemAt(target:Object) : int
      {
         for(var o:Object = target; o != null && o !== body; o = o.parent)
         {
            for(var i:int = 0; i < items.length; i++)
            {
               if(items[i].sprite === o)
               {
                  return i;
               }
            }
         }
         return -1;
      }

      private function rightClicked(e:MouseEvent) : void
      {
         e.stopPropagation();
         if(ctx != null)
         {
            closeContext();
            return;
         }
         if(osk != null)
         {
            closeOsk();
            return;
         }
         if(picker != null)
         {
            closePicker();
            return;
         }
         if(dateBox != null)
         {
            closeDatePicker();
            return;
         }
         var i:int = itemAt(e.target);
         if(i < 0)
         {
            return;
         }
         if(i != focus)
         {
            focus = i;
            paintFocus();
         }
         var it:Object = items[i];
         if(it.rightUse != null)
         {
            it.rightUse();
            return;
         }
         var at:Point = body.globalToLocal(new Point(e.stageX,e.stageY));
         openContext(it,at.x + 4,at.y + 4);
      }

      private function tabPicker(i:int) : Function
      {
         return function():void
         {
            showTab(i);
         };
      }

      protected function showTab(i:int) : void
      {
         if(i < 0 || i >= tabNames.length || i == tab)
         {
            return;
         }
         tab = i;
         focus = 0;
         build();
      }

      protected function stepTab(dir:int) : void
      {
         var n:int = tabNames.length;
         var t:int = tab;
         for(var k:int = 0; k < n; k++)
         {
            t = (t + dir + n) % n;
            if(!tabOff(t))
            {
               showTab(t);
               return;
            }
         }
      }

      protected function build() : void
      {
         if(body == null)
         {
            return;
         }
         if(tabOff(tab))
         {
            tab = 0;
         }
         clearFlows();
         UiKit.paintTabs(tabClips,tab);
         for(var t:int = 0; t < tabClips.length; t++)
         {
            tabClips[t].alpha = tabOff(t) ? 0.4 : 1;
         }
         var kept:Array = [];
         if(tab == builtTab)
         {
            for each(var old:Object in scrollers)
            {
               kept.push(-old.content.y);
            }
         }
         var kept_w:Object = tab == builtTab && focus < items.length && items[focus] != null ? items[focus].w : null;
         builtTab = tab;
         if(tabBody != null)
         {
            body.removeChild(tabBody);
         }
         tabBody = new Sprite();
         body.addChild(tabBody);
         if(osk != null && osk.parent === body)
         {
            body.addChild(osk);
         }
         if(ctx != null && ctx.parent === body)
         {
            body.addChild(ctx);
         }
         items = [];
         scrollers = [];
         if(pageTitle != null && pageTitle.text != title)
         {
            pageTitle.text = title;
         }
         try
         {
            buildTab(tab);
            built();
         }
         catch(e:Error)
         {
            ErrorLog.write("window tab " + tab + " not fully built: " + e + " " + e.getStackTrace());
         }
         for(var n:int = 0; n < scrollers.length; n++)
         {
            var sc0:Object = scrollers[n];
            sc0.scrollTo(n < kept.length ? kept[n] : 0);
            if(sc0.show != null && (sc0.show[0] < -sc0.content.y || sc0.show[1] > -sc0.content.y + sc0.height))
            {
               sc0.scrollTo(sc0.show[0] < -sc0.content.y ? sc0.show[0] : sc0.show[1] - sc0.height);
            }
         }
         if(kept_w != null)
         {
            for(var f:int = 0; f < items.length; f++)
            {
               if(items[f].w === kept_w)
               {
                  focus = f;
                  break;
               }
            }
         }
         focus = Math.max(0,Math.min(focus,items.length - 1));
         paintFocus();
         status.text = statusText();
         var h:String = hintText();
         h = h != null ? h : defaultHint();
         if(h != hintShown)
         {
            hintShown = h;
            Prompts.fill(this,hint,h,20,12,UiKit.GREY,hintRight);
         }
      }

      private var flows:Dictionary = new Dictionary(true);

      protected function describeText(field:TextField, text:String) : void
      {
         text = text != null ? text : "";
         var box:Sprite = flows[field];
         if(text.search(/\{[A-Za-z0-9]+\}/) < 0)
         {
            if(box != null)
            {
               Prompts.clear(this,box);
            }
            field.visible = true;
            field.text = text;
            return;
         }
         if(box == null || box.parent != field.parent)
         {
            box = new Sprite();
            field.parent.addChild(box);
            flows[field] = box;
         }
         box.x = field.x + 2;
         box.y = field.y + 1;
         field.text = Prompts.plain(text);
         field.visible = false;
         var f:Object = field.defaultTextFormat;
         Prompts.flow(this,box,text,field.wordWrap ? field.width - 4 : 2000,Number(f.size),uint(f.color),Number(f.size) + 6);
      }

      private function clearFlows() : void
      {
         for each(var box:Sprite in flows)
         {
            Prompts.clear(this,box);
         }
         flows = new Dictionary(true);
      }

      protected function defaultHint() : String
      {
         var n:Object = Prompts.KEYS;
         return n.tabs + " TABS     " + n.page + " PAGE     " + n.select + " SELECT     " + (hasMenus() ? n.option +
            " MENU     " : "") + n.back + " BACK";
      }

      protected function hasMenus() : Boolean
      {
         for each(var it:Object in items)
         {
            if(it != null && (it.player != null || it.players != null || it.menu != null))
            {
               return true;
            }
         }
         return false;
      }

      public static function buttonNames() : Object
      {
         var pad:String = null;
         try
         {
            if(class_687.var_11971 == 2)
            {
               var last:Object = class_687.var_15058 != null ? class_112.var_6873.method_4935(class_687.var_15058.mControllerID) : null;
               for each(var c:Object in last != null ? [last] : class_112.var_9206)
               {
                  if(c != null && c.mID != 0)
                  {
                     var type:Object = c.method_7757();
                     pad = type != null && String(type.var_15259).indexOf("PS") == 0 ? "ps" : "xbox";
                     break;
                  }
               }
            }
         }
         catch(e:Error)
         {
         }
         if(pad == "ps")
         {
            return {"tabs":"L1/R1","page":"L2/R2","select":"CROSS","back":"CIRCLE","option":"TRIANGLE"};
         }
         if(pad == "xbox")
         {
            return {"tabs":"LB/RB","page":"LT/RT","select":"A","back":"B","option":"Y"};
         }
         return {"tabs":"[ ]","page":"- =","select":"ENTER","back":"ESC","option":"X"};
      }

      protected function scrollerOf(it:Object) : Object
      {
         for each(var sc:Object in scrollers)
         {
            if(it != null && sc.content === it.parent)
            {
               return sc;
            }
         }
         return null;
      }

      protected function pageFocus(dir:int) : void
      {
         if(items.length == 0)
         {
            return;
         }
         var start:Object = items[focus];
         var sc:Object = scrollerOf(start);
         var n:int = focus;
         if(sc == null)
         {
            n = dir < 0 ? 0 : items.length - 1;
         }
         else
         {
            var reach:Number = Math.max(30,sc.height - start.height);
            while(n + dir >= 0 && n + dir < items.length && items[n + dir].parent === start.parent &&
                  Math.abs(items[n + dir].sprite.y - start.sprite.y) <= reach)
            {
               n += dir;
            }
            if(n == focus)
            {
               n = Math.max(0,Math.min(items.length - 1,focus + dir));
            }
         }
         focus = n;
         paintFocus();
      }

      protected function panel(x:Number, y:Number, w:Number, h:Number) : Sprite
      {
         var p:Sprite = new Sprite();
         p.x = x;
         p.y = y;
         tabBody.addChild(p);
         UiKit.rect(p,0,0,w,h,UiKit.PANEL);
         return p;
      }

      protected function scroller(parent:Sprite, x:Number, y:Number, w:Number, h:Number) : Sprite
      {
         var view:Sprite = new Sprite();
         view.x = x;
         view.y = y;
         parent.addChild(view);
         var hit:Shape = new Shape();
         hit.graphics.beginFill(0,0);
         hit.graphics.drawRect(0,0,w,h);
         hit.graphics.endFill();
         view.addChild(hit);
         var content:Sprite = new Sprite();
         view.addChild(content);
         content.mask = UiKit.rect(view,0,0,w,h,0);
         var bar:Sprite = new Sprite();
         view.addChild(bar);
         var grab:Number = -1;
         var thumbSize:Function = function():Number
         {
            return Math.max(24,h * h / content.height);
         };
         var scrollTo:Function = function(to:Number):void
         {
            var max:Number = Math.max(0,content.height - h);
            content.y = -Math.max(0,Math.min(to,max));
            bar.graphics.clear();
            if(max > 0)
            {
               bar.graphics.beginFill(0,0);
               bar.graphics.drawRect(w - 12,0,12,h);
               bar.graphics.beginFill(UiKit.LINE);
               bar.graphics.drawRect(w - 4,0,4,h);
               bar.graphics.beginFill(grab >= 0 ? UiKit.WHITE : UiKit.GREY);
               var thumb:Number = thumbSize();
               bar.graphics.drawRect(grab >= 0 ? w - 6 : w - 4,(h - thumb) * -content.y / max,grab >= 0 ? 6 : 4,thumb);
               bar.graphics.endFill();
            }
         };
         var dragTo:Function = function(mouseY:Number):void
         {
            var max:Number = Math.max(0,content.height - h);
            var room:Number = h - thumbSize();
            if(max > 0 && room > 0)
            {
               scrollTo((mouseY - grab) / room * max);
            }
         };
         var moved:Function = function(e:MouseEvent):void
         {
            dragTo(bar.mouseY);
         };
         var released:Function = function(e:MouseEvent):void
         {
            grab = -1;
            if(bar.stage != null)
            {
               bar.stage.removeEventListener(MouseEvent.MOUSE_MOVE,moved);
               bar.stage.removeEventListener(MouseEvent.MOUSE_UP,released);
            }
            scrollTo(-content.y);
         };
         bar.addEventListener(MouseEvent.MOUSE_DOWN,function(e:MouseEvent):void
         {
            var max:Number = Math.max(0,content.height - h);
            if(max <= 0 || bar.stage == null)
            {
               return;
            }
            e.stopPropagation();
            var thumb:Number = thumbSize();
            var top:Number = (h - thumb) * -content.y / max;
            grab = bar.mouseY >= top && bar.mouseY <= top + thumb ? bar.mouseY - top : thumb / 2;
            dragTo(bar.mouseY);
            bar.stage.addEventListener(MouseEvent.MOUSE_MOVE,moved);
            bar.stage.addEventListener(MouseEvent.MOUSE_UP,released);
         });
         bar.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            e.stopPropagation();
         });
         view.addEventListener(MouseEvent.MOUSE_WHEEL,function(e:MouseEvent):void
         {
            scrollTo(-content.y - e.delta * 15);
         });
         scrollers.push({"content":content,"height":h,"scrollTo":scrollTo});
         return content;
      }

      protected function itemFocuser(i:int) : Function
      {
         return function(e:MouseEvent):void
         {
            focus = i;
            paintFocus();
         };
      }

      protected function paintFocus() : void
      {
         for(var i:int = 0; i < items.length; i++)
         {
            var it:Object = items[i];
            if(it.focusLine != null)
            {
               it.sprite.removeChild(it.focusLine);
               it.focusLine = null;
            }
            if(it.cursor != null)
            {
               it.cursor.visible = i == focus;
            }
            if(i == focus)
            {
               for each(var sc:Object in scrollers)
               {
                  if(sc.content === it.parent)
                  {
                     var top:Number = it.sprite.y;
                     var bottom:Number = it.sprite.y + it.height;
                     if(top < -sc.content.y)
                     {
                        sc.scrollTo(top);
                     }
                     else if(bottom > -sc.content.y + sc.height)
                     {
                        sc.scrollTo(bottom - sc.height);
                     }
                  }
               }
               var box:Array = it.focusBox != null ? it.focusBox : [0,0,it.width,it.height];
               var s:Shape = new Shape();
               s.graphics.beginFill(UiKit.TEAL);
               s.graphics.drawRect(box[0],box[1],4,box[3]);
               s.graphics.endFill();
               if(it.focusOutline)
               {
                  s.graphics.beginFill(0xFFFFFF,0.1);
                  s.graphics.drawRect(box[0],box[1],box[2],box[3]);
                  s.graphics.endFill();
                  s.graphics.lineStyle(2,UiKit.TEAL);
                  s.graphics.drawRect(box[0] + 1,box[1] + 1,box[2] - 2,box[3] - 2);
               }
               it.sprite.addChild(s);
               it.focusLine = s;
               focused(it);
            }
         }
      }

      protected function button(parent:Sprite, label:String, x:Number, y:Number, w:Number, act:Function, h:Number = 30,
                                size:int = 14) : Sprite
      {
         var b:Sprite = new Sprite();
         b.x = x;
         b.y = y;
         b.buttonMode = true;
         parent.addChild(b);
         UiKit.rect(b,0,0,w,h,UiKit.WHITE,6);
         UiKit.text(b,label,w / 2,h > 24 ? (h - 20) / 2 : 1,size,UiKit.NAVY_TEXT,UiKit.XBOLD,0,true);
         b.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            e.stopPropagation();
            act();
         });
         return b;
      }

      protected function typeText(title:String, initial:String, max:int, done:Function, symbols:Boolean = false) : void
      {
         oskRows = symbols ? OSK_ROWS.concat([OSK_SYMBOLS]) : OSK_ROWS;
         oskTitle = title;
         oskText = initial != null ? initial : "";
         oskMax = max;
         oskDone = done;
         oskRow = 1;
         oskCol = 0;
         typedBox = null;
         if(!usingController())
         {
            drawTypingBox();
            return;
         }
         if(body != null && body.stage != null && body.stage.focus is TextField)
         {
            body.stage.focus = null;
         }
         drawOsk();
      }

      protected static function usingController() : Boolean
      {
         try
         {
            return class_687.var_11971 == 2;
         }
         catch(e:Error)
         {
         }
         return true;
      }

      private function drawTypingBox() : void
      {
         if(body == null)
         {
            return;
         }
         if(!keyHook)
         {
            keyHook = true;
            Hooks.keyDown.add(function(event:Object):Boolean
            {
               var w:BigWindow = typingIn;
               return w != null && w.typedBox != null && w.typedBox.stage != null && w.typedBox.stage.focus === w.typedBox;
            });
         }
         closeOsk();
         osk = new Sprite();
         body.addChild(osk);
         var dim:Shape = new Shape();
         dimAll(dim);
         osk.addChild(dim);
         var panel:Sprite = new Sprite();
         panel.x = -310;
         panel.y = 0;
         osk.addChild(panel);
         UiKit.rect(panel,0,0,620,110,UiKit.PANEL,8);
         UiKit.text(panel,oskTitle,16,10,14,UiKit.GREY,UiKit.XBOLD);
         UiKit.rect(panel,16,32,588,34,UiKit.WHITE,6);
         UiKit.text(panel,"ENTER: DONE     ESC: CANCEL",16,80,11,UiKit.GREY,UiKit.BOLD);
         var box:TextField = new TextField();
         box.type = TextFieldType.INPUT;
         box.defaultTextFormat = new TextFormat("_sans",16,UiKit.NAVY_TEXT,true);
         box.x = 24;
         box.y = 36;
         box.width = 572;
         box.height = 26;
         box.maxChars = oskMax;
         box.text = oskText;
         panel.addChild(box);
         typedBox = box;
         typingIn = this;
         osk.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            e.stopPropagation();
            if(box.stage != null)
            {
               box.stage.focus = box;
            }
         });
         box.addEventListener(KeyboardEvent.KEY_DOWN,function(e:KeyboardEvent):void
         {
            if(e.keyCode == 13)
            {
               e.stopPropagation();
               var done:Function = oskDone;
               var text:String = box.text;
               closeOsk();
               if(done != null)
               {
                  done(text);
               }
            }
            else if(e.keyCode == 27)
            {
               e.stopPropagation();
               e.preventDefault();
               closeOsk();
            }
         });
         if(box.stage != null)
         {
            box.stage.focus = box;
            box.setSelection(box.length,box.length);
         }
      }

      protected function get keyboardOpen() : Boolean
      {
         return osk != null;
      }

      private function closeOsk() : void
      {
         if(oskHint != null)
         {
            Prompts.clear(this,oskHint);
            oskHint = null;
         }
         if(osk != null && osk.parent != null)
         {
            osk.parent.removeChild(osk);
         }
         osk = null;
         if(typedBox != null)
         {
            if(typedBox.stage != null && typedBox.stage.focus === typedBox)
            {
               typedBox.stage.focus = null;
            }
            typedBox = null;
         }
         if(typingIn === this)
         {
            typingIn = null;
         }
      }

      private function oskLabel(r:int, c:int) : String
      {
         if(r < oskRows.length)
         {
            var ch:String = String(oskRows[r]).charAt(c);
            return oskLower ? ch.toLowerCase() : ch;
         }
         for each(var b:Array in OSK_BOTTOM)
         {
            if(c >= b[1] && c < b[1] + b[2])
            {
               return b[0] == "abc" && oskLower ? "ABC" : String(b[0]);
            }
         }
         return "";
      }

      private function oskPress(r:int, c:int) : void
      {
         var label:String = oskLabel(r,c);
         if(r < oskRows.length)
         {
            if(oskText.length < oskMax)
            {
               oskText += label;
            }
         }
         else if(label == "SPACE")
         {
            if(oskText.length < oskMax)
            {
               oskText += " ";
            }
         }
         else if(label == "PASTE")
         {
            oskText = (oskText + clipboardLine()).substr(0,oskMax);
         }
         else if(label == "DEL")
         {
            oskText = oskText.substr(0,Math.max(0,oskText.length - 1));
         }
         else if(label == "DONE")
         {
            var done:Function = oskDone;
            var text:String = oskText;
            closeOsk();
            done(text);
            return;
         }
         else
         {
            oskLower = !oskLower;
         }
         drawOsk();
      }

      private static function clipboardLine() : String
      {
         try
         {
            var t:* = Clipboard.generalClipboard.getData(ClipboardFormats.TEXT_FORMAT);
            if(t != null)
            {
               var out:String = "";
               var s:String = String(t);
               for(var i:int = 0; i < s.length; i++)
               {
                  var c:Number = s.charCodeAt(i);
                  out += c == 10 || c == 13 || c == 9 ? " " : (c >= 32 && c != 127 ? s.charAt(i) : "");
               }
               return out.replace(/^\s+|\s+$/g,"");
            }
         }
         catch(e:Error)
         {
         }
         return "";
      }

      private function oskMove(dr:int, dc:int) : void
      {
         var rows:int = oskRows.length + 1;
         if(dr != 0)
         {
            oskRow = (oskRow + dr + rows) % rows;
         }
         if(dc != 0)
         {
            if(oskRow == oskRows.length)
            {
               var at:int = 0;
               for(var i:int = 0; i < OSK_BOTTOM.length; i++)
               {
                  if(oskCol >= OSK_BOTTOM[i][1] && oskCol < OSK_BOTTOM[i][1] + OSK_BOTTOM[i][2])
                  {
                     at = i;
                  }
               }
               at = (at + dc + OSK_BOTTOM.length) % OSK_BOTTOM.length;
               oskCol = OSK_BOTTOM[at][1];
            }
            else
            {
               oskCol = (oskCol + dc + 10) % 10;
            }
         }
         drawOsk();
      }

      private function oskClicker(r:int, c:int) : Function
      {
         return function(e:MouseEvent):void
         {
            e.stopPropagation();
            oskRow = r;
            oskCol = c;
            oskPress(r,c);
         };
      }

      private function drawOsk() : void
      {
         if(body == null)
         {
            return;
         }
         if(oskHint != null)
         {
            Prompts.clear(this,oskHint);
            oskHint = null;
         }
         if(osk != null && osk.parent != null)
         {
            osk.parent.removeChild(osk);
         }
         osk = new Sprite();
         body.addChild(osk);
         var dim:Shape = new Shape();
         dimAll(dim);
         osk.addChild(dim);
         osk.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            e.stopPropagation();
         });
         var panel:Sprite = new Sprite();
         panel.x = -310;
         panel.y = -60;
         osk.addChild(panel);
         var panelH:Number = 78 + (oskRows.length + 1) * 44 + 32;
         UiKit.rect(panel,0,0,620,panelH,UiKit.PANEL,8);
         UiKit.text(panel,oskTitle,16,10,14,UiKit.GREY,UiKit.XBOLD);
         UiKit.rect(panel,16,32,588,34,UiKit.WHITE,6);
         UiKit.fit(UiKit.text(panel,oskText + "_",24,38,16,UiKit.NAVY_TEXT,UiKit.BOLD),570);
         var n:Object = Prompts.KEYS;
         oskHint = new Sprite();
         oskHint.y = panelH - 29;
         panel.addChild(oskHint);
         Prompts.fill(this,oskHint,n.select + " TYPE     " + n.option + " DELETE     " + n.back + " CANCEL",18,11,UiKit.GREY,NaN,16);
         for(var r:int = 0; r <= oskRows.length; r++)
         {
            var keys:Array = [];
            if(r < oskRows.length)
            {
               for(var c:int = 0; c < 10; c++)
               {
                  keys.push([c,1]);
               }
            }
            else
            {
               for each(var b:Array in OSK_BOTTOM)
               {
                  keys.push([b[1],b[2]]);
               }
            }
            for each(var k:Array in keys)
            {
               var key:Sprite = new Sprite();
               key.x = 16 + k[0] * 59;
               key.y = 78 + r * 44;
               key.buttonMode = true;
               panel.addChild(key);
               var on:Boolean = r == oskRow && oskCol >= k[0] && oskCol < k[0] + k[1];
               UiKit.rect(key,0,0,k[1] * 59 - 5,38,on ? UiKit.TEAL : UiKit.BODY,6);
               UiKit.text(key,oskLabel(r,k[0]),(k[1] * 59 - 5) / 2,8,15,on ? UiKit.NAVY_TEXT : UiKit.WHITE,UiKit.BOLD,0,true);
               key.addEventListener(MouseEvent.CLICK,oskClicker(r,k[0]));
            }
         }
      }

      private function oskInput(input:int) : void
      {
         if(typedBox != null)
         {
            if(input == 18 || input == 19)
            {
               closeOsk();
            }
            return;
         }
         switch(input)
         {
            case 4:
               oskMove(-1,0);
               break;
            case 5:
               oskMove(1,0);
               break;
            case 1:
               oskMove(0,-1);
               break;
            case 2:
               oskMove(0,1);
               break;
            case 23:
            case 17:
            case 11:
               oskPress(oskRow,oskCol);
               break;
            case 21:
               oskText = oskText.substr(0,Math.max(0,oskText.length - 1));
               drawOsk();
               break;
            case 18:
            case 19:
               closeOsk();
         }
      }

      protected function pickFrom(title:String, names:Array, current:int, done:Function, icon:Function = null,
                                  wide:Boolean = false) : void
      {
         pickTitle = title;
         pickNames = names;
         pickIcon = icon;
         pickCols = icon == null ? PICK_COLS : (wide ? PICK_WIDE_COLS : PICK_ICON_COLS);
         pickW = icon == null ? 236 : (wide ? 150 : 74);
         pickH = icon == null ? 34 : (wide ? 98 : 76);
         pickAt = Math.max(0,Math.min(current,names.length - 1));
         pickDone = done;
         drawPicker();
      }

      private static const PICK_ICON_COLS:int = 12;
      private static const PICK_WIDE_COLS:int = 6;
      private var pickShown:int = 1;
      private var pickTop:int = 0;
      private var pickContent:Sprite;
      private var pickBar:Sprite;
      private var pickIcon:Function = null;
      private var pickCols:int = PICK_COLS;
      private var pickW:Number = 236;
      private var pickH:Number = 34;

      protected function get pickerOpen() : Boolean
      {
         return picker != null;
      }

      private function drawPicker() : void
      {
         if(body == null)
         {
            return;
         }
         closePicker();
         picker = new Sprite();
         body.addChild(picker);
         var dim:Sprite = new Sprite();
         dimAll(dim);
         picker.addChild(dim);
         dim.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            e.stopPropagation();
            closePicker();
         });
         var rows:int = Math.ceil(pickNames.length / pickCols);
         var cellW:Number = pickW;
         var inside:Rectangle = fullPage ? screen : new Rectangle(-HALF,-200,HALF * 2,580);
         pickCols = Math.max(1,Math.min(pickCols,int((inside.width - 40) / (cellW + 8))));
         rows = Math.ceil(pickNames.length / pickCols);
         pickShown = Math.max(1,Math.min(rows,int((inside.height - 24 - 52 - 36) / (pickH + 6))));
         pickTop = 0;
         var panelW:Number = 32 + pickCols * (cellW + 8) - 8 + (pickShown < rows ? 12 : 0);
         var panelH:Number = 52 + pickShown * (pickH + 6) + 36;
         var panel:Sprite = new Sprite();
         panel.x = inside.x + (inside.width - panelW) / 2;
         panel.y = Math.max(inside.y + 12,Math.min(fullPage ? inside.y + (inside.height - panelH) / 2 : 120 - panelH / 2,
            inside.bottom - panelH - 12));
         picker.addChild(panel);
         panel.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            e.stopPropagation();
         });
         UiKit.rect(panel,0,0,panelW,panelH,UiKit.PANEL,8);
         UiKit.fit(UiKit.text(panel,pickTitle,16,12,15,UiKit.GREY,UiKit.XBOLD),panelW - 32);
         var view:Sprite = new Sprite();
         view.y = 46;
         panel.addChild(view);
         pickContent = new Sprite();
         view.addChild(pickContent);
         pickContent.mask = UiKit.rect(view,0,-2,panelW,pickShown * (pickH + 6) + 2,0);
         pickBar = new Sprite();
         pickBar.x = panelW - 14;
         view.addChild(pickBar);
         view.addEventListener(MouseEvent.MOUSE_WHEEL,function(e:MouseEvent):void
         {
            scrollPicker(e.delta > 0 ? -1 : 1);
         });
         pickCells = [];
         for(var i:int = 0; i < pickNames.length; i++)
         {
            var cell:Sprite = new Sprite();
            cell.x = 16 + i % pickCols * (cellW + 8);
            cell.y = int(i / pickCols) * (pickH + 6);
            cell.buttonMode = true;
            pickContent.addChild(cell);
            cell.addEventListener(MouseEvent.CLICK,pickClick(i));
            cell.addEventListener(MouseEvent.ROLL_OVER,pickHover(i));
            pickCells.push(cell);
         }
         paintPicker();
         var n:Object = Prompts.KEYS;
         pickerHint = new Sprite();
         pickerHint.y = panelH - 29;
         pickerHint.x = 16;
         panel.addChild(pickerHint);
         Prompts.fill(this,pickerHint,n.select + " PICK     " + n.back + " CANCEL",18,11,UiKit.GREY,NaN,16);
      }

      private function scrollPicker(dir:int) : void
      {
         var rows:int = Math.ceil(pickNames.length / pickCols);
         var top:int = Math.max(0,Math.min(rows - pickShown,pickTop + dir));
         if(top != pickTop)
         {
            pickTop = top;
            placePicker();
         }
      }

      private function placePicker() : void
      {
         if(pickContent == null)
         {
            return;
         }
         var rows:int = Math.ceil(pickNames.length / pickCols);
         var row:int = int(pickAt / pickCols);
         if(row < pickTop)
         {
            pickTop = row;
         }
         else if(row >= pickTop + pickShown)
         {
            pickTop = row - pickShown + 1;
         }
         pickContent.y = -pickTop * (pickH + 6);
         pickBar.graphics.clear();
         if(rows > pickShown)
         {
            var h:Number = pickShown * (pickH + 6) - 6;
            pickBar.graphics.beginFill(UiKit.LINE);
            pickBar.graphics.drawRect(4,0,4,h);
            pickBar.graphics.beginFill(UiKit.GREY);
            pickBar.graphics.drawRect(4,h * pickTop / rows,4,Math.max(16,h * pickShown / rows));
            pickBar.graphics.endFill();
         }
      }

      private function paintPicker() : void
      {
         placePicker();
         for(var i:int = 0; i < pickCells.length; i++)
         {
            var cell:Sprite = pickCells[i];
            cell.removeChildren();
            var on:Boolean = i == pickAt;
            UiKit.rect(cell,0,0,pickW,pickH,on ? UiKit.TEAL : UiKit.BODY,6);
            if(pickIcon != null)
            {
               var bm:DisplayObject = pickIcon(i) as DisplayObject;
               if(bm != null)
               {
                  bm.x = (pickW - bm.width) / 2;
                  bm.y = 4;
                  cell.addChild(bm);
               }
               var label:Object = UiKit.fit(UiKit.text(cell,String(pickNames[i]),0,pickH - 18,10,on ? UiKit.NAVY_TEXT : UiKit.WHITE,
                  UiKit.XBOLD),pickW - 8);
               label.x = (pickW - label.width) / 2;
               continue;
            }
            var plain:Object = UiKit.fit(UiKit.text(cell,String(pickNames[i]),0,7,14,on ? UiKit.NAVY_TEXT : UiKit.WHITE,UiKit.BOLD),
               pickW - 16);
            plain.x = (pickW - plain.width) / 2;
         }
      }

      private function pickClick(i:int) : Function
      {
         return function(e:MouseEvent):void
         {
            e.stopPropagation();
            pickAt = i;
            choosePicked();
         };
      }

      private function pickHover(i:int) : Function
      {
         return function(e:MouseEvent):void
         {
            if(pickAt != i)
            {
               pickAt = i;
               paintPicker();
            }
         };
      }

      private function choosePicked() : void
      {
         var done:Function = pickDone;
         var at:int = pickAt;
         closePicker();
         if(done != null)
         {
            done(at);
         }
      }

      private function closePicker() : void
      {
         if(pickerHint != null)
         {
            Prompts.clear(this,pickerHint);
            pickerHint = null;
         }
         if(picker != null && picker.parent != null)
         {
            picker.parent.removeChild(picker);
         }
         picker = null;
         pickContent = null;
      }

      private function pickerInput(input:int) : void
      {
         var n:int = pickNames.length;
         switch(input)
         {
            case 1:
               pickAt = pickAt % pickCols == 0 ? Math.min(n - 1,pickAt + pickCols - 1) : pickAt - 1;
               break;
            case 2:
               pickAt = pickAt % pickCols == pickCols - 1 || pickAt == n - 1 ? pickAt - pickAt % pickCols : pickAt + 1;
               break;
            case 4:
               pickAt = pickAt - pickCols >= 0 ? pickAt - pickCols : pickAt;
               break;
            case 5:
               pickAt = pickAt + pickCols < n ? pickAt + pickCols : pickAt;
               break;
            case 23:
            case 17:
            case 11:
               choosePicked();
               return;
            case 18:
            case 19:
               closePicker();
               return;
         }
         paintPicker();
      }

      private var ctx:Sprite;
      private var ctxHint:Sprite;
      private var ctxEntries:Array;
      private var ctxTitle:String;
      private var ctxAt:int = 0;
      private var ctxRows:Array;
      private var ctxX:Number = 0;
      private var ctxY:Number = 0;
      private static const CTX_W:Number = 250;
      private var ctxShown:int = 1;
      private var ctxTop:int = 0;
      private var ctxContent:Sprite;
      private var ctxBar:Sprite;
      private static const CTX_ROW:Number = 32;

      protected function contextEntries(it:Object) : Array
      {
         var out:Array = [];
         if(it == null)
         {
            return out;
         }
         try
         {
            var own:Array = it.menu != null ? it.menu() as Array || [] : [];
            var many:Array = it.players is Array ? (it.players as Array).filter(function(p:Object, ... rest):Boolean
            {
               return p != null && (int(p.account) > 0 || uint(p.pid) != 0);
            }) : [];
            if(many.length == 1 && it.player == null)
            {
               out = PlayerMenu.entries(many[0],own);
            }
            else if(many.length > 1)
            {
               for each(var p:Object in many)
               {
                  out.push([String(p.name || "?").toUpperCase() + "  >",playerOpener(p)]);
               }
               out = out.concat(own);
            }
            else
            {
               out = it.player != null ? PlayerMenu.entries(it.player,own) : own;
            }
         }
         catch(e:Error)
         {
            ErrorLog.write("window: a row's menu not built: " + e);
         }
         return out;
      }

      private function playerOpener(p:Object) : Function
      {
         return function():void
         {
            var x:Number = ctxX;
            var y:Number = ctxY;
            openContext({"player":p},x,y);
         };
      }

      protected function openContext(it:Object, x:Number = NaN, y:Number = NaN) : Boolean
      {
         var list:Array = contextEntries(it);
         if(list.length == 0 || body == null)
         {
            return false;
         }
         closeContext();
         ctxEntries = list;
         var only:Object = it.player != null ? it.player : it.players is Array && it.players.length == 1 ? it.players[0] : null;
         ctxTitle = it.menuTitle != null ? String(it.menuTitle) : only != null && only.name != null ?
            String(only.name).toUpperCase() : "";
         ctxAt = 0;
         if(isNaN(x) || isNaN(y))
         {
            var box:Array = it.focusBox != null ? it.focusBox : [0,0,it.width,it.height];
            var at:Point = body.globalToLocal(DisplayObject(it.sprite).localToGlobal(new Point(box[0] + 40,box[1] + box[3])));
            x = at.x;
            y = at.y + 2;
         }
         drawContext(x,y);
         return true;
      }

      private function drawContext(x:Number, y:Number) : void
      {
         ctxX = x;
         ctxY = y;
         ctx = new Sprite();
         body.addChild(ctx);
         var catcher:Sprite = new Sprite();
         var all:Rectangle = fullPage ? screen : new Rectangle(-HALF - 200,-220,HALF * 2 + 400,640);
         catcher.graphics.beginFill(0,0);
         catcher.graphics.drawRect(all.x,all.y,all.width,all.height);
         catcher.graphics.endFill();
         ctx.addChild(catcher);
         catcher.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            e.stopPropagation();
            closeContext();
         });
         var top:Number = ctxTitle != "" ? 32 : 10;
         var inside:Rectangle = fullPage ? screen : new Rectangle(-HALF,-200,HALF * 2,580);
         ctxShown = Math.max(1,Math.min(ctxEntries.length,int((inside.height - 12 - top - 34) / CTX_ROW)));
         ctxTop = 0;
         var h:Number = top + ctxShown * CTX_ROW + 34;
         var panel:Sprite = new Sprite();
         panel.x = Math.max(inside.x + 6,Math.min(x,inside.right - CTX_W - 6));
         panel.y = Math.max(inside.y + 6,Math.min(y,inside.bottom - h - 6));
         ctx.addChild(panel);
         panel.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            e.stopPropagation();
         });
         UiKit.rect(panel,-2,-2,CTX_W + 4,h + 4,UiKit.TEAL,9);
         UiKit.rect(panel,0,0,CTX_W,h,UiKit.PANEL,8);
         if(ctxTitle != "")
         {
            UiKit.fit(UiKit.text(panel,ctxTitle,14,8,13,UiKit.GREY,UiKit.XBOLD),CTX_W - 28);
         }
         var view:Sprite = new Sprite();
         view.y = top;
         panel.addChild(view);
         ctxContent = new Sprite();
         view.addChild(ctxContent);
         ctxContent.mask = UiKit.rect(view,0,0,CTX_W,ctxShown * CTX_ROW,0);
         ctxBar = new Sprite();
         ctxBar.x = CTX_W - 10;
         view.addChild(ctxBar);
         view.addEventListener(MouseEvent.MOUSE_WHEEL,function(e:MouseEvent):void
         {
            var next:int = Math.max(0,Math.min(ctxEntries.length - ctxShown,ctxTop + (e.delta > 0 ? -1 : 1)));
            if(next != ctxTop)
            {
               ctxTop = next;
               placeContext(false);
            }
         });
         ctxRows = [];
         for(var i:int = 0; i < ctxEntries.length; i++)
         {
            var row:Sprite = new Sprite();
            row.x = 8;
            row.y = i * CTX_ROW;
            row.buttonMode = true;
            ctxContent.addChild(row);
            row.addEventListener(MouseEvent.CLICK,contextClick(i));
            row.addEventListener(MouseEvent.ROLL_OVER,contextHover(i));
            ctxRows.push(row);
         }
         paintContext();
         var n:Object = Prompts.KEYS;
         ctxHint = new Sprite();
         ctxHint.x = 14;
         ctxHint.y = h - 28;
         panel.addChild(ctxHint);
         Prompts.fill(this,ctxHint,n.select + " PICK     " + n.back + " CLOSE",18,11,UiKit.GREY,NaN,16);
      }

      private function placeContext(follow:Boolean) : void
      {
         if(ctxContent == null)
         {
            return;
         }
         if(follow && ctxAt < ctxTop)
         {
            ctxTop = ctxAt;
         }
         else if(follow && ctxAt >= ctxTop + ctxShown)
         {
            ctxTop = ctxAt - ctxShown + 1;
         }
         ctxContent.y = -ctxTop * CTX_ROW;
         ctxBar.graphics.clear();
         var n:int = ctxEntries.length;
         if(n > ctxShown)
         {
            var h:Number = ctxShown * CTX_ROW - 4;
            ctxBar.graphics.beginFill(UiKit.LINE);
            ctxBar.graphics.drawRect(2,0,4,h);
            ctxBar.graphics.beginFill(UiKit.GREY);
            ctxBar.graphics.drawRect(2,h * ctxTop / n,4,Math.max(16,h * ctxShown / n));
            ctxBar.graphics.endFill();
         }
      }

      private function paintContext() : void
      {
         placeContext(true);
         var scrolled:Boolean = ctxEntries.length > ctxShown;
         for(var i:int = 0; i < ctxRows.length; i++)
         {
            var row:Sprite = ctxRows[i];
            row.removeChildren();
            var on:Boolean = i == ctxAt;
            UiKit.rect(row,0,0,CTX_W - (scrolled ? 28 : 16),CTX_ROW - 4,on ? UiKit.TEAL : UiKit.BODY,5);
            UiKit.fit(UiKit.text(row,String(ctxEntries[i][0]),12,5,14,on ? UiKit.NAVY_TEXT : UiKit.WHITE,UiKit.BOLD),
               CTX_W - (scrolled ? 52 : 40));
         }
      }

      private function contextClick(i:int) : Function
      {
         return function(e:MouseEvent):void
         {
            e.stopPropagation();
            ctxAt = i;
            contextPick();
         };
      }

      private function contextHover(i:int) : Function
      {
         return function(e:MouseEvent):void
         {
            if(ctxAt != i)
            {
               ctxAt = i;
               paintContext();
            }
         };
      }

      private function contextPick() : void
      {
         var entry:Array = ctxEntries != null && ctxAt < ctxEntries.length ? ctxEntries[ctxAt] as Array : null;
         closeContext();
         if(entry != null && entry[1] is Function)
         {
            try
            {
               entry[1]();
            }
            catch(e:Error)
            {
               ErrorLog.write("window: menu entry " + entry[0] + " failed: " + e);
            }
         }
      }

      private function closeContext() : void
      {
         if(ctxHint != null)
         {
            Prompts.clear(this,ctxHint);
            ctxHint = null;
         }
         if(ctx != null && ctx.parent != null)
         {
            ctx.parent.removeChild(ctx);
         }
         ctx = null;
         ctxContent = null;
      }

      private function contextInput(input:int) : void
      {
         var n:int = ctxEntries.length;
         switch(input)
         {
            case 4:
               ctxAt = (ctxAt - 1 + n) % n;
               break;
            case 5:
               ctxAt = (ctxAt + 1) % n;
               break;
            case 23:
            case 17:
            case 11:
               contextPick();
               return;
            case 18:
            case 19:
            case 21:
               closeContext();
               return;
         }
         paintContext();
      }

      private static const MONTH_NAMES:Array = ["JANUARY","FEBRUARY","MARCH","APRIL","MAY","JUNE","JULY","AUGUST",
         "SEPTEMBER","OCTOBER","NOVEMBER","DECEMBER"];
      private static const WEEKDAYS:Array = ["SUN","MON","TUE","WED","THU","FRI","SAT"];
      private static const DAY_W:Number = 64;
      private static const DAY_H:Number = 44;

      protected function pickDate(title:String, at:Number, min:Number, max:Number, done:Function) : void
      {
         dateTitle = title;
         dateMin = midnight(min);
         dateMax = midnight(max);
         dateAt = new Date(Math.max(dateMin,Math.min(dateMax,midnight(at))));
         dateDone = done;
         drawDatePicker();
      }

      private static function midnight(ms:Number) : Number
      {
         var d:Date = new Date(ms);
         return new Date(d.fullYear,d.month,d.date).time;
      }

      private function drawDatePicker() : void
      {
         if(body == null)
         {
            return;
         }
         closeDatePicker();
         dateBox = new Sprite();
         body.addChild(dateBox);
         var dim:Sprite = new Sprite();
         dimAll(dim);
         dateBox.addChild(dim);
         dim.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            e.stopPropagation();
            closeDatePicker();
         });
         var panelW:Number = 32 + 7 * (DAY_W + 6) - 6;
         var panelH:Number = 108 + 6 * (DAY_H + 6) + 36;
         var panel:Sprite = new Sprite();
         panel.x = -panelW / 2;
         panel.y = Math.max(-220,110 - panelH / 2);
         dateBox.addChild(panel);
         panel.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            e.stopPropagation();
         });
         UiKit.rect(panel,0,0,panelW,panelH,UiKit.PANEL,8);
         UiKit.fit(UiKit.text(panel,dateTitle,16,12,15,UiKit.GREY,UiKit.XBOLD),panelW - 32);
         UiKit.arrow(panel,16,48,-1,function():void
         {
            moveDate(0,-1);
         });
         UiKit.text(panel,MONTH_NAMES[dateAt.month] + " " + dateAt.fullYear,panelW / 2,46,18,UiKit.WHITE,UiKit.XBOLD,0,true);
         UiKit.arrow(panel,panelW - 38,48,1,function():void
         {
            moveDate(0,1);
         });
         for(var w:int = 0; w < 7; w++)
         {
            UiKit.text(panel,WEEKDAYS[w],16 + w * (DAY_W + 6) + DAY_W / 2,86,11,UiKit.GREY,UiKit.XBOLD,0,true);
         }
         var first:Date = new Date(dateAt.fullYear,dateAt.month,1);
         var days:int = new Date(dateAt.fullYear,dateAt.month + 1,0).date;
         var today:Number = midnight(new Date().time);
         for(var d:int = 1; d <= days; d++)
         {
            var at:int = first.day + d - 1;
            var ms:Number = new Date(dateAt.fullYear,dateAt.month,d).time;
            var ok:Boolean = ms >= dateMin && ms <= dateMax;
            var on:Boolean = d == dateAt.date;
            var cell:Sprite = new Sprite();
            cell.x = 16 + at % 7 * (DAY_W + 6);
            cell.y = 108 + int(at / 7) * (DAY_H + 6);
            panel.addChild(cell);
            UiKit.rect(cell,0,0,DAY_W,DAY_H,on ? UiKit.TEAL : ok ? UiKit.BODY : UiKit.PANEL,6);
            if(ms == today && !on)
            {
               var ring:Shape = new Shape();
               ring.graphics.lineStyle(2,UiKit.TEAL);
               ring.graphics.drawRoundRect(1,1,DAY_W - 2,DAY_H - 2,10);
               cell.addChild(ring);
            }
            UiKit.text(cell,String(d),DAY_W / 2,11,16,on ? UiKit.NAVY_TEXT : ok ? UiKit.WHITE : UiKit.DIM,UiKit.XBOLD,0,true);
            if(ok)
            {
               cell.buttonMode = true;
               cell.addEventListener(MouseEvent.CLICK,dateClick(ms));
            }
         }
         var n:Object = Prompts.KEYS;
         dateHint = new Sprite();
         dateHint.y = panelH - 29;
         dateHint.x = 16;
         panel.addChild(dateHint);
         Prompts.fill(this,dateHint,n.tabs + " MONTH     " + n.select + " PICK     " + n.back + " CANCEL",18,11,UiKit.GREY,NaN,16);
      }

      private function dateClick(ms:Number) : Function
      {
         return function(e:MouseEvent):void
         {
            e.stopPropagation();
            dateAt = new Date(ms);
            chooseDate();
         };
      }

      private function moveDate(days:int, months:int) : void
      {
         var t:Date = new Date(dateAt.fullYear,dateAt.month + months,dateAt.date + days);
         if(months != 0 && t.month != (dateAt.month + months + 12) % 12)
         {
            t = new Date(dateAt.fullYear,dateAt.month + months + 1,0);
         }
         dateAt = new Date(Math.max(dateMin,Math.min(dateMax,t.time)));
         drawDatePicker();
      }

      private function chooseDate() : void
      {
         var done:Function = dateDone;
         var ms:Number = dateAt.time;
         closeDatePicker();
         if(done != null)
         {
            done(ms);
         }
      }

      private function closeDatePicker() : void
      {
         if(dateHint != null)
         {
            Prompts.clear(this,dateHint);
            dateHint = null;
         }
         if(dateBox != null && dateBox.parent != null)
         {
            dateBox.parent.removeChild(dateBox);
         }
         dateBox = null;
      }

      private function dateInput(input:int) : void
      {
         switch(input)
         {
            case 1:
               moveDate(-1,0);
               break;
            case 2:
               moveDate(1,0);
               break;
            case 4:
               moveDate(-7,0);
               break;
            case 5:
               moveDate(7,0);
               break;
            case 26:
            case 24:
               moveDate(0,-1);
               break;
            case 27:
            case 25:
               moveDate(0,1);
               break;
            case 23:
            case 17:
            case 11:
               chooseDate();
               break;
            case 18:
            case 19:
               closeDatePicker();
         }
      }

      override public function HandleInput(input:int) : Boolean
      {
         if(!method_5588() || covered())
         {
            return false;
         }
         if(osk != null)
         {
            oskInput(input);
            return true;
         }
         if(picker != null)
         {
            pickerInput(input);
            return true;
         }
         if(dateBox != null)
         {
            dateInput(input);
            return true;
         }
         if(ctx != null)
         {
            contextInput(input);
            return true;
         }
         if(blockInput())
         {
            return true;
         }
         var it:Object = focus < items.length ? items[focus] : null;
         switch(input)
         {
            case 18:
            case 19:
               backKey();
               break;
            case 26:
               stepTab(-1);
               break;
            case 27:
               stepTab(1);
               break;
            case 24:
               pageFocus(-1);
               break;
            case 25:
               pageFocus(1);
               break;
            case 4:
               if(it == null || !moveIn(it,-1))
               {
                  focus = Math.max(0,focus - 1);
                  paintFocus();
               }
               break;
            case 5:
               if(it == null || !moveIn(it,1))
               {
                  focus = Math.min(items.length - 1,focus + 1);
                  paintFocus();
               }
               break;
            case 21:
               if(it != null)
               {
                  optionItem(it);
               }
               break;
            case 1:
            case 2:
               if(it != null)
               {
                  useItem(it,input == 1 ? -1 : 1);
               }
               break;
            case 23:
            case 17:
            case 11:
               if(it != null)
               {
                  useItem(it,0);
               }
         }
         return true;
      }

      override public function OnDestroyScreen() : void
      {
         clearFlows();
         osk = null;
         picker = null;
         dateBox = null;
         ctx = null;
         items = [];
         tabClips = [];
         body = null;
         tabBody = null;
      }
   }
}
