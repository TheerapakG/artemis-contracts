pragma solidity 0.6.12;

//import "@openzeppelin/contracts/math/SafeMath.sol";
//import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
//import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
//import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';

import "github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.1.0/contracts/access/Ownable.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.1.0/contracts/token/ERC20/SafeERC20.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.1.0/contracts/utils/Pausable.sol";
import "github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.1.0/contracts/utils/ReentrancyGuard.sol";

contract IFOwithCollateral is ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;   // How many tokens the user has provided.
        bool claimed;  // default false
        bool hasCollateral; // default false
    }

    // admin address
    address public adminAddress;
    // The raising token
    IERC20 public lpToken;
    // The offering token
    IERC20 public offeringToken;
    // The block number when IFO starts
    uint256 public startBlock;
    // The block number when IFO ends
    uint256 public endBlock;
    // total amount of raising tokens need to be raised
    uint256 public raisingAmount;
    // total amount of offeringToken that will offer
    uint256 public offeringAmount;
    // total amount of raising tokens that have already raised
    uint256 public totalAmount;
    // 0
    uint256 public totalAdminLpWithdrawn = 0;
    uint public COLLATERAL_LOCKED_PERIOD = 604800; // 14 days
    // delay for 2 weeks
    uint delayForFullSweep;
    // The Collateral Token
    IERC20 public collateralToken;

    // The required collateral amount
    uint256 public requiredCollateralAmount;
    // address => amount
    mapping (address => UserInfo) public userInfo;
    // participators
    address[] public addressList;


    event Deposit(address indexed user, uint256 amount);
    event DepositCollateral(address indexed user, uint256 amount);
    event Harvest(address indexed user, uint256 offeringAmount, uint256 excessAmount);

    constructor(
        IERC20 _lpToken,
        IERC20 _offeringToken,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _offeringAmount,
        uint256 _raisingAmount,
        address _adminAddress,
        IERC20 _collateralToken,
        uint256 _requiredCollateralAmount
    ) public {
        lpToken = _lpToken;
        offeringToken = _offeringToken;
        startBlock = _startBlock;
        endBlock = _endBlock;
        offeringAmount = _offeringAmount;
        raisingAmount= _raisingAmount;
        totalAmount = 0;
        adminAddress = _adminAddress;
        collateralToken = _collateralToken;
        requiredCollateralAmount = _requiredCollateralAmount;
    }

    modifier onlyAdmin() {
        require(msg.sender == adminAddress, "admin: wut?");
        _;
    }

    function setOfferingAmount(uint256 _offerAmount) public onlyAdmin {
        require (block.number < startBlock, 'not ifo time');
        offeringAmount = _offerAmount;
    }

    function setRaisingAmount(uint256 _raisingAmount) public onlyAdmin {
        require (block.number < startBlock, 'not ifo time');
        raisingAmount= _raisingAmount;
    }

    function setStartBlock(uint256 _startBlock) public onlyAdmin {
        require (block.number < startBlock, 'not ifo time');
        startBlock= _startBlock;
    }

    function setEndBlock(uint256 _endBlock) public onlyAdmin {
        require (block.number < startBlock, 'not ifo time');
        endBlock= _endBlock;
    }

    function setLpToken(IERC20 _lpToken) public onlyAdmin {
        require (block.number < startBlock, 'not ifo time');
        lpToken= _lpToken;
    }

    function setOfferingToken(IERC20 _offeringToken) public onlyAdmin {
        require (block.number < startBlock, 'not ifo time');
        offeringToken= _offeringToken;
    }

    function depositCollateral() public {
        require (block.number > startBlock && block.number < endBlock, 'not ifo time');
        require (!userInfo[msg.sender].hasCollateral, 'user already staked collateral');

        uint256 collateral_amount = collateralToken.balanceOf(msg.sender);
        require(collateral_amount >= requiredCollateralAmount, "depositCollateral:insufficient collateral");

        // collateralTokens with transfer-tax are NOT supported.
        collateralToken.safeTransferFrom(msg.sender, address(this), requiredCollateralAmount);
        userInfo[msg.sender].hasCollateral = true;

        emit DepositCollateral(msg.sender, requiredCollateralAmount);
    }

    function deposit(uint256 _amount) public {
        require (block.number > startBlock && block.number < endBlock, 'not ifo time');
        require (_amount > 0, 'need _amount > 0');
        require (userInfo[msg.sender].hasCollateral, 'user needs to stake collateral first');

        lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        if (userInfo[msg.sender].amount == 0) {
            addressList.push(address(msg.sender));
        }
        userInfo[msg.sender].amount = userInfo[msg.sender].amount.add(_amount);
        totalAmount = totalAmount.add(_amount);
        emit Deposit(msg.sender, _amount);
    }

    function harvest() public nonReentrant {
        // Can only be called once for each user
        // Will refund Collateral, give IFO token, and return an overflow lpToken
        require (block.number > endBlock, 'not harvest time');
        require (!userInfo[msg.sender].claimed, 'already claimed');
        uint256 offeringTokenAmount = getOfferingAmount(msg.sender);
        uint256 refundingTokenAmount = getRefundingAmount(msg.sender);

        collateralToken.safeTransfer(address(msg.sender), requiredCollateralAmount);
        if (offeringTokenAmount > 0) {
            offeringToken.safeTransfer(address(msg.sender), offeringTokenAmount);
        }
        if (refundingTokenAmount > 0) {
            lpToken.safeTransfer(address(msg.sender), refundingTokenAmount);
        }
        userInfo[msg.sender].claimed = true;
        emit Harvest(msg.sender, offeringTokenAmount, refundingTokenAmount);
    }

    function hasHarvest(address _user) external view returns(bool) {
        return userInfo[_user].claimed;
    }

    function hasCollateral(address _user) external view returns(bool) {
        return userInfo[_user].hasCollateral;
    }

    // allocation 100000 means 0.1(10%), 1 meanss 0.000001(0.0001%), 1000000 means 1(100%)
    function getUserAllocation(address _user) public view returns(uint256) {
        return userInfo[_user].amount.mul(1e12).div(totalAmount).div(1e6);
    }

    // get the amount of IFO token you will get
    function getOfferingAmount(address _user) public view returns(uint256) {
        if (userInfo[_user].amount <= 0) {
            return 0;
        }
        if (totalAmount > raisingAmount) {
            uint256 allocation = getUserAllocation(_user);
            return offeringAmount.mul(allocation).div(1e6);
        }
        else {
            // userInfo[_user] / (raisingAmount / offeringAmount)
            return userInfo[_user].amount.mul(offeringAmount).div(raisingAmount);
        }
    }

    // get the amount of lp token you will be refunded
    function getRefundingAmount(address _user) public view returns(uint256) {
        if (userInfo[_user].amount <= 0) {
            return 0;
        }
        if (totalAmount <= raisingAmount) {
            return 0;
        }
        uint256 allocation = getUserAllocation(_user);
        uint256 payAmount = raisingAmount.mul(allocation).div(1e6);
        return userInfo[_user].amount.sub(payAmount);
    }

    function getAddressListLength() external view returns(uint256) {
        return addressList.length;
    }

    function finalWithdraw(uint256 _lpAmount) public onlyAdmin {  // uint256 _offerAmount
        if (block.number < endBlock + delayForFullSweep) {
            // Only check this condition for the first 14 days after IFO
            require (_lpAmount + totalAdminLpWithdrawn <= raisingAmount, 'withdraw exceeds raisingAmount');
        }
        require (_lpAmount < lpToken.balanceOf(address(this)), 'not enough token 0');
        lpToken.safeTransfer(address(msg.sender), _lpAmount);
        totalAdminLpWithdrawn = totalAdminLpWithdrawn + _lpAmount;
    }


    function retrieveCollateral() external nonReentrant {
        require(block.number >= endBlock.add(COLLATERAL_LOCKED_PERIOD), 'collateral still locked');
        require(userInfo[msg.sender].hasCollateral, 'User has no collateral');
        userInfo[msg.sender].hasCollateral = false;
        collateralToken.safeTransfer(msg.sender, requiredCollateralAmount);
    }

    function changeRequiredCollateralAmount(uint256 _newCollateralAmount) public onlyAdmin returns (bool) {
        uint256 oldCollateralAmount = requiredCollateralAmount;
        requiredCollateralAmount = _newCollateralAmount;
        emit RequiredCollateralChanged(
            address(collateralToken),
            requiredCollateralAmount,
            oldCollateralAmount
        );
    }
    event RequiredCollateralChanged(
        address collateralToken,
        uint256 newRequiredCollateral,
        uint256 oldRequiredCollateral
    );

}
