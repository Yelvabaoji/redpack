pragma solidity ^0.4.24;
/// 使用0.4.24是为了moac链 - www.moac.io

/// @title 红包合约
/// @author yelvabaoji - xfshen@moacfoundation.cn
contract Redpack {
   address public owner;

   uint public minPackAmount = 1 * (10 ** 18); // 最低参与金额, 1 moac/mfc
   uint public maxPackAmount = 10000 * (10 ** 18); // 最高参与金额, 10000 moac/mfc
   uint public constant LIMIT_AMOUNT_OF_PACK = 100000 * (10 ** 18);

   uint public minPackCount = 1; // 最少1个红包可抢
   uint public maxPackCount = 10000; // 最多10000个红包可抢

   uint public totalPackAmounts = 0; // 该合约的余额
   uint public numberOfPlayers = 0; // 总的发红包数量
   address[] public players; // 发红包的人的列表

   struct Player {
      uint id; // 红包的id
      address owner; // 红包创建者的地址
      uint amount; // 红包里面塞钱塞了多少？
      uint balance; // 红包余额
      uint count; // 指定多少个红包数量
      uint amountPerPack; // 如果是均分，则每个红包的金额
      bool isRandom; // 指定是均分还是随机
      uint[] randomAmount; // 随机分配时，先产生count个随机数
      uint randomFactor; // 所有的随机数总和/count，用以计算最终的分配数
      address[] hunterList; // 抢红包的地址列表
      mapping(address => uint) hunterInfo; // 领取红包的人的列表：地址:数量
   }

   // 红包id到红包发红包人详细映射
   mapping(uint => Player) public playerInfo;

   // 这是为了人家发送币到合约地址的时候，收取
   function() public payable {}
   // event Received(address, uint);
   // receive() external payable { // receive关键字是solidity 6.0引进的
   //    emit Received(msg.sender, msg.value);
   // }
   // fallback() external payable;


   /// @notice 构造函数
   /// @param _minPackAmount 最小充钱数
   /// @param _maxPackAmount 最大充钱数
   constructor (uint _minPackAmount, uint _maxPackAmount) public {
      owner = msg.sender;

      if(_minPackAmount > 0) minPackAmount = _minPackAmount;
      if(_maxPackAmount > 0 && _maxPackAmount <= LIMIT_AMOUNT_OF_PACK)
         maxPackAmount = _maxPackAmount;
   }

   function kill() public {
      if(msg.sender == owner) selfdestruct(owner);
   }

   /// @notice 总红包数
   function getPlayerInfo() public view returns (
      uint nTotalPackAmounts,
      uint nNumberOfPlayers,
      address[] playerList
   ) {
     return (
        totalPackAmounts,
        numberOfPlayers,
        players
      );
   }

   //********************************************************************/
   // 创建红包
   //********************************************************************/

   event redpackCreated(uint id);
   event redpackWithdraw(uint amount);

   /// @notice 发红包充值
   /// @param count 可抢多少个红包
   /// @param isRandom 是固定分割还是随机分割
   function toll(uint count, bool isRandom) public payable {
      require(msg.value >= minPackAmount && msg.value <= maxPackAmount, "amount out of range(1..10000");
      require(count >= minPackCount && count <= maxPackCount, "最少1个, 最多10000个");

      uint id = numberOfPlayers;
      playerInfo[id].amount = msg.value;
      playerInfo[id].balance = msg.value;
      playerInfo[id].count = count;
      playerInfo[id].isRandom = isRandom;
      playerInfo[id].id = id;
      if (isRandom) {
         uint total = 0;
         for (uint i = 0; i < count; i++) {
            playerInfo[id].randomAmount[i] = uint(keccak256(abi.encodePacked(now, msg.sender, i))) % 100;
            total += playerInfo[id].randomAmount[i];
         }
         playerInfo[id].randomFactor = 100 / total; // 随机数按照 百分比计算足够了。
      } else {
         playerInfo[id].amountPerPack = msg.value / count; // 如果是均分的话，则每一份的金额是多少
      }

      totalPackAmounts += msg.value;
      numberOfPlayers++; // 创建的红包数量增加
      players.push(msg.sender); // player列表增加

      emit redpackCreated(id);
   }

   /// @notice 创建者提取余下的金额
   /// @param id 红包的id
   function withdrawBalance(uint id) public {
      require(msg.sender == playerInfo[id].owner, "not the owner.");
      require(playerInfo[id].balance > 0, "balance is 0.");
      require(playerInfo[id].balance <= totalPackAmounts, "not enough budget.");

      msg.sender.transfer(playerInfo[id].balance);
      totalPackAmounts -= playerInfo[id].balance;

      emit redpackWithdraw(playerInfo[id].balance);
   }

   /// @notice 某个红包统计信息
   /// @param id - 地址
   // 红包创建时间
   // 金额
   // 随机 / 平均
   // 个数
   // 余额
   // 已经抢了多少，还有多少
   function getPackInfo(uint id) public view returns (
      uint amount,
      uint balance,
      uint count,
      uint amountPerPack,
      bool isRandom
   ) {
      Player storage player = playerInfo[id];
      return (
         player.amount,
         player.balance,
         player.count,
         player.amountPerPack,
         player.isRandom
      );
   }

   //********************************************************************/
   // 抢红包
   //********************************************************************/

   event redpackGrabbed(uint amount);

   /// @notice 检查地址是否已经抢过该红包了。
   /// @param _id 哪一个红包
   /// @param _hunter 哪一个抢红包的人
   function checkHunterExists(uint _id, address _hunter) public view returns(bool) {
      for (uint256 i = 0; i < playerInfo[_id].hunterList.length; i++){
         if(playerInfo[_id].hunterList[i] == _hunter) return true;
      }
      return false;
   }

   /// @notice 抢红包。注意：抢完红包以后，抢的数据还保留着，以备查询
   /// @param id 抢的是哪一个红包
   function hunting(uint id) public payable {
      // 先检查该红包有没有余额
      require(playerInfo[id].balance > 0, "redpack is empty");
      require(playerInfo[id].count > playerInfo[id].hunterList.length, "exceed number of redpacks");
      require(!checkHunterExists(id, msg.sender), 'already grabbed');

      if(playerInfo[id].isRandom) {
         // 按照随机因子计算抢到的金额，这里可能有细微的误差
         uint index = playerInfo[id].hunterList.length;
         uint value = playerInfo[id].randomFactor * playerInfo[id].randomAmount[index] * playerInfo[id].amount;
         if (playerInfo[id].hunterList.length + 1 >= playerInfo[id].count) {
            // 考虑到计算的误差，最后一次抢红包，把余额全部发送出去
            hunted(id, playerInfo[id].balance);
            playerInfo[id].balance = 0;

         } else {
            hunted(id, value);
            playerInfo[id].balance -= value;
         }
      } else {
         // 考虑到计算的误差 (比如100块钱发给3个人红包平均分），最后一次抢红包，把余额全部发送出去
         if (playerInfo[id].balance > playerInfo[id].amountPerPack) {
            // 如果余额 > 1份，但是小于2份，则一次发送完毕
            if (playerInfo[id].balance < playerInfo[id].amountPerPack * 2) {
               hunted(id, playerInfo[id].balance);
               playerInfo[id].balance = 0; // 发送完成，余额为0
            } else {
               // 如果余额 > 2份，则发送一份
               hunted(id, playerInfo[id].amountPerPack);
               playerInfo[id].balance -= playerInfo[id].amountPerPack;
            }
         } else {
            // 等于就是最后一个抢红包的人 （小于不可能）
            hunted(id, playerInfo[id].balance);
            playerInfo[id].balance = 0;
         }
      }
   }
   function hunted(uint _id, uint _amount) internal {
      require(_amount <= totalPackAmounts, "grab: not enough budget.");
      msg.sender.transfer(_amount);
      totalPackAmounts -= _amount;
      playerInfo[_id].hunterList.push(msg.sender);

      emit redpackGrabbed(_amount);
   }

   /// @notice 抢红包的记录，即在什么时间，抢了多少金额 - 这个可以通过查询我的特定交易记录来判断
   // function huntingRecord(uint id) public view returns () {
   // }

}
