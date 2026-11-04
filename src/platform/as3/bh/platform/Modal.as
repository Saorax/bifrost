package bh.platform
{
   import flash.display.MovieClip;
   import flash.text.TextField;

   public final class Modal
   {
      private static var labels:Object = {};

      private static var nextLabel:int = 0;

      private static var shown:Array = null;

      private static var shownTitle:String = null;

      private static var shownConfig:Object = null;

      private static const LONG_TEXT:int = 60;

      public function Modal()
      {
      }

      public static function show(title:String, text:String, buttons:Array = null, long:Boolean = false, escape:Boolean = true) : Boolean
      {
         try
         {
            if(buttons == null || buttons.length == 0)
            {
               buttons = [{"label":"Close"}];
            }
            shown = buttons;
            shownTitle = title;
            var c:class_438 = new class_438();
            shownConfig = c;
            c.var_14896 = long || text != null && (text.length > LONG_TEXT || text.indexOf("
") >= 0) ? class_435.Long :
               class_435.Normal;
            c.var_756 = null;
            c.var_8015 = title;
            c.var_4130 = null;
            c.var_10167 = text;
            c.var_4984 = 16316921;
            if(buttons.length == 1)
            {
               c.buttonMode = class_436.OneButton;
               c.var_5062 = key(buttons[0].label);
               c.var_3619 = action(buttons[0]);
               c.var_12739 = escape ? class_437.LeftOrMiddleCallback : class_437.NoEscape;
            }
            else
            {
               c.buttonMode = class_436.TwoButtons;
               c.var_11130 = key(buttons[0].label);
               c.var_12076 = action(buttons[0]);
               c.var_1768 = key(buttons[1].label);
               c.var_11995 = action(buttons[1]);
               c.var_2769 = true;
               c.var_12739 = escape ? class_437.HideWithoutCallback : class_437.NoEscape;
            }
            var screen:Object = ScreenManager.var_13854;
            if(screen.isActive)
            {
               screen.method_905();
            }
            class_727.PostEvent("UI_System_ServerPopup_Play");
            screen.method_6837(c);
            refresh(screen as class_439,c);
            return true;
         }
         catch(e:Error)
         {
            Platform.log("popup failed (" + e.message + "): " + title + ": " + text);
         }
         return false;
      }

      private static function refresh(screen:class_439, c:class_438) : void
      {
         try
         {
            var panel:MovieClip = screen.panelClip;
            rebind(screen.var_856,panel,"am_BodyLong");
            rebind(screen.var_237,panel,"am_BodyNormal");
            rebind(screen.var_4933,panel,"am_TitleSingleLine");
            rebind(screen.var_2756,panel,"am_TitleMultiLine");
            screen.method_2827(c);
         }
         catch(e:Error)
         {
            Platform.log("popup text not refreshed: " + e.message);
         }
      }

      private static function rebind(lt:LocalizedText, panel:MovieClip, holder:String) : void
      {
         if(lt == null)
         {
            return;
         }
         var box:MovieClip = panel != null ? class_51.method_3081(panel,holder) : null;
         var tf:TextField = box != null ? class_51.method_2013(box,"am_Text") : null;
         if(tf != null && tf !== lt.var_2544)
         {
            tf.visible = lt.var_2544.visible;
            lt.var_2544 = tf;
         }
         lt.var_3517 = lt.var_2348 = lt.var_9020 = "
";
      }

      public static function close(title:String) : Boolean
      {
         try
         {
            var screen:Object = ScreenManager.var_13854;
            if(screen != null && screen.isActive && shownTitle == title && screen.var_6447 === shownConfig)
            {
               screen.Hide();
               shownTitle = null;
               return true;
            }
         }
         catch(e:Error)
         {
         }
         return false;
      }

      public static function press(index:int) : Boolean
      {
         var screen:Object = ScreenManager.var_13854;
         if(shown == null || index < 0 || index >= shown.length || screen == null || !screen.isActive)
         {
            return false;
         }
         screen.Hide();
         action(shown[index])(index);
         return true;
      }

      private static function action(button:Object) : Function
      {
         var f:Function = button.action as Function;
         return function(index:uint):void
         {
            if(f != null)
            {
               try
               {
                  f();
               }
               catch(e:Error)
               {
                  Platform.log("popup button failed: " + e.getStackTrace());
               }
            }
         };
      }

      private static function key(label:String) : String
      {
         label = label || "Close";
         var k:String = labels[label];
         if(k == null)
         {
            k = "UI_Bifrost_Button_" + nextLabel++;
            labels[label] = k;
         }
         class_256.var_5943.var_15061.method_65(k,label);
         return k;
      }
   }
}
