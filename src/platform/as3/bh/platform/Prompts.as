package bh.platform
{
   import flash.display.DisplayObject;
   import flash.display.MovieClip;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.geom.Rectangle;
   import flash.utils.Dictionary;

   public final class Prompts
   {
      public static const KEYS:Object = {"tabs":"{PageLeft2}{PageRight2}","page":"{PageLeft}{PageRight}","select":"{Select}",
         "back":"{Back}","option":"{Option}"};

      private static function word(name:String) : String
      {
         var n:Object = BigWindow.buttonNames();
         switch(name)
         {
            case "PageLeft2":
               return n.tabs.split("/")[0].split(" ")[0];
            case "PageRight2":
               return n.tabs.indexOf("/") > 0 ? n.tabs.split("/")[1] : n.tabs.split(" ")[1];
            case "PageLeft":
               return n.page.split("/")[0].split(" ")[0];
            case "PageRight":
               return n.page.indexOf("/") > 0 ? n.page.split("/")[1] : n.page.split(" ")[1];
            case "Select":
               return n.select;
            case "Back":
               return n.back;
            case "Option":
               return n.option;
         }
         return name.toUpperCase();
      }

      public static function flow(screen:ScreenBase, box:Sprite, spec:String, width:Number, textSize:Number = 13,
                                  color:uint = 0x7F8C99, size:Number = 20) : Sprite
      {
         return fill(screen,box,spec,size,textSize,color,NaN,box.x,null,width);
      }

      public static function plain(spec:String) : String
      {
         return spec.replace(/\{([A-Za-z0-9]+)\}/g,function(m:String, name:String, ... rest):String
         {
            return word(name);
         });
      }

      public static function fill(screen:ScreenBase, bar:Sprite, spec:String, size:Number = 20, textSize:Number = 12,
                                  color:uint = 0x7F8C99, right:Number = NaN, left:Number = 0, device:Object = null,
                                  wrap:Number = 0) : Sprite
      {
         clear(screen,bar);
         var parts:Array = [];
         var re:RegExp = /\{([A-Za-z0-9]+)\}/g;
         var at:int = 0;
         var m:Object;
         while((m = re.exec(spec)) != null)
         {
            if(m.index > at)
            {
               parts.push({"text":spec.substring(at,m.index)});
            }
            parts.push({"key":m[1]});
            at = m.index + m[0].length;
         }
         if(at < spec.length)
         {
            parts.push({"text":spec.substring(at)});
         }
         if(wrap > 0)
         {
            var words:Array = [];
            for each(var tp:Object in parts)
            {
               if(tp.text == null)
               {
                  words.push(tp);
                  continue;
               }
               var lines:Array = String(tp.text).split(String.fromCharCode(10));
               for(var li:int = 0; li < lines.length; li++)
               {
                  if(li > 0)
                  {
                     words.push({"br":true});
                  }
                  var ws:Array = String(lines[li]).split(" ");
                  for(var wi:int = 0; wi < ws.length; wi++)
                  {
                     if(ws[wi] != "")
                     {
                        words.push({"text":ws[wi],"word":true,"space":wi < ws.length - 1 || ws[wi] == ""});
                     }
                     else if(words.length > 0 && words[words.length - 1].key != null)
                     {
                        words[words.length - 1].space = true;
                     }
                  }
               }
            }
            parts = words;
         }
         var widgets:Array = [];
         for each(var p:Object in parts)
         {
            if(p.br)
            {
               continue;
            }
            if(p.word)
            {
               p.field = UiKit.text(bar,p.text,0,0,textSize,color,UiKit.MEDIUM);
               p.lead = 0;
               p.trail = p.space ? 4 : 0;
               continue;
            }
            if(p.text != null)
            {
               p.field = UiKit.text(bar,p.text.replace(/^ +| +$/g,""),0,0,textSize,color,UiKit.MEDIUM);
               p.lead = p.text.charAt(0) == " " ? 6 : 0;
               p.trail = p.text.charAt(p.text.length - 1) == " " ? 18 : 0;
               continue;
            }
            var clip:MovieClip = new MovieClip();
            clip.name = "am_Hotkey_" + p.key + "_" + size;
            bar.addChild(clip);
            p.clip = clip;
            p.fallback = UiKit.text(bar,word(p.key),0,0,textSize,UiKit.LIGHT,UiKit.XBOLD);
            try
            {
               var w:class_680 = new class_680(screen.owner,clip);
               w.var_11925 = true;
               if(device != null)
               {
                  w.method_6177(class_223(device),true);
               }
               else
               {
                  screen.method_2685(w);
                  w.Update();
               }
               p.widget = w;
               widgets.push(w);
            }
            catch(e:Error)
            {
               ErrorLog.write("prompts: " + p.key + ": " + e);
            }
         }
         bar.mouseChildren = false;
         bar.mouseEnabled = false;
         var state:Object = {"parts":parts,"widgets":widgets,"size":size,"right":right,"left":left,"sig":null,"wrap":wrap};
         bars[bar] = state;
         layout(bar,state);
         if(!bar.hasEventListener(Event.ENTER_FRAME))
         {
            bar.addEventListener(Event.ENTER_FRAME,relayout);
         }
         return bar;
      }

      public static function clear(screen:ScreenBase, bar:Sprite) : void
      {
         var state:Object = bars[bar];
         if(state != null)
         {
            for each(var w:class_680 in state.widgets)
            {
               try
               {
                  if(screen.var_40 != null)
                  {
                     var i:int = screen.var_40.indexOf(w);
                     if(i >= 0)
                     {
                        screen.var_40.splice(i,1);
                     }
                  }
                  w.Destroy();
               }
               catch(e:Error)
               {
               }
            }
            delete bars[bar];
         }
         bar.removeChildren();
      }

      private static var bars:Object = new Dictionary(true);

      private static function relayout(e:Event) : void
      {
         var bar:Sprite = e.currentTarget as Sprite;
         var state:Object = bars[bar];
         if(state == null || bar.stage == null)
         {
            return;
         }
         layout(bar,state);
      }

      private static function layout(bar:Sprite, state:Object) : void
      {
         var sig:Array = state.sig != null ? state.sig : (state.sig = []);
         var changed:Boolean = false;
         var n:int = 0;
         var p:Object;
         for each(p in state.parts)
         {
            if(p.clip != null)
            {
               var shown:Boolean = p.clip.numChildren > 0 && p.clip.width > 0;
               p.fallback.visible = !shown;
               var w:Number = shown ? Math.round(p.clip.width) : -1;
               if(n >= sig.length || sig[n] !== w)
               {
                  sig[n] = w;
                  changed = true;
               }
               n++;
            }
         }
         if(sig.length != n)
         {
            sig.length = n;
            changed = true;
         }
         if(!changed)
         {
            return;
         }
         if(state.wrap > 0)
         {
            flowLayout(bar,state);
            return;
         }
         var x:Number = 0;
         var mid:Number = state.size / 2;
         for each(p in state.parts)
         {
            if(p.field != null)
            {
               x += p.lead;
               p.field.x = x;
               p.field.y = mid - p.field.height / 2;
               x += p.field.width + p.trail;
            }
            else if(p.fallback.visible)
            {
               p.fallback.x = x;
               p.fallback.y = mid - p.fallback.height / 2;
               x += p.fallback.width + 2;
            }
            else
            {
               var r:Rectangle = p.clip.getBounds(p.clip);
               p.clip.x = x - r.x;
               p.clip.y = mid - (r.y + r.height / 2);
               x += r.width + 2;
            }
         }
         bar.x = isNaN(state.right) ? state.left : state.right - x;
      }

      private static function flowLayout(bar:Sprite, state:Object) : void
      {
         var x:Number = 0;
         var y:Number = 0;
         var lineH:Number = state.size + 2;
         for each(var p:Object in state.parts)
         {
            if(p.br)
            {
               x = 0;
               y += lineH;
               continue;
            }
            var w:Number;
            var obj:DisplayObject;
            var r:Rectangle = null;
            if(p.field != null)
            {
               obj = p.field;
               w = p.field.textWidth;
            }
            else if(p.fallback.visible)
            {
               obj = p.fallback;
               w = p.fallback.textWidth;
            }
            else
            {
               obj = p.clip;
               r = p.clip.getBounds(p.clip);
               w = r.width;
            }
            if(x > 0 && x + w > state.wrap)
            {
               x = 0;
               y += lineH;
            }
            if(r != null)
            {
               obj.x = x - r.x;
               obj.y = y + lineH / 2 - (r.y + r.height / 2);
            }
            else
            {
               obj.x = x - 2;
               obj.y = y + lineH / 2 - obj.height / 2;
            }
            x += w + (r != null ? 2 : 0) + (p.space ? 4 : 0);
         }
      }
   }
}
