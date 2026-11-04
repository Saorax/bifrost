package bh.platform
{
   import flash.display.Sprite;

   public class ModerationWindow extends BigWindow
   {
      private static const ROWS:int = 8;
      private static const PLAYER_ACTIONS:Array = [["MUTE 1 HOUR","mute",60],["MUTE 1 DAY","mute",1440],["UNMUTE","unmute",0],
         ["BAN 1 DAY","ban",1440],["BAN 7 DAYS","ban",10080],["BAN FOR GOOD","ban",0],["UNBAN","unban",0],
         ["RESET 1V1 RATING","resetrating",0,"1v1"],["RESET EVERY RATING","resetrating",0,""]];
      private static const REPORT_ACTIONS:Array = [["MUTE 1 HOUR","mute",60],["MUTE 1 DAY","mute",1440],
         ["BAN 1 DAY","ban",1440],["BAN 7 DAYS","ban",10080],["BAN FOR GOOD","ban",0],["DISMISS","dismiss",0]];

      private static var window:ModerationWindow;

      private var reportRows:Array = [];
      private var found:Array = [];
      private var notes:Array = [];
      private var searched:String = "";
      private var line:String = "";

      public function ModerationWindow(core:GameCore)
      {
         super(core);
      }

      public static function open() : void
      {
         if(window == null || ScreenManager.allScreens.indexOf(window) < 0)
         {
            window = new ModerationWindow(ScreenManager.owner);
            ScreenManager.registerScreen(window);
            if(ScreenManager.var_14744 != null)
            {
               window.registrationIndex = ScreenManager.var_14744.registrationIndex;
            }
         }
         if(!window.isActive)
         {
            window.Display();
            window.refresh();
         }
      }

      public static function get shown() : ModerationWindow
      {
         return window != null && window.isActive ? window : null;
      }

      override protected function get title() : String
      {
         return "MODERATION";
      }

      override protected function get tabNames() : Array
      {
         return ["REPORTS","PLAYERS","ANNOUNCE"];
      }

      override protected function statusText() : String
      {
         return line != "" ? line : "SERVER ADMIN";
      }

      public function refresh() : void
      {
         Moderation.ask("reports",{},function(a:Object):void
         {
            reportRows = (a.reports as Array) || [];
            redraw();
         });
         Moderation.ask("announcements",{},function(a:Object):void
         {
            notes = (a.announcements as Array) || [];
            redraw();
         });
      }

      private function redraw() : void
      {
         if(isActive)
         {
            build();
         }
      }

      private function act(action:String, args:Object) : void
      {
         var why:String = Moderation.ask(action,args,function(a:Object):void
         {
            line = String(a.message || (a.ok ? "Done." : "Not done.")).toUpperCase();
            if(action == "dismiss" || action == "ban" || action == "mute")
            {
               refresh();
            }
            if(action == "announce" || action == "unannounce")
            {
               refresh();
            }
            if(searched != "" && action != "announce" && action != "unannounce")
            {
               find(searched);
            }
            redraw();
         });
         if(why != null)
         {
            line = why.toUpperCase();
            redraw();
         }
      }

      private function find(name:String) : void
      {
         searched = name;
         Moderation.ask("find",{"name":name},function(a:Object):void
         {
            found = (a.players as Array) || [];
            line = found.length == 0 ? "NOBODY NAMED " + name.toUpperCase() : found.length + " FOUND";
            redraw();
         });
      }

      override protected function buildTab(i:int) : void
      {
         var p:Sprite = panel(area.x,area.y,area.width,area.height);
         var w:Number = area.width - 40;
         var y:Number = 16;
         if(i == 0)
         {
            if(reportRows.length == 0)
            {
               UiKit.text(p,"No open reports. Players report others from the game's own Report Player.",20,y,15,UiKit.LIGHT,
                  UiKit.MEDIUM);
            }
            for each(var r:Object in reportRows.slice(0,ROWS))
            {
               rowButton(p,String(r.reporter) + "  >  " + String(r.target) + ":  " + (r.text || "(no reason)"),y,w,
                  reportUser(r));
               y += 44;
            }
            return;
         }
         if(i == 1)
         {
            var findAct:Function = function():void
            {
               typeText("FIND A PLAYER",searched,32,function(v:String):void
               {
                  v = v.replace(/^\s+|\s+$/g,"");
                  if(v != "")
                  {
                     find(v);
                  }
               });
            };
            var fb:Sprite = button(p,"FIND A PLAYER",20,y,220,findAct);
            items.push({"sprite":fb,"parent":p,"width":220,"height":30,"use":findAct});
            y += 48;
            for each(var f:Object in found.slice(0,ROWS))
            {
               var tags:Array = [f.online ? "SIGNED IN" : "OFFLINE", f.account ? "DISCORD" : "GUEST"];
               if(f.muted)
               {
                  tags.push("MUTED");
               }
               if(f.banned)
               {
                  tags.push("BANNED");
               }
               rowButton(p,String(f.name) + "    " + tags.join("  ·  "),y,w,playerUser(f));
               y += 44;
            }
            return;
         }
         var newAct:Function = function():void
         {
            typeText("NEW ANNOUNCEMENT","",200,function(v:String):void
            {
               v = v.replace(/^\s+|\s+$/g,"");
               if(v != "")
               {
                  act("announce",{"text":v});
               }
            },true);
         };
         var nb:Sprite = button(p,"NEW ANNOUNCEMENT",20,y,260,newAct);
         items.push({"sprite":nb,"parent":p,"width":260,"height":30,"use":newAct});
         UiKit.text(p,"Shown in every game's notification list now and at each sign-in, until removed.",300,y + 6,13,
            UiKit.GREY,UiKit.MEDIUM);
         y += 48;
         for each(var n:Object in notes.slice(0,ROWS))
         {
            rowButton(p,"#" + n.id + "  " + String(n.text),y,w,noteUser(n));
            y += 44;
         }
      }

      private function rowButton(p:Sprite, text:String, y:Number, w:Number, onUse:Function) : void
      {
         var s:Sprite = new Sprite();
         s.x = 20;
         s.y = y;
         s.buttonMode = true;
         p.addChild(s);
         UiKit.rect(s,0,0,w,38,UiKit.BODY,6);
         UiKit.fit(UiKit.text(s,text,14,9,15,UiKit.WHITE,UiKit.BOLD),w - 28);
         s.addEventListener("click",function(e:Object):void
         {
            onUse();
         });
         items.push({"sprite":s,"parent":p,"width":w,"height":38,"use":onUse});
      }

      private function reportUser(r:Object) : Function
      {
         return function():void
         {
            pickFrom(String(r.target).toUpperCase(),labels(REPORT_ACTIONS),0,function(k:int):void
            {
               var a:Array = REPORT_ACTIONS[k];
               if(a[1] == "dismiss")
               {
                  act("dismiss",{"id":r.id});
               }
               else
               {
                  act(a[1],{"key":r.key,"minutes":a[2],"reason":String(r.text || "reported")});
               }
            });
         };
      }

      private function playerUser(f:Object) : Function
      {
         return function():void
         {
            pickFrom(String(f.name).toUpperCase(),labels(PLAYER_ACTIONS),0,function(k:int):void
            {
               var a:Array = PLAYER_ACTIONS[k];
               act(a[1],{"key":f.key,"minutes":a[2],"ladder":a.length > 3 ? a[3] : ""});
            });
         };
      }

      private function noteUser(n:Object) : Function
      {
         return function():void
         {
            pickFrom("ANNOUNCEMENT #" + n.id,["REMOVE IT"],0,function(k:int):void
            {
               act("unannounce",{"id":n.id});
            });
         };
      }

      private static function labels(actions:Array) : Array
      {
         var out:Array = [];
         for each(var a:Array in actions)
         {
            out.push(a[0]);
         }
         return out;
      }

   }
}
