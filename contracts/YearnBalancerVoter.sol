pragma solidity ^0.6.5;
pragma experimental ABIEncoderV2;

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

interface IBalancerPool is IERC20 {
    function getPoolId() external view returns (bytes32 poolId);
}

interface IBalancerVault {
    enum JoinKind {INIT, EXACT_TOKENS_IN_FOR_BPT_OUT, TOKEN_IN_FOR_EXACT_BPT_OUT, ALL_TOKENS_IN_FOR_EXACT_BPT_OUT}
    enum ExitKind {EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, EXACT_BPT_IN_FOR_TOKENS_OUT, BPT_IN_FOR_EXACT_TOKENS_OUT}

    // enconding formats https://github.com/balancer-labs/balancer-v2-monorepo/blob/master/pkg/balancer-js/src/pool-weighted/encoder.ts
    struct JoinPoolRequest {
        address[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    struct ExitPoolRequest {
        address[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable;

    function exitPool(
        bytes32 poolId,
        address sender,
        address payable recipient,
        ExitPoolRequest calldata request
    ) external;
}

contract YearnBalancerVoter {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    
    address constant private weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address constant public mintr = address(0x239e55F427D44C3cc793f49bFB507ebe76638a2b);
    address constant public bal = address(0xba100000625a3754423978a60c9317c58a424e3D);
    address constant public balLP = address(0x5c6Ee304399DBdB9C8Ef030aB642B10820DB8F56);
    address constant public escrow = address(0xC128a9954e6c874eA3d62ce62B468bA073093F25);
    
    address public governance;
    address public proxy;
    IBalancerVault public constant bVault = IBalancerVault(0x20dd72Ed959b6147912C2e529F0a0C651c33c9ce);
    IBalancerPool public constant stakeLp = IBalancerPool(0xcdE5a11a4ACB4eE4c805352Cec57E236bdBC3837);
    address[] internal assets;
    
    constructor() public {
        governance = msg.sender;
        assets = [address(weth), address(bal)];
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
    
    function createLock(uint _value, uint _unlockTime, bool _convert) external {
        require(msg.sender == proxy || msg.sender == governance, "!authorized");
        if (_convert){
            uint _balAmount = IERC20(bal).balanceOf(address(this));
            _convertBAL(_balAmount, true);
        }
        IERC20(balLP).safeApprove(escrow, 0);
        IERC20(balLP).safeApprove(escrow, _value);
        VoteEscrow(escrow).create_lock(_value, _unlockTime);
    }
    
    function increaseAmountMax(bool _convert) external {
        require(msg.sender == proxy || msg.sender == governance, "!authorized");
        if (_convert){
            uint _balAmount = IERC20(bal).balanceOf(address(this));
            if(_balAmount > 0){
                _convertBAL(_balAmount, true);
            }
        }
        uint lpAmount = IERC20(balLP).balanceOf(address(this));
        IERC20(balLP).safeApprove(escrow, 0);
        IERC20(balLP).safeApprove(escrow, lpAmount);
        VoteEscrow(escrow).increase_amount(lpAmount);
    }

    function increaseAmountExact(uint _amount, bool _convert) external {
        require(msg.sender == proxy || msg.sender == governance, "!authorized");
        if (_convert){
            uint _balAmount = IERC20(bal).balanceOf(address(this));
            if(_balAmount > 0){
                _convertBAL(_balAmount, true);
            }
        }
        uint lpAmount = IERC20(balLP).balanceOf(address(this));
        require(_amount <= lpAmount, "!TooMuch");
        IERC20(balLP).safeApprove(escrow, 0);
        IERC20(balLP).safeApprove(escrow, _amount);
        VoteEscrow(escrow).increase_amount(_amount);
    }
    
    function release() external {
        require(msg.sender == proxy || msg.sender == governance, "!authorized");
        VoteEscrow(escrow).withdraw();
    }
    
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }

    function convertBAL(uint _amount, bool _join) external {
        require(msg.sender == governance, "!governance");
        _convertBAL(_amount, _join);
    }

    function _convertBAL(uint _amount, bool _join) internal {
        if (_amount > 0) {
            uint256[] memory amounts = new uint256[](2);
            if (_join) {
                amounts[1] = _amount; // BAL
                bytes memory userData = abi.encode(IBalancerVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amounts, 0);
                IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest(assets, amounts, userData, false);
                bVault.joinPool(stakeLp.getPoolId(), address(this), address(this), request);
            } else {
                bytes memory userData = abi.encode(IBalancerVault.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT, _amount, 1);
                IBalancerVault.ExitPoolRequest memory request = IBalancerVault.ExitPoolRequest(assets, amounts, userData, false);
                bVault.exitPool(stakeLp.getPoolId(), address(this), payable(address(this)), request);
            }
        }
    }
    
    function execute(address to, uint value, bytes calldata data) external returns (bool, bytes memory) {
        require(msg.sender == proxy || msg.sender == governance, "!governance");
        (bool success, bytes memory result) = to.call{value:value}(data);
        
        return (success, result);
    }


}