const { assert } = require("chai");

const OwnedUpgradeabilityProxy = artifacts.require('OwnedUpgradeabilityProxy');
const Market = artifacts.require("MockMarket");
const Plotus = artifacts.require("Plotus");
const Master = artifacts.require("Master");
const PlotusToken = artifacts.require("PlotusToken");
const BLOT = artifacts.require("BLOT");
const MockUniswapRouter = artifacts.require("MockUniswapRouter");
const BigNumber = require("bignumber.js");

const web3 = Market.web3;
const increaseTime = require("./utils/increaseTime.js").increaseTime;
// get etherum accounts
// swap ether with LOT

contract("Market", async function ([
  user1,
  user2,
  user3,
  user4,
  user5,
  user6,
  user7,
  user8,
  user9,
  user10,
]) {
  it("Place the bets with ether", async () => {
    masterInstance = await OwnedUpgradeabilityProxy.deployed();
    masterInstance = await Master.at(masterInstance.address);
    plotusToken = await PlotusToken.deployed();
    BLOTInstance = await BLOT.deployed();
    MockUniswapRouterInstance = await MockUniswapRouter.deployed();
    plotusNewAddress = await masterInstance.getLatestAddress(
      web3.utils.toHex("PL")
    );
    plotusNewInstance = await Plotus.at(plotusNewAddress);
    // console.log(await plotusNewInstance.getOpenMarkets());
    openMarkets = await plotusNewInstance.getOpenMarkets();

    console.log(`OpenMaket : ${openMarkets["_openMarkets"][0]}`);

    marketInstance = await Market.at(openMarkets["_openMarkets"][0]);
    await increaseTime(10001);
    assert.ok(marketInstance);

    // setting option price in eth
    await marketInstance.setOptionPrice(1, 9);
    await marketInstance.setOptionPrice(2, 18);
    await marketInstance.setOptionPrice(3, 27);

    // set price
    // user 1
    // set price lot
    await MockUniswapRouterInstance.setPrice("1000000000000000");
    await plotusToken.approve(
      openMarkets["_openMarkets"][0],
      "100000000000000000000",
      {
        from: user1,
      }
    );
    await marketInstance.placePrediction(
      plotusToken.address,
      "100000000000000000000",
      2,
      1,
      { from: user1 }
    );

    // user 2
    await MockUniswapRouterInstance.setPrice("2000000000000000");
    // await plotusToken.transfer(user2, "500000000000000000000");

    // await plotusToken.approve(
    //   openMarkets["_openMarkets"][0],
    //   "400000000000000000000",
    //   {
    //     from: user2,
    //   }
    // );
    // await marketInstance.placePrediction(
    //   plotusToken.address,
    //   "400000000000000000000",
    //   2,
    //   2,
    //   { from: user2 }
    // );
    await plotusToken.approve(BLOTInstance.address, "1000000000000000000000");
    await BLOTInstance.mint(user2, "1000000000000000000000");
    // await BLOTInstance.transferFrom(user1, user2, "500000000000000000000", {
    //   from: user1,
    // });

    await BLOTInstance.approve(
      openMarkets["_openMarkets"][0],
      "400000000000000000000",
      {
        from: user2,
      }
    );
    console.log(await BLOTInstance.balanceOf(user1));
    await BLOTInstance.addMinter(marketInstance.address);
    await marketInstance.placePrediction(
      BLOTInstance.address,
      "400000000000000000000",
      2,
      5,
      { from: user2 }
    );

    // user 3
    await MockUniswapRouterInstance.setPrice("1000000000000000");
    await plotusToken.transfer(user3, "500000000000000000000");
    await plotusToken.approve(
      openMarkets["_openMarkets"][0],
      "210000000000000000000",
      {
        from: user3,
      }
    );
    await marketInstance.placePrediction(
      plotusToken.address,
      "210000000000000000000",
      2,
      2,
      { from: user3 }
    );
    // user 4
    await MockUniswapRouterInstance.setPrice("15000000000000000");

    await plotusToken.approve(BLOTInstance.address, "1000000000000000000000");
    await BLOTInstance.mint(user4, "1000000000000000000000");
    await BLOTInstance.approve(
      openMarkets["_openMarkets"][0],
      "123000000000000000000",
      {
        from: user4,
      }
    );
    await marketInstance.placePrediction(
      BLOTInstance.address,
      "123000000000000000000",
      3,
      5,
      { from: user4 }
    );

    // await plotusToken.transfer(user4, "200000000000000000000");

    // await plotusToken.approve(
    //   openMarkets["_openMarkets"][0],
    //   "123000000000000000000",
    //   {
    //     from: user4,
    //   }
    // );
    // await marketInstance.placePrediction(
    //   plotusToken.address,
    //   "123000000000000000000",
    //   3,
    //   3,
    //   { from: user4 }
    // );

    // user 5
    await MockUniswapRouterInstance.setPrice("12000000000000000");
    await marketInstance.placePrediction(
      "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
      "1000000000000000000",
      1,
      4,
      { value: "1000000000000000000", from: user5 }
    );

    // user 6
    await MockUniswapRouterInstance.setPrice("14000000000000000");
    await marketInstance.placePrediction(
      "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
      "2000000000000000000",
      1,
      5,
      { value: "2000000000000000000", from: user6 }
    );
    // user 7
    await MockUniswapRouterInstance.setPrice("10000000000000000");

    await marketInstance.placePrediction(
      "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
      "1000000000000000000",
      2,
      2,
      { value: "1000000000000000000", from: user7 }
    );
    // user 8
    await MockUniswapRouterInstance.setPrice("45000000000000000");
    await marketInstance.placePrediction(
      "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
      "3000000000000000000",
      3,
      3,
      { value: "3000000000000000000", from: user8 }
    );
    // user 9
    await MockUniswapRouterInstance.setPrice("51000000000000000");
    await marketInstance.placePrediction(
      "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
      "1000000000000000000",
      3,
      1,
      { value: "1000000000000000000", from: user9 }
    );
    // user 10
    await MockUniswapRouterInstance.setPrice("12000000000000000");
    await marketInstance.placePrediction(
      "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
      "2000000000000000000",
      2,
      4,
      { value: "2000000000000000000", from: user10 }
    );
  });

  it("1.Bet Points allocated properly in ether", async () => {
    accounts = [
      user1,
      user2,
      user3,
      user4,
      user5,
      user6,
      user7,
      user8,
      user9,
      user10,
    ];
    options = [2, 2, 2, 3, 1, 1, 2, 3, 3, 2];
    getBetPoints = async (user, option, expected) => {
      // return bet points of user
      let betPoins = await marketInstance.userPredictionPoints(user, option);
      betPoins = betPoins / 1;
      return betPoins;
    };
    betPointsExpected = [
      5.552777778,
      222.1111111,
      23.32166667,
      341.4958333,
      444.0,
      1110,
      111,
      333,
      37,
      444,
    ];

    // console.log("bet points for user 1");
    // betPointsUser1 = await getBetPoints(accounts[0], options[0]);
    // betPointsUser3 = await getBetPoints(accounts[2], options[2]);

    // console.log(
    //   `bet points : ${betPointsUser1} expected : ${betPointsExpected[0]} `
    // );
    // console.log("bet points for user 3");
    // console.log(
    //   `bet points : ${betPointsUser3} expected : ${betPointsExpected[2]} `
    // );
    for (let index = 0; index < 10; index++) {
      let betPoints = await getBetPoints(accounts[index], options[index]);
      betPoints = betPoints / 1000;
      betPoints = betPoints.toFixed(1);
      console.log(`user${index + 1} : option : ${options[index]}  `);
      console.log(
        `bet points : ${betPoints} expected : ${betPointsExpected[
          index
        ].toFixed(1)} `
      );
    }
    // console.log(await plotusToken.balanceOf(user1));

    // close market
    await increaseTime(36001);
    await marketInstance.calculatePredictionResult(1);
    await increaseTime(36001);
    // plotus contract balance eth balance
    plotusBalanceBefore = await web3.eth.getBalance(plotusNewAddress);
    console.log(`plotus eth balance before commision : ${plotusBalanceBefore}`);
    lotBalanceBefore = await plotusToken.balanceOf(
      openMarkets["_openMarkets"][0]
    );
    lotBalanceBefore = lotBalanceBefore / 1;
    console.log(`Lot Balance of market before commision : ${lotBalanceBefore}`);
    // lot supply , lot balance of market
    await MockUniswapRouterInstance.setPrice("1000000000000000");

    await marketInstance.exchangeCommission();

    plotusBalanceAfter = await web3.eth.getBalance(plotusNewAddress);
    console.log(`plotus balance after commision : ${plotusBalanceAfter}`);
    lotBalanceAfter = await plotusToken.balanceOf(
      openMarkets["_openMarkets"][0]
    );
    lotBalanceAfter = lotBalanceAfter / 1;
    console.log(`Lot Balance of market before commision : ${lotBalanceAfter}`);
    console.log(`Difference : ${lotBalanceAfter - lotBalanceBefore}`);
  });

  it("2.check total return for each user bet values in eth", async () => {
    accounts = [
      user1,
      user2,
      user3,
      user4,
      user5,
      user6,
      user7,
      user8,
      user9,
      user10,
    ];
    options = [2, 2, 2, 3, 1, 1, 2, 3, 3, 2];
    getReturnsInEth = async (user) => {
      // return userReturn in eth
      const response = await marketInstance.getReturn(user);
      let returnAmountInEth = response[0][1];
      return returnAmountInEth;
    };

    const returnInEthExpected = [
      0,
      0,
      0,
      0,
      2.140714286,
      4.852285714,
      0.5994,
      1.1988,
      0.7992,
      0.3996,
    ];
    // calulate  rewards for every user in eth

    console.log("Rewards in Eth");
    for (let index = 0; index < 10; index++) {
      // check eth returns
      let returns = await getReturnsInEth(accounts[index]);
      console.log(
        `return : ${returns} Expected :${returnInEthExpected[index]}`
      );
    }
  });
  it("3.Check User Recived The appropriate amount", async () => {
    accounts = [
      user1,
      user2,
      user3,
      user4,
      user5,
      user6,
      user7,
      user8,
      user9,
      user10,
    ];
    const totalReturnLotExpexted = [
      79.96903925,
      0.3615700097,
      125.9749649,
      0.5559138899,
      179.776064,
      449.44016,
      0.1806945671,
      0.5420837014,
      0.06023152238,
      0.7227782685,
    ];
    const returnInEthExpected = [
      0,
      0,
      0,
      0,
      2.140714286,
      4.852285714,
      0.5994,
      1.1988,
      0.7992,
      0.3996,
    ];

    for (let account of accounts) {
      console.log(`User ${accounts.indexOf(account) + 1}`);
      beforeClaim = await web3.eth.getBalance(account);
      beforeClaimToken = await plotusToken.balanceOf(account);
      await marketInstance.claimReturn(account);
      afterClaim = await web3.eth.getBalance(account);
      afterClaimToken = await plotusToken.balanceOf(account);
      diff = afterClaim - beforeClaim;
      diff = new BigNumber(diff);
      conv = new BigNumber(1000000000000000000);
      diff = diff / conv;
      diff = diff.toFixed(2);
      expectedInEth = returnInEthExpected[accounts.indexOf(account)].toFixed(2);
      console.log(`Returned in Eth : ${diff}  Expected : ${expectedInEth} `);
      assert.equal(diff, expectedInEth);

      diffToken = afterClaimToken - beforeClaimToken;
      diffToken = diffToken / conv;
      diffToken = diffToken.toFixed(2);
      expectedInLot = totalReturnLotExpexted[accounts.indexOf(account)].toFixed(
        2
      );
      assert.equal(diffToken, expectedInLot);
      console.log(
        `Returned in Lot : ${diffToken}  Expected : ${expectedInLot} `
      );
    }
    console.log((await web3.eth.getBalance(marketInstance.address)) / 1);
  });
});