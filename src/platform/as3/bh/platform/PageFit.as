package bh.platform
{
   import flash.Lib;
   import flash.display.Stage;
   import flash.events.Event;
   import flash.display.Sprite;
   import flash.geom.Point;
   import flash.geom.Rectangle;

   public final class PageFit
   {
      private static const WIDEST:Number = 1366 / 768;

      public function PageFit()
      {
      }

      public static function screen(full:Rectangle) : Rectangle
      {
         var s:Stage = Lib.current.stage;
         if(s == null || s.stageWidth <= 0 || s.stageHeight <= 0 || s.stageWidth / s.stageHeight >= WIDEST)
         {
            return null;
         }
         return new Rectangle(full.x,full.y,full.width,full.width * s.stageHeight / s.stageWidth);
      }

      public static function keep(body:Sprite, page:Rectangle) : void
      {
         var place:Function = function(e:Event = null):void
         {
            if(body.parent == null || body.stage == null)
            {
               return;
            }
            var tl:Point = body.parent.globalToLocal(new Point(0,0));
            var br:Point = body.parent.globalToLocal(new Point(body.stage.stageWidth,body.stage.stageHeight));
            var w:Number = br.x - tl.x;
            var h:Number = br.y - tl.y;
            var k:Number = Math.min(w / page.width,h / page.height);
            if(k > 0)
            {
               var x:Number = tl.x + (w - page.width * k) / 2 - page.x * k;
               var y:Number = tl.y + (h - page.height * k) / 2 - page.y * k;
               if(body.scaleX != k || body.x != x || body.y != y)
               {
                  body.scaleX = body.scaleY = k;
                  body.x = x;
                  body.y = y;
               }
            }
         };
         body.addEventListener(Event.ADDED_TO_STAGE,place);
         body.addEventListener(Event.ENTER_FRAME,place);
         place();
      }
   }
}
