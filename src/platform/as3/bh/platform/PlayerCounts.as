package bh.platform
{
   import bh.platform.net.ServerStats;
   import flash.display.MovieClip;
   import flash.display.Sprite;
   import flash.geom.Rectangle;
   import flash.text.TextField;
   import flash.utils.getTimer;

   public final class PlayerCounts
   {
      private static const QUERY:String = "activity";
      private static const ASK_EVERY:int = 10000;
      private static const TAG:String = "bifrostCount";
      private static const MENU:Object = {"0":"casual","1":"ranked","3":"custom","5":"offline"};
      private static const OFFLINE:Object = {"0":"couch","1":"training"};

      private static var lastAsk:int = -ASK_EVERY;
      private static var frame:int = 0;

      public function PlayerCounts()
      {
      }

      public static function init() : void
      {
         ServerStats.register();
         ServerStats.listeners.push(function(query:String):void
         {
            if(query == QUERY)
            {
               paint();
            }
         });
         Hooks.frameStarting.add(onFrame);
         Hooks.mainMenuButtonsBuilt.add(function(m:Object):void
         {
            paint();
         });
      }

      private static function onFrame() : void
      {
         if(++frame % 30 != 0)
         {
            return;
         }
         if(!shown(ScreenManager.var_10617) && !shown(ScreenManager.var_5652) && !shown(ScreenManager.var_9828) &&
            !shown(ScreenManager.var_4976))
         {
            return;
         }
         var now:int = getTimer();
         if(now - lastAsk >= ASK_EVERY)
         {
            lastAsk = now;
            ServerStats.ask(QUERY);
         }
         paint();
      }

      private static function shown(s:Object) : Boolean
      {
         return s != null && s.isActive;
      }

      public static function get activity() : Object
      {
         var a:Object = ServerStats.get(QUERY);
         return a != null && a.error == null ? a : null;
      }

      private static function paint() : void
      {
         var a:Object = activity;
         try
         {
            var menu:Object = ScreenManager.var_10617;
            if(menu != null && menu.buttons != null)
            {
               for(var i:String in MENU)
               {
                  var b:Object = menu.buttons[int(i)];
                  tag(b != null ? b.clip : null,a != null ? a[MENU[i]] : null,false);
               }
            }
            var casual:Object = ScreenManager.var_5652;
            if(shown(casual) && casual.buttons != null && casual.var_4482 != null)
            {
               for(var c:int = 0; c < casual.buttons.length; c++)
               {
                  var row:Object = c < casual.var_4482.length && c < int(casual.var_2295) ? casual.var_4482[c] : null;
                  tag(casual.buttons[c].clip,a != null && row != null ? int(a.playlists[String(row.var_8356)]) : null,true);
               }
            }
            var ranked:Object = ScreenManager.var_9828;
            if(shown(ranked) && ranked.buttons != null)
            {
               var rows:Array = [byName("1v1Ranked"),byName("2v2Ranked"),class_301.var_2273];
               for(var r:int = 0; r < ranked.buttons.length; r++)
               {
                  var rr:Object = r < rows.length ? rows[r] : null;
                  tag(ranked.buttons[r].clip,a != null && rr != null ? int(a.playlists[String(rr.var_8356)]) : null,true);
               }
            }
            var offline:Object = ScreenManager.var_4976;
            if(shown(offline) && offline.buttons != null)
            {
               for(var o:int = 0; o < offline.buttons.length; o++)
               {
                  var field:String = OFFLINE[String(o)];
                  tag(offline.buttons[o].clip,a != null && field != null ? a[field] : null,true);
               }
            }
         }
         catch(e:Error)
         {
         }
      }

      private static function byName(name:String) : Object
      {
         for each(var list:Object in [class_301.var_4530,class_301.var_5445,class_301.var_8617])
         {
            if(list == null)
            {
               continue;
            }
            for each(var row:Object in list)
            {
               if(row != null && row.var_6054 == name)
               {
                  return row;
               }
            }
         }
         return null;
      }

      private static function tag(clip:MovieClip, count:*, card:Boolean) : void
      {
         if(clip == null)
         {
            return;
         }
         var t:Sprite = clip.getChildByName(TAG) as Sprite;
         if(count == null || isNaN(Number(count)))
         {
            if(t != null)
            {
               t.visible = false;
            }
            return;
         }
         var n:int = int(count);
         var text:String = n == 1 ? "1 PLAYING" : n + " PLAYING";
         if(t == null)
         {
            t = new Sprite();
            t.name = TAG;
            t.mouseEnabled = t.mouseChildren = false;
            UiKit.text(t,"",14,2,card ? 20 : 15,UiKit.WHITE,UiKit.BOLD);
         }
         if(t.parent != clip || clip.getChildIndex(t) != clip.numChildren - 1)
         {
            clip.addChild(t);
         }
         t.visible = true;
         var label:TextField = t.getChildAt(0) as TextField;
         if(label.text == text && t.width > 0)
         {
            return;
         }
         label.text = text;
         var w:Number = Math.ceil(label.width) + 22;
         var h:Number = Math.ceil(label.height) + 4;
         t.graphics.clear();
         t.graphics.beginFill(0x000000,0.6);
         t.graphics.drawRoundRect(0,0,w,h,h,h);
         t.graphics.endFill();
         t.graphics.beginFill(n > 0 ? UiKit.TEAL : UiKit.GREY);
         t.graphics.drawCircle(8,h / 2,4);
         t.graphics.endFill();
         if(card)
         {
            t.x = Math.round(13 - w / 2);
            t.y = -176;
            return;
         }
         clip.removeChild(t);
         var r:Rectangle = clip.getBounds(clip);
         clip.addChild(t);
         t.x = Math.round(r.right + 10);
         t.y = Math.round(r.y + (r.height - h) / 2);
      }
   }
}
