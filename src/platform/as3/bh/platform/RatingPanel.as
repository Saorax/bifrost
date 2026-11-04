package bh.platform
{
   import flash.display.Bitmap;
   import flash.display.Sprite;
   import flash.display.Stage;
   import flash.utils.getTimer;

   public class RatingPanel
   {
      private static const SHOW_MS:int = 9000;
      private static var panel:Sprite;
      private static var until:int = 0;
      private static var hooked:Boolean = false;

      public function RatingPanel()
      {
      }

      public static function show(info:Object) : void
      {
         var stage:Stage = Object(GameApp.mainInstance).stage;
         if(stage == null || info == null || info.after == null)
         {
            return;
         }
         if(!hooked)
         {
            hooked = true;
            Hooks.frameStarting.add(fade);
         }
         hide();
         var before:int = int(info.before);
         var after:int = int(info.after);
         var change:int = after - before;
         var tier:String = String(info.tier || "Tin");
         panel = new Sprite();
         panel.mouseEnabled = panel.mouseChildren = false;
         var w:Number = 560;
         var h:Number = 118;
         UiKit.rect(panel,0,0,w,h,UiKit.PANEL,12);
         UiKit.rect(panel,4,4,w - 8,h - 8,UiKit.BODY,10);
         var icon:Bitmap = LeaderboardWindow.tierBanner(tier,84,after);
         if(icon != null)
         {
            icon.x = 16;
            icon.y = 16;
            panel.addChild(icon);
         }
         var ladder:String = String(info.ladder || "1v1").toUpperCase();
         UiKit.text(panel,ladder + " RATING",116,12,14,UiKit.GREY,UiKit.XBOLD);
         UiKit.text(panel,String(after),116,30,34,UiKit.WHITE,UiKit.XBOLD);
         UiKit.text(panel,(change >= 0 ? "+" : "") + change,232,40,22,change >= 0 ? UiKit.TEAL : UiKit.RED,UiKit.XBOLD);
         var up:Boolean = info.tier_before != null && String(info.tier_before) != tier && change > 0;
         var down:Boolean = info.tier_before != null && String(info.tier_before) != tier && change < 0;
         var tierText:Object = UiKit.text(panel,(up ? "TIER UP: " : "") + tier.toUpperCase(),0,14,16,
            up ? UiKit.TEAL : (down ? UiKit.RED : UiKit.LIGHT),UiKit.XBOLD);
         tierText.x = w - 20 - tierText.width;
         var barX:Number = 116;
         var barW:Number = w - barX - 24;
         var barY:Number = 82;
         UiKit.rect(panel,barX,barY,barW,12,UiKit.DIM,6);
         var start:Number = Number(info.start);
         var next:Number = info.next != null ? Number(info.next) : NaN;
         var part:Number = isNaN(next) ? 1 : Math.max(0,Math.min(1,(after - start) / (next - start)));
         if(part > 0)
         {
            UiKit.rect(panel,barX,barY,Math.max(12,barW * part),12,UiKit.TEAL,6);
         }
         UiKit.text(panel,isNaN(next) ? "Top tier" : (int(next) - after) + " to the next tier",barX,barY + 14,11,UiKit.GREY,
            UiKit.BOLD);
         if(info.team != null)
         {
            var tc:int = int(info.team.after) - int(info.team.before);
            var teamText:Object = UiKit.text(panel,"TEAM " + info.team.after + " (" + (tc >= 0 ? "+" : "") + tc + ")",0,48,14,
               tc >= 0 ? UiKit.TEAL : UiKit.RED,UiKit.XBOLD);
            teamText.x = w - 20 - teamText.width;
         }
         var scale:Number = stage.stageWidth / 1920;
         panel.scaleX = panel.scaleY = scale;
         panel.x = (stage.stageWidth - w * scale) / 2;
         panel.y = stage.stageHeight * 0.04;
         stage.addChild(panel);
         until = getTimer() + SHOW_MS;
      }

      private static function hide() : void
      {
         if(panel != null && panel.parent != null)
         {
            panel.parent.removeChild(panel);
         }
         panel = null;
      }

      private static function fade() : void
      {
         if(panel != null && getTimer() > until)
         {
            hide();
         }
      }
   }
}
