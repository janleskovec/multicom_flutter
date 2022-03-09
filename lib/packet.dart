/// packet type "enum"
class PacketType {
  static const discovery       = PacketType(0); // discovery packet (only returns identifier msg)
  static const discoveryHelo   = PacketType(1); // discovery reply packet
  static const ping            = PacketType(2); // echo
  static const get             = PacketType(3); // uses random nonce (does not prevent dupicate callbacks)
  static const getReply        = PacketType(4); // reply msg after get
  static const send            = PacketType(5); // uses sequential nonce (ensures callback only gets called once + order)
  static const post            = PacketType(6); // uses sequential nonce + sends ack (ensures callback only gets called once + order)
  static const ack             = PacketType(7); // used to reply after post (contains session id and nonce)
  static const notFound        = PacketType(8); // endpoint not found (contains session id and nonce)

  const PacketType(this.type);

  final int type;

  @override
  bool operator ==(other) {
    // compare to int
    if (other.runtimeType == int) {
      return type == (other as int);
    }
    
    // compare to same type
    if (other.runtimeType == PacketType) {
      return type == (other as PacketType).type;
    }
    
    // other types --> not equal
    return false;
  }

  @override
  int get hashCode => type;

}