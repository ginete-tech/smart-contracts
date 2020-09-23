pragma solidity 0.5.7;
import "./external/openzeppelin-solidity/math/SafeMath.sol";
import "./external/govblocks-protocol/interfaces/IGovernance.sol";
import "./external/govblocks-protocol/Governed.sol";
import "./external/proxy/OwnedUpgradeabilityProxy.sol";
import "./external/string-utils/strings.sol";
import "./interfaces/IToken.sol";
import "./interfaces/IMarket.sol";
import "./interfaces/Iupgradable.sol";
import "./interfaces/IMarketUtility.sol";

contract MarketRegistry is Governed, Iupgradable {

    using SafeMath for uint256; 
    using strings for *; 

    enum MarketType {
      HourlyMarket,
      DailyMarket,
      WeeklyMarket
    }

    struct MarketTypeData {
      uint256 predictionTime;
      uint256 optionRangePerc;
    }

    struct MarketCurrency {
      address marketImplementation;
      address currencyFeedAddress;
      bool isChainlinkFeed;
      bytes32 currencyName;
    }

    struct MarketCreationData {
      address marketAddress;
      address penultimateMarket;
      uint256 startTime;
    }

    struct DisputeStake {
      address staker;
      uint256 stakeAmount;
      uint256 proposalId;
      uint256 ethDeposited;
      uint256 tokenDeposited;
    }

    struct MarketData {
      bool isMarket;
      uint256 marketFlushFund;
      DisputeStake disputeStakes;
    }

    struct UserData {
      uint256 lastClaimedIndex;
      uint256 totalEthStaked;
      uint256 totalPlotStaked;
      address[] marketsParticipated;
      mapping(address => bool) marketsParticipatedFlag;
    }

    uint internal marketCreationFallbackTime;
    uint internal marketCreationIncentive;
    uint internal marketFlushFundPLOT;
    
    mapping(address => MarketData) marketData;
    mapping(address => UserData) userData;
    mapping(uint256 => mapping(uint256 => MarketCreationData)) public marketCreationData;
    mapping(uint256 => address) disputeProposalId;
    // mapping(uint256 => mapping(uint256 => uint256)) public marketTypeCurrencyStartTime; //Markets of type and currency

    address constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public tokenController;

    MarketTypeData[] marketTypes;
    MarketCurrency[] marketCurrencies;

    bool public marketCreationPaused;

    IToken public plotToken;
    IMarketUtility public marketUtility;
    IGovernance internal governance;
    IMaster ms;


    event MarketQuestion(address indexed marketAdd, bytes32 stockName, uint256 indexed predictionType, uint256 startTime);
    event PlacePrediction(address indexed user,uint256 value, uint256 predictionPoints, address predictionAsset,uint256 prediction,address indexed marketAdd,uint256 _leverage);
    event MarketResult(address indexed marketAdd, uint256[] totalReward, uint256 winningOption, uint256 closeValue);
    event Claimed(address indexed marketAdd, address indexed user, uint256[] reward, address[] _predictionAssets, uint256 incentive, address incentiveToken);
    event MarketTypes(uint256 indexed index, uint256 predictionTime, uint256 optionRangePerc);
    event MarketCurrencies(uint256 indexed index, address marketImplementation,  address feedAddress, bytes32 currencyName, bool isChainlinkFeed);
    event DisputeRaised(address indexed marketAdd, address raisedBy, uint256 proposalId, uint256 proposedValue);
    event DisputeResolved(address indexed marketAdd, bool status);

    /**
    * @dev Checks if given addres is valid market address.
    */
    function isMarket(address _address) public view returns(bool) {
      return marketData[_address].isMarket;
    }

    function isWhitelistedSponsor(address _address) public view returns(bool) {
      return ms.whitelistedSponsor(_address);
    }

    /**
    * @dev Initialize the PlotX MarketRegistry.
    * @param _marketUtility The address of market config.
    * @param _plotToken The instance of PlotX token.
    */
    function initiate(address _marketUtility, address _plotToken, address payable[] memory _configParams) public {
      require(address(ms) == msg.sender);
      marketCreationFallbackTime = 15 minutes;
      marketCreationIncentive = 10 ether;
      plotToken = IToken(_plotToken);
      address tcAddress = ms.getLatestAddress("TC");
      tokenController = tcAddress;
      marketUtility = IMarketUtility(_generateProxy(_marketUtility));
      marketUtility.initialize(_configParams);
      plotToken.approve(address(governance), ~uint256(0));
    }

    /**
    * @dev Start the initial market.
    */
    function addInitialMarketTypesAndStart(uint _marketStartTime, address _ethMarketImplementation, address _btcMarketImplementation) external payable {
      require(marketTypes.length == 0);
      _addNewMarketCurrency(_ethMarketImplementation);
      _addNewMarketCurrency(_btcMarketImplementation);
      _addMarket(1 hours, 20);
      _addMarket(24 hours, 50);
      _addMarket(7 days, 100);

      for(uint256 i = 0;i < marketTypes.length; i++) {
          marketCreationData[i][0].startTime = _marketStartTime;
          marketCreationData[i][1].startTime = _marketStartTime;
          createMarket(i, 0);
          createMarket(i, 1);
      }
    }

    /**
    * @dev Add new market type.
    * @param _predictionTime The time duration of market.
    * @param _marketStartTime The time at which market will create.
    */
    function addNewMarketType(uint256 _predictionTime, uint256 _marketStartTime, uint256 _optionRangePerc) external onlyAuthorizedToGovern {
      require(_marketStartTime > now);
      uint256 _marketType = marketTypes.length;
      _addMarket(_predictionTime, _optionRangePerc);
      for(uint256 j = 0;j < marketCurrencies.length; j++) {
        marketCreationData[_marketType][j].startTime = _marketStartTime;
        createMarket(_marketType, j);
      }
    }

    function _addMarket(uint256 _predictionTime, uint256 _optionRangePerc) internal {
      uint256 _marketType = marketTypes.length;
      marketTypes.push(MarketTypeData(_predictionTime, _optionRangePerc));
      emit MarketTypes(_marketType, _predictionTime, _optionRangePerc);
    }

    /**
    * @dev Add new market currency.
    */
    function addNewMarketCurrency(address _marketImplementation, uint256 _marketStartTime) external onlyAuthorizedToGovern {
      uint256 _marketCurrencyIndex = marketCurrencies.length;
      _addNewMarketCurrency(_marketImplementation);
      for(uint256 j = 0;j < marketTypes.length; j++) {
        marketCreationData[j][_marketCurrencyIndex].startTime = _marketStartTime;
        createMarket(j, _marketCurrencyIndex);
      }
    }

    function _addNewMarketCurrency(address _marketImplementation) internal {
      uint256 _marketCurrencyIndex = marketCurrencies.length;
      (bytes32 _currencyName, address _priceFeed, bool _isChainlinkFeed) = IMarket(_marketImplementation).getMarketFeedData();
      marketCurrencies.push(MarketCurrency(_marketImplementation, _priceFeed, _isChainlinkFeed, _currencyName));
      emit MarketCurrencies(_marketCurrencyIndex, _marketImplementation, _priceFeed, _currencyName, _isChainlinkFeed);
    }

    /**
    * @dev Update the implementations of the market.
    */
    function updateMarketImplementations(uint256[] calldata _currencyIndexes, address[] calldata _marketImplementations) external onlyAuthorizedToGovern {
      require(_currencyIndexes.length == _marketImplementations.length);
      for(uint256 i = 0;i< _currencyIndexes.length; i++) {
        marketCurrencies[_currencyIndexes[i]].marketImplementation = _marketImplementations[i];
      }
    }

    /**
    * @dev Upgrade the implementations of the contract.
    * @param _proxyAddress the proxy address.
    * @param _newImplementation Address of new implementation contract
    */
    function upgradeContractImplementation(address payable _proxyAddress, address _newImplementation) 
        external onlyAuthorizedToGovern
    {
      require(_newImplementation != address(0));
      OwnedUpgradeabilityProxy tempInstance 
          = OwnedUpgradeabilityProxy(_proxyAddress);
      tempInstance.upgradeTo(_newImplementation);
    }

    /**
     * @dev Changes the master address and update it's instance
     */
    function setMasterAddress() public {
      OwnedUpgradeabilityProxy proxy =  OwnedUpgradeabilityProxy(address(uint160(address(this))));
      require(msg.sender == proxy.proxyOwner(),"Sender is not proxy owner.");
      ms = IMaster(msg.sender);
      masterAddress = msg.sender;
      governance = IGovernance(ms.getLatestAddress("GV"));
    }

    /**
    * @dev Creates the new market.
    * @param _marketType The type of the market.
    * @param _marketCurrencyIndex the index of market currency.
    */
    function _createMarket(uint256 _marketType, uint256 _marketCurrencyIndex, uint256 _minValue, uint256 _maxValue, uint256 _marketStartTime) internal {
      require(!marketCreationPaused);
      MarketTypeData memory _marketTypeData = marketTypes[_marketType];
      // MarketCurrency memory _marketCurrencyData = marketCurrencies[_marketCurrencyIndex];
      // address _feedAddress;
      // if(!(_marketCurrencyData.isChainlinkFeed) && (_marketTypeData.predictionTime == 1 hours)) {
      //   _feedAddress = _marketCurrencyData.currencyFeedAddress;
      // } else {
      //   _feedAddress = address(plotToken);
      // }
      // marketUtility.update(_feedAddress);
      address payable _market = _generateProxy(marketCurrencies[_marketCurrencyIndex].marketImplementation);
      marketData[_market].isMarket = true;
      IMarket(_market).initiate(_marketStartTime, _marketTypeData.predictionTime, _minValue, _maxValue);
      emit MarketQuestion(_market, IMarket(_market).marketCurrency(), _marketType, _marketStartTime);
      _marketStartTime = _marketStartTime.add(_marketTypeData.predictionTime);
      marketCreationData[_marketType][_marketCurrencyIndex].startTime = _marketStartTime;

      (marketCreationData[_marketType][_marketCurrencyIndex].penultimateMarket, marketCreationData[_marketType][_marketCurrencyIndex].marketAddress) =
       (marketCreationData[_marketType][_marketCurrencyIndex].marketAddress, _market);
    }

    /**
    * @dev Creates the new market
    * @param _marketType The type of the market.
    * @param _marketCurrencyIndex the index of market currency.
    */
    function createMarket(uint256 _marketType, uint256 _marketCurrencyIndex) public payable{
      address _previousMarket = marketCreationData[_marketType][_marketCurrencyIndex].marketAddress;
      address penultimateMarket = marketCreationData[_marketType][_marketCurrencyIndex].penultimateMarket;
      if(_previousMarket != address(0)) {
        IMarket(_previousMarket).exchangeCommission();
        (,,,,,,,, uint _status) = getMarketDetails(_previousMarket);
        require(_status >= uint(IMarket.PredictionStatus.InSettlement));
      }
      if(penultimateMarket != address(0)) {
        IMarket(penultimateMarket).settleMarket();
      }
      uint _marketStartTime = calculateStartTimeForMarket(_marketType, _marketCurrencyIndex);
      uint256 _optionRangePerc = marketTypes[_marketType].optionRangePerc;
      uint currentPrice = marketUtility.getAssetPriceUSD(marketCurrencies[_marketCurrencyIndex].currencyFeedAddress, marketCurrencies[_marketCurrencyIndex].isChainlinkFeed);
      _optionRangePerc = currentPrice.mul(_optionRangePerc.div(2)).div(1000); 
      uint _minValue = currentPrice.sub(_optionRangePerc);
      uint _maxValue = currentPrice.add(_optionRangePerc);
      _createMarket(_marketType, _marketCurrencyIndex, _minValue, _maxValue, _marketStartTime);
      _transferIncentiveForCreation();
    }

    /**
    * @dev Internal function to reward user for initiating market creation call
    */
    function _transferIncentiveForCreation() internal {
      if((plotToken.balanceOf(address(this)).sub(marketFlushFundPLOT)) > marketCreationIncentive) {
        _transferAsset(address(plotToken), msg.sender, marketCreationIncentive);
      }
    }

    function calculateStartTimeForMarket(uint256 _marketType, uint256 _marketCurrencyIndex) public view returns(uint256 _marketStartTime) {
      _marketStartTime = marketCreationData[_marketType][_marketCurrencyIndex].startTime;
      uint predictionTime = marketTypes[_marketType].predictionTime;
      if(now > _marketStartTime.add(predictionTime)) {
        uint noOfMarketsSkipped = ((now).sub(_marketStartTime)).div(predictionTime);
       _marketStartTime = _marketStartTime.add(noOfMarketsSkipped.mul(predictionTime));
      }
    }

    /**
    * @dev Updates Flag to pause creation of market.
    */
    function pauseMarketCreation() external onlyAuthorizedToGovern {
      require(!marketCreationPaused);
        marketCreationPaused = true;
    }

    /**
    * @dev Updates Flag to resume creation of market.
    */
    function resumeMarketCreation() external onlyAuthorizedToGovern {
      require(marketCreationPaused);
        marketCreationPaused = false;
    }

    /**
    * @dev Create proposal if user wants to raise the dispute.
    * @param proposalTitle The title of proposal created by user.
    * @param description The description of dispute.
    * @param solutionHash The ipfs solution hash.
    * @param action The encoded action for solution.
    * @param _stakeForDispute The token staked to raise the diospute.
    * @param _user The address who raises the dispute.
    */
    function createGovernanceProposal(string memory proposalTitle, string memory description, string memory solutionHash, bytes memory action, uint256 _stakeForDispute, address _user, uint256 _ethSentToPool, uint256 _tokenSentToPool, uint256 _proposedValue) public {
      require(isMarket(msg.sender));
      uint256 proposalId = governance.getProposalLength();
      marketData[msg.sender].disputeStakes = DisputeStake(_user, _stakeForDispute, proposalId, _ethSentToPool, _tokenSentToPool);
      disputeProposalId[proposalId] = msg.sender;
      governance.createProposalwithSolution(proposalTitle, proposalTitle, description, 10, solutionHash, action);
      emit DisputeRaised(msg.sender, _user, proposalId, _proposedValue);
    }

    /**
    * @dev Resolve the dispute if wrong value passed at the time of market result declaration.
    * @param _marketAddress The address specify the market.
    * @param _result The final result of the market.
    */
    function resolveDispute(address payable _marketAddress, uint256 _result) external onlyAuthorizedToGovern {
      uint256 ethDepositedInPool = marketData[_marketAddress].disputeStakes.ethDeposited;
      uint256 plotDepositedInPool = marketData[_marketAddress].disputeStakes.tokenDeposited;
      uint256 stakedAmount = marketData[_marketAddress].disputeStakes.stakeAmount;
      address payable staker = address(uint160(marketData[_marketAddress].disputeStakes.staker));
      address plotTokenAddress = address(plotToken);
      marketFlushFundPLOT = marketFlushFundPLOT.sub(marketData[_marketAddress].marketFlushFund);
      delete marketData[_marketAddress].marketFlushFund;
      // _transferAsset(ETH_ADDRESS, _marketAddress, ethDepositedInPool);
      _transferAsset(plotTokenAddress, _marketAddress, plotDepositedInPool);
      IMarket(_marketAddress).resolveDispute.value(ethDepositedInPool)(true, _result);
      emit DisputeResolved(_marketAddress, true);
      _transferAsset(plotTokenAddress, staker, stakedAmount);
    }

    /**
    * @dev Burns the tokens of member who raised the dispute, if dispute is rejected.
    * @param _proposalId Id of dispute resolution proposal
    */
    function burnDisputedProposalTokens(uint _proposalId) external onlyAuthorizedToGovern {
      address disputedMarket = disputeProposalId[_proposalId];
      IMarket(disputedMarket).resolveDispute(false, 0);
      emit DisputeResolved(disputedMarket, false);
      uint _stakedAmount = marketData[disputedMarket].disputeStakes.stakeAmount;
      plotToken.burn(_stakedAmount);
    }

    function withdrawForRewardDistribution(uint256 withdrawPercent) external returns(uint256) {
      require(isMarket(msg.sender));
      uint256 _amount = marketFlushFundPLOT.mul(withdrawPercent).div(100);
      marketFlushFundPLOT = marketFlushFundPLOT.sub(_amount);
      _transferAsset(address(plotToken), msg.sender, _amount);
      return _amount;
    }
 
    /**
    * @dev Claim the pending return of the market.
    * @param maxRecords Maximum number of records to claim reward for
    */
    function claimPendingReturn(uint256 maxRecords) external {
      uint256 i;
      uint len = userData[msg.sender].marketsParticipated.length;
      uint lastClaimed = len;
      uint count;
      for(i = userData[msg.sender].lastClaimedIndex; i < len && count < maxRecords; i++) {
        if(IMarket(userData[msg.sender].marketsParticipated[i]).claimReturn(msg.sender) > 0) {
          count++;
        } else {
          if(lastClaimed == len) {
            lastClaimed = i;
          }
        }
      }
      if(lastClaimed == len) {
        lastClaimed = i;
      }
      userData[msg.sender].lastClaimedIndex = lastClaimed;
    }

    function () external payable {
    }

    function transferAssets(address _asset, address payable _to, uint _amount) external onlyAuthorizedToGovern {
      _transferAsset(_asset, _to, _amount);
    }

    /**
    * @dev Transfer the assets to specified address.
    * @param _asset The asset transfer to the specific address.
    * @param _recipient The address to transfer the asset of
    * @param _amount The amount which is transfer.
    */
    function _transferAsset(address _asset, address payable _recipient, uint256 _amount) internal {
      if(_amount > 0) { 
        if(_asset == ETH_ADDRESS) {
          _recipient.transfer(_amount);
        } else {
          require(IToken(_asset).transfer(_recipient, _amount));
        }
      }
    }

    function updateUintParameters(bytes8 code, uint256 value) external onlyAuthorizedToGovern {
      if(code == "FBTIME") {
        marketCreationFallbackTime = value;
      } else if(code == "MCRINC") {
        marketCreationIncentive = value;
      } else {
        marketUtility.updateUintParameters(code, value);
      }
    }

    function updateConfigAddressParameters(bytes8 code, address payable value) external onlyAuthorizedToGovern {
      marketUtility.updateAddressParameters(code, value);
    }

    /**
     * @dev to generater proxy 
     * @param _contractAddress of the proxy
     */
    function _generateProxy(address _contractAddress) internal returns(address payable) {
        OwnedUpgradeabilityProxy tempInstance = new OwnedUpgradeabilityProxy(_contractAddress);
        return address(tempInstance);
    }

    /**
    * @dev Emits the MarketResult event.
    * @param _totalReward The amount of reward to be distribute.
    * @param winningOption The winning option of the market.
    * @param closeValue The closing value of the market currency.
    */
    function callMarketResultEvent(uint256[] calldata _totalReward, uint256 winningOption, uint256 closeValue, uint _tokenAmountToPool, bool _isMarketFlushFund) external {
      require(isMarket(msg.sender));
      if(_isMarketFlushFund) {
        marketFlushFundPLOT = marketFlushFundPLOT.add(_tokenAmountToPool);
        marketData[msg.sender].marketFlushFund = marketFlushFundPLOT;
      }
      emit MarketResult(msg.sender, _totalReward, winningOption, closeValue);
    }
    
    /**
    * @dev Emits the PlacePrediction event and sets the user data.
    * @param _user The address who placed prediction.
    * @param _value The amount of ether user staked.
    * @param _predictionPoints The positions user will get.
    * @param _predictionAsset The prediction assets user will get.
    * @param _prediction The option range on which user placed prediction.
    * @param _leverage The leverage selected by user at the time of place prediction.
    */
    function setUserGlobalPredictionData(address _user,uint256 _value, uint256 _predictionPoints, address _predictionAsset, uint256 _prediction, uint256 _leverage) external {
      require(isMarket(msg.sender));
      if(_predictionAsset == ETH_ADDRESS) {
        userData[_user].totalEthStaked = userData[_user].totalEthStaked.add(_value);
      } else {
        userData[_user].totalPlotStaked = userData[_user].totalPlotStaked.add(_value);
      }
      if(!userData[_user].marketsParticipatedFlag[msg.sender]) {
        userData[_user].marketsParticipated.push(msg.sender);
        userData[_user].marketsParticipatedFlag[msg.sender] = true;
      }
      emit PlacePrediction(_user, _value, _predictionPoints, _predictionAsset, _prediction, msg.sender,_leverage);
    }

    /**
    * @dev Emits the claimed event.
    * @param _user The address who claim their reward.
    * @param _reward The reward which is claimed by user.
    * @param predictionAssets The prediction assets of user.
    * @param incentives The incentives of user.
    * @param incentiveToken The incentive tokens of user.
    */
    function callClaimedEvent(address _user ,uint[] calldata _reward, address[] calldata predictionAssets, uint incentives, address incentiveToken) external {
      require(isMarket(msg.sender));
      emit Claimed(msg.sender, _user, _reward, predictionAssets, incentives, incentiveToken);
    }

    function getUintParameters(bytes8 code) external view returns(uint256 value) {
      if(code == "FBTIME") {
        value = marketCreationFallbackTime;
      } else if(code == "MCRINC") {
        value = marketCreationIncentive;
      }
    }

    /**
    * @dev Gets the market details of the specified address.
    * @param _marketAdd The market address to query the details of market.
    * @return _feedsource bytes32 representing the currency or stock name of the market.
    * @return minvalue uint[] memory representing the minimum range of all the options of the market.
    * @return maxvalue uint[] memory representing the maximum range of all the options of the market.
    * @return optionprice uint[] memory representing the option price of each option ranges of the market.
    * @return _ethStaked uint[] memory representing the ether staked on each option ranges of the market.
    * @return _plotStaked uint[] memory representing the plot staked on each option ranges of the market.
    * @return _predictionType uint representing the type of market.
    * @return _expireTime uint representing the expire time of the market.
    * @return _predictionStatus uint representing the status of the market.
    */
    function getMarketDetails(address _marketAdd)public view returns
    (bytes32 _feedsource,uint256[] memory minvalue,uint256[] memory maxvalue,
      uint256[] memory optionprice,uint256[] memory _ethStaked, uint256[] memory _plotStaked,uint256 _predictionType,uint256 _expireTime, uint256 _predictionStatus){
      return IMarket(_marketAdd).getData();
    }

    /**
    * @dev Gets the market details of the specified user address.
    * @param user The address to query the details of market.
    * @param fromIndex The index to query the details from.
    * @param toIndex The index to query the details to
    * @return _market address[] memory representing the address of the market.
    * @return _winnigOption uint256[] memory representing the winning option range of the market.
    */
    function getMarketDetailsUser(address user, uint256 fromIndex, uint256 toIndex) external view returns
    (address[] memory _market, uint256[] memory _winnigOption){
      uint256 totalMarketParticipated = userData[user].marketsParticipated.length;
      if(totalMarketParticipated > 0 && fromIndex < totalMarketParticipated) {
        uint256 _toIndex = toIndex;
        if(_toIndex >= totalMarketParticipated) {
          _toIndex = totalMarketParticipated - 1;
        }
        _market = new address[](_toIndex.sub(fromIndex).add(1));
        _winnigOption = new uint256[](_toIndex.sub(fromIndex).add(1));
        for(uint256 i = fromIndex; i <= _toIndex; i++) {
          _market[i] = userData[user].marketsParticipated[i];
          _winnigOption[i] = IMarket(_market[i]).WinningOption();
        }
      }
    }

    /**
    * @dev Gets the addresses of open markets.
    * @return _openMarkets address[] memory representing the open market addresses.
    * @return _marketTypes uint256[] memory representing the open market types.
    */
    function getOpenMarkets() external view returns(address[] memory _openMarkets, uint256[] memory _marketTypes, bytes32[] memory _marketCurrencies) {
      uint256  count = 0;
      uint256 marketTypeLength = marketTypes.length;
      uint256 marketCurrencyLength = marketCurrencies.length;
      _openMarkets = new address[]((marketTypeLength).mul(marketCurrencyLength));
      _marketTypes = new uint256[]((marketTypeLength).mul(marketCurrencyLength));
      _marketCurrencies = new bytes32[]((marketTypeLength).mul(marketCurrencyLength));
      for(uint256 i = 0; i< marketTypeLength; i++) {
        for(uint256 j = 0; j< marketCurrencyLength; j++) {
          _openMarkets[count] = marketCreationData[i][j].marketAddress;
          _marketTypes[count] = i;
          _marketCurrencies[count] = marketCurrencies[j].currencyName;
          count++;
        }
      }
    }

    // /**
    // * @dev Calculates the user pending return amount.
    // * @param _user The address to query the pending return amount of.
    // * @return pendingReturn uint256 representing the pending return amount of user.
    // * @return incentive uint256 representing the incentive.
    // */
    // function calculateUserPendingReturn(address _user) external view returns(uint[] memory returnAmount, address[] memory _predictionAssets, uint[] memory incentive, address[] memory _incentiveTokens) {
    //   uint256 _return;
    //   uint256 _incentive;
    //   for(uint256 i = lastClaimedIndex[_user]; i < marketsParticipated[_user].length; i++) {
    //     // pendingReturn = pendingReturn.add(marketsParticipated[_user][i].call(abi.encodeWithSignature("getPendingReturn(uint256)", _user)));
    //     (_return, _incentive) = IMarket(marketsParticipated[_user][i]).getPendingReturn(_user);
    //     pendingReturn = pendingReturn.add(_return);
    //     incentive = incentive.add(_incentive);
    //   }
    // }

}
