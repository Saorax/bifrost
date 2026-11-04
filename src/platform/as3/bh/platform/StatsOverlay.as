package bh.platform
{
   import bh.platform.net.Desync;
   import bh.platform.net.HudPing;
   import bh.platform.net.P2PSession;
   import flash.display.Sprite;
   import flash.display.Stage;
   import flash.events.Event;
   import flash.system.System;
   import flash.text.TextField;
   import flash.utils.getTimer;

   public final class StatsOverlay
   {
      public static const KEY:uint = 123;
      public static const POSITIONS:Array = ["Off","Top left","Top middle","Top right","Bottom left","Bottom middle",
         "Bottom right"];
      public static const SIZES:Array = ["Small","Medium","Large"];
      public static const LAYOUTS:Array = ["Side by side","Stacked"];
      private static const FONT_SIZES:Array = [12,15,19];
      public static const LINES:Array = [
         ["overlayFps","FPS",true,"Frames per second over the last half second."],
         ["overlayFrameTime","FRAME TIME",true,"The average frame and the longest one in the last half second: a long " +
            "frame is a drop."],
         ["overlayPing","PING",true,"The round trip to the other player in a P2P match (the slowest one with more " +
            "players), measured every second."],
         ["overlayNetwork","P2P DETAILS",true,"In a P2P match: the path (direct, or through the server's relay), the input " +
            "delay chosen from the ping, rollbacks so far and the longest one, times this PC waited for a late input, and " +
            "the desync check (OK, or DESYNC when the two PCs' matches differ), and MODS DIFFER when the other player runs other content mods."],
         ["overlayClock","CLOCK",false,"The time of day."],
         ["overlayMemory","MEMORY",false,"The game's memory in use (the heap the collections scan)."]];
      private static const UPDATE_MS:int = 500;

      private static var stage:Stage;
      private static var box:Sprite;
      private static var field:TextField;
      private static var shownSize:int = -1;
      private static var listening:Boolean = false;
      private static var hidden:Boolean = false;

      private static var windowStart:int = 0;
      private static var lastFrame:int = 0;
      private static var frames:int = 0;
      private static var worst:int = 0;

      public function StatsOverlay()
      {
      }

      public static function init() : void
      {
         Hooks.gameCreated.add(function(main:Object):void
         {
            stage = main.stage;
            apply();
         });
         Hooks.keyDown.add(onKey);
      }

      public static function get position() : int
      {
         var v:* = ModSettings.value("overlayPosition");
         return v == null ? 0 : Math.max(0,Math.min(POSITIONS.length - 1,int(v)));
      }

      public static function set position(p:int) : void
      {
         ModSettings.setValue("overlayPosition",p);
         hidden = false;
         apply();
      }

      public static function get size() : int
      {
         var v:* = ModSettings.value("overlaySize");
         return v == null ? 1 : Math.max(0,Math.min(SIZES.length - 1,int(v)));
      }

      public static function set size(s:int) : void
      {
         ModSettings.setValue("overlaySize",s);
         apply();
      }

      public static function get arrangement() : int
      {
         var v:* = ModSettings.value("overlayLayout");
         return v == null ? 0 : Math.max(0,Math.min(LAYOUTS.length - 1,int(v)));
      }

      public static function set arrangement(l:int) : void
      {
         ModSettings.setValue("overlayLayout",l);
         apply();
      }

      public static function lineOn(i:int) : Boolean
      {
         return ModSettings.flag(LINES[i][0],LINES[i][2]);
      }

      public static function setLine(i:int, on:Boolean) : void
      {
         ModSettings.setFlag(LINES[i][0],on);
         refresh(getTimer());
      }

      private static function onKey(event:Object) : Boolean
      {
         if(event == null || uint(event.keyCode) != KEY || event.ctrlKey || event.altKey || event.shiftKey)
         {
            return false;
         }
         if(position == 0)
         {
            position = 1;
         }
         else
         {
            hidden = !hidden;
            apply();
         }
         return true;
      }

      public static function apply() : void
      {
         if(stage == null)
         {
            return;
         }
         var on:Boolean = position != 0 && !hidden;
         if(!on)
         {
            if(listening)
            {
               stage.removeEventListener(Event.ENTER_FRAME,onFrame);
               listening = false;
            }
            if(box != null && box.parent != null)
            {
               box.parent.removeChild(box);
            }
            return;
         }
         if(box == null)
         {
            box = new Sprite();
            box.mouseEnabled = box.mouseChildren = false;
         }
         if(shownSize != size)
         {
            if(field != null)
            {
               box.removeChild(field);
            }
            shownSize = size;
            field = UiKit.text(box,"",6,3,FONT_SIZES[shownSize],UiKit.WHITE,UiKit.BOLD);
         }
         stage.addChild(box);
         if(!listening)
         {
            lastFrame = windowStart = getTimer();
            frames = worst = 0;
            stage.addEventListener(Event.ENTER_FRAME,onFrame,false,-1000);
            listening = true;
         }
         refresh(getTimer());
      }

      private static function onFrame(e:Event) : void
      {
         var now:int = getTimer();
         var took:int = now - lastFrame;
         lastFrame = now;
         frames++;
         if(took > worst)
         {
            worst = took;
         }
         if(now - windowStart >= UPDATE_MS)
         {
            refresh(now);
         }
      }

      private static function refresh(now:int) : void
      {
         if(field == null || box == null || box.parent == null)
         {
            return;
         }
         var span:int = Math.max(1,now - windowStart);
         var sideBySide:Boolean = arrangement == 0;
         var parts:Array = [];
         if(lineOn(0))
         {
            parts.push(frames > 0 ? Math.round(frames * 1000 / span) + " FPS" : "- FPS");
         }
         if(lineOn(1) && frames > 0)
         {
            parts.push((span / frames).toFixed(1) + " ms, worst " + worst);
         }
         var ping:int = P2PSession.ping;
         var inHud:Boolean = HudPing.showing;
         if(lineOn(2) && P2PSession.active && !inHud)
         {
            parts.push("PING " + (ping >= 0 ? ping + " ms" : "-"));
         }
         if(lineOn(3) && P2PSession.active && !inHud)
         {
            parts.push(P2PSession.pathName.toUpperCase() + ", DELAY " + P2PSession.inputDelay + " ms");
            parts.push(P2PSession.rollbackCount + " ROLLBACKS (max " + P2PSession.deepestRollback + " ms), " +
               P2PSession.waitCount + " WAITS");
            parts.push(Desync.mismatches > 0 ? "DESYNC at " + (Desync.firstAt / 1000).toFixed(1) + " s" :
               "SYNC OK (" + Desync.compared + " checks)");
            if(P2PSession.modsState == "DIFFER")
            {
               parts.push("MODS DIFFER");
            }
         }
         if(lineOn(4))
         {
            var d:Date = new Date();
            parts.push((d.hours < 10 ? "0" : "") + d.hours + ":" + (d.minutes < 10 ? "0" : "") + d.minutes);
         }
         if(lineOn(5))
         {
            parts.push(Math.round(System.totalMemoryNumber / 1048576) + " MB");
         }
         field.text = parts.join(sideBySide ? "   |   " : "\n");
         windowStart = now;
         frames = worst = 0;
         layout();
      }

      private static const TRAINING_BAR:Number = 0.064;

      private static function trainingBarShown() : Boolean
      {
         try
         {
            var screen:* = ScreenManager.var_4377;
            return screen != null && screen.panelClip != null && screen.panelClip.stage != null && screen.panelClip.visible;
         }
         catch(e:Error)
         {
         }
         return false;
      }

      private static function layout() : void
      {
         var w:Number = field.width + 12;
         var h:Number = field.height + 6;
         box.graphics.clear();
         if(field.text.length > 0)
         {
            box.graphics.beginFill(0x000000,0.55);
            box.graphics.drawRoundRect(0,0,w,h,8,8);
            box.graphics.endFill();
         }
         var sw:Number = stage.stageWidth;
         var sh:Number = stage.stageHeight;
         var p:int = position;
         var column:int = (p - 1) % 3;
         box.x = column == 0 ? 8 : (column == 1 ? Math.round((sw - w) / 2) : sw - w - 8);
         box.y = p <= 3 ? 8 : sh - h - 8;
         if(p == 1 && trainingBarShown())
         {
            box.y = Math.round(sh * TRAINING_BAR) + 4;
         }
         if(box.parent != null && box.parent.getChildIndex(box) != box.parent.numChildren - 1)
         {
            box.parent.setChildIndex(box,box.parent.numChildren - 1);
         }
      }
   }
}
