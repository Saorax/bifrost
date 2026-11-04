package bh.platform.net
{
   import bh.platform.Hooks;
   import flash.display.Sprite;
   import flash.text.TextField;
   import flash.text.TextFieldType;
   import flash.text.TextFormat;

   public final class PlayerName
   {
      public static const KEY:uint = 121;

      public static const SET_NAME:int = 11002;

      private static var box:Sprite = null;

      private static const NAME_CHANGED:int = 2430;

      private static var pending:String = null;
      private static var answered:Boolean = false;

      private static var field:TextField = null;

      private static var note:TextField = null;

      public function PlayerName()
      {
      }

      public static function init() : void
      {
         Hooks.keyDown.add(function(event:Object):Boolean
         {
            if(box != null)
            {
               if(event.keyCode == 13)
               {
                  save();
               }
               else if(event.keyCode == 27)
               {
                  close();
               }
               return true;
            }
            if(event.keyCode == KEY)
            {
               open();
               return true;
            }
            return false;
         });
         Hooks.keyUp.add(function(event:Object):Boolean
         {
            return box != null;
         });
         Hooks.packetReceived.add(function(packet:Object):Boolean
         {
            if(packet != null && packet.type == NAME_CHANGED && pending != null)
            {
               answered = true;
            }
            return false;
         });
         Hooks.frameStarting.add(function():void
         {
            if(!answered)
            {
               return;
            }
            answered = false;
            var g:Object = game();
            if(g != null && String(g.var_13290) != pending)
            {
               g.var_7572 = g.var_13290;
               PrivateServer.log("name " + pending + " refused by the server; still " + g.var_13290);
            }
            pending = null;
         });
      }

      public static function check(name:String) : String
      {
         if(!/^[A-Za-z0-9_\- ]{3,16}$/.test(name))
         {
            return "3-16 letters, digits, spaces, _ or -";
         }
         if(name != name.replace(/^\s+|\s+$/g,"") || name.indexOf("  ") >= 0)
         {
            return "no spaces at the start or end, and no double spaces";
         }
         if(/^[0-9 ]+$/.test(name))
         {
            return "not only digits";
         }
         return null;
      }

      private static function game() : Object
      {
         try
         {
            return Object(GameApp.mainInstance).var_13259;
         }
         catch(e:Error)
         {
         }
         return null;
      }

      private static function open() : void
      {
         var g:Object = game();
         if(g == null || g.serverConnection == null || !g.serverConnection.isConnected())
         {
            PrivateServer.log("F10: not connected to the private server, no name box");
            return;
         }
         box = new Sprite();
         box.graphics.beginFill(0x0f1115,0.94);
         box.graphics.lineStyle(2,0x4cc2b6);
         box.graphics.drawRoundRect(0,0,460,150,18,18);
         box.graphics.endFill();
         box.addChild(label("Your name in the game",16,20,16,true));
         field = new TextField();
         field.type = TextFieldType.INPUT;
         field.defaultTextFormat = new TextFormat("_sans",20,0xe8ebf1);
         field.background = true;
         field.backgroundColor = 0x1f232c;
         field.border = true;
         field.borderColor = 0x2b313d;
         field.maxChars = 16;
         field.restrict = "A-Za-z0-9_\\- ";
         field.x = 20;
         field.y = 48;
         field.width = 420;
         field.height = 32;
         field.text = String(g.var_7572 || "");
         box.addChild(field);
         note = label("Enter saves, Esc closes. 3-16 letters, digits, spaces, _ or -.",12,20,96,false);
         box.addChild(note);
         var stage:Object = Object(GameApp.mainInstance).stage;
         box.x = int((stage.stageWidth - 460) / 2);
         box.y = int((stage.stageHeight - 150) / 2);
         stage.addChild(box);
         stage.focus = field;
         field.setSelection(0,field.text.length);
      }

      private static function label(text:String, size:int, x:int, y:int, bold:Boolean) : TextField
      {
         var t:TextField = new TextField();
         t.defaultTextFormat = new TextFormat("_sans",size,bold ? 0xe8ebf1 : 0x98a2b3,bold);
         t.text = text;
         t.selectable = false;
         t.x = x;
         t.y = y;
         t.width = 420;
         t.height = 40;
         t.wordWrap = true;
         return t;
      }

      private static function save() : void
      {
         var why:String = change(field.text);
         if(why != null)
         {
            note.text = "Not saved: " + why + ".";
            note.textColor = 0xfbbf24;
            return;
         }
         close();
      }

      public static function current() : String
      {
         var g:Object = game();
         return g != null && g.var_7572 != null ? String(g.var_7572) : "";
      }

      public static function change(name:String) : String
      {
         var why:String = check(name);
         if(why != null)
         {
            return why;
         }
         var g:Object = game();
         try
         {
            var p:NetPacket = new NetPacket(SET_NAME);
            p.writeString(name);
            var sent:Boolean = g != null && g.serverConnection != null && g.sendToServer(p);
            p.method_839();
            if(!sent)
            {
               return "not connected to the private server";
            }
            g.var_7572 = name;
            g.var_13290 = name;
            pending = name;
            PrivateServer.log("name set to " + name);
         }
         catch(e:Error)
         {
            return e.message;
         }
         return null;
      }

      private static function close() : void
      {
         if(box != null && box.parent != null)
         {
            box.parent.removeChild(box);
         }
         box = null;
         field = null;
         note = null;
      }
   }
}
