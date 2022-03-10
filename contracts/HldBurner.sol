// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

 interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
     function factory() external pure returns (address);
     function WETH() external pure returns (address);
     function addLiquidityETH(
         address token,
         uint amountTokenDesired,
         uint amountTokenMin,
         uint amountETHMin,
         address to,
         uint deadline
     ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
 }
 

contract hldBurner is Ownable {
    using SafeMath for uint256;

    address public hldToken;
    IUniswapV2Router02 router;

    uint256 public burnThreshold = 5 *(10 ** 16);
    
    constructor(address _token, address _router){
    	hldToken = _token;
        router = IUniswapV2Router02(_router);    	
    }
    

    function _burnTokens(uint256 ethBalance) internal {
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = hldToken;

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethBalance}(
            0,
            path,
            0x000000000000000000000000000000000000dEaD,
            block.timestamp
        ); 
    }
    function changeToken(address _token) public virtual onlyOwner {
    	hldToken = _token;
    }

    function changeBurnThreshold(uint256 _burnThreshold)  public virtual onlyOwner {
    	burnThreshold = _burnThreshold;
    }

    function changeRouter(address _router)  public virtual onlyOwner {
        router = IUniswapV2Router02(_router);
    }

    function withdrawEth()  public virtual onlyOwner {
		payable(msg.sender).transfer(address(this).balance);
    }

    function burnEmUp()  external payable virtual  {
        uint256 ethBalance = address(this).balance;
        if (ethBalance >= burnThreshold) {
            _burnTokens(ethBalance);
        }
    }

    receive() external payable {
        uint256 ethBalance = address(this).balance;
        if (ethBalance >= burnThreshold) {
       	    _burnTokens(ethBalance);
        }
    }

}

