package bh.platform
{
   import flash.display.Stage;
   import flash.events.Event;
   import flash.filesystem.File;
   import flash.filesystem.FileMode;
   import flash.filesystem.FileStream;
   import flash.text.TextField;
   import flash.text.TextFieldAutoSize;
   import flash.text.TextFormat;

   public final class VersionLabel
   {
      private static var stage:Stage;
      private static var label:TextField;
      private static var tick:int = 0;
      private static var release:String = null;

      public function VersionLabel()
      {
      }

      public static function init() : void
      {
         Hooks.gameCreated.add(function(main:Object):void
         {
            stage = main.stage;
            stage.addEventListener(Event.ENTER_FRAME,onFrame,false,-1000);
         });
      }

      private static function onFrame(e:Event) : void
      {
         if(++tick % 20 != 0)
         {
            return;
         }
         try
         {
            var own:Object = ScreenManager.var_13477 != null ? ScreenManager.var_13477.var_3415 : null;
            if(own != null && own.visible)
            {
               own.visible = false;
            }
         }
         catch(err2:Error)
         {
         }
         if(release == null)
         {
            release = installedRelease();
         }
         var show:Boolean = false;
         try
         {
            var core:Object = ScreenManager.owner;
            show = GameApp.var_12250 && release != "" && !(core != null && core.gameState == 6);
         }
         catch(err:Error)
         {
         }
         if(!show)
         {
            if(label != null)
            {
               label.visible = false;
            }
            return;
         }
         if(label == null)
         {
            label = new TextField();
            label.selectable = false;
            label.mouseEnabled = false;
            label.autoSize = TextFieldAutoSize.LEFT;
            label.defaultTextFormat = new TextFormat("_sans",13,0xFFFFFF,true);
            label.alpha = 0.6;
         }
         var text:String = release;
         if(label.text != text)
         {
            label.text = text;
         }
         if(label.parent !== stage || stage.getChildIndex(label) != stage.numChildren - 1)
         {
            stage.addChild(label);
         }
         label.x = 8;
         label.y = stage.stageHeight - label.height - 4;
         label.visible = true;
      }

      private static function installedRelease() : String
      {
         try
         {
            var f:File = File.applicationDirectory.resolvePath("bifrost-engine.json");
            if(f.exists)
            {
               var s:FileStream = new FileStream();
               s.open(f,FileMode.READ);
               var name:String = JSON.parse(s.readUTFBytes(s.bytesAvailable)).release;
               s.close();
               if(name)
               {
                  return name;
               }
            }
         }
         catch(e:Error)
         {
         }
         return "";
      }
   }
}
