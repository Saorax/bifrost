package bh.platform
{
   import flash.display.Bitmap;
   import flash.display.BitmapData;
   import flash.display.DisplayObject;
   import flash.display.Loader;
   import flash.display.MovieClip;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.IOErrorEvent;
   import flash.events.MouseEvent;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.geom.Rectangle;
   import flash.text.Font;
   import flash.text.TextField;
   import flash.text.TextFieldAutoSize;
   import flash.text.TextFormat;
   import flash.utils.ByteArray;

   public final class UiKit
   {
      public static const PANEL:uint = 0x0B2336;
      public static const BODY:uint = 0x061521;
      public static const TEAL:uint = 0x4FE3D0;
      public static const WHITE:uint = 0xFFFFFF;
      public static const GREY:uint = 0x7F8C99;
      public static const LIGHT:uint = 0xC8D2DC;
      public static const RED:uint = 0xFF5F5F;
      public static const ROW_SELECTED:uint = 0x123A5A;
      public static const LINE:uint = 0x1D3A52;
      public static const NAVY_TEXT:uint = 0x0B2336;
      public static const DIM:uint = 0x2A3A4A;
      public static const GOLD:uint = 0xF5B841;
      public static const SILVER:uint = 0xB4CBE0;
      public static const BRONZE:uint = 0xD08A4E;

      public static const BOLD:String = "BMG Bespoke Sans Bold";
      public static const XBOLD:String = "BMG Bespoke Sans Extrabold";
      public static const MEDIUM:String = "BMG Author Medium";

      private static var keys:Object = {};
      private static var nextKey:int = 0;
      private static var bitmaps:Object = {};
      private static var waiting:Object = {};
      private static var fontsChecked:Boolean = false;
      private static var gameFonts:Boolean = false;

      public function UiKit()
      {
      }

      public static function key(text:String) : String
      {
         if(keys[text] == null)
         {
            keys[text] = "BH_UiKit_T" + nextKey++;
            if(Localization.var_14676 != null)
            {
               Localization.var_14676.var_15061.method_65(keys[text],text);
            }
         }
         return keys[text];
      }

      private static function fontsReady() : Boolean
      {
         if(!fontsChecked)
         {
            fontsChecked = true;
            for each(var f:Font in Font.enumerateFonts(false))
            {
               if(f.fontName == BOLD)
               {
                  gameFonts = true;
               }
            }
         }
         return gameFonts;
      }

      public static function text(parent:Sprite, s:String, x:Number, y:Number, size:Number, color:uint, font:String,
                                  width:Number = 0, center:Boolean = false) : TextField
      {
         var t:TextField = new TextField();
         t.selectable = false;
         t.mouseEnabled = false;
         t.embedFonts = fontsReady();
         t.defaultTextFormat = new TextFormat(t.embedFonts ? font : "_sans",size,color,!t.embedFonts && font != MEDIUM);
         t.autoSize = TextFieldAutoSize.LEFT;
         if(width > 0)
         {
            t.multiline = true;
            t.wordWrap = true;
            t.width = width;
         }
         t.text = s;
         t.x = center ? x - t.width / 2 : x;
         t.y = y;
         parent.addChild(t);
         return t;
      }

      public static function placeColour(place:int, other:uint) : uint
      {
         return place == 1 ? GOLD : place == 2 ? SILVER : place == 3 ? BRONZE : other;
      }

      public static function fit(t:TextField, width:Number) : TextField
      {
         var s:String = t.text;
         while(t.width > width && s.length > 1)
         {
            s = s.substr(0,s.length - 1);
            t.text = s + "...";
         }
         return t;
      }

      public static function rect(parent:Sprite, x:Number, y:Number, w:Number, h:Number, color:uint,
                                  radius:Number = 0) : Shape
      {
         var s:Shape = new Shape();
         s.graphics.beginFill(color);
         if(radius > 0)
         {
            s.graphics.drawRoundRect(x,y,w,h,radius,radius);
         }
         else
         {
            s.graphics.drawRect(x,y,w,h);
         }
         s.graphics.endFill();
         parent.addChild(s);
         return s;
      }

      public static function forgetPictures() : void
      {
         bitmaps = {};
      }

      public static function picture(parent:Sprite, file:File, w:Number, h:Number, cover:Boolean) : void
      {
         if(file == null || !file.exists)
         {
            return;
         }
         var place:Function = function(bd:BitmapData):void
         {
            var b:Bitmap = new Bitmap(bd,"auto",true);
            var scale:Number = cover ? Math.max(w / bd.width,h / bd.height) : Math.min(w / bd.width,h / bd.height);
            b.scaleX = b.scaleY = scale;
            b.x = (w - b.width) / 2;
            b.y = (h - b.height) / 2;
            parent.addChild(b);
            if(cover)
            {
               b.mask = rect(parent,0,0,w,h,0);
            }
         };
         var path:String = file.nativePath;
         if(bitmaps[path] is BitmapData)
         {
            place(bitmaps[path]);
            return;
         }
         if(waiting[path] != null)
         {
            waiting[path].push(place);
            return;
         }
         waiting[path] = [place];
         try
         {
            var bytes:ByteArray = new ByteArray();
            var stream:FileStream = new FileStream();
            stream.open(file,FileMode.READ);
            stream.readBytes(bytes);
            stream.close();
            var loader:Loader = new Loader();
            loader.contentLoaderInfo.addEventListener(Event.COMPLETE,function(e:Event):void
            {
               var bd:BitmapData = (loader.content as Bitmap).bitmapData;
               bitmaps[path] = bd;
               for each(var f:Function in waiting[path])
               {
                  f(bd);
               }
               delete waiting[path];
            });
            loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR,function(e:Event):void
            {
               delete waiting[path];
            });
            loader.loadBytes(bytes);
         }
         catch(e:Error)
         {
            delete waiting[path];
         }
      }

      public static function icon(parent:Sprite, clip:DisplayObject, x:Number, y:Number, size:Number) : Sprite
      {
         var holder:Sprite = new Sprite();
         holder.mouseEnabled = false;
         holder.mouseChildren = false;
         holder.x = x;
         holder.y = y;
         parent.addChild(holder);
         if(clip == null)
         {
            return holder;
         }
         holder.addChild(clip);
         var b:Rectangle = clip.getBounds(holder);
         if(b.width > 0 && b.height > 0)
         {
            var scale:Number = Math.min(size / b.width,size / b.height);
            clip.scaleX = clip.scaleY = scale;
            b = clip.getBounds(holder);
            clip.x -= b.x + b.width / 2 - size / 2;
            clip.y -= b.y + b.height / 2 - size / 2;
         }
         return holder;
      }

      public static function badge(parent:Sprite, letter:String, x:Number, y:Number, size:Number) : void
      {
         rect(parent,x,y,size,size,LINE,size);
         text(parent,letter,x + size / 2,y + size / 2 - size * 0.32,size * 0.45,TEAL,XBOLD,0,true);
      }

      public static function arrow(parent:Sprite, x:Number, y:Number, dir:int, act:Function) : Sprite
      {
         var b:Sprite = new Sprite();
         b.x = x;
         b.y = y;
         b.buttonMode = true;
         rect(b,0,0,22,22,WHITE,6);
         var s:Shape = new Shape();
         s.graphics.beginFill(NAVY_TEXT);
         if(dir < 0)
         {
            s.graphics.moveTo(14,5);
            s.graphics.lineTo(7,11);
            s.graphics.lineTo(14,17);
         }
         else
         {
            s.graphics.moveTo(8,5);
            s.graphics.lineTo(15,11);
            s.graphics.lineTo(8,17);
         }
         s.graphics.endFill();
         b.addChild(s);
         b.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            e.stopPropagation();
            act();
         });
         parent.addChild(b);
         return b;
      }

      public static function toggle(t:Sprite, on:Boolean) : void
      {
         t.removeChildren();
         t.buttonMode = true;
         rect(t,0,0,64,26,on ? TEAL : DIM,26);
         rect(t,on ? 40 : 2,2,22,22,WHITE,22);
         text(t,on ? "ON" : "OFF",on ? 10 : 29,3,14,on ? BODY : GREY,XBOLD);
      }

      public static function frame(screen:ScreenBase, title:String, half:Number, onClose:Function) : Sprite
      {
         var panel:MovieClip = screen.panelClip;
         for(var i:int = 0; i < panel.numChildren; i++)
         {
            var child:DisplayObject = panel.getChildAt(i);
            var ornament:Boolean = child is Shape && Math.abs(child.y + 175) < 3;
            child.visible = ornament || child.name == "am_Close" || child.name == "am_Header";
         }
         var back:Sprite = new Sprite();
         panel.addChildAt(back,0);
         rect(back,-half + 7,-220 + 8,half * 2,640,0x04090E);
         rect(back,-half,-220,half * 2,640,PANEL);
         screen.addLocalizedText(panel,"am_Header",key(title),Localization.var_13893);
         var close:MovieClip = class_51.method_3081(panel,"am_Close");
         if(close != null)
         {
            close.x += -half + 397.4;
            screen.method_7481(close,onClose);
         }
         var body:Sprite = new Sprite();
         panel.addChild(body);
         rect(body,-half,-121.8,half * 2,451,BODY);
         return body;
      }

      public static function tabButton(parent:Sprite, label:String, x:Number, y:Number, scale:Number, onClick:Function) : MovieClip
      {
         var clip:MovieClip = class_687.method_1497("a_TabButton","UI_EventCenter");
         clip.x = x;
         clip.y = y;
         clip.scaleX = clip.scaleY = scale;
         if(clip.getChildByName("am_Text") != null)
         {
            clip.getChildByName("am_Text").visible = false;
         }
         var holder:Sprite = new Sprite();
         clip.addChild(holder);
         text(holder,label,79,6,17,NAVY_TEXT,BOLD,0,true);
         clip.buttonMode = true;
         clip.mouseChildren = false;
         clip.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            onClick();
         });
         clip.addEventListener(MouseEvent.ROLL_OVER,function(e:MouseEvent):void
         {
            clip.gotoAndStop(clip.selected ? "OverSelected" : "Over");
         });
         clip.addEventListener(MouseEvent.ROLL_OUT,function(e:MouseEvent):void
         {
            clip.gotoAndStop(clip.selected ? "Selected" : "Ready");
         });
         parent.addChild(clip);
         return clip;
      }

      public static function gotoLabel(clip:MovieClip, label:String) : void
      {
         if(clip == null)
         {
            return;
         }
         for each(var l:Object in clip.currentLabels)
         {
            if(l.name == label)
            {
               clip.gotoAndStop(label);
               return;
            }
         }
      }

      public static function paintTabs(tabs:Array, selected:int) : void
      {
         for(var i:int = 0; i < tabs.length; i++)
         {
            var clip:MovieClip = tabs[i];
            clip.selected = i == selected;
            clip.gotoAndStop(i == selected ? "Selected" : "Ready");
         }
      }

      public static function chips(parent:Sprite, names:Array, selected:int, focused:Boolean, onPick:Function) : Number
      {
         parent.removeChildren();
         var x:Number = 0;
         for(var i:int = 0; i < names.length; i++)
         {
            var chip:Sprite = new Sprite();
            chip.x = x;
            chip.buttonMode = true;
            parent.addChild(chip);
            var on:Boolean = i == selected;
            var label:TextField = text(chip,String(names[i]).toUpperCase(),12,3,13,on ? NAVY_TEXT : LIGHT,XBOLD);
            var back:Shape = rect(chip,0,0,label.width + 24,24,on ? TEAL : LINE,24);
            chip.setChildIndex(back,0);
            if(on && focused)
            {
               rect(chip,6,27,label.width + 12,3,WHITE);
            }
            chip.addEventListener(MouseEvent.CLICK,pickHandler(onPick,i));
            x += label.width + 30;
         }
         return x;
      }

      private static function pickHandler(onPick:Function, i:int) : Function
      {
         return function(e:MouseEvent):void
         {
            onPick(i);
         };
      }
   }
}
