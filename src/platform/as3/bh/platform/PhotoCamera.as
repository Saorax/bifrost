package bh.platform
{
   import flash.display.Stage;
   import flash.events.MouseEvent;

   public final class PhotoCamera
   {
      private static const MIN_ZOOM:Number = 0.25;
      private static const MAX_ZOOM:Number = 6;

      private static var stage:Stage;
      private static var active:Boolean = false;
      private static var panX:Number = 0;
      private static var panY:Number = 0;
      private static var zoom:Number = 1;
      private static var dragging:Boolean = false;
      private static var lastX:Number = 0;
      private static var lastY:Number = 0;
      private static var scale:Number = 1;

      public function PhotoCamera()
      {
      }

      public static function init() : void
      {
         Hooks.gameCreated.add(function(main:Object):void
         {
            stage = main.stage;
         });
         Hooks.keyDown.add(onKey);
         Hooks.cameraPlaced.add(placed);
         Hooks.matchEnded.add(function(... rest):void
         {
            on = false;
         });
      }

      public static function get on() : Boolean
      {
         return active;
      }

      public static function set on(value:Boolean) : void
      {
         if(value == active)
         {
            return;
         }
         active = value;
         panX = panY = 0;
         zoom = 1;
         dragging = false;
         if(stage == null)
         {
            return;
         }
         if(active)
         {
            stage.addEventListener(MouseEvent.MOUSE_DOWN,onDown);
            stage.addEventListener(MouseEvent.MOUSE_UP,onUp);
            stage.addEventListener(MouseEvent.MOUSE_MOVE,onMove);
            stage.addEventListener(MouseEvent.MOUSE_WHEEL,onWheel);
         }
         else
         {
            stage.removeEventListener(MouseEvent.MOUSE_DOWN,onDown);
            stage.removeEventListener(MouseEvent.MOUSE_UP,onUp);
            stage.removeEventListener(MouseEvent.MOUSE_MOVE,onMove);
            stage.removeEventListener(MouseEvent.MOUSE_WHEEL,onWheel);
         }
      }

      public static function nudge(dx:Number, dy:Number, zoomBy:Number) : void
      {
         panX -= dx / scale;
         panY -= dy / scale;
         zoom = Math.max(MIN_ZOOM,Math.min(MAX_ZOOM,zoom * zoomBy));
      }

      public static function describe() : String
      {
         return (active ? "on" : "off") + ", pan " + Math.round(panX) + "," + Math.round(panY) + ", zoom " + zoom.toFixed(2);
      }

      private static function onKey(event:Object) : Boolean
      {
         if(event == null || uint(event.keyCode) != Screenshot.KEY || !event.ctrlKey || !event.shiftKey || event.altKey)
         {
            return false;
         }
         on = !active;
         DummyDrift.show(active ? "Free camera: drag to move, wheel to zoom (Ctrl+Shift+F12 ends it)" : "Game camera",2500);
         return true;
      }

      private static function onDown(e:MouseEvent) : void
      {
         dragging = true;
         lastX = e.stageX;
         lastY = e.stageY;
      }

      private static function onUp(e:MouseEvent) : void
      {
         dragging = false;
      }

      private static function onMove(e:MouseEvent) : void
      {
         if(!dragging || !e.buttonDown)
         {
            dragging = false;
            return;
         }
         nudge(e.stageX - lastX,e.stageY - lastY,1);
         lastX = e.stageX;
         lastY = e.stageY;
      }

      private static function onWheel(e:MouseEvent) : void
      {
         nudge(0,0,e.delta > 0 ? 1.1 : 1 / 1.1);
      }

      private static function placed(camera:class_52) : void
      {
         if(!active || stage == null)
         {
            return;
         }
         var game:GameCore = camera.owner;
         var s:Number = game.var_9075.scaleX;
         if(s == 0)
         {
            return;
         }
         var cx:Number = (stage.stageWidth / 2 - game.var_9075.x) / s + panX;
         var cy:Number = (stage.stageHeight / 2 - game.var_9075.y) / s + panY;
         scale = s * zoom;
         game.var_9075.scaleX = game.var_9075.scaleY = scale;
         game.var_9075.x = stage.stageWidth / 2 - cx * scale;
         game.var_9075.y = stage.stageHeight / 2 - cy * scale;
         if(game.levelLayer3D != null)
         {
            game.levelLayer3D.scaleX = game.levelLayer3D.scaleY = scale;
            game.levelLayer3D.x = game.var_9075.x;
            game.levelLayer3D.y = game.var_9075.y;
         }
      }
   }
}
