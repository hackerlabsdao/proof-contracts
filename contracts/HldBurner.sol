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
    address payable public devWallet;
    address payable public daoWallet;
    uint256 public devFee = 0;
    uint256 public daoFee = 0;
    uint256 public burnFee = 1;    
    uint256 public totalFee = 1;

    IUniswapV2Router02 router;

    uint256 public burnThreshold = 5 *(10 ** 16);
    
    constructor(address _token, address _router){
        hldToken = _token;
        daoWallet = payable(msg.sender);
        devWallet = payable(msg.sender);
        router = IUniswapV2Router02(_router);       
    }
    

    function _burnTokens(uint256 ethBalance) internal {
        uint256 amountETH = address(this).balance;
        uint256 devBalance = amountETH.mul(devFee).div(totalFee);
        uint256 daoBalance = amountETH.mul(daoFee).div(totalFee);
        uint256 burnBalance = amountETH.sub(devBalance).sub(daoBalance);

        devWallet.transfer(devBalance);
        daoWallet.transfer(daoBalance);

        if (burnBalance > 0) {
            address[] memory path = new address[](2);
            path[0] = router.WETH();
            path[1] = hldToken;

            router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: burnBalance}(
                0,
                path,
                0x000000000000000000000000000000000000dEaD,
                block.timestamp
            );             
        }

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

    function changeFees(uint256 newDevFee, uint256 newDaoFee, uint256 newBurnFee) external onlyOwner {
        devFee = newDevFee;
        daoFee = newDaoFee;
        burnFee = newBurnFee;

        totalFee = devFee.add(daoFee).add(burnFee);
    }

    function changeDevWallet(address payable newDevWallet) external onlyOwner {
        devWallet = payable(newDevWallet);
    } 

    function changeDaoWallet(address payable newDaoWallet) external onlyOwner {
        daoWallet = payable(newDaoWallet);
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

