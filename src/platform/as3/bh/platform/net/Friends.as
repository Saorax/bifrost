package bh.platform.net
{
   import bh.platform.ProfileMenu;
   import bh.platform.Busy;
   import bh.platform.FriendsWindow;
   import bh.platform.Hooks;
   import bh.platform.Prompts;
   import bh.platform.UiKit;
   import flash.display.Sprite;
   import flash.events.MouseEvent;
   import flash.text.TextField;

   public final class Friends
   {
      public static const FRIEND_ADD:int = 11050;
      public static const FRIEND_REMOVE:int = 11051;
      public static const WINDOW_COMMAND:int = 11052;
      public static const WINDOW_STATE:int = 11053;
      private static const BUSY:String = "friends";

      public static var state:Object = null;

      public static var stateArrived:Function = null;

      private static var tabPrompt:Sprite;

      private static var registered:Boolean = false;

      public function Friends()
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
         Hooks.friendsTabInput.add(function(screen:Object, input:int):Boolean
         {
            if(PrivateServer.host == null || input != 21 || !screen.isActive)
            {
               return false;
            }
            FriendsWindow.open();
            return true;
         });
         Hooks.friendsTabRefreshed.add(showTabPrompt);
         Hooks.keyDown.add(function(event:Object):Boolean
         {
            var w:FriendsWindow = FriendsWindow.shown;
            return w != null && w.boxHasKeys();
         });
         Hooks.addFriendPressed.add(function(screen:Object):Boolean
         {
            if(PrivateServer.host == null)
            {
               return false;
            }
            try
            {
               var member:Object = screen.method_8614();
               if(member != null)
               {
                  send(FRIEND_ADD,uint(member.var_14656));
               }
            }
            catch(e:Error)
            {
               PrivateServer.log("friends: add friend failed (" + e.message + ")");
            }
            return true;
         });
         Hooks.podiumAddFriendPressed.add(function(screen:Object, podium:int):Boolean
         {
            if(PrivateServer.host == null)
            {
               return false;
            }
            try
            {
               var ids:Object = screen.var_9597;
               var member:Object = ids != null && podium < int(ids.length) && uint(ids[podium]) != 0 ? screen.method_162(uint(ids[podium])) : null;
               if(member != null)
               {
                  send(FRIEND_ADD,uint(member.var_14656));
               }
            }
            catch(e:Error)
            {
               PrivateServer.log("friends: add friend (podium) failed (" + e.message + ")");
            }
            return true;
         });
         Hooks.guildMemberMenuBuilt.add(function(screen:Object, member:Object):void
         {
            if(PrivateServer.host == null || member == null)
            {
               return;
            }
            try
            {
               var core:Object = Object(GameApp.mainInstance).var_13259;
               var id:uint = uint(member.var_14656);
               var steam:String = member.var_7572;
               var gameOffers:Boolean = steam != null && steam != "" && steam != "0" && uint(member.var_1895) == 1 &&
                  uint(core.var_15161) == 1;
               if(id == 0 || id == uint(core.var_14656) || core.var_13870.h[id] != null || gameOffers)
               {
                  return;
               }
               screen.var_12457.method_5926(class_64.var_1636[4],"",screen.method_7819(4),false);
            }
            catch(e:Error)
            {
               PrivateServer.log("friends: guild menu entry failed (" + e.message + ")");
            }
         });
         Hooks.guildAddFriendPressed.add(function(screen:Object):Boolean
         {
            if(PrivateServer.host == null)
            {
               return false;
            }
            try
            {
               var member:Object = screen.method_3250();
               if(member != null)
               {
                  send(FRIEND_ADD,uint(member.var_14656));
               }
            }
            catch(e:Error)
            {
               PrivateServer.log("friends: add friend (guild) failed (" + e.message + ")");
            }
            return true;
         });
         Hooks.friendsMenuBuilt.add(function(screen:Object):void
         {
            if(PrivateServer.host == null)
            {
               return;
            }
            try
            {
               var friend:Object = screen.var_8915;
               if(friend == null)
               {
                  return;
               }
               ProfileMenu.friendEntry(screen,friend);
               screen.var_12457.method_5926("Remove Friend","",function(_:Boolean):void
               {
                  remove(screen,friend);
               },false,true,false);
            }
            catch(e:Error)
            {
               PrivateServer.log("friends: menu entry failed (" + e.message + ")");
            }
         });
      }

      public static var answered:Function = null;

      public static function command(action:String, who:String = "", then:Function = null) : void
      {
         answered = then;
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var packet:NetPacket = new NetPacket(WINDOW_COMMAND);
            packet.writeString(action);
            packet.writeString(who != null ? who : "");
            if(core.sendToServer(packet))
            {
               Busy.start(BUSY,action == "list" ? "LOADING FRIENDS" : "SENDING TO THE SERVER");
            }
            packet.method_839();
            if(action != "list")
            {
               PrivateServer.log("friends: window " + action + " " + who);
            }
         }
         catch(e:Error)
         {
            PrivateServer.log("friends: window " + action + " failed (" + e.message + ")");
         }
      }

      private static function onPacket(packet:Object) : Boolean
      {
         if(packet == null || packet.type != WINDOW_STATE)
         {
            return false;
         }
         Busy.done(BUSY);
         try
         {
            state = JSON.parse(packet.readString());
            if(stateArrived != null)
            {
               stateArrived();
            }
            var once:Function = answered;
            answered = null;
            if(once != null)
            {
               once(state.ok != false,String(state.message || ""));
            }
         }
         catch(e:Error)
         {
            PrivateServer.log("friends: bad window state (" + e.message + ")");
         }
         return true;
      }

      public static function dropRow(pid:uint) : void
      {
         try
         {
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var row:Object = core.var_13870.h[pid];
            if(row == null)
            {
               return;
            }
            var list:Object = core.var_2825;
            var at:int = int(list.indexOf(row));
            if(at >= 0)
            {
               list.splice(at,1);
            }
            core.var_13870.remove(pid);
            var tab:Object = ScreenManager.var_1534;
            if(tab != null)
            {
               if(tab.var_8915 === row)
               {
                  tab.var_8915 = null;
               }
               tab.var_243 = true;
            }
         }
         catch(e:Error)
         {
            PrivateServer.log("friends: row " + pid + " not dropped (" + e.message + ")");
         }
      }

      private static function showTabPrompt(screen:Object) : void
      {
         try
         {
            var panel:Object = screen.panelClip;
            var show:Boolean = PrivateServer.host != null && !screen.owner.var_12613 && !screen.owner.var_5582;
            if(tabPrompt == null)
            {
               if(!show || panel == null)
               {
                  return;
               }
               tabPrompt = new Sprite();
               tabPrompt.buttonMode = true;
               var bar:Sprite = new Sprite();
               tabPrompt.addChild(bar);
               Prompts.fill(screen as ScreenBase,bar,Prompts.KEYS.option + " FIND FRIENDS",20,13,UiKit.WHITE);
               tabPrompt.graphics.beginFill(0,0);
               tabPrompt.graphics.drawRect(-4,-4,Math.max(bar.width,120) + 8,28);
               tabPrompt.graphics.endFill();
               tabPrompt.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
               {
                  e.stopPropagation();
                  FriendsWindow.open();
               });
            }
            var header:Object = screen.var_2459 != null ? screen.var_2459.clip : null;
            var title:Object = header != null ? header["am_Header"] : null;
            var into:Object = title != null ? title.parent : panel;
            if(into != null && tabPrompt.parent !== into)
            {
               into.addChild(tabPrompt);
            }
            if(title != null)
            {
               var tw:Number = title is TextField ? Math.min(TextField(title).textWidth + 8,title.width) : title.width;
               tabPrompt.x = title.x + tw + 24 + PROMPT_X;
               tabPrompt.y = title.y + (title.height - 20) / 2 + PROMPT_Y;
            }
            else
            {
               tabPrompt.x = PROMPT_X;
               tabPrompt.y = PROMPT_Y;
            }
            tabPrompt.visible = show;
         }
         catch(e:Error)
         {
            PrivateServer.log("friends: tab prompt failed (" + e.message + ")");
         }
      }

      public static var PROMPT_X:Number = 0;
      public static var PROMPT_Y:Number = 0;

      private static function remove(screen:Object, friend:Object) : void
      {
         try
         {
            var id:uint = uint(friend.var_14656);
            send(FRIEND_REMOVE,id);
            var core:Object = Object(GameApp.mainInstance).var_13259;
            var list:Object = core.var_2825;
            var at:int = int(list.indexOf(friend));
            if(at >= 0)
            {
               list.splice(at,1);
            }
            core.var_13870.remove(id);
            screen.var_8915 = null;
            screen.var_12457.Hide(false);
            screen.var_243 = true;
         }
         catch(e:Error)
         {
            PrivateServer.log("friends: remove failed (" + e.message + ")");
         }
      }

      public static function send(type:int, id:uint) : void
      {
         var core:Object = Object(GameApp.mainInstance).var_13259;
         var packet:NetPacket = new NetPacket(type);
         packet.writeUint(id);
         core.sendToServer(packet);
         packet.method_839();
         PrivateServer.log("friends: " + (type == FRIEND_ADD ? "asked to be friends with" : "asked to end the friendship with") +
            " player " + id);
      }
   }
}
