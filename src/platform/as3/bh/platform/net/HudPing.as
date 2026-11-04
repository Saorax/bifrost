package bh.platform.net
{
   import bh.platform.Hooks;
   import bh.platform.UiKit;
   import flash.display.Sprite;
   import flash.display.Stage;
   import flash.text.TextField;

   public final class HudPing
   {
      public static var showing:Boolean = false;

      private static var block:Sprite = null;
      private static var field:TextField = null;
      private static var colour:int = -1;
      private static var registered:Boolean = false;
      private static var lastText:String = "";
      private static var lastPing:int = int.MIN_VALUE;
      private static var lastDelay:int = -1;
      private static var lastSync:Boolean = false;
      private static var lastRb:int = -1;

      public function HudPing()
      {
      }

      public static function register() : void
      {
         if(registered)
         {
            return;
         }
         registered = true;
         Hooks.frameRendering.add(onFrame);
      }

      private static function hide() : void
      {
         showing = false;
         colour = -1;
         if(block != null && block.parent != null)
         {
            block.parent.removeChild(block);
         }
      }

      private static function onFrame() : void
      {
         try
         {
            var hud:Object = ScreenManager.var_14460;
            if(!P2PSession.active || hud == null || !hud.isActive || hud.var_11076 || hud.var_11218 == null)
            {
               hide();
               return;
            }
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var s:Stage = Object(GameApp.mainInstance).stage as Stage;
            var icon:Object = hud.var_11218.mTheDO3D;
            icon.isActive = true;
            var ping:int = P2PSession.ping;
            var level:int = ping < 0 ? 0 : (ping >= 368 ? 3 : (ping >= 240 ? 2 : (ping >= 144 ? 1 : 0)));
            if(level != colour)
            {
               colour = level;
               hud.var_11218.method_1285(class_448.var_12904[level],0);
            }
            var delay:int = int(P2PSession.inputDelay);
            var sync:Boolean = Desync.mismatches == 0;
            var rb:int = int(P2PSession.rollbackCount);
            var text:String = lastText;
            if(ping != lastPing || delay != lastDelay || sync != lastSync || rb != lastRb)
            {
               lastPing = ping;
               lastDelay = delay;
               lastSync = sync;
               lastRb = rb;
               text = (ping >= 0 ? ping + " ms" : "- ms") + "\nDELAY " + delay + "\n" + (sync ? "SYNC OK" : "DESYNC") +
                  "  RB " + rb;
            }
            if(block == null)
            {
               block = new Sprite();
               block.mouseEnabled = block.mouseChildren = false;
               field = UiKit.text(block,"",0,0,12,UiKit.WHITE,UiKit.BOLD);
            }
            if(text != lastText)
            {
               lastText = text;
               field.text = text;
               block.graphics.clear();
               block.graphics.beginFill(0,0.45);
               block.graphics.drawRoundRect(-6,-3,field.width + 12,field.height + 6,8,8);
               block.graphics.endFill();
            }
            var scale:Number = Number(core.main.var_14514);
            var rootX:Number = Number(core.var_12202.x);
            var rootY:Number = Number(core.var_12202.y);
            var widthUi:Number = (field.width + 16) / scale;
            var iconX:Number = Number(hud.var_11888.x) + Number(icon.x);
            var iconY:Number = Number(hud.var_11888.y) + Number(icon.y);
            block.x = Math.round((iconX - widthUi + 2) * scale + rootX);
            block.y = Math.round((iconY - 4) * scale + rootY);
            if(block.parent == null)
            {
               s.addChild(block);
            }
            var base:Number = -Number(hud.var_3523) * 65 - 23 - 46 - widthUi;
            hud.var_5850.var_5063.x = base;
            hud.var_7038.var_5063.x = base - 70;
            showing = true;
         }
         catch(e:Error)
         {
            hide();
         }
      }
   }
}
