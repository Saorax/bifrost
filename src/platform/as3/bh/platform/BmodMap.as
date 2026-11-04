package bh.platform
{
   public final class BmodMap
   {
      public var keys:Array = [];

      private var values:Object = {};

      public function BmodMap()
      {
      }

      public function has(key:*) : Boolean
      {
         var k:String = "k" + key;
         var found:Boolean = k in values;
         return found;
      }

      public function get(key:*) : *
      {
         var k:String = "k" + key;
         return k in values ? values[k] : null;
      }

      public function set(key:*, value:*) : void
      {
         var k:String = "k" + key;
         if(!(k in values))
         {
            keys.push(key);
         }
         values[k] = value;
      }

      public function add(key:*, amount:Number) : void
      {
         var k:String = "k" + key;
         if(!(k in values))
         {
            keys.push(key);
            values[k] = amount;
            return;
         }
         values[k] = values[k] + amount;
      }

      public function remove(key:*) : void
      {
         var k:String = "k" + key;
         if(!(k in values))
         {
            return;
         }
         delete values[k];
         for(var i:int = 0; i < keys.length; i++)
         {
            if(String(keys[i]) == String(key))
            {
               keys.splice(i,1);
               break;
            }
         }
      }

      public function get length() : int
      {
         return keys.length;
      }
   }
}
