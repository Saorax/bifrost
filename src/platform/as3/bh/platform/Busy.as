package bh.platform
{
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.display.Stage;
   import flash.text.TextField;
   import flash.utils.getTimer;

   public final class Busy
   {
      private static const RING:Number = 11;

      private static var registered:Boolean = false;
      public static var showAfter:int = 300;
      private static var waits:Array = [];
      private static var shown:Sprite;
      private static var ring:Shape;
      private static var shownLabel:String = null;

      public static function start(key:String, label:String, timeoutMs:int = 20000) : void
      {
         if(!registered)
         {
            registered = true;
            Hooks.frameStarting.add(onFrame);
         }
         var now:int = getTimer();
         for each(var w:Object in waits)
         {
            if(w.key == key)
            {
               w.label = label;
               w.until = now + timeoutMs;
               draw();
               return;
            }
         }
         waits.push({"key":key,"label":label,"from":now,"until":now + timeoutMs});
         draw();
      }

      public static function done(key:String) : void
      {
         if(drop(key) != null)
         {
            draw();
         }
      }

      public static function waiting(key:String) : Boolean
      {
         for each(var w:Object in waits)
         {
            if(w.key == key)
            {
               return true;
            }
         }
         return false;
      }

      public static function get label() : String
      {
         return waits.length > 0 ? String(waits[0].label) : "";
      }

      public static var history:Array = [];

      private static function drop(key:String) : Object
      {
         for(var i:int = 0; i < waits.length; i++)
         {
            if(waits[i].key == key)
            {
               return waits.splice(i,1)[0];
            }
         }
         return null;
      }

      private static function visibleLabel() : String
      {
         return waits.length > 0 && getTimer() - int(waits[0].from) >= showAfter ? String(waits[0].label) : "";
      }

      private static function onFrame() : void
      {
         if(waits.length == 0 && shown == null)
         {
            return;
         }
         var now:int = getTimer();
         for(var i:int = waits.length - 1; i >= 0; i--)
         {
            if(int(waits[i].until) <= now)
            {
               waits.splice(i,1);
            }
         }
         draw();
         if(ring != null)
         {
            ring.rotation = (now / 2.5) % 360;
         }
      }

      private static function draw() : void
      {
         var text:String = visibleLabel();
         if(text == shownLabel && (shown != null) == (text != ""))
         {
            return;
         }
         shownLabel = text;
         if(shown != null && shown.parent != null)
         {
            shown.parent.removeChild(shown);
         }
         shown = null;
         ring = null;
         if(text == "")
         {
            return;
         }
         history.push(text);
         if(history.length > 12)
         {
            history.shift();
         }
         var stage:Stage = null;
         try
         {
            stage = Object(GameApp.mainInstance).stage;
         }
         catch(e:Error)
         {
         }
         if(stage == null)
         {
            return;
         }
         var k:Number = stage.stageHeight / 1080;
         var size:Number = Math.max(13,Math.round(17 * k));
         shown = new Sprite();
         shown.mouseEnabled = shown.mouseChildren = false;
         var t:TextField = UiKit.text(shown,text,0,0,size,UiKit.WHITE,UiKit.BOLD);
         var r:Number = RING * k;
         var pad:Number = 12 * k;
         var w:Number = pad + r * 2 + pad * 0.8 + t.textWidth + pad;
         var h:Number = Math.max(r * 2,t.textHeight) + pad * 1.4;
         shown.graphics.beginFill(UiKit.BODY,0.85);
         shown.graphics.drawRoundRect(0,0,w,h,10 * k,10 * k);
         shown.graphics.endFill();
         shown.graphics.lineStyle(1,UiKit.TEAL,0.6);
         shown.graphics.drawRoundRect(0,0,w,h,10 * k,10 * k);
         t.x = pad + r * 2 + pad * 0.8;
         t.y = (h - t.textHeight) / 2 - 2;
         ring = new Shape();
         ring.graphics.lineStyle(Math.max(2,3 * k),UiKit.DIM);
         ring.graphics.drawCircle(0,0,r);
         ring.graphics.lineStyle(Math.max(2,3 * k),UiKit.TEAL);
         ring.graphics.moveTo(r,0);
         for(var a:int = 1; a <= 12; a++)
         {
            var rad:Number = a / 12 * Math.PI * 0.6;
            ring.graphics.lineTo(Math.cos(rad) * r,Math.sin(rad) * r);
         }
         ring.x = pad + r;
         ring.y = h / 2;
         shown.addChild(ring);
         shown.x = stage.stageWidth - w - 24 * k;
         shown.y = stage.stageHeight - h - 22 * k;
         stage.addChild(shown);
      }
   }
}
