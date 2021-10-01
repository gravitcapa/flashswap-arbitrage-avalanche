// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

import "@pangolindex/exchange-contracts/contracts/pangolin-core/interfaces/IERC20.sol";
import "@pangolindex/exchange-contracts/contracts/pangolin-core/interfaces/IPangolinCallee.sol";
import "@pangolindex/exchange-contracts/contracts/pangolin-periphery/libraries/PangolinLibrary.sol";
import "@pangolindex/exchange-contracts/contracts/pangolin-core/interfaces/IPangolinPair.sol";
import "@pangolindex/exchange-contracts/contracts/pangolin-lib/libraries/TransferHelper.sol";

import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeRouter02.sol";

import "hardhat/console.sol";

contract FlashSwapPangoJoe is IPangolinCallee {
  address immutable pangolinFactory;

  uint constant deadline = 30000 days;
  IJoeRouter02 immutable joeRouter;

  constructor(address _joeRouter, address _pangolinFactory) public {
    pangolinFactory = _pangolinFactory;
    joeRouter = IJoeRouter02(_joeRouter);
  }
    // gets tokens/WAVAX via Pangolin flash swap, swaps for the WAVAX/tokens on Joe, repays Pangolin, and keeps the rest!
  function pangolinCall(address _sender, uint _amount0, uint _amount1, bytes calldata _data) external override {
      address sender = _sender;
      address[] memory pangoPath = new address[](2);
      address[] memory joePath = new address[](2);

      uint amountToken = _amount0 == 0 ? _amount1 : _amount0;
      
      address token0 = IPangolinPair(msg.sender).token0(); // fetch the address of token0 AVAX
      address token1 = IPangolinPair(msg.sender).token1(); // fetch the address of token1 USDT

      require(msg.sender == PangolinLibrary.pairFor(pangolinFactory, token0, token1), "Unauthorized"); 
      require(_amount0 == 0 || _amount1 == 0);

      pangoPath[0] = _amount0 == 0 ? token0 : token1;
      pangoPath[1] = _amount0 == 0 ? token1 : token0;

      joePath[0] = _amount0 == 0 ? token1 : token0;
      joePath[1] = _amount0 == 0 ? token0 : token1;

      IERC20 token = IERC20(_amount0 == 0 ? token1 : token0);
      IERC20 partnerToken = IERC20(_amount0 == 0 ? token0 : token1);
      
      token.approve(address(joeRouter), amountToken);

      // no need for require() check, if amount required is not sent pangolinRouter will revert

      uint amountRequired = PangolinLibrary.getAmountsIn(pangolinFactory, amountToken, pangoPath)[0];

      uint amountReceived = joeRouter.swapExactTokensForTokens(amountToken, amountRequired, joePath, address(this), deadline)[1];
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