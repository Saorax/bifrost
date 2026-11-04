package bh.platform
{
   import flash.utils.Dictionary;

   public final class Notices
   {
      public static const TYPE:uint = 50;
      private static const MAX:int = 8;

      private static var notes:Dictionary = new Dictionary();

      public function Notices()
      {
         super();
      }

      public static function add(key:String, title:String, text:String, icon:String, actions:Array = null) : Boolean
      {
         var core:Object = ScreenManager.owner;
         if(core == null || core.var_8451 == null || core.var_8451.var_9554 == null)
         {
            return false;
         }
         remove(key,false);
         var list:Object = core.var_8451.var_9554;
         var mine:Array = [];
         for each(var e:Object in list)
         {
            if(notes[e] != null)
            {
               mine.push(e);
            }
         }
         while(mine.length >= MAX)
         {
            drop(mine.pop());
         }
         try
         {
            if(class_282.var_1505 != null && class_282.var_1505.h[TYPE] == null)
            {
               class_282.var_1505.h[TYPE] = "Empty_String";
            }
         }
         catch(err:Error)
         {
         }
         var entry:class_282 = new class_282(TYPE);
         notes[entry] = {"key":key,"title":title,"text":text,"icon":icon,"actions":actions || []};
         list.unshift(entry);
         refresh();
         Platform.log("notices: " + key + ": " + title + " - " + text);
         return true;
      }

      public static function remove(key:String, redraw:Boolean = true) : void
      {
         for(var e:Object in notes)
         {
            if(notes[e].key == key)
            {
               drop(e);
               if(redraw)
               {
                  refresh();
               }
               return;
            }
         }
      }

      public static function owns(entry:Object) : Boolean
      {
         return entry != null && notes[entry] != null;
      }

      public static function describe() : Array
      {
         var out:Array = [];
         var core:Object = ScreenManager.owner;
         if(core != null && core.var_8451 != null)
         {
            for each(var e:Object in core.var_8451.var_9554)
            {
               var n:Object = notes[e];
               if(n != null)
               {
                  out.push(n.key + ": " + n.title + " - " + n.text);
               }
            }
         }
         return out;
      }

      public static function noticeRows(list:Object) : void
      {
         if(list == null)
         {
            return;
         }
         for each(var row:Object in list)
         {
            var n:Object = row != null ? notes[row.var_14927] : null;
            if(n == null)
            {
               continue;
            }
            row.var_4355 = "Empty_String";
            row.var_13044 = n.title;
            row.var_14009 = "Empty_String";
            row.var_11786 = "";
            row.var_1221 = n.text;
            row.var_12946 = n.icon;
         }
      }

      public static function noticeTitle(hub:Object) : void
      {
         var n:Object = selected(hub);
         if(n != null)
         {
            hub.var_12457.method_7982(n.title);
            hub.var_12457.method_3789();
         }
      }

      public static function noticeButtons(hub:Object) : void
      {
         var n:Object = selected(hub);
         if(n == null)
         {
            return;
         }
         var entry:Object = hub.method_1885();
         for each(var a:Object in n.actions)
         {
            hub.var_12457.method_5926(String(a.label),"",press(hub,entry,a.action),false,true,false);
         }
         hub.var_12457.method_5926("DISMISS","",press(hub,entry,null),false,true,false);
      }

      private static function press(hub:Object, entry:Object, action:Function) : Function
      {
         return function(b:Boolean = false):void
         {
            var n:Object = notes[entry];
            drop(entry);
            hub.var_13237 = hub.method_4811();
            ScreenManager.var_11733.method_3789();
            if(action != null)
            {
               try
               {
                  action();
               }
               catch(e:Error)
               {
                  Platform.log("notices: " + (n != null ? n.key : "?") + ": " + e.message);
               }
            }
         };
      }

      private static function selected(hub:Object) : Object
      {
         if(hub == null)
         {
            return null;
         }
         var e:Object = hub.method_1885();
         return e != null ? notes[e] : null;
      }

      private static function drop(entry:Object) : void
      {
         delete notes[entry];
         var core:Object = ScreenManager.owner;
         if(core != null && core.var_8451 != null)
         {
            core.var_8451.method_3728(entry.var_10501);
         }
      }

      private static function refresh() : void
      {
         try
         {
            if(ScreenManager.var_8315 != null)
            {
               ScreenManager.var_8315.method_8886();
            }
            if(ScreenManager.var_11733 != null)
            {
               ScreenManager.var_11733.method_3789();
            }
         }
         catch(e:Error)
         {
         }
      }
   }
}
