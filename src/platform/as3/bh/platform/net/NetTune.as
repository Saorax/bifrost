package bh.platform.net
{
   import bh.platform.UiKit;
   import flash.display.Sprite;
   import flash.display.Stage;
   import flash.utils.getTimer;

   public final class NetTune
   {
      public static const TUNE_SAMPLES:int = 6;
      public static const TUNE_MS:int = 3000;
      public static const SHOW_MS:int = 7000;

      public static var decided:Boolean = false;

      public static var smoothingMs:uint = 0;

      private static var panel:Sprite;
      private static var shownAt:int = 0;
      private static var lines:Array = [];

      public function NetTune()
      {
      }

      public static function reset() : void
      {
         decided = false;
         smoothingMs = 0;
         lines = [];
         hide();
      }

      public static function get interval() : int
      {
         return decided ? 1000 : 250;
      }

      private static function sorted(list:Array) : Array
      {
         return (list || []).concat().sort(Array.NUMERIC);
      }

      public static function measure(samples:Array, sent:int, answered:int) : Object
      {
         var s:Array = sorted(samples);
         if(s.length < 3)
         {
            return null;
         }
         var median:int = int(s[int(s.length / 2)]);
         var p90:int = int(s[Math.min(s.length - 1,int(Math.ceil(s.length * 0.9)) - 1)]);
         var loss:Number = sent > 2 ? Math.max(0,1 - answered / Math.max(1,sent - 2)) : 0;
         return {"rtt":median,"p90":p90,"jitter":p90 - median,"loss":loss,"samples":s.length};
      }

      public static function delayFor(m:Object, maxAuto:uint, highPing:uint) : uint
      {
         var cap:uint = m.p90 > 200 ? uint(Math.min(highPing,Math.max(maxAuto,Math.ceil(m.p90 / 4 / 16) * 16))) : maxAuto;
         var want:uint = uint(Math.max(32,Math.ceil((m.rtt / 2 + m.jitter + 8) / 16) * 16));
         if(m.loss >= 0.05)
         {
            want += 16;
            cap += 16;
         }
         return uint(Math.min(cap,want));
      }

      public static function smoothingFor(m:Object) : uint
      {
         return uint(Math.max(80,Math.min(200,Math.round((100 + m.rtt / 4 + m.jitter) / 10) * 10)));
      }

      public static function describe(m:Object, path:String, delay:uint, delayFixed:Boolean, rollback:Boolean,
                                      smoothing:Boolean, smoothMs:uint) : Array
      {
         return ["Round trip " + m.rtt + " ms" + (m.jitter > 0 ? " (jitter " + m.jitter + " ms" : " (") +
            (m.loss > 0 ? ", " + Math.round(m.loss * 100) + "% lost)" : (m.jitter > 0 ? ")" : "steady)")) + ", " + path,
            "Input delay " + delay + " ms" + (delayFixed ? " (set by the room)" : ""),
            "Rollback " + (rollback ? "on" : "off") + (rollback && smoothing ? ", smoothing " + smoothMs + " ms" : "")];
      }

      public static function show(text:Array) : void
      {
         lines = text;
         shownAt = getTimer();
         draw();
      }

      public static function update(index:int, text:String) : void
      {
         if(index < lines.length)
         {
            lines[index] = text;
            if(panel != null)
            {
               draw();
            }
         }
      }

      private static function stage() : Stage
      {
         try
         {
            return Object(GameApp.mainInstance).stage as Stage;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private static function draw() : void
      {
         var s:Stage = stage();
         if(s == null || lines.length == 0)
         {
            return;
         }
         hide();
         var sc:Number = s.stageHeight / 1080;
         panel = new Sprite();
         panel.mouseEnabled = panel.mouseChildren = false;
         var w:Number = 560 * sc;
         var h:Number = (48 + lines.length * 24) * sc;
         UiKit.rect(panel,0,0,w,h,UiKit.PANEL,10 * sc);
         UiKit.rect(panel,0,0,w,4 * sc,UiKit.TEAL,0);
         UiKit.text(panel,"NETWORK SETTINGS FOR THIS MATCH",16 * sc,12 * sc,15 * sc,UiKit.TEAL,UiKit.XBOLD);
         for(var i:int = 0; i < lines.length; i++)
         {
            UiKit.text(panel,lines[i],16 * sc,(40 + i * 24) * sc,14 * sc,UiKit.WHITE,UiKit.BOLD);
         }
         panel.x = (s.stageWidth - w) / 2;
         panel.y = 24 * sc;
         s.addChild(panel);
      }

      public static function tick() : void
      {
         if(panel != null && getTimer() - shownAt > SHOW_MS)
         {
            hide();
         }
      }

      public static function hide() : void
      {
         if(panel != null && panel.parent != null)
         {
            panel.parent.removeChild(panel);
         }
         panel = null;
      }
   }
}
