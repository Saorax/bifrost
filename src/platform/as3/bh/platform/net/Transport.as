package bh.platform.net
{
   public interface Transport
   {
      function get name() : String;

      function send(connection:Object, packet:NetPacket) : Boolean;
   }
}
