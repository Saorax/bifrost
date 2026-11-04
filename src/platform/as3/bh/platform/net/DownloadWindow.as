package bh.platform.net
{
   import bh.platform.UiKit;
   import flash.display.Shape;
   import flash.display.Sprite;
   import flash.display.Stage;
   import flash.text.TextField;

   public final class DownloadWindow
   {
      private static const W:Number = 560;
      private static const H:Number = 120;

      private static var box:Sprite = null;
      private static var title:TextField = null;
      private static var detail:TextField = null;
      private static var fill:Shape = null;

      public function DownloadWindow()
      {
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

      public static function progress(name:String, index:int, count:int, loaded:Number, total:Number) : void
      {
         var s:Stage = stage();
         if(s == null)
         {
            return;
         }
         if(box == null)
         {
            box = new Sprite();
            box.mouseEnabled = box.mouseChildren = false;
            UiKit.rect(box,0,0,W,H,UiKit.PANEL,10);
            UiKit.rect(box,20,78,W - 40,18,UiKit.BODY,6);
            fill = new Shape();
            box.addChild(fill);
            title = UiKit.text(box,"",20,14,20,UiKit.WHITE,UiKit.BOLD);
            detail = UiKit.text(box,"",20,44,14,UiKit.LIGHT,UiKit.MEDIUM);
         }
         if(box.parent == null || box.parent.getChildIndex(box) != box.parent.numChildren - 1)
         {
            s.addChild(box);
         }
         box.x = Math.round((s.stageWidth - W) / 2);
         box.y = Math.round(s.stageHeight * 0.12);
         title.text = "DOWNLOADING MODS" + (count > 1 ? "  " + index + " / " + count : "");
         var kb:String = total > 0 ? Math.round(loaded / 1024) + " of " + Math.round(total / 1024) + " KB" :
            Math.round(loaded / 1024) + " KB";
         detail.text = name + "   " + kb;
         UiKit.fit(detail,W - 40);
         var part:Number = total > 0 ? Math.max(0,Math.min(1,loaded / total)) : 0;
         var whole:Number = count > 0 ? (index - 1 + part) / count : part;
         fill.graphics.clear();
         fill.graphics.beginFill(UiKit.TEAL);
         fill.graphics.drawRoundRect(20,78,Math.max(6,(W - 40) * whole),18,6,6);
         fill.graphics.endFill();
      }

      public static function close() : void
      {
         if(box != null && box.parent != null)
         {
            box.parent.removeChild(box);
         }
      }
   }
}
