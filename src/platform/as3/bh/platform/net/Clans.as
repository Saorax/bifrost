package bh.platform.net
{
   import bh.platform.Hooks;
   import flash.display.DisplayObject;
   import flash.display.DisplayObjectContainer;
   import flash.text.TextField;
   import flash.text.TextFormat;
   import flash.text.TextFormatAlign;
   import flash.utils.setTimeout;

   public final class Clans
   {
      public static const CREATE:int = 100;
      public static const HISTORY:int = 11092;

      private static var registered:Boolean = false;

      public function Clans()
      {
      }

      public static function register() : void
      {
         if(registered)
         {
            return;
         }
         registered = true;
         Hooks.packetReceived.add(function(packet:Object):Boolean
         {
            if(packet == null || packet.type != HISTORY)
            {
               return false;
            }
            try
            {
               var lines:Array = [];
               var n:uint = packet.readUint();
               for(var i:int = 0; i < int(Math.min(n,100)); i++)
               {
                  lines.push({"ago":packet.readUint(),"pid":packet.readUint(),"name":packet.readString(),
                     "text":packet.readString(),"officers":packet.method_5885()});
               }
               showHistory(lines,0);
            }
            catch(e:Error)
            {
               PrivateServer.log("clans: chat history unreadable (" + e.message + ")");
            }
            return true;
         });
         Hooks.guildCreatePressed.add(function(screen:Object, button:uint):Boolean
         {
            if(PrivateServer.host == null)
            {
               return false;
            }
            try
            {
               create(screen);
            }
            catch(e:Error)
            {
               PrivateServer.log("clans: create failed (" + e.message + ")");
            }
            return true;
         });
         Hooks.guildCreateShown.add(function(screen:Object):void
         {
            if(PrivateServer.host == null)
            {
               return;
            }
            try
            {
               var gold:Object = screen.var_13537;
               gold.clip.visible = false;
               var idol:Object = screen.var_5631;
               idol.clip.x = gold.clip.x + (902.6 - 656.5) / 2;
               var glass:DisplayObjectContainer = class_51.method_3081(idol.clip,"am_Glass") as DisplayObjectContainer;
               if(glass != null)
               {
                  var icon:DisplayObject = glass.getChildByName("am_Currency_Icon_Idol_49");
                  if(icon != null)
                  {
                     icon.visible = false;
                  }
                  var cost:TextField = glass.getChildByName("am_Cost") as TextField;
                  if(cost != null)
                  {
                     for each(var text:Object in screen.localizedTexts)
                     {
                        if(text.var_2544 == cost)
                        {
                           text.method_1229("UI_Guild_Creation");
                        }
                     }
                     var format:TextFormat = cost.getTextFormat();
                     format.align = TextFormatAlign.CENTER;
                     cost.setTextFormat(format);
                  }
               }
               idol.method_6165();
               gold.method_6165();
            }
            catch(e:Error)
            {
               PrivateServer.log("clans: create screen prices not hidden (" + e.message + ")");
            }
         });
      }

      private static function showHistory(lines:Array, tries:int) : void
      {
         var core:Object = Object(GameApp.mainInstance).var_13259;
         var chat:Object = ScreenManager.var_3257;
         if(core == null || chat == null)
         {
            if(tries < 30)
            {
               setTimeout(function():void
               {
                  showHistory(lines,tries + 1);
               },500);
            }
            else
            {
               PrivateServer.log("clans: chat history not shown (no chat)");
            }
            return;
         }
         if(core.var_5688)
         {
            return;
         }
         var unread:Boolean = chat.var_8801;
         var flagged:Boolean = chat.var_1582;
         var now:Date = new Date();
         var shown:int = 0;
         try
         {
            chat.method_8707("Guild chat history: the last " + lines.length + (lines.length == 1 ? " message" : " messages"));
            for each(var line:Object in lines)
            {
               if(core.method_5635(line.pid))
               {
                  continue;
               }
               var channel:uint = line.officers ? class_59.var_910.var_11005 : class_59.var_8190.var_11005;
               chat.method_8865(channel,line.name,"[" + when(now,uint(line.ago)) + "] " + line.text,
                  line.pid == core.var_14656,line.pid);
               shown++;
            }
         }
         catch(e:Error)
         {
            PrivateServer.log("clans: chat history stopped (" + e.message + ")");
         }
         chat.var_8801 = unread;
         chat.var_1582 = flagged;
         PrivateServer.log("clans: chat history, " + shown + " of " + lines.length + " lines shown");
      }

      private static function when(now:Date, ago:uint) : String
      {
         var at:Date = new Date(now.time - ago * 1000);
         var hm:String = at.hours + ":" + (at.minutes < 10 ? "0" : "") + at.minutes;
         if(at.fullYear == now.fullYear && at.month == now.month && at.date == now.date)
         {
            return hm;
         }
         return ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][at.month] + " " + at.date + " " + hm;
      }

      private static function create(screen:Object) : void
      {
         var field:Object = screen.var_2928;
         var text:String = field.var_2544.text;
         if(text == null || text.length == 0 || text == field.var_13977)
         {
            text = "";
         }
         text = text.replace(/ +/g," ");
         if(text.indexOf(" ") == 0)
         {
            text = text.substr(1);
         }
         if(text.length > 0 && text.lastIndexOf(" ") == text.length - 1)
         {
            text = text.substr(0,text.length - 1);
         }
         if(text.length < 2 || text.length > 20)
         {
            screen.method_3968(28);
            return;
         }
         screen.var_7815.method_397(false);
         var core:Object = Object(GameApp.mainInstance).var_13259;
         var packet:NetPacket = new NetPacket(CREATE);
         packet.method_7572(0);
         packet.writeString(text);
         core.sendToServer(packet);
         packet.method_839();
         PrivateServer.log("clans: asked to create \"" + text + "\"");
      }
   }
}
