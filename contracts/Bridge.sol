pragma solidity ^0.8.20;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20, IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC777} from "@openzeppelin/contracts/token/ERC777/ERC777.sol";

contract Bridge {
    uint256 public immutable CHAIN_ID;
    address public immutable FLAG_TOKEN;
    address public relayer;
    mapping(uint256 => address) public remoteBridge;
    mapping(address => uint256) public remoteBridgeChainId;
    mapping(uint256 => mapping(address => bool)) public isTokenRegisteredAtRemote;

    uint256 internal msgNonce;
    mapping(bytes32 => bool) public relayedMessages;
    uint256 public relayedMessageSenderChainId;
    address public relayedMessageSenderAddress;
    mapping(address => address) public remoteTokenToLocalToken;
    mapping(address => bool) public isBridgedERC20;

    event SendRemoteMessage(
        uint256 indexed targetChainId,
        address indexed targetAddress,
        address indexed sourceAddress,
        uint256 msgValue,
        uint256 msgNonce,
        bytes msgData
    );
    event RelayedMessage(bytes32 indexed msgHash);

    event ETH_transfer(address indexed to, uint256 amount);
    event ERC20_register(address indexed token, string name, string symbol);
    event ERC20_transfer(address indexed token, address indexed to, uint256 amount);

    constructor(address _relayer, address flagToken, uint256 chainId) {
        relayer = _relayer;
        FLAG_TOKEN = flagToken;
        CHAIN_ID = chainId;
    }

    modifier onlyRelayer() {
        require(msg.sender == relayer, "R");
        _;
    }

    modifier onlyRemoteBridge() {
        uint256 senderChainId = Bridge(payable(msg.sender)).relayedMessageSenderChainId();
        require(
            msg.sender == remoteBridge[senderChainId] && senderChainId != 0
                && remoteBridgeChainId[msg.sender] == senderChainId,
            "RB"
        );
        _;
    }

    function isSolved() external view returns (bool) {
        return IERC20(FLAG_TOKEN).balanceOf(address(this)) < 90 ether;
    }

    function registerRemoteBridge(uint256 _remoteChainId, address _remoteBridge) external onlyRelayer {
        remoteBridge[_remoteChainId] = _remoteBridge;
        remoteBridgeChainId[_remoteBridge] = _remoteChainId;
    }

    receive() external payable virtual {
        require(msg.sender == tx.origin, "Only EOA");
        ethOut(msg.sender);
    }

    function ethOut(address _to) public payable virtual {
        emit ETH_transfer(_to, msg.value);
        uint256 _remoteChainId = CHAIN_ID == 1 ? 2 : 1;
        address _remoteBridge = remoteBridge[_remoteChainId];
        this.sendRemoteMessage{value: msg.value}(
            _remoteChainId, _remoteBridge, abi.encodeWithSelector(Bridge.ethIn.selector, _to)
        );
    }

    function ethIn(address _to) external payable onlyRemoteBridge {
        emit ETH_transfer(_to, msg.value);
        Address.sendValue(payable(_to), msg.value);
    }

    function ERC20Out(address _token, address _to, uint256 _amount) external {
        emit ERC20_transfer(_token, _to, _amount);

        uint256 _remoteChainId = CHAIN_ID == 1 ? 2 : 1;
        address _remoteBridge = remoteBridge[_remoteChainId];

        if (isBridgedERC20[_token]) {
            BridgedERC20(_token).burn(msg.sender, _amount);
            _token = BridgedERC20(_token).REMOTE_TOKEN();
        } else {
            uint256 balance = IERC20(_token).balanceOf(address(this));
            require(IERC20(_token).transferFrom(msg.sender, address(this), _amount), "T");
            _amount = IERC20(_token).balanceOf(address(this)) - balance;
            if (!isTokenRegisteredAtRemote[_remoteChainId][_token]) {
                this.sendRemoteMessage(
                    _remoteChainId,
                    _remoteBridge,
                    abi.encodeWithSelector(
                        Bridge.ERC20Register.selector,
                        _token,
                        IERC20Metadata(_token).name(),
                        IERC20Metadata(_token).symbol()
                    )
                );
                isTokenRegisteredAtRemote[_remoteChainId][_token] = true;
            }
        }

        this.sendRemoteMessage(
            _remoteChainId, _remoteBridge, abi.encodeWithSelector(Bridge.ERC20In.selector, _token, _to, _amount)
        );
    }

    function ERC20Register(address _remoteToken, string memory _name, string memory _symbol)
        external
        onlyRemoteBridge
    {
        emit ERC20_register(_remoteToken, _name, _symbol);

        if (remoteTokenToLocalToken[_remoteToken] == address(0)) {
            address _token = address(new BridgedERC20(msg.sender, _remoteToken, _name, _symbol));
            remoteTokenToLocalToken[_remoteToken] = _token;
            isBridgedERC20[_token] = true;
        }
    }

    function ERC20In(address _token, address _to, uint256 _amount) external payable onlyRemoteBridge {
        emit ERC20_transfer(_token, _to, _amount);

        if (remoteTokenToLocalToken[_token] != address(0)) {
            BridgedERC20(remoteTokenToLocalToken[_token]).mint(_to, _amount);
        } else {
            require(IERC20(_token).transfer(_to, _amount), "T");
        }
    }

    function sendRemoteMessage(uint256 _targetChainId, address _targetAddress, bytes calldata _message)
        public
        payable
    {
        require(msg.sender == address(this), "S");
        require(_targetChainId != CHAIN_ID, "C");
        require(_targetAddress != address(0), "A");
        emit SendRemoteMessage(_targetChainId, _targetAddress, msg.sender, msg.value, msgNonce, _message);
        
        uint256 _sourceChainId = CHAIN_ID;
        address _sourceAddress = address(this);

        bytes32 h = keccak256(
            abi.encodeWithSignature(
                "relayMessage(address,uint256,address,uint256,uint256,bytes)",
                _targetAddress,
                _sourceChainId,
                _sourceAddress,
                msg.value,
                msgNonce,
                _message
            )
        );
        require(relayedMessages[h] == false, "H");
        relayedMessages[h] = true;
        emit RelayedMessage(h);
        relayedMessageSenderChainId = _sourceChainId;
        relayedMessageSenderAddress = _sourceAddress;
        (bool success, bytes memory result) = _targetAddress.call{value: msg.value}(_message);
        require(success, string(result));
        relayedMessageSenderChainId = 0;
        relayedMessageSenderAddress = address(0);

        unchecked {
            ++msgNonce;
        }
    }
}

