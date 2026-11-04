package bh.platform
{
   import bh.platform.net.Friends;
   import bh.platform.net.PrivateServer;
   import flash.display.Sprite;
   import flash.events.Event;
   import flash.events.MouseEvent;
   import flash.text.TextField;
   import flash.text.TextFieldType;
   import flash.text.TextFormat;

   public class FriendsWindow extends BigWindow
   {
      private static const TABS:Array = ["FRIENDS"];
      private static const ASK_EVERY:int = 300;

      private static var window:FriendsWindow;

      private var box:TextField;
      private var typedName:String = "";
      private var armed:String = null;
      private var frames:int = 0;
      private var lastMessage:String = "";
      private var waiting:Boolean = true;
      private var pending:Boolean = false;
      private var firstRight:int = 0;
      private var lastLeft:int = 0;
      private var lastRight:int = -1;

      public function FriendsWindow(core:GameCore)
      {
         super(core);
      }

      public static function open() : void
      {
         if(window == null || ScreenManager.allScreens.indexOf(window) < 0)
         {
            window = new FriendsWindow(ScreenManager.owner);
            ScreenManager.registerScreen(window);
            if(ScreenManager.var_14744 != null)
            {
               window.registrationIndex = ScreenManager.var_14744.registrationIndex;
            }
         }
         if(!window.isActive)
         {
            window.armed = null;
            window.lastLeft = 0;
            window.lastRight = -1;
            window.lastMessage = "";
            window.waiting = Friends.state == null;
            window.Display();
         }
         Friends.stateArrived = function():void
         {
            if(window != null && window.isActive)
            {
               window.arrived();
            }
         };
         Friends.command("list");
      }

      public static function get shown() : FriendsWindow
      {
         return window != null && window.isActive ? window : null;
      }

      override protected function get title() : String
      {
         return "FRIENDS";
      }

      override protected function get tabNames() : Array
      {
         return TABS;
      }

      override protected function get confirmLabel() : String
      {
         return "DONE";
      }

      override protected function statusText() : String
      {
         var st:Object = Friends.state;
         if(PrivateServer.host == null)
         {
            return "Offline: friends live on the project's server.";
         }
         if(lastMessage != "")
         {
            return lastMessage;
         }
         if(st == null)
         {
            return "Asking the server...";
         }
         if(!st.signed_in)
         {
            return "Sign in with Discord (Options > Account) to have friends.";
         }
         return "Your Discord user ID: " + st.me;
      }

      override protected function back() : void
      {
         if(window === this)
         {
            Friends.stateArrived = null;
         }
         Hide();
      }

      override protected function everyFrame() : void
      {
         if(typing())
         {
            return;
         }
         if(pending)
         {
            pending = false;
            build();
         }
         if(++frames >= ASK_EVERY)
         {
            frames = 0;
            Friends.command("list");
         }
      }

      private function arrived() : void
      {
         var st:Object = Friends.state;
         if(st != null && st.message != null && st.message != "")
         {
            lastMessage = st.message;
         }
         else if(st != null && lastMessage.indexOf("Friend request sent to ") == 0)
         {
            for each(var f:Object in st.friends)
            {
               if(lastMessage == "Friend request sent to " + f.name + ".")
               {
                  lastMessage = "You and " + f.name + " are now friends.";
               }
            }
         }
         var first:Boolean = waiting;
         waiting = false;
         if(typing())
         {
            pending = true;
            return;
         }
         build();
         if(first)
         {
            focus = 0;
            paintFocus();
         }
      }

      public function typing() : Boolean
      {
         return boxHasKeys() || keyboardOpen;
      }

      public function boxHasKeys() : Boolean
      {
         return box != null && box.stage != null && box.stage.focus === box;
      }

      override protected function get fullPage() : Boolean
      {
         return true;
      }

      private function get LEFT_W() : Number
      {
         return Math.round(area.width * 0.55);
      }

      private function get RIGHT_X() : Number
      {
         return area.x + LEFT_W + 16;
      }

      private function get RIGHT_W() : Number
      {
         return area.width - LEFT_W - 16;
      }

      override protected function blockInput() : Boolean
      {
         return typing();
      }

      override protected function buildTab(i:int) : void
      {
         var st:Object = Friends.state;
         var left:Sprite = panel(area.x,area.y,LEFT_W,area.height);
         var right:Sprite = panel(RIGHT_X,area.y,RIGHT_W,area.height);
         var friends:Array = st != null && st.friends != null ? st.friends : [];
         var online:int = 0;
         for each(var f:Object in friends)
         {
            online += f.online ? 1 : 0;
         }
         UiKit.text(left,"YOUR FRIENDS" + (friends.length > 0 ? "  ·  " + online + " ONLINE" : ""),14,10,14,UiKit.GREY,UiKit.XBOLD);
         if(st != null && st.everyone)
         {
            UiKit.text(left,"On this server everyone is your friend (server setting).",14,32,12,UiKit.GREY,UiKit.MEDIUM);
         }
         var y0:Number = st != null && st.everyone ? 54 : 36;
         var half:Number = Math.round(area.height / 2);
         var list:Sprite = scroller(left,0,y0,LEFT_W,half - y0 - 6);
         var y:Number = 0;
         if(friends.length == 0)
         {
            UiKit.text(list,waiting ? "Asking the server..." : "No friends yet. Add one on the right: a Discord name, a player " +
               "name or a Discord user ID. Friends show in the social hub's Friends tab, where Join, Spectate and " +
               "Invite work.",14,4,13,UiKit.LIGHT,UiKit.MEDIUM,LEFT_W - 40);
         }
         for each(f in friends)
         {
            friendRow(list,y,f);
            y += 40;
         }
         var recent:Array = st != null && st.recent != null ? st.recent : [];
         online = 0;
         for each(f in recent)
         {
            online += f.online ? 1 : 0;
         }
         UiKit.rect(left,14,half - 2,LEFT_W - 28,1,UiKit.LINE);
         UiKit.text(left,"PLAYED WITH RECENTLY" + (recent.length > 0 ? "  ·  " + online + " ONLINE" : ""),14,half + 8,14,
            UiKit.GREY,UiKit.XBOLD);
         var lower:Sprite = scroller(left,0,half + 34,LEFT_W,area.height - half - 40);
         if(recent.length == 0)
         {
            UiKit.text(lower,waiting ? "" : "Nobody yet: the players of your matches of the last 30 days show here, with " +
               "what they're doing now.",14,4,13,UiKit.LIGHT,UiKit.MEDIUM,LEFT_W - 40);
         }
         y = 0;
         for each(f in recent)
         {
            recentRow(lower,y,f);
            y += 40;
         }
         firstRight = items.length;
         buildAdd(right);
         var side:Sprite = scroller(right,0,112,RIGHT_W,area.height - 118);
         y = 0;
         y = section(side,y,"REQUESTS TO YOU",st != null ? st.incoming : null,"incoming");
         y = section(side,y,"WAITING FOR AN ANSWER",st != null ? st.outgoing : null,"outgoing");
         y = section(side,y,"ON THE SERVER NOW",st != null ? st.online : null,"online");
         if(y == 0)
         {
            UiKit.text(side,waiting ? "" : "No requests, and nobody else is signed in right now.",14,4,13,UiKit.GREY,
               UiKit.MEDIUM,RIGHT_W - 30);
         }
      }

      private function buildAdd(right:Sprite) : void
      {
         UiKit.text(right,"ADD A FRIEND",14,10,14,UiKit.GREY,UiKit.XBOLD);
         var holder:Sprite = new Sprite();
         right.addChild(holder);
         var bx:Number = 14;
         var by:Number = 36;
         var bw:Number = RIGHT_W - 130;
         UiKit.rect(holder,bx,by,bw,28,UiKit.WHITE,4);
         box = new TextField();
         box.type = TextFieldType.INPUT;
         box.defaultTextFormat = new TextFormat("_sans",15,UiKit.NAVY_TEXT);
         box.x = bx + 6;
         box.y = by + 3;
         box.width = bw - 12;
         box.height = 24;
         box.maxChars = 40;
         box.text = typedName;
         holder.addChild(box);
         var hint:TextField = UiKit.text(holder,"Discord name, player name or ID",bx + 8,by + 5,13,UiKit.GREY,UiKit.MEDIUM);
         hint.visible = box.text.length == 0;
         box.addEventListener(Event.CHANGE,function(e:Event):void
         {
            typedName = box.text;
            hint.visible = box.text.length == 0;
         });
         box.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            e.stopPropagation();
            if(box.stage != null)
            {
               box.stage.focus = box;
            }
         });
         box.addEventListener("keyDown",function(e:Object):void
         {
            if(e.keyCode == 13)
            {
               e.stopPropagation();
               box.stage.focus = null;
               add();
            }
            else if(e.keyCode == 27)
            {
               e.stopPropagation();
               e.preventDefault();
               box.stage.focus = null;
            }
         });
         items.push({"w":"box","sprite":holder,"parent":right,"width":bw,"height":28,"focusBox":[bx - 8,by,bw,28],
            "use":function():void
            {
               typeText("FRIEND'S NAME OR ID",typedName,40,function(v:String):void
               {
                  typedName = v;
                  add();
               });
            }});
         var b:Sprite = button(right,"ADD",RIGHT_W - 108,by - 1,94,add,30,14);
         items.push({"w":"add","sprite":b,"parent":right,"width":94,"height":30,"use":add});
         UiKit.text(right,"They get your request as an invite in the game (and on the sign-in page); once they accept, " +
            "you're friends.",14,72,11,UiKit.GREY,UiKit.MEDIUM,RIGHT_W - 28);
      }

      private function add() : void
      {
         var who:String = typedName.replace(/^\s+|\s+$/g,"");
         if(who == "")
         {
            lastMessage = "Type a Discord name, a player name or a Discord user ID first.";
            build();
            return;
         }
         Friends.command("add",who);
         typedName = "";
         lastMessage = "Sending...";
         build();
      }

      private function friendRow(list:Sprite, y:Number, f:Object) : void
      {
         var r:Sprite = new Sprite();
         r.y = y;
         list.addChild(r);
         var w:Number = LEFT_W - 20;
         UiKit.rect(r,10,0,w,36,UiKit.BODY,4);
         var dot:Sprite = new Sprite();
         dot.graphics.beginFill(f.online ? UiKit.TEAL : UiKit.DIM);
         dot.graphics.drawCircle(26,18,5);
         dot.graphics.endFill();
         r.addChild(dot);
         UiKit.fit(UiKit.text(r,String(f.name),40,4,15,f.online ? UiKit.WHITE : UiKit.LIGHT,UiKit.BOLD),250);
         UiKit.fit(UiKit.text(r,String(f.status).toUpperCase(),300,8,12,f.online ? UiKit.TEAL : UiKit.GREY,UiKit.XBOLD),170);
         var it:Object = {"w":"friend " + f.id,"sprite":r,"parent":list,"width":w,"height":36,"focusBox":[10,0,w,36]};
         if(f.removable)
         {
            var armedHere:Boolean = armed == f.id;
            var b:Sprite = button(r,armedHere ? "SURE?" : "REMOVE",w - 96,4,96,remover(f),28,12);
            b.alpha = armedHere ? 1 : 0.75;
            it.option = remover(f);
         }
         it.use = friendMenu(f);
         it.rightUse = it.use;
         r.addEventListener(MouseEvent.CLICK,function(e:MouseEvent):void
         {
            it.use();
         });
         items.push(it);
      }

      private function recentRow(list:Sprite, y:Number, p:Object) : void
      {
         var r:Sprite = new Sprite();
         r.y = y;
         list.addChild(r);
         var w:Number = LEFT_W - 20;
         UiKit.rect(r,10,0,w,36,UiKit.BODY,4);
         var dot:Sprite = new Sprite();
         dot.graphics.beginFill(p.online ? UiKit.TEAL : UiKit.DIM);
         dot.graphics.drawCircle(26,18,5);
         dot.graphics.endFill();
         r.addChild(dot);
         UiKit.fit(UiKit.text(r,String(p.name),40,7,15,p.online ? UiKit.WHITE : UiKit.LIGHT,UiKit.BOLD),250);
         UiKit.fit(UiKit.text(r,String(p.status).toUpperCase(),300,3,12,p.online ? UiKit.TEAL : UiKit.GREY,UiKit.XBOLD),w - 410);
         UiKit.fit(UiKit.text(r,(p.teammate ? "TEAMMATE" : "OPPONENT") + "  ·  " + agoText(Number(p.ago)),300,19,10,UiKit.GREY,
            UiKit.MEDIUM),w - 410);
         button(r,"ADD",w - 96,4,96,act("add",p),28,12);
         var it:Object = {"w":"recent " + p.id,"sprite":r,"parent":list,"width":w,"height":36,"focusBox":[10,0,w,36],
            "use":act("add",p),"player":{"pid":uint(p.pid),"id":String(p.id),"name":String(p.name)}};
         items.push(it);
      }

      public static function agoText(s:Number) : String
      {
         if(isNaN(s) || s < 3600)
         {
            return Math.max(1,Math.floor((isNaN(s) ? 0 : s) / 60)) + " MIN AGO";
         }
         if(s < 86400)
         {
            return Math.floor(s / 3600) + " H AGO";
         }
         var d:int = Math.floor(s / 86400);
         return d + (d == 1 ? " DAY AGO" : " DAYS AGO");
      }

      private function friendMenu(f:Object) : Function
      {
         return function():void
         {
            try
            {
               var tab:Object = ScreenManager.var_1534;
               var at:int = -1;
               if(tab != null && tab.isActive && uint(f.pid) != 0)
               {
                  tab.method_1964();
                  var list:Object = tab.owner.var_2825;
                  for(var i:int = 0; i < int(list.length); i++)
                  {
                     if(uint(list[i].var_14656) == uint(f.pid))
                     {
                        at = i;
                        break;
                     }
                  }
               }
               if(at < 0)
               {
                  lastMessage = f.name + " isn't on the social hub's Friends tab yet; try again in a moment.";
                  build();
                  return;
               }
               var per:uint = uint(tab.var_12235);
               tab.var_7257 = uint(at / per);
               tab.method_1964();
               back();
               tab.var_12346 = uint(at % per);
               tab.var_243 = true;
               tab.method_6666(false);
               tab.method_3789();
            }
            catch(e:Error)
            {
               lastMessage = "The game's menu for " + f.name + " didn't open (" + e.message + ").";
               build();
            }
         };
      }

      private function remover(f:Object) : Function
      {
         return function():void
         {
            if(armed != f.id)
            {
               armed = f.id;
               lastMessage = "Press REMOVE again to end the friendship with " + f.name + ".";
               build();
               return;
            }
            armed = null;
            Friends.command("remove",f.id);
            if(uint(f.pid) != 0)
            {
               Friends.dropRow(uint(f.pid));
            }
         };
      }

      private function section(side:Sprite, y:Number, title:String, list:Array, kind:String) : Number
      {
         if(list == null || list.length == 0)
         {
            return y;
         }
         UiKit.text(side,title,14,y + 4,12,UiKit.GREY,UiKit.XBOLD);
         y += 26;
         for each(var p:Object in list)
         {
            var r:Sprite = new Sprite();
            r.y = y;
            side.addChild(r);
            var w:Number = RIGHT_W - 28;
            UiKit.rect(r,10,0,w,32,UiKit.BODY,4);
            UiKit.fit(UiKit.text(r,String(p.name),20,5,14,UiKit.WHITE,UiKit.BOLD),kind == "incoming" ? 170 : 250);
            var it:Object = {"w":kind + " " + p.id,"sprite":r,"parent":side,"width":w,"height":32,"focusBox":[10,0,w,32],
               "player":{"pid":uint(p.pid),"id":String(p.id),"name":String(p.name)}};
            if(kind == "incoming")
            {
               button(r,"ACCEPT",w - 186,3,90,act("accept",p),26,12);
               button(r,"DECLINE",w - 90,3,86,act("decline",p),26,12);
               it.use = act("accept",p);
               it.option = act("decline",p);
               it.menu = entryList("DECLINE FRIEND REQUEST",act("decline",p));
            }
            else if(kind == "outgoing")
            {
               button(r,"CANCEL",w - 90,3,86,act("cancel",p),26,12);
               it.option = act("cancel",p);
               it.menu = entryList("CANCEL FRIEND REQUEST",act("cancel",p));
            }
            else
            {
               button(r,"ADD",w - 90,3,86,act("add",p),26,12);
               it.use = act("add",p);
            }
            items.push(it);
            y += 36;
         }
         return y + 6;
      }

      private static function entryList(label:String, run:Function) : Function
      {
         return function():Array
         {
            return [[label,run]];
         };
      }

      private function act(action:String, p:Object) : Function
      {
         return function():void
         {
            Friends.command(action,p.id);
            lastMessage = "Sending...";
            build();
         };
      }

      override protected function hintText() : String
      {
         return Prompts.KEYS.select + " SELECT     " + Prompts.KEYS.option + " REMOVE / DECLINE / CANCEL / MENU     " +
            Prompts.KEYS.back + " CLOSE";
      }

      override protected function useItem(it:Object, dir:int) : void
      {
         if(dir == 0 || it.change != null)
         {
            super.useItem(it,dir);
            return;
         }
         var to:int = -1;
         if(focus == firstRight || focus == firstRight + 1)
         {
            to = focus + dir;
            if(to == firstRight - 1)
            {
               to = firstRight > 0 ? Math.min(lastLeft,firstRight - 1) : -1;
            }
            else if(to == firstRight + 2)
            {
               to = -1;
            }
         }
         else if(focus < firstRight && dir > 0)
         {
            lastLeft = focus;
            to = lastRight >= firstRight && lastRight < items.length ? lastRight : firstRight;
         }
         else if(focus > firstRight + 1 && dir < 0 && firstRight > 0)
         {
            lastRight = focus;
            to = Math.min(lastLeft,firstRight - 1);
         }
         if(to >= 0 && to < items.length)
         {
            focus = to;
            paintFocus();
         }
      }

      override protected function focused(it:Object) : void
      {
         if(armed != null && it.option == null)
         {
            armed = null;
         }
      }

   }
}
