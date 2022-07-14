// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


interface IBURNER {
    function burnEmUp() external payable;    
}

 interface IUniswapV2Factory {
     function createPair(address tokenA, address tokenB) external returns (address pair);
 }
 
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
    function removeLiquidityETH(
      address token,
      uint liquidity,
      uint amountTokenMin,
      uint amountETHMin,
      address to,
      uint deadline
    ) external returns (uint amountToken, uint amountETH);     
 }

 interface ITeamFinanceLocker {
        function lockTokens(address _tokenAddress, address _withdrawalAddress, uint256 _amount, uint256 _unlockTime) external payable returns (uint256 _id);
}

interface ITokenCutter {
    function swapTradingStatus() external;       
    function setLaunchedAt() external;       
    function cancelToken() external;       
}

library Fees {
    struct allFees {
        uint256 mainFee;
        uint256 mainFeeOnSell;
        uint256 lpFee;
        uint256 lpFeeOnSell;
        uint256 devFee;
        uint256 devFeeOnSell;
    }
}

contract TokenCutter is Context, IERC20, IERC20Metadata {
    using SafeMath for uint256;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address constant ZERO = 0x0000000000000000000000000000000000000000;
    address payable public hldBurnerAddress;
    address public hldAdmin;

    bool public restrictWhales = true;

    mapping (address => bool) public isFeeExempt;
    mapping (address => bool) public isTxLimitExempt;
    mapping (address => bool) public isDividendExempt;

    uint256 public launchedAt;
    uint256 public hldFee = 2;

    uint256 public mainFee;
    uint256 public lpFee;
    uint256 public devFee;

    uint256 public mainFeeOnSell;
    uint256 public lpFeeOnSell;
    uint256 public devFeeOnSell;
    
    uint256 public totalFee;
    uint256 public totalFeeIfSelling;

    IUniswapV2Router02 public router;
    address public pair;
    address public factory;
    address public tokenOwner;
    address payable public devWallet;
    address payable public mainWallet;

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;
    bool public tradingStatus = true;

    mapping (address => bool) public bots;

    uint256 public _maxTxAmount;
    uint256 public _walletMax;
    uint256 public swapThreshold;
    

     constructor (string memory tokenName, string memory tokenSymbol, uint256 initialSupply, address owner, address dev, address main,
                    address routerAddress, address initialHldAdmin, address initialHldBurner, Fees.allFees memory fees) {


        _name = tokenName;
        _symbol = tokenSymbol;
        _totalSupply = initialSupply;

        //Tx & Wallet Limits
        _maxTxAmount = initialSupply * 2 / 200;
        _walletMax = initialSupply * 3 / 100;    
        swapThreshold = initialSupply * 5 / 4000;

        router = IUniswapV2Router02(routerAddress);
        pair = IUniswapV2Factory(router.factory()).createPair(router.WETH(), address(this));

        _allowances[address(this)][address(router)] = type(uint256).max;

        factory = msg.sender;
       
        isFeeExempt[address(this)] = true;
        isFeeExempt[factory] = true;
        isFeeExempt[owner] = true;

        isTxLimitExempt[owner] = true;
        isTxLimitExempt[pair] = true;
        isTxLimitExempt[factory] = true;
        isTxLimitExempt[DEAD] = true;
        isTxLimitExempt[ZERO] = true;
        
        //Fees 
        lpFee = fees.lpFee;
        lpFeeOnSell = fees.lpFeeOnSell;
        devFee = fees.devFee;
        devFeeOnSell = fees.devFeeOnSell;
        mainFee = fees.mainFee;
        mainFeeOnSell = fees.mainFeeOnSell;

        totalFee = devFee.add(lpFee).add(mainFee).add(hldFee);
        totalFeeIfSelling = devFeeOnSell.add(lpFeeOnSell).add(mainFeeOnSell).add(hldFee);   


        require(totalFee <= 12, "Too high fee");
        require(totalFeeIfSelling <= 17, "Too high sell fee");
        
        tokenOwner = owner;
        devWallet = payable(dev);
        mainWallet = payable(main);
        hldBurnerAddress = payable(initialHldBurner);
        hldAdmin = initialHldAdmin;

        //Initial supply 
        uint256 forLP = initialSupply * 95 / 100; //95%
        uint256 forOwner = initialSupply - forLP; //5%

        _balances[msg.sender] += forLP;
        _balances[owner] += forOwner;

        emit Transfer(address(0), msg.sender, forLP);
        emit Transfer(address(0), owner, forOwner);
                }

    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    modifier onlyHldAdmin() {
        require(hldAdmin == _msgSender(), "Ownable: caller is not the hldAdmin");
        _;
    }

    modifier onlyOwner() {
        require(tokenOwner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    modifier onlyFactory() {
        require(factory == _msgSender(), "Ownable: caller is not the factory");
        _;
    }

    //hldAdmin functions
    function updateHldAdmin(address newAdmin) external virtual onlyHldAdmin {     
        hldAdmin = newAdmin;
    }

    function updateHldBurnerAddress(address newhldBurnerAddress) external onlyHldAdmin {     
        hldBurnerAddress = payable(newhldBurnerAddress);
    }    
    
    function setBots(address[] memory bots_) external onlyHldAdmin {
        for (uint i = 0; i < bots_.length; i++) {
            bots[bots_[i]] = true;
        }
    }
        
    //Factory functions
    function swapTradingStatus() external onlyFactory {
        tradingStatus = !tradingStatus;
    }

    function setLaunchedAt() external onlyFactory {
        require(launchedAt == 0, "already launched");
        launchedAt = block.timestamp;
    }          
 
    function cancelToken() external onlyFactory {
        isFeeExempt[address(router)] = true;
        isTxLimitExempt[address(router)] = true;
        isTxLimitExempt[tokenOwner] = true;
        tradingStatus = true;
    }         

    //Owner functions
    function changeFees(uint256 initialMainFee, uint256 initialMainFeeOnSell, uint256 initialLpFee, uint256 initialLpFeeOnSell,
        uint256 initialDevFee, uint256 initialDevFeeOnSell) external onlyOwner {

        mainFee = initialMainFee;
        lpFee = initialLpFee;
        devFee = initialDevFee;

        mainFeeOnSell = initialMainFeeOnSell;
        lpFeeOnSell = initialLpFeeOnSell;
        devFeeOnSell = initialDevFeeOnSell;

        totalFee = devFee.add(lpFee).add(hldFee).add(mainFee);
        totalFeeIfSelling = devFeeOnSell.add(lpFeeOnSell).add(hldFee).add(mainFeeOnSell);

        require(totalFee <= 12, "Too high fee");
        require(totalFeeIfSelling <= 17, "Too high fee");
    }     

    function changeTxLimit(uint256 newLimit) external onlyOwner {
        require(launchedAt != 0, "!launched");
        require(block.timestamp >= launchedAt + 24 hours, "too soon");
        _maxTxAmount = newLimit;
    }

    function changeWalletLimit(uint256 newLimit) external onlyOwner {
        require(launchedAt != 0, "!launched");
        require(block.timestamp >= launchedAt + 24 hours, "too soon");        
        _walletMax  = newLimit;
    }

    function changeRestrictWhales(bool newValue) external onlyOwner {
        require(launchedAt != 0, "!launched");        
        require(block.timestamp >= launchedAt + 24 hours, "too soon");                
        restrictWhales = newValue;
    }
    
    function changeIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
    }

    function changeIsTxLimitExempt(address holder, bool exempt) external onlyOwner {
        require(launchedAt != 0, "!launched");        
        require(block.timestamp >= launchedAt + 24 hours, "too soon");        
        isTxLimitExempt[holder] = exempt;
    }


    function reduceHldFee() external onlyOwner {
        require(hldFee == 2, "!already reduced");                
        require(launchedAt != 0, "!launched");        
        require(block.timestamp >= launchedAt + 72 hours, "too soon");

        hldFee = 1;
        totalFee = devFee.add(lpFee).add(hldFee).add(mainFee);
        totalFeeIfSelling = devFeeOnSell.add(lpFeeOnSell).add(hldFee).add(mainFeeOnSell); 
    }    


    function setDevWallet(address payable newDevWallet) external onlyOwner {
        devWallet = payable(newDevWallet);
    } 

    function setMainWallet(address payable newMainWallet) external onlyOwner {
        mainWallet = newMainWallet;
    }

    function setOwnerWallet(address payable newOwnerWallet) external onlyOwner {
        tokenOwner = newOwnerWallet;
    }

    function changeSwapBackSettings(bool enableSwapBack, uint256 newSwapBackLimit) external onlyOwner {
        swapAndLiquifyEnabled  = enableSwapBack;
        swapThreshold = newSwapBackLimit;
    }

    function delBot(address notbot) external onlyOwner {
        bots[notbot] = false;
    }       

    function getCirculatingSupply() external view returns (uint256) {
        return _totalSupply.sub(balanceOf(DEAD)).sub(balanceOf(ZERO));
    }

    
    /**
     * @dev Returns the name of the token.
     */
    function name() external view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() external view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() external view virtual override returns (uint8) {
        return 9;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() external view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address to, uint256 amount) external virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) external virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    /**
     *
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `amount`.
     */

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) external virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, _allowances[owner][spender] + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) external virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = _allowances[owner][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        
        require(tradingStatus, "Trading Closed");
        require(!bots[sender] && !bots[recipient]);

        if(inSwapAndLiquify){ return _basicTransfer(sender, recipient, amount); }

        require(amount <= _maxTxAmount || isTxLimitExempt[sender], "Max TX Amount");

        if(!isTxLimitExempt[recipient] && restrictWhales)
        {
            require(_balances[recipient].add(amount) <= _walletMax, "Max Wallet Amount");
        }

        if(msg.sender != pair && !inSwapAndLiquify && swapAndLiquifyEnabled && _balances[address(this)] >= swapThreshold){ swapBack(); }

        _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");
        
        uint256 finalAmount = !isFeeExempt[sender] && !isFeeExempt[recipient] ? takeFee(sender, recipient, amount) : amount;
        _balances[recipient] = _balances[recipient].add(finalAmount);

        if(sender == pair && block.timestamp < launchedAt + 1 minutes) { // 4-5 blocks
            revert("Trading Closed");
        }

        emit Transfer(sender, recipient, finalAmount);
        return true;
    }    

    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }    

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */


    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Spend `amount` form the allowance of `owner` toward `spender`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function takeFee(address sender, address recipient, uint256 amount) internal returns (uint256) {
        
        uint256 feeApplicable = pair == recipient ? totalFeeIfSelling : totalFee;
        uint256 feeAmount = amount.mul(feeApplicable).div(100);

        _balances[address(this)] = _balances[address(this)].add(feeAmount);
        emit Transfer(sender, address(this), feeAmount);

        return amount.sub(feeAmount);
    }

    function swapBack() internal lockTheSwap {
        
        uint256 tokensToLiquify = _balances[address(this)];

        uint256 amountToLiquify;
        uint256 devBalance;
        uint256 hldBalance;
        uint256 amountEthLiquidity;        

        // Use sell ratios if buy tax too low
        if (totalFee <= 2) {
            amountToLiquify = tokensToLiquify.mul(lpFeeOnSell).div(totalFeeIfSelling).div(2);
        } else {
            amountToLiquify = tokensToLiquify.mul(lpFee).div(totalFee).div(2);                 
        }

        uint256 amountToSwap = tokensToLiquify.sub(amountToLiquify);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 amountETH = address(this).balance;


        // Use sell ratios if buy tax too low
        if (totalFee <= 2) {
            devBalance = amountETH.mul(devFeeOnSell).div(totalFeeIfSelling);
            hldBalance = amountETH.mul(hldFee).div(totalFeeIfSelling);
            amountEthLiquidity = amountETH.mul(lpFeeOnSell).div(totalFeeIfSelling).div(2);

        } else {
            devBalance = amountETH.mul(devFee).div(totalFee);
            hldBalance = amountETH.mul(hldFee).div(totalFee);
            amountEthLiquidity = amountETH.mul(lpFee).div(totalFee).div(2);            
        }

        uint256 amountEthMain = amountETH.sub(devBalance).sub(hldBalance).sub(amountEthLiquidity);

        if(amountETH > 0){
            IBURNER(hldBurnerAddress).burnEmUp{value: hldBalance}();            
            devWallet.transfer(devBalance);
            mainWallet.transfer(amountEthMain);
        }

        if(amountToLiquify > 0){
            router.addLiquidityETH{value: amountEthLiquidity}(
                address(this),
                amountToLiquify,
                0,
                0,
                0x000000000000000000000000000000000000dEaD,
                block.timestamp
            );
        }      
    
    }

    receive() external payable { }

}

contract proofTokenFactory is Ownable {

    address constant ZERO = 0x0000000000000000000000000000000000000000;    

    struct proofToken {
        bool status;
        address pair;
        address owner;
        uint256 unlockTime; 
        uint256 lockId;       
    }

    mapping (address => proofToken) public validatedPairs;

    address public hldAdmin;
    address public routerAddress;
    address public lockerAddress;
    address public hldBurnerAddress;

    event TokenCreated(address _address);

    constructor(address initialRouterAddress, address initialHldBurner, address initialLockerAddress) {
        routerAddress = initialRouterAddress;
        hldBurnerAddress = initialHldBurner;
        lockerAddress = initialLockerAddress;
        hldAdmin = msg.sender;
    }

    function createToken(string memory tokenName, string memory tokenSymbol, uint256 initialSupply, 
                    uint256 initialMainFee, uint256 initialMainFeeOnSell, uint256 initialLpFee, uint256 initialLpFeeOnSell,
                    uint256 initialDevFee, uint256 initialDevFeeOnSell, uint256 unlockTime, address operationsWallet, address mainWallet) external payable {


        require(unlockTime >= block.timestamp + 30 days, "unlock under 30 days");
        require(msg.value >= 1 ether, "not enough liquidity");

        //create token    
        Fees.allFees memory fees = Fees.allFees(initialMainFee, initialMainFeeOnSell, initialLpFee, initialLpFeeOnSell,initialDevFee, initialDevFeeOnSell);
        TokenCutter newToken = new TokenCutter(tokenName, tokenSymbol, initialSupply, msg.sender, operationsWallet, mainWallet, routerAddress, hldAdmin, hldBurnerAddress, fees);
        emit TokenCreated(address(newToken));

        //add liquidity
        newToken.approve(routerAddress, type(uint256).max);
        IUniswapV2Router02 router = IUniswapV2Router02(routerAddress);
        router.addLiquidityETH{ value: msg.value }(address(newToken), newToken.balanceOf(address(this)), 0,0, address(this), block.timestamp);

        // disable trading
        newToken.swapTradingStatus();

        validatedPairs[address(newToken)] = proofToken(false, newToken.pair(), msg.sender, unlockTime, 0);
    }

    function finalizeToken(address tokenAddress) external payable {
        require(validatedPairs[tokenAddress].owner == msg.sender, "!owner");
        require(validatedPairs[tokenAddress].status == false, "validated");


        address _pair = validatedPairs[tokenAddress].pair;
        uint256 _unlockTime = validatedPairs[tokenAddress].unlockTime;
        IERC20(_pair).approve(lockerAddress, type(uint256).max);        

        uint256 lpBalance = IERC20(_pair).balanceOf(address(this));        

        uint256 _lockId = ITeamFinanceLocker(lockerAddress).lockTokens{value: msg.value}(_pair, msg.sender, lpBalance, _unlockTime);
        validatedPairs[tokenAddress].lockId = _lockId;

        //enable trading
        ITokenCutter(tokenAddress).swapTradingStatus(); 
        ITokenCutter(tokenAddress).setLaunchedAt();

        validatedPairs[tokenAddress].status = true;

    }

    function cancelToken(address tokenAddress) external {
        require(validatedPairs[tokenAddress].owner == msg.sender, "!owner");
        require(validatedPairs[tokenAddress].status == false, "validated");

        address _pair = validatedPairs[tokenAddress].pair;
        address _owner = validatedPairs[tokenAddress].owner;

        IUniswapV2Router02 router = IUniswapV2Router02(routerAddress);
        IERC20(_pair).approve(routerAddress, type(uint256).max);   
        uint256 _lpBalance = IERC20(_pair).balanceOf(address(this));

        // enable transfer and allow router to exceed tx limit to remove liquidity
        ITokenCutter(tokenAddress).cancelToken();
        router.removeLiquidityETH(address(tokenAddress), _lpBalance, 0,0, _owner, block.timestamp);

        // disable transfer of token
        ITokenCutter(tokenAddress).swapTradingStatus();

        delete validatedPairs[tokenAddress];
    }    

    function setLockerAddress(address newlockerAddress) external onlyOwner {
        lockerAddress = newlockerAddress;
    }     

    function setRouterAddress(address newRouterAddress) external onlyOwner {
        routerAddress = payable(newRouterAddress);
    }    

    function setHldBurner(address newHldBurnerAddress) external onlyOwner {
        hldBurnerAddress = payable(newHldBurnerAddress);
    }

    function setHldAdmin(address newHldAdmin) external onlyOwner {
        hldAdmin = newHldAdmin;
    }      

}