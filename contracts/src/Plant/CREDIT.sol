// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "../interfaces/ICREDIT.sol";
import "../interfaces/IUniswap.sol";
import "./PlantNFT.sol";
import "../Tree/TreeNFT.sol";
import "../Tree/Types.sol";

contract CREDIT is IERC20, ICREDIT, Ownable {
    string public constant name = "CREDIT";
    string public constant symbol = "CRTT";
    uint8 public constant decimals = 18;
    uint256 public totalSupply = 1000;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    IERC20 public immutable WETH;
    IERC20 public immutable USDC;

    IUniswapV2Router02 public immutable router;
    address public immutable pair;

    PlantNFT public plantNft;
    TreeNFT public treeNft;
    address private plantNFTAddress;
    address private treeNFTAddress;

    uint256 public maxWallet = type(uint256).max;

    mapping(address => bool) public isTransferExempt;
    mapping(address => bool) public isFeeExempt;
    mapping(address => bool) public isMaxExempt;
    mapping(address => bool) public isUniswapPair;

    // Fees are charged on swaps
    Types.FeeRecipients public feeRecipients;
    Types.Fees public fees;
    uint16 public feeTotal = 350;

    // Taxes are charged on transfers 
    uint16 public tax = 300;

    // Basis for all fee and tax values
    uint16 public constant bps = 10_000;

    bool public contractSellEnabled = true;
    uint256 public contractSellThreshold = 65e18;
    uint256 public minSwapAmountToTriggerContractSell = 0;

    bool public mintingEnabled = true;
    bool public burningEnabled = true;
    bool public tradingEnabled = false;
    bool public isContractSelling = false;

    modifier contractSelling() {
        isContractSelling = true;
        _;
        isContractSelling = false;
    }

    constructor(
        address _usdc
    ) {
        router = IUniswapV2Router02(0xD99D1c33F9fC3444f8101754aBC46c52416550D1); // pancakeswap router address 
        USDC = IERC20(_usdc);

        pair = IUniswapV2Factory(router.factory()).createPair(address(USDC), address(this));

        WETH = IERC20(router.WETH());

        plantNft = new PlantNFT(this, router, USDC, msg.sender);
        treeNft = new TreeNFT(this, router, USDC, msg.sender);
        plantNFTAddress = address(plantNft);
        treeNFTAddress = address(treeNft);

        isTransferExempt[msg.sender] = true;
        isFeeExempt[msg.sender] = true;
        isMaxExempt[msg.sender] = true;
        //plantNFT
        isTransferExempt[plantNFTAddress] = true;
        isFeeExempt[plantNFTAddress] = true;
        isMaxExempt[plantNFTAddress] = true;
        //treeNFT
        isTransferExempt[treeNFTAddress] = true;
        isFeeExempt[treeNFTAddress] = true;
        isMaxExempt[treeNFTAddress] = true;
        isTransferExempt[address(0)] = true;
        isFeeExempt[address(0)] = true;
        isMaxExempt[address(0)] = true;
        isMaxExempt[address(this)] = true;
        isUniswapPair[pair] = true;

        allowance[address(this)][address(router)] = type(uint256).max;

        feeRecipients = Types.FeeRecipients(
            0xc766B8c9741BC804FCc378FdE75560229CA3AB1E, // operation 
            0x682Ce32507D2825A540Ad31dC4C2B18432E0e5Bd, // development
            0x9f27d8958B96B7Ecf3117184A252DC8d2bb7463D //marketing
        );

        fees = Types.Fees(100,100,150);

        uint256 toEmissions = 200;
        uint256 toDeployer = totalSupply - toEmissions - toEmissions;

        balanceOf[msg.sender] = toDeployer;
        emit Transfer(address(0), msg.sender, toDeployer);

        balanceOf[plantNFTAddress] = toEmissions;
        balanceOf[treeNFTAddress] = toEmissions;
        emit Transfer(address(0), plantNFTAddress, toEmissions);
        emit Transfer(address(0), treeNFTAddress, toEmissions);
    }

    function mintCredits(uint256 _amount) external onlyOwner {
        require(mintingEnabled, "Minting is disabled");

        totalSupply += _amount;
        unchecked {
            balanceOf[msg.sender] += _amount;
        }
        emit Transfer(address(0), msg.sender, _amount);
    }

    function burnCredits(address _burnee, uint256 _amount) external onlyOwner returns (bool) {
        require(burningEnabled, "Burning is disabled");
        require(balanceOf[_burnee] >= _amount, "Cannot burn more than an account has");

        totalSupply -= _amount;

        balanceOf[_burnee] -= _amount;
        emit Transfer(_burnee, address(0), _amount);
        return true;
    }

    function burnForseedPlantNFT(address _burnee, uint256 _amount) external returns (bool) {
        require(msg.sender == address(plantNft), "Only the  Plant NFT contract can burn");
        require(balanceOf[_burnee] >= _amount, "Cannot burn more than an account has");

        uint256 allowed = allowance[_burnee][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[_burnee][msg.sender] = allowed - _amount;
        }

        totalSupply -= _amount;

        balanceOf[_burnee] -= _amount;
        emit Transfer(_burnee, address(0), _amount);
        return true;
    }

    function burnForseedTreeNFT(address _burnee, uint256 _amount) external returns (bool) {
        require(msg.sender == address(treeNft), "Only the  Tree NFT contract can burn");
        require(balanceOf[_burnee] >= _amount, "Cannot burn more than an account has");

        uint256 allowed = allowance[_burnee][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[_burnee][msg.sender] = allowed - _amount;
        }

        totalSupply -= _amount;

        balanceOf[_burnee] -= _amount;
        emit Transfer(_burnee, address(0), _amount);
        return true;
    }

    function approve(address _spender, uint256 _amount) public override returns (bool) {
        allowance[msg.sender][_spender] = _amount;
        emit Approval(msg.sender, _spender, _amount);
        return true;
    }

    function transfer(address _recipient, uint256 _amount) external override returns (bool) {
        return _transferFrom(msg.sender, _recipient, _amount);
    }

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external override returns (bool) {
        uint256 allowed = allowance[_sender][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[_sender][msg.sender] = allowed - _amount;
        }

        return _transferFrom(_sender, _recipient, _amount);
    }

    function _transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) private returns (bool) {
        if (isContractSelling) {
            return _simpleTransfer(_sender, _recipient, _amount);
        }

        require(tradingEnabled || isTransferExempt[_sender], "Trading is currently disabled");

        bool sell = isUniswapPair[_recipient] || _recipient == address(router);

        if (!sell && !isMaxExempt[_recipient]) {
            require((balanceOf[_recipient] + _amount) <= maxWallet, "Max wallet has been triggered");
        }

        if (
            sell &&
            _amount >= minSwapAmountToTriggerContractSell &&
            !isUniswapPair[msg.sender] &&
            !isContractSelling &&
            contractSellEnabled &&
            balanceOf[address(this)] >= contractSellThreshold
        ) {
            _contractSell();
        }

        balanceOf[_sender] -= _amount;

        uint256 amountAfter = _amount;
        if (
            ((isUniswapPair[_sender] || _sender == address(router)) ||
                (isUniswapPair[_recipient] || _recipient == address(router)))
                ? !isFeeExempt[_sender] && !isFeeExempt[_recipient]
                : false
        ) {
            amountAfter = _collectFee(_sender, _amount);
        } else if (!isFeeExempt[_sender] && !isFeeExempt[_recipient]) {
            amountAfter = _collectTax(_sender, _amount);
        }

        unchecked {
            balanceOf[_recipient] += amountAfter;
        }
        emit Transfer(_sender, _recipient, amountAfter);

        return true;
    }

    function _simpleTransfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) private returns (bool) {
        balanceOf[_sender] -= _amount;
        unchecked {
            balanceOf[_recipient] += _amount;
        }
        return true;
    }

    function _contractSell() private contractSelling {
        uint256 ethBefore = address(this).balance;

        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = address(USDC);
        path[2] = address(WETH);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            balanceOf[address(this)],
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 ethAfter = address(this).balance - ethBefore;

        if (ethAfter > bps) {
            bool success;
            (success, ) = feeRecipients.operationTeam.call{value: (ethAfter * fees.operations) / bps}("");
            require(success, "Could not send ETH");
            (success, ) = feeRecipients.developmentTeam.call{value: (ethAfter * fees.development) / bps}(
                ""
            );
            require(success, "Could not send ETH");
            (success, ) = feeRecipients.marketingTeam.call{value: (ethAfter * fees.marketing) / bps}("");
            require(success, "Could not send ETH");
            
        }
    }

    function _collectFee(address _sender, uint256 _amount) private returns (uint256) {
        uint256 feeAmount = (_amount * feeTotal) / bps;

        unchecked {
            balanceOf[address(this)] += feeAmount;
        }
        emit Transfer(_sender, address(this), feeAmount);

        return _amount - feeAmount;
    }

    function _collectTax(address _sender, uint256 _amount) private returns (uint256) {
        uint256 taxAmount = (_amount * tax) / bps;

        totalSupply -= taxAmount;

        emit Transfer(_sender, address(0), _amount);

        return _amount - taxAmount;
    }

    function setMaxWallet(uint256 _maxWallet) external onlyOwner {
        maxWallet = _maxWallet;
    }

    function setIsTransferExempt(address _holder, bool _exempt) external onlyOwner {
        isTransferExempt[_holder] = _exempt;
    }

    function setIsFeeExempt(address _holder, bool _exempt) external onlyOwner {
        isFeeExempt[_holder] = _exempt;
    }

    function setIsMaxExempt(address _holder, bool _exempt) external onlyOwner {
        isMaxExempt[_holder] = _exempt;
    }

    function setIsUniswapPair(address _pair, bool _isPair) external onlyOwner {
        isUniswapPair[_pair] = _isPair;
    }

    function setContractSelling(
        bool _contractSellEnabled,
        uint256 _contractSellThreshold,
        uint256 _minSwapAmountToTriggerContractSell
    ) external onlyOwner {
        contractSellEnabled = _contractSellEnabled;
        contractSellThreshold = _contractSellThreshold;
        minSwapAmountToTriggerContractSell = _minSwapAmountToTriggerContractSell;
    }

    function setFees(Types.Fees calldata _fees) external onlyOwner {
        fees = _fees;

        feeTotal =
            _fees.operations +
            _fees.development +
            _fees.marketing;
    }

    function setFeeRecipients(Types.FeeRecipients calldata _feeRecipients) external onlyOwner {
        feeRecipients = _feeRecipients;
    }

    function setTax(uint16 _tax) external onlyOwner {
        tax = _tax;
    }

    function setTradingEnabled(bool _enabled) external onlyOwner {
        tradingEnabled = _enabled;
    }

    function setPlantNft(PlantNFT _plantNft) external onlyOwner {
        plantNft = _plantNft;
        plantNFTAddress = address(plantNft);

        isTransferExempt[plantNFTAddress] = true;
        isFeeExempt[plantNFTAddress] = true;
        isMaxExempt[plantNFTAddress] = true;
    }

    function setTreeNft(TreeNFT _treeNft) external onlyOwner {
        treeNft = _treeNft;
        treeNFTAddress = address(treeNft);

        isTransferExempt[treeNFTAddress] = true;
        isFeeExempt[treeNFTAddress] = true;
        isMaxExempt[treeNFTAddress] = true;
    }

    function permanentlyDisableMinting() external onlyOwner {
        mintingEnabled = false;
    }

    function permanentlyDisableBurning() external onlyOwner {
        burningEnabled = false;
    }

    function withdrawETH(address _recipient) external onlyOwner {
        (bool success, ) = _recipient.call{value: address(this).balance}("");
        require(success, "Could not send ETH");
    }

    function withdrawToken(IERC20 _token, address _recipient) external onlyOwner {
        _token.transfer(_recipient, _token.balanceOf(address(this)));
    }

    receive() external payable {}
}
