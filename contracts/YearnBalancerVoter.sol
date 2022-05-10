pragma solidity ^0.6.0;

import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";

interface Controller {
    function vaults(address) external view returns (address);
    function rewards() external view returns (address);
}

interface Gauge {
    function deposit(uint) external;
    function balanceOf(address) external view returns (uint);
    function withdraw(uint) external;
}

interface Mintr {
    function mint(address) external;
}

interface VoteEscrow {
    function create_lock(uint, uint) external;
    function increase_amount(uint) external;
    function withdraw() external;
}

contract YearnBalancerVoter {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    
    address constant public mintr = address(0x239e55F427D44C3cc793f49bFB507ebe76638a2b);
    address constant public bal = address(0xba100000625a3754423978a60c9317c58a424e3D);
    address constant public balLP = address(0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56);
    address constant public escrow = address(0xC128a9954e6c874eA3d62ce62B468bA073093F25);
    
    address public governance;
    address public proxy;
    
    constructor() public {
        governance = msg.sender;
    }
    
    function getName() external pure returns (string memory) {
        return "YearnBalancerVoter";
    }
    
    function setProxy(address _proxy) external {
        require(msg.sender == governance, "!governance");
        proxy = _proxy;
    }
    
    // Controller only function for creating additional rewards from dust
    function withdraw(IERC20 _asset) external returns (uint balance) {
        require(msg.sender == proxy, "!controller");
        balance = _asset.balanceOf(address(this));
        _asset.safeTransfer(proxy, balance);
    }
    
    function createLock(uint _value, uint _unlockTime) external {
        require(msg.sender == proxy || msg.sender == governance, "!authorized");
        IERC20(bal).safeApprove(escrow, 0);
        IERC20(bal).safeApprove(escrow, _value);
        VoteEscrow(escrow).create_lock(_value, _unlockTime);
    }
    
    function increaseAmount(uint _value) external {
        require(msg.sender == proxy || msg.sender == governance, "!authorized");
        IERC20(bal).safeApprove(escrow, 0);
        IERC20(bal).safeApprove(escrow, _value);
        VoteEscrow(escrow).increase_amount(_value);
    }
    
    function release() external {
        require(msg.sender == proxy || msg.sender == governance, "!authorized");
        VoteEscrow(escrow).withdraw();
    }
    
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }
    
    function execute(address to, uint value, bytes calldata data) external returns (bool, bytes memory) {
        require(msg.sender == proxy || msg.sender == governance, "!governance");
        (bool success, bytes memory result) = to.call.value(value)(data);
        
        return (success, result);
    }
}