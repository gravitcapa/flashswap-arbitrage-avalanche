// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

import "@traderjoe-xyz/core/contracts/interfaces/IERC20.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeCallee.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/libraries/JoeLibrary.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoePair.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/libraries/TransferHelper.sol";

import '@pangolindex/exchange-contracts/contracts/pangolin-periphery/interfaces/IPangolinRouter.sol';

import "hardhat/console.sol";

contract FlashSwapJoePango is IJoeCallee {
  address immutable joeFactory;

  uint constant deadline = 30000 days;
  IPangolinRouter immutable pangolinRouter;

  constructor(address _pangolinRouter, address _joeFactory) public {
    joeFactory = _joeFactory;
    pangolinRouter = IPangolinRouter(_pangolinRouter);
  }
    // gets tokens/WAVAX via Pangolin flash swap, swaps for the WAVAX/tokens on Pangolin, repays Joe, and keeps the rest!
  function joeCall(address _sender, uint _amount0, uint _amount1, bytes calldata _data) external override {
      address sender = _sender;
      address[] memory joePath = new address[](2);
      address[] memory pangolinPath = new address[](2);

      uint amountToken = _amount0 == 0 ? _amount1 : _amount0;
      
      address token0 = IJoePair(msg.sender).token0(); // fetch the address of token0 AVAX
      address token1 = IJoePair(msg.sender).token1(); // fetch the address of token1 USDT

      require(msg.sender == JoeLibrary.pairFor(joeFactory, token0, token1), "Unauthorized"); 
      require(_amount0 == 0 || _amount1 == 0);

      joePath[0] = _amount0 == 0 ? token0 : token1;
      joePath[1] = _amount0 == 0 ? token1 : token0;

      pangolinPath[0] = _amount0 == 0 ? token1 : token0;
      pangolinPath[1] = _amount0 == 0 ? token0 : token1;

      IERC20 token = IERC20(_amount0 == 0 ? token1 : token0);
      IERC20 partnerToken = IERC20(_amount0 == 0 ? token0 : token1);
      
      token.approve(address(pangolinRouter), amountToken);

      // no need for require() check, if amount required is not sent pangolinRouter will revert

      uint amountRequired = JoeLibrary.getAmountsIn(joeFactory, amountToken, joePath)[0];

      uint amountReceived = pangolinRouter.swapExactTokensForTokens(amountToken, amountRequired, pangolinPath, address(this), deadline)[1];
      console.log('Amount Received', amountReceived);
      assert(amountReceived > amountRequired); // fail if we didn't get enough tokens back to repay our flash loan

      console.log('Profit should be', amountReceived - amountRequired);

      uint balance = partnerToken.balanceOf(msg.sender);
      console.log('Partner Token Balance Pango', balance);

      balance = partnerToken.balanceOf(address(this));
      console.log('Partner Token Balance Contract', balance);

      TransferHelper.safeTransfer(address(partnerToken), msg.sender, amountRequired); // return tokens to Pangolin pair
      TransferHelper.safeTransfer(address(partnerToken), sender, amountReceived - amountRequired); // PROFIT!!!

      balance = partnerToken.balanceOf(address(this));
      console.log('Contract Token Balance after Profit withdrawn', balance);
      balance = partnerToken.balanceOf(sender);
      console.log('My Token Balance after Profit', balance);
  }
}