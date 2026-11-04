package bh.platform
{
   import flash.display.Sprite;
   import flash.events.MouseEvent;
   import flash.net.SharedObject;
   import flash.utils.ByteArray;
   import flash.utils.getQualifiedClassName;

   public class SaveEditorWindow extends BigWindow
   {
      private static const STORES:Array = [["GAME DATA","sbSavedGameData"],["PROFILE","bhProfileData"],
         ["KEY BINDINGS","bhKeybinds"],["SAVED DATA","sbSavedData"]];
      private static const COLS:int = 2;
      private static const ROW_H:Number = 34;

      private static var window:SaveEditorWindow;

      private var paths:Array = [[],[],[],[]];
      private var note:String = "";

      public function SaveEditorWindow(core:GameCore)
      {
         super(core);
      }

      public static function open() : void
      {
         if(window == null || ScreenManager.allScreens.indexOf(window) < 0)
         {
            window = new SaveEditorWindow(ScreenManager.owner);
            ScreenManager.registerScreen(window);
            if(ScreenManager.var_14744 != null)
            {
               window.registrationIndex = ScreenManager.var_14744.registrationIndex;
            }
         }
         if(!window.isActive)
         {
            window.note = "";
            window.Display();
         }
      }

      public static function get shown() : SaveEditorWindow
      {
         return window != null && window.isActive ? window : null;
      }

      private function get ROW_W() : Number
      {
         return Math.floor((area.width - 30) / COLS);
      }

      override protected function get fullPage() : Boolean
      {
         return true;
      }

      override protected function get title() : String
      {
         return "SAVE FILE EDITOR";
      }

      override protected function get tabNames() : Array
      {
         var out:Array = [];
         for each(var st:Array in STORES)
         {
            out.push(st[0]);
         }
         return out;
      }

      override protected function get tabLayout() : Array
      {
         return [-500,220,0.85];
      }

      override protected function get confirmLabel() : String
      {
         return "DONE";
      }

      override protected function statusText() : String
      {
         if(note != "")
         {
            return note;
         }
         var path:Array = paths[tab];
         return PrefixedName(tab) + (path.length > 0 ? " > " + path.join(" > ") : "");
      }

      private static function PrefixedName(i:int) : String
      {
         return SaveCopy.PREFIX + STORES[i][1];
      }

      private function store(i:int) : SharedObject
      {
         try
         {
            return SharedObject.getLocal(PrefixedName(i),"/");
         }
         catch(e:Error)
         {
            Platform.log("save editor: can't open " + PrefixedName(i) + ": " + e.message);
         }
         return null;
      }

      private function node() : Object
      {
         var so:SharedObject = store(tab);
         var at:Object = so != null ? so.data : null;
         for each(var k:String in paths[tab])
         {
            if(at == null || !isContainer(at[k]))
            {
               paths[tab] = [];
               return so != null ? so.data : null;
            }
            at = at[k];
         }
         return at;
      }

      private static function isContainer(v:*) : Boolean
      {
         return v != null && typeof v == "object" && !(v is ByteArray) && !(v is Date);
      }

      private static function keysOf(o:Object) : Array
      {
         var out:Array = [];
         for(var k:String in o)
         {
            out.push(k);
         }
         if(o is Array)
         {
            out.sort(Array.NUMERIC);
         }
         else
         {
            out.sort(Array.CASEINSENSITIVE);
         }
         return out;
      }

      private static function describe(v:*) : String
      {
         if(v === null || v === undefined)
         {
            return "(empty)";
         }
         if(v is ByteArray)
         {
            return ByteArray(v).length + " bytes (packed)";
         }
         if(v is Array)
         {
            return "LIST, " + (v as Array).length + " items  >";
         }
         if(isContainer(v))
         {
            return "OBJECT, " + keysOf(v).length + " keys  >";
         }
         if(v is String)
         {
            return "\"" + v + "\"";
         }
         return String(v);
      }

      override protected function buildTab(i:int) : void
      {
         var p:Sprite = panel(area.x,area.y,area.width,area.height);
         var at:Object = node();
         if(at == null)
         {
            UiKit.text(p,"This save can't be opened.",20,20,15,UiKit.LIGHT,UiKit.BOLD);
            return;
         }
         var content:Sprite = scroller(p,10,10,area.width - 20,area.height - 20);
         var n:int = 0;
         if(paths[i].length > 0)
         {
            row(content,n++,"< BACK","to " + (paths[i].length > 1 ? paths[i][paths[i].length - 2] : "the top"),UiKit.TEAL,
               function():void
               {
                  stepOut();
               },null);
         }
         var keys:Array = keysOf(at);
         if(keys.length == 0)
         {
            UiKit.text(content,"(nothing saved here)",14,n > 0 ? ROW_H + 16 : 10,14,UiKit.GREY,UiKit.BOLD);
         }
         for each(var k:String in keys)
         {
            addValue(content,n++,at,k);
         }
      }

      private function addValue(content:Sprite, index:int, at:Object, k:String) : void
      {
         var v:* = at[k];
         var act:Function = null;
         var change:Function = null;
         if(isContainer(v))
         {
            act = function():void
            {
               paths[tab] = (paths[tab] as Array).concat([k]);
               note = "";
               focus = 0;
               build();
            };
         }
         else if(v is Boolean)
         {
            act = change = function(dir:int = 1):void
            {
               write(at,k,!at[k]);
            };
         }
         else if(v is Number)
         {
            change = function(dir:int):void
            {
               write(at,k,Number(at[k]) + dir);
            };
            act = function():void
            {
               typeText(k,String(at[k]),20,function(text:String):void
               {
                  if(text != null && text != "" && !isNaN(Number(text)))
                  {
                     write(at,k,v is int || v is uint ? int(Number(text)) : Number(text));
                  }
               },true);
            };
         }
         else if(v is String)
         {
            act = function():void
            {
               typeText(k,String(at[k]),200,function(text:String):void
               {
                  if(text != null)
                  {
                     write(at,k,text);
                  }
               },true);
            };
         }
         var kind:String = v is Boolean ? "TRUE/FALSE" : (v is Number ? "NUMBER" : (v is String ? "TEXT" :
            (isContainer(v) ? "" : getQualifiedClassName(v).split("::").pop().toUpperCase())));
         row(content,index,k,describe(v),act != null || change != null ? UiKit.WHITE : UiKit.GREY,act,change,kind);
      }

      private function row(parent:Sprite, index:int, label:String, value:String, color:uint, act:Function,
                           change:Function, kind:String = "") : void
      {
         var r:Sprite = new Sprite();
         r.x = (index % COLS) * (ROW_W + 10);
         r.y = int(index / COLS) * (ROW_H + 4);
         r.buttonMode = act != null;
         parent.addChild(r);
         UiKit.rect(r,0,0,ROW_W,ROW_H,UiKit.BODY,5);
         UiKit.fit(UiKit.text(r,label,12,8,13,color,UiKit.XBOLD),190);
         UiKit.fit(UiKit.text(r,value,210,8,13,UiKit.LIGHT,UiKit.BOLD),ROW_W - 300);
         if(kind != "")
         {
            var t:* = UiKit.text(r,kind,0,10,10,UiKit.GREY,UiKit.XBOLD);
            t.x = ROW_W - 10 - t.width;
         }
         var i:int = items.length;
         r.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            focus = i;
            paintFocus();
            if(act != null)
            {
               act();
            }
         });
         items.push({"sprite":r,"width":ROW_W,"height":ROW_H,"parent":parent,"use":act,"change":change,"about":label,"value":value});
      }

      private function write(at:Object, k:String, value:*) : void
      {
         var before:* = at[k];
         at[k] = value;
         var so:SharedObject = store(tab);
         try
         {
            so.flush();
            note = k + ": " + describe(before) + " -> " + describe(value) + ". Saved; some changes show after a restart.";
            Platform.log("save editor: " + PrefixedName(tab) + " " + (paths[tab] as Array).concat([k]).join(".") + " " +
               describe(before) + " -> " + describe(value));
         }
         catch(e:Error)
         {
            at[k] = before;
            note = "Couldn't save: " + e.message;
         }
         build();
      }

      private function stepOut() : void
      {
         var path:Array = paths[tab];
         if(path.length > 0)
         {
            paths[tab] = path.slice(0,path.length - 1);
            note = "";
            focus = 0;
            build();
         }
      }

      override protected function useItem(it:Object, dir:int) : void
      {
         if(dir != 0 && it.change != null && !(it.use != null && it.change === it.use))
         {
            it.change(dir);
            return;
         }
         if(dir != 0)
         {
            var to:int = focus + dir;
            if(to >= 0 && to < items.length)
            {
               focus = to;
               paintFocus();
            }
            return;
         }
         if(it.use != null)
         {
            it.use();
         }
      }

      override protected function moveIn(it:Object, dir:int) : Boolean
      {
         var to:int = focus + dir * COLS;
         if(to >= 0 && to < items.length)
         {
            focus = to;
            paintFocus();
         }
         return true;
      }

      override protected function backKey() : void
      {
         if((paths[tab] as Array).length > 0)
         {
            stepOut();
         }
         else
         {
            back();
         }
      }

      override protected function showTab(i:int) : void
      {
         note = "";
         super.showTab(i);
      }
   }
}