contract Token is ERC777 {
    constructor(address user, address[] memory a) ERC777("Token", "Tok", a) {
        _mint(msg.sender, 100 ether, "", "", false);
        _mint(user, 1 ether, "", "", false);
    }
}

contract BridgedERC20 is ERC20 {
    Bridge public immutable BRIDGE;
    Bridge public immutable REMOTE_BRIDGE;
    address public immutable REMOTE_TOKEN;

    modifier onlyBridge() {
        require(msg.sender == address(BRIDGE), "B");
        _;
    }

    modifier onlyRemoteBridge() {
        require(msg.sender == address(BRIDGE), "RB1");
        require(
            REMOTE_BRIDGE.relayedMessageSenderChainId() != 0
                && BRIDGE.remoteBridgeChainId(REMOTE_BRIDGE.relayedMessageSenderAddress()) == REMOTE_BRIDGE.relayedMessageSenderChainId(),
            "RB2"
        );
        _;
    }

    constructor(address _remoteBridge, address _remoteToken, string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        BRIDGE = Bridge(payable(msg.sender));
        REMOTE_BRIDGE = Bridge(payable(_remoteBridge));
        REMOTE_TOKEN = _remoteToken;
    }

    function mint(address _to, uint256 _amount) external onlyRemoteBridge {
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external onlyBridge {
        _burn(_from, _amount);
    }
}