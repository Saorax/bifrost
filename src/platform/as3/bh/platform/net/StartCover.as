package bh.platform.net
{
   import bh.platform.Hooks;
   import flash.display.DisplayObject;
   import flash.display.Sprite;
   import flash.display.Stage;
   import flash.utils.getTimer;

   public final class StartCover
   {
      private static const ROOM:int = 2445;
      private static const FOUND:int = 2436;
      private static const QUEUE_CLOSED:int = 2428;
      private static const WATCH_AFTER_MS:int = 3000;
      private static const COVER_MS:int = 5000;

      private static var cover:Sprite = null;
      private static var since:int = 0;
      private static var registered:Boolean = false;
      private static var watchUntil:int = 0;
      private static var watchFrame:int = 0;
      private static var lastLine:String = "";

      public function StartCover()
      {
      }

      public static function register() : void
      {
         if(registered)
         {
            return;
         }
         registered = true;
         Hooks.packetReceived.add(onPacket);
         Hooks.matchPreviewShown.add(function(core:Object, info:Object):void
         {
            hide();
            if(watchUntil != 0)
            {
               watchUntil = getTimer() + WATCH_AFTER_MS;
               PrivateServer.log("start cover: loading preview shown, cover off (frame " + watchFrame + ")");
            }
         });
         Hooks.matchEnded.add(function(... args):void
         {
            watchUntil = getTimer() + 25000;
            watchFrame = 0;
            lastLine = "";
            PrivateServer.log("start cover: match ended, watching");
         });
         Hooks.frameStarting.add(function():void
         {
            if(cover != null && getTimer() - since > COVER_MS)
            {
               hide();
            }
            watch();
         });
      }

      private static function onPacket(packet:Object) : Boolean
      {
         if(packet != null && packet.type == FOUND)
         {
            watchUntil = getTimer() + 30000;
            watchFrame = 0;
            lastLine = "";
            PrivateServer.log("start cover: match found (2436), watching");
         }
         if(packet != null && packet.type == QUEUE_CLOSED && P2PMatch.queueMatch != null)
         {
            if(watchUntil != 0)
            {
               PrivateServer.log("start cover: 2428 at frame " + watchFrame + ", covering");
            }
            show();
         }
         if(packet != null && packet.type == ROOM)
         {
            if(watchUntil != 0)
            {
               PrivateServer.log("start cover: 2445 at frame " + watchFrame + (P2PMatch.queueMatch != null ? ", covering" : ", no queue match yet: not covered"));
            }
            if(P2PMatch.queueMatch != null)
            {
               show();
            }
         }
         return false;
      }

      private static function shown(screen:Object) : String
      {
         try
         {
            if(screen == null)
            {
               return "none";
            }
            var d:DisplayObject = screen.var_2459 != null ? screen.var_2459.clip as DisplayObject : null;
            var a:Number = 1;
            var on:Boolean = false;
            while(d != null)
            {
               if(!d.visible)
               {
                  a = 0;
               }
               a *= d.alpha;
               on = d is Stage;
               d = d.parent;
            }
            return (screen.isActive ? "active" : "inactive") + (on ? " a=" + a.toFixed(2) : " off-stage");
         }
         catch(e:Error)
         {
            return "?" + e.message;
         }
         return "";
      }

      private static function watch() : void
      {
         if(watchUntil == 0)
         {
            return;
         }
         if(getTimer() > watchUntil)
         {
            watchUntil = 0;
            PrivateServer.log("start cover: watch ended at frame " + watchFrame);
            return;
         }
         watchFrame++;
         var active:Array = [];
         try
         {
            for each(var sc:Object in ScreenManager.allScreens)
            {
               if(sc != null && sc.isActive)
               {
                  active.push(sc.clipName + (shown(sc).indexOf("off-stage") >= 0 ? "(off-stage)" : ""));
               }
            }
            active.push("gameState " + Object(GameApp.mainInstance).var_13259.gameState);
         }
         catch(e:Error)
         {
            active.push("?" + e.message);
         }
         var line:String = "cover " + (cover != null && cover.parent != null ? "on" : "off") + ": " + active.join(", ");
         if(line != lastLine)
         {
            lastLine = line;
            PrivateServer.log("start cover: frame " + watchFrame + " (" + getTimer() + " ms): " + line);
         }
      }

      private static function show() : void
      {
         try
         {
            var s:Stage = Object(GameApp.mainInstance).stage as Stage;
            if(s == null)
            {
               return;
            }
            if(cover == null)
            {
               cover = new Sprite();
               cover.mouseEnabled = cover.mouseChildren = false;
            }
            cover.graphics.clear();
            cover.graphics.beginFill(0x061521);
            cover.graphics.drawRect(0,0,s.stageWidth,s.stageHeight);
            cover.graphics.endFill();
            s.addChild(cover);
            since = getTimer();
         }
         catch(e:Error)
         {
         }
      }

      public static function hide() : void
      {
         if(cover != null && cover.parent != null)
         {
            cover.parent.removeChild(cover);
         }
      }
   }
}
