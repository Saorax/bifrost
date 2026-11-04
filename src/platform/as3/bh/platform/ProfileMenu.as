package bh.platform
{
   import flash.utils.Dictionary;

   public final class ProfileMenu
   {
      public function ProfileMenu()
      {
      }

      public static function addEntry(menu:Object) : void
      {
         try
         {
            menu.var_12457.method_5926(class_64.var_1636[12],"",menu.method_7819(12),false);
         }
         catch(e:Error)
         {
            Platform.log("profile: no View Profile entry in the player menu (" + e.message + ")");
         }
      }

      public static function friendEntry(screen:Object, friend:Object) : void
      {
         var id:uint = uint(friend.var_14656);
         var name:String = String(friend.var_14792 || "");
         screen.var_12457.method_5926(class_64.var_1636[12],"",function(_:Boolean):void
         {
            ProfileWindow.open(id,name);
         },false);
      }

      public static function lobbyEntry(tab:Object) : void
      {
         try
         {
            var list:Object = tab.owner.var_6244.var_7930;
            var at:uint = uint(tab.var_7195 + class_209.method_2130(tab.var_7257,tab.var_11385));
            if(at >= uint(list.length))
            {
               return;
            }
            var member:Object = list[at];
            var id:uint = uint(member.var_14656);
            if(id == 0)
            {
               return;
            }
            var name:String = member.var_6307 != null ? String(member.var_6307.var_14792 || "") : "";
            tab.var_12457.method_5926(class_64.var_1636[12],"",function(_:Boolean):void
            {
               ProfileWindow.open(id,name);
            },false);
         }
         catch(e:Error)
         {
            Platform.log("profile: no View Profile entry in the lobby menu (" + e.message + ")");
         }
      }

      private static var podiumViews:Dictionary = new Dictionary(true);

      public static function podiumEntries(board:Object) : void
      {
         try
         {
            if(board.var_9597 == null || board.var_5240 == null)
            {
               return;
            }
            for(var s:int = 0; s < int(board.var_9597.length); s++)
            {
               var entry:Object = board.method_162(board.var_9597[s]);
               var menu:Object = board.var_5240[s];
               if(entry == null || menu == null || menu.var_9906 == null || uint(entry.var_14656) == 0)
               {
                  continue;
               }
               var used:int = 0;
               var have:Boolean = false;
               for(var k:int = 0; k < int(menu.var_9906.length); k++)
               {
                  if(menu.var_9906[k] != null)
                  {
                     used++;
                     have = have || menu.var_9906[k] === podiumViews[menu];
                  }
               }
               if(have || used >= int(menu.var_9906.length))
               {
                  continue;
               }
               var view:Function = podiumView(uint(entry.var_14656),entry.var_6307 != null ?
                  String(entry.var_6307.var_14792 || "") : "");
               podiumViews[menu] = view;
               menu.method_5926(class_64.var_1636[12],"a_PodiumMenuIcon_Friends","UI_Icons",used,view);
               menu.method_8229();
            }
         }
         catch(e:Error)
         {
            Platform.log("profile: no View Profile entry in the podium menus (" + e.message + ")");
         }
      }

      public static function menuLabels(screen:Object) : String
      {
         try
         {
            return screen.var_12457.var_2448.join(" | ");
         }
         catch(e:Error)
         {
            return "unreadable (" + e.message + ")";
         }
         return "";
      }

      private static function podiumView(id:uint, name:String) : Function
      {
         return function(... _):void
         {
            ProfileWindow.open(id,name);
         };
      }

      public static function view(menu:Object) : void
      {
         try
         {
            var who:Object = menu.method_3250();
            if(who != null && uint(who.var_14656) != 0)
            {
               ProfileWindow.open(uint(who.var_14656));
            }
         }
         catch(e:Error)
         {
            Platform.log("profile: View Profile failed (" + e.message + ")");
         }
      }
   }
}
