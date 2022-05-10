pragma solidity ^0.6.5;

import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";


interface Gauge {
    function deposit(uint256) external;

    function balanceOf(address) external view returns (uint256);

    function withdraw(uint256) external;

    function claim_rewards(address) external;

    function rewarded_token() external returns (address);

    function reward_tokens(uint256) external returns (address);
}

interface FeeDistribution {
    function claim_many(address[20] calldata) external returns (bool);

    function last_token_time() external view returns (uint256);

    function time_cursor() external view returns (uint256);

    function time_cursor_of(address) external view returns (uint256);
}

interface Mintr {
    function mint(address) external;
}

interface IProxy {
    function execute(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool, bytes memory);

    function increaseAmount(uint256) external;
}

library SafeProxy {
    function safeExecute(
        IProxy voter,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        (bool success, ) = voter.execute(to, value, data);
        if (!success) assert(false);
    }
}

contract VoterProxy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using SafeProxy for IProxy;

    event VoterApproved(address voter);
    event VoterRevoked(address voter);
    event StrategyApproved(address strategy);
    event StrategyRevoked(address strategy);
    event NewGovernance(address governance);

    IProxy public constant voter = IProxy(0xF147b8125d2ef93FB6965Db97D6746952a133934);
    address public constant mintr = address(0x239e55F427D44C3cc793f49bFB507ebe76638a2b);
    address public constant bal = address(0xba100000625a3754423978a60c9317c58a424e3D);
    address public constant gauge = address(0xC128468b7Ce63eA702C1f104D55A2566b13D3ABD); // Gauge controller
    address public constant yveBAL = address(0xc5bDdf9843308380375a611c18B50Fb9341f502A);

    // gauge => strategies
    mapping(address => address) public strategies;
    mapping(address => bool) public voters;
    address public governance;

    uint256 lastTimeCursor;

    constructor() public {
        governance = msg.sender;
    }

    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
        emit NewGovernance(_governance);
    }

    function approveStrategy(address _gauge, address _strategy) external {
        require(msg.sender == governance, "!governance");
        strategies[_gauge] = _strategy;
        emit StrategyApproved(_strategy);
    }

    function revokeStrategy(address _gauge) external {
        require(msg.sender == governance, "!governance");
        require(strategies[_gauge] != address(0), "!exists");
        address _strategy = strategies[_gauge];
        strategies[_gauge] = address(0);
        emit StrategyRevoked(_strategy);
    }

    function approveVoter(address _voter) external {
        require(msg.sender == governance, "!governance");
        voters[_voter] = true;
        emit VoterApproved(_voter);
    }

    function revokeVoter(address _voter) external {
        require(msg.sender == governance, "!governance");
        voters[_voter] = false;
        emit VoterRevoked(_voter);
    }

    function lock() external {
        uint256 amount = IERC20(bal).balanceOf(address(voter));
        if (amount > 0) voter.increaseAmount(amount);
    }

    function vote(address _gauge, uint256 _amount) public {
        require(voters[msg.sender], "!voter");
        voter.safeExecute(gauge, 0, abi.encodeWithSignature("vote_for_gauge_weights(address,uint256)", _gauge, _amount));
    }

    function withdraw(
        address _gauge,
        address _token,
        uint256 _amount
    ) public returns (uint256) {
        require(strategies[_gauge] == msg.sender, "!strategy");
        uint256 _balance = IERC20(_token).balanceOf(address(voter));
        voter.safeExecute(_gauge, 0, abi.encodeWithSignature("withdraw(uint256)", _amount));
        _balance = IERC20(_token).balanceOf(address(voter)).sub(_balance);
        voter.safeExecute(_token, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, _balance));
        return _balance;
    }

    function balanceOf(address _gauge) public view returns (uint256) {
        return IERC20(_gauge).balanceOf(address(voter));
    }

    function withdrawAll(address _gauge, address _token) external returns (uint256) {
        require(strategies[_gauge] == msg.sender, "!strategy");
        return withdraw(_gauge, _token, balanceOf(_gauge));
    }

    function deposit(address _gauge, address _token) external {
        require(strategies[_gauge] == msg.sender, "!strategy");
        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(address(voter), _balance);
        _balance = IERC20(_token).balanceOf(address(voter));

        voter.safeExecute(_token, 0, abi.encodeWithSignature("approve(address,uint256)", _gauge, 0));
        voter.safeExecute(_token, 0, abi.encodeWithSignature("approve(address,uint256)", _gauge, _balance));
        voter.safeExecute(_gauge, 0, abi.encodeWithSignature("deposit(uint256)", _balance));
    }

    function harvest(address _gauge) external {
        require(strategies[_gauge] == msg.sender, "!strategy");
        uint256 _balance = IERC20(bal).balanceOf(address(voter));
        voter.safeExecute(mintr, 0, abi.encodeWithSignature("mint(address)", _gauge));
        _balance = (IERC20(bal).balanceOf(address(voter))).sub(_balance);
        voter.safeExecute(bal, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, _balance));
    }

    function claimRewards(address _gauge, address _token) external {
        require(strategies[_gauge] == msg.sender, "!strategy");
        Gauge(_gauge).claim_rewards(address(voter));
        voter.safeExecute(_token, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, IERC20(_token).balanceOf(address(voter))));
    }
}