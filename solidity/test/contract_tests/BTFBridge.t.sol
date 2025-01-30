// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "src/BTFBridge.sol";
import "src/test_contracts/UUPSProxy.sol";
import "src/WrappedToken.sol";
import "src/WrappedTokenDeployer.sol";
import "src/libraries/StringUtils.sol";

contract BTFBridgeTest is Test {
    using StringUtils for string;

    struct MintOrder {
        uint256 amount;
        bytes32 senderID;
        bytes32 fromTokenID;
        address recipient;
        address toERC20;
        uint32 nonce;
        uint32 senderChainID;
        uint32 recipientChainID;
        bytes32 name;
        bytes16 symbol;
        uint8 decimals;
        address approveSpender;
        uint256 approveAmount;
        address feePayer;
    }

    uint256 constant _OWNER_KEY = 1;
    uint256 constant _ALICE_KEY = 2;
    uint256 constant _BOB_KEY = 3;

    uint32 constant _CHAIN_ID = 31555;

    address _owner = vm.addr(_OWNER_KEY);
    address _alice = vm.addr(_ALICE_KEY);
    address _bob = vm.addr(_BOB_KEY);

    WrappedTokenDeployer _wrappedTokenDeployer;

    BTFBridge _wrappedBridge;
    BTFBridge _baseBridge;

    address newImplementation = address(8);

    address wrappedProxy;
    address baseProxy;

    event BurnFeeUpdated(uint256 oldFee, uint256 newFee);
    event BurnFeesWithdrawn(uint256 amount);

    function setUp() public {
        vm.chainId(_CHAIN_ID);
        vm.startPrank(_owner);

        _wrappedTokenDeployer = new WrappedTokenDeployer();

        address[] memory initialControllers = new address[](1);
        initialControllers[0] = _owner; // Add owner as controller

        // Encode the initialization call
        // address[] memory initialControllers = new address[](0);

        uint256 burnFeeInWei = 0.01 ether;

        // Encode the initialization call
        bytes memory initializeData = abi.encodeWithSelector(
            BTFBridge.initialize.selector,
            _owner,
            address(0),
            address(_wrappedTokenDeployer),
            true,
            _owner,
            initialControllers,
            burnFeeInWei // Add burn fee
        );

        BTFBridge wrappedImpl = new BTFBridge();

        UUPSProxy wrappedProxyContract = new UUPSProxy(address(wrappedImpl), initializeData);

        wrappedProxy = address(wrappedProxyContract);

        // Cast the proxy to BTFBridge
        _wrappedBridge = BTFBridge(payable(address(wrappedProxy)));
        // Encode the initialization call
        bytes memory baseInitializeData = abi.encodeWithSelector(
            BTFBridge.initialize.selector, _owner, address(0), _wrappedTokenDeployer, false, _owner, initialControllers
        );

        BTFBridge baseImpl = new BTFBridge();

        UUPSProxy baseProxyContract = new UUPSProxy(address(baseImpl), baseInitializeData);

        baseProxy = address(baseProxyContract);

        // Cast the proxy to BTFBridge
        _baseBridge = BTFBridge(payable(address(baseProxy)));
        require(_baseBridge.isWrappedSide() == false, "Base bridge not properly initialized");

        vm.stopPrank();
    }

    function testMinterCanisterAddress() public view {
        assertEq(_wrappedBridge.minterCanisterAddress(), _owner);
    }

    // batch tests

    function testBatchMintSuccess() public {
        vm.startPrank(_owner);
        bytes32 base_token_id_1 = _createIdFromPrincipal(abi.encodePacked(uint8(1)));
        address token1 = _wrappedBridge.deployERC20("WholaLottaLove", "LEDZEP", 21, base_token_id_1);
        MintOrder memory order_1 = _createDefaultMintOrder(base_token_id_1, token1, 0);

        bytes32 base_token_id_2 = _createIdFromPrincipal(abi.encodePacked(uint8(2)));
        address token2 = _wrappedBridge.deployERC20("Gabibbo", "GAB", 10, base_token_id_2);
        MintOrder memory order_2 = _createDefaultMintOrder(base_token_id_2, token2, 1);

        MintOrder[] memory orders = new MintOrder[](2);
        orders[0] = order_1;
        orders[1] = order_2;
        bytes memory encodedOrders = _batchMintOrders(orders);
        bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);

        uint32[] memory ordersToProcess = new uint32[](2);
        ordersToProcess[0] = 0;
        ordersToProcess[1] = 1;
        uint8[] memory processedOrders = _wrappedBridge.batchMint(encodedOrders, signature, ordersToProcess);

        address recipient = order_1.recipient;
        uint256 amount = order_1.amount;

        assertEq(processedOrders[0], _wrappedBridge.MINT_ERROR_CODE_OK());
        assertEq(processedOrders[1], _wrappedBridge.MINT_ERROR_CODE_OK());

        assertEq(WrappedToken(token1).balanceOf(recipient), amount);
        assertEq(WrappedToken(token2).balanceOf(recipient), amount);
        vm.stopPrank();
    }

    function testBatchMintProcessAllIfToProcessIsZero() public {
        vm.startPrank(_owner); // Single prank session for the entire test

        bytes32 base_token_id_1 = _createIdFromPrincipal(abi.encodePacked(uint8(1)));
        address token1 = _wrappedBridge.deployERC20("WholaLottaLove", "LEDZEP", 21, base_token_id_1);
        MintOrder memory order_1 = _createDefaultMintOrder(base_token_id_1, token1, 0);

        bytes32 base_token_id_2 = _createIdFromPrincipal(abi.encodePacked(uint8(2)));
        address token2 = _wrappedBridge.deployERC20("Gabibbo", "GAB", 10, base_token_id_2);
        MintOrder memory order_2 = _createDefaultMintOrder(base_token_id_2, token2, 1);

        MintOrder[] memory orders = new MintOrder[](2);
        orders[0] = order_1;
        orders[1] = order_2;
        bytes memory encodedOrders = _batchMintOrders(orders);
        bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);

        uint32[] memory ordersToProcess = new uint32[](0);
        uint8[] memory processedOrders = _wrappedBridge.batchMint(encodedOrders, signature, ordersToProcess);

        address recipient = order_1.recipient;
        uint256 amount = order_1.amount;

        assertEq(processedOrders[0], _wrappedBridge.MINT_ERROR_CODE_OK());
        assertEq(processedOrders[1], _wrappedBridge.MINT_ERROR_CODE_OK());

        assertEq(WrappedToken(token1).balanceOf(recipient), amount);
        assertEq(WrappedToken(token2).balanceOf(recipient), amount);

        vm.stopPrank(); // End the single prank session
    }

    function testBatchMintProcessAllIfToProcessIsZeroDebug() public {
        // Log initial state
        console.log("Test started. Owner address:", _owner);
        console.log("Is owner a controller?", _wrappedBridge.controllerAccessList(_owner));

        vm.startPrank(_owner);
        console.log("After startPrank. Is owner a controller?", _wrappedBridge.controllerAccessList(_owner));

        bytes32 base_token_id_1 = _createIdFromPrincipal(abi.encodePacked(uint8(1)));
        address token1 = _wrappedBridge.deployERC20("WholaLottaLove", "LEDZEP", 21, base_token_id_1);
        MintOrder memory order_1 = _createDefaultMintOrder(base_token_id_1, token1, 0);

        console.log(
            "After first token deployment. Is owner still controller?", _wrappedBridge.controllerAccessList(_owner)
        );

        bytes32 base_token_id_2 = _createIdFromPrincipal(abi.encodePacked(uint8(2)));
        address token2 = _wrappedBridge.deployERC20("Gabibbo", "GAB", 10, base_token_id_2);
        MintOrder memory order_2 = _createDefaultMintOrder(base_token_id_2, token2, 1);

        console.log(
            "After second token deployment. Is owner still controller?", _wrappedBridge.controllerAccessList(_owner)
        );

        MintOrder[] memory orders = new MintOrder[](2);
        orders[0] = order_1;
        orders[1] = order_2;
        bytes memory encodedOrders = _batchMintOrders(orders);
        bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);

        uint32[] memory ordersToProcess = new uint32[](0);

        console.log("Right before batchMint. Current msg.sender:", msg.sender);
        console.log("Is current sender a controller?", _wrappedBridge.controllerAccessList(msg.sender));

        uint8[] memory processedOrders = _wrappedBridge.batchMint(encodedOrders, signature, ordersToProcess);

        address recipient = order_1.recipient;
        uint256 amount = order_1.amount;

        assertEq(processedOrders[0], _wrappedBridge.MINT_ERROR_CODE_OK());
        assertEq(processedOrders[1], _wrappedBridge.MINT_ERROR_CODE_OK());

        assertEq(WrappedToken(token1).balanceOf(recipient), amount);
        assertEq(WrappedToken(token2).balanceOf(recipient), amount);

        vm.stopPrank();
    }

    function testBatchMintProcessOnlyIfRequested() public {
        vm.startPrank(_owner); // Add this line to impersonate owner

        bytes32 base_token_id_1 = _createIdFromPrincipal(abi.encodePacked(uint8(1)));
        address token1 = _wrappedBridge.deployERC20("WholaLottaLove", "LEDZEP", 21, base_token_id_1);
        MintOrder memory order_1 = _createDefaultMintOrder(base_token_id_1, token1, 0);

        bytes32 base_token_id_2 = _createIdFromPrincipal(abi.encodePacked(uint8(2)));
        address token2 = _wrappedBridge.deployERC20("Gabibbo", "GAB", 10, base_token_id_2);
        MintOrder memory order_2 = _createDefaultMintOrder(base_token_id_2, token2, 1);

        MintOrder[] memory orders = new MintOrder[](2);
        orders[0] = order_1;
        orders[1] = order_2;
        bytes memory encodedOrders = _batchMintOrders(orders);
        bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);

        uint32[] memory ordersToProcess = new uint32[](1);
        ordersToProcess[0] = 0;
        uint8[] memory processedOrders = _wrappedBridge.batchMint(encodedOrders, signature, ordersToProcess);

        address recipient = order_1.recipient;
        uint256 amount = order_1.amount;

        assertEq(processedOrders[0], _wrappedBridge.MINT_ERROR_CODE_OK());
        assertEq(processedOrders[1], _wrappedBridge.MINT_ERROR_CODE_PROCESSING_NOT_REQUESTED());

        assertEq(WrappedToken(token1).balanceOf(recipient), amount);
        assertEq(WrappedToken(token2).balanceOf(recipient), 0);

        vm.stopPrank(); // Add this line to stop impersonating owner
    }

    function testBatchMintInvalidRecipient() public {
        // Debug initial state
        console.log("Owner address:", _owner);
        console.log("Is owner initially a controller?", _wrappedBridge.controllerAccessList(_owner));

        vm.startPrank(_owner);

        console.log("After startPrank - Is owner a controller?", _wrappedBridge.controllerAccessList(_owner));

        // Create and deploy required token first
        MintOrder memory order = _createDefaultMintOrder();
        order.recipient = address(0); // Set invalid recipient

        // Log order details
        console.log("Token address:", order.toERC20);
        console.log("Order recipient:", order.recipient);

        MintOrder[] memory orders = new MintOrder[](1);
        orders[0] = order;
        bytes memory encodedOrders = _batchMintOrders(orders);
        bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);

        uint32[] memory ordersToProcess = new uint32[](1);
        ordersToProcess[0] = 0;

        // Record initial state
        uint256 initialBalance = 0; // Since recipient is address(0)

        // Attempt mint with zero recipient
        uint8[] memory processedOrders = _wrappedBridge.batchMint(encodedOrders, signature, ordersToProcess);

        // Verify error code
        assertEq(
            processedOrders[0], _wrappedBridge.MINT_ERROR_CODE_ZERO_RECIPIENT(), "Should fail with ZERO_RECIPIENT error"
        );

        // Verify no tokens were minted
        assertEq(
            WrappedToken(order.toERC20).balanceOf(address(0)),
            initialBalance,
            "No tokens should be minted to zero address"
        );

        vm.stopPrank();
    }

    function testBatchMintUsedNonce() public {
        vm.startPrank(_owner); // Add this line to impersonate owner

        bytes32 base_token_id_1 = _createIdFromPrincipal(abi.encodePacked(uint8(1)));
        address token1 = _wrappedBridge.deployERC20("WholaLottaLove", "LEDZEP", 21, base_token_id_1);
        MintOrder memory order_1 = _createDefaultMintOrder(base_token_id_1, token1, 0);

        bytes32 base_token_id_2 = _createIdFromPrincipal(abi.encodePacked(uint8(2)));
        address token2 = _wrappedBridge.deployERC20("Gabibbo", "GAB", 10, base_token_id_2);
        MintOrder memory order_2 = _createDefaultMintOrder(base_token_id_2, token2, 0);

        MintOrder[] memory orders = new MintOrder[](2);
        orders[0] = order_1;
        orders[1] = order_2;
        bytes memory encodedOrders = _batchMintOrders(orders);
        bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);

        uint32[] memory ordersToProcess = new uint32[](2);
        ordersToProcess[0] = 0;
        ordersToProcess[1] = 1;
        uint8[] memory processedOrders = _wrappedBridge.batchMint(encodedOrders, signature, ordersToProcess);

        assertEq(processedOrders[0], _wrappedBridge.MINT_ERROR_CODE_OK());
        assertEq(processedOrders[1], _wrappedBridge.MINT_ERROR_CODE_USED_NONCE());

        assertEq(WrappedToken(order_2.toERC20).balanceOf(order_2.recipient), 0);

        vm.stopPrank(); // Add this line to stop impersonating owner
    }

    function testBatchMintInvalidPair() public {
        vm.startPrank(_owner); // Start as owner/controller

        // Create order but modify the fromTokenID to be different
        // from what was registered during deployment
        MintOrder memory order = _createDefaultMintOrder();
        order.fromTokenID = _createIdFromPrincipal(abi.encodePacked(uint8(1)));

        MintOrder[] memory orders = new MintOrder[](1);
        orders[0] = order;
        bytes memory encodedOrders = _batchMintOrders(orders);
        bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);

        uint32[] memory ordersToProcess = new uint32[](1);
        ordersToProcess[0] = 0;

        // Record initial balance
        uint256 initialBalance = WrappedToken(order.toERC20).balanceOf(order.recipient);

        // Should fail with TOKENS_NOT_BRIDGED error
        uint8[] memory processedOrders = _wrappedBridge.batchMint(encodedOrders, signature, ordersToProcess);

        // Verify correct error code
        assertEq(
            processedOrders[0],
            _wrappedBridge.MINT_ERROR_CODE_TOKENS_NOT_BRIDGED(),
            "Should fail with TOKENS_NOT_BRIDGED error"
        );

        // Verify no tokens were minted
        assertEq(
            WrappedToken(order.toERC20).balanceOf(order.recipient),
            initialBalance,
            "No tokens should be minted for invalid pair"
        );

        vm.stopPrank();
    }

    function testBatchMintInvalidSignature() public {
        vm.startPrank(_owner);

        // Create and setup the order
        MintOrder memory order = _createDefaultMintOrder();
        MintOrder[] memory orders = new MintOrder[](1);
        orders[0] = order;
        bytes memory encodedOrders = _batchMintOrders(orders);
        bytes memory invalidSignature = new bytes(0);

        uint32[] memory ordersToProcess = new uint32[](1);
        ordersToProcess[0] = 0;

        bool hasError;
        bytes memory errorData;

        // Try the operation and capture the error
        try _wrappedBridge.batchMint(encodedOrders, invalidSignature, ordersToProcess) {
            hasError = false;
        } catch (bytes memory err) {
            hasError = true;
            errorData = err;
            console.logBytes(err); // Log the actual error data
        }

        assertTrue(hasError, "Operation should revert");

        // Compare with expected error
        bytes memory expectedError = abi.encodeWithSelector(
            ECDSA.ECDSAInvalidSignatureLength.selector,
            0 // length of invalid signature
        );

        assertEq(keccak256(errorData), keccak256(expectedError), "Incorrect error signature");

        vm.stopPrank();
    }

    function testBatchMintInvalidOrderLength() public {
        vm.startPrank(_owner);
        bytes memory badEncodedOrder = abi.encodePacked(uint8(1));
        bytes memory signature = _batchMintOrdersSignature(badEncodedOrder, _OWNER_KEY);

        uint32[] memory ordersToProcess = new uint32[](0);
        vm.expectRevert("Incorrect mint orders batch encoding");
        _wrappedBridge.batchMint(badEncodedOrder, signature, ordersToProcess);
        vm.stopPrank();
    }

    function testGetWrappedToken() public {
        vm.startPrank(_owner);
        bytes32 baseTokenId = _createIdFromPrincipal(abi.encodePacked(uint8(1)));
        address wrappedToken = _wrappedBridge.deployERC20("Test", "TST", 18, baseTokenId);
        assertEq(_wrappedBridge.getWrappedToken(baseTokenId), wrappedToken);
        vm.stopPrank();
    }

    function testGetBaseToken() public {
        vm.startPrank(_owner);
        bytes32 base_token_id = _createIdFromPrincipal(abi.encodePacked(uint8(1)));
        address wrapped = _wrappedBridge.deployERC20("Test", "TST", 18, base_token_id);
        assertEq(_wrappedBridge.getBaseToken(wrapped), base_token_id);
        vm.stopPrank();
    }

    // Creates a wrapped token with custom name, symbol, and decimals
    function testDeployERC20CustomDecimals() public {
        vm.startPrank(_owner);
        bytes32 base_token_id = _createIdFromPrincipal(abi.encodePacked(uint8(1)));
        address wrapped_address = _wrappedBridge.deployERC20("WholaLottaLove", "LEDZEP", 21, base_token_id);
        WrappedToken token = WrappedToken(wrapped_address);
        assertEq(token.name(), "WholaLottaLove");
        assertEq(token.symbol(), "LEDZEP");
        assertEq(token.decimals(), 21);
        vm.stopPrank();
    }

    function testListTokenPairs() public {
        vm.startPrank(_owner);
        bytes32 baseTokenId = _createIdFromPrincipal(abi.encodePacked(uint8(1)));
        address wrappedToken = _wrappedBridge.deployERC20("Test", "TST", 18, baseTokenId);

        (address[] memory wrapped, bytes32[] memory base) = _wrappedBridge.listTokenPairs();
        assertEq(wrapped[0], wrappedToken);
        assertEq(base[0], baseTokenId);
        vm.stopPrank();
    }

    function testBurnWrappedSideWithoutApprove() public {
        // Start as owner to create token
        vm.startPrank(_owner);

        bytes memory principal = abi.encodePacked(uint8(1), uint8(2), uint8(3));

        // deploy erc20 so it can be used
        MintOrder memory order = _createSelfMintOrder();

        MintOrder[] memory orders = new MintOrder[](1);
        orders[0] = order;

        bytes memory encodedOrders = _batchMintOrders(orders);
        bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);

        uint32[] memory ordersToProcess = new uint32[](0);
        _wrappedBridge.batchMint(encodedOrders, signature, ordersToProcess);

        // Verify initial balance
        assertEq(WrappedToken(order.toERC20).balanceOf(address(_owner)), order.amount);

        // Get burn fee and fund owner
        uint256 burnFee = _wrappedBridge.burnFeeInWei();
        vm.deal(_owner, burnFee);

        bytes32 memo = bytes32(abi.encodePacked(uint8(0)));

        // Try to burn without approving
        // Owner can burn without approve because the token is owned by the bridge
        _wrappedBridge.burn{ value: burnFee }(
            1, // Amount to burn
            order.toERC20, // Token address
            order.fromTokenID, // Token ID
            principal, // Recipient on other chain
            memo // Memo
        );

        // Verify burn was successful
        assertEq(
            WrappedToken(order.toERC20).balanceOf(address(_owner)),
            order.amount - 1, // Original amount minus burned amount
            "Burn should succeed without approval for owner"
        );

        vm.stopPrank();
    }

    function testBurnBaseSideWithoutApproveShouldFail() public {
        // Setup token with owner
        vm.startPrank(_owner);

        // Create token
        WrappedToken token = new WrappedToken("Test", "TST", 18, _owner);

        // When owner transfers, it automatically mints and transfers
        token.transfer(_alice, 1 ether);

        vm.stopPrank();

        // Setup Alice for the burn attempt
        uint256 burnAmount = 1 ether;
        uint256 burnFee = _baseBridge.burnFeeInWei();
        vm.deal(_alice, burnFee);

        // Try to burn as Alice without approving first
        vm.startPrank(_alice);

        vm.expectRevert("Invalid operation on base side");
        _baseBridge.burn{ value: burnFee }(
            burnAmount, address(token), bytes32(0), abi.encodePacked(uint8(1)), bytes32(0)
        );
        vm.stopPrank();

        // Verify the tokens are still in Alice's account
        assertEq(token.balanceOf(_alice), 1 ether);
    }

    function testBurnWrappedSideWithDeployedErc20() public {
        vm.startPrank(_owner);

        uint256 burnAmount = 1000; // Match the amount that gets minted
        uint256 burnFee = _wrappedBridge.burnFeeInWei();

        // Create and deploy token
        MintOrder memory order = _createDefaultMintOrder();
        address token = order.toERC20;

        // Debug info
        console.log("Token owner:", WrappedToken(token).owner());
        console.log("Current caller (_owner):", _owner);
        console.log("Bridge address:", address(_wrappedBridge));

        // Mint tokens to Alice using batchMint
        MintOrder[] memory orders = new MintOrder[](1);
        orders[0] = order;
        bytes memory encodedOrders = _batchMintOrders(orders);
        bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);

        uint32[] memory ordersToProcess = new uint32[](1);
        ordersToProcess[0] = 0;
        _wrappedBridge.batchMint(encodedOrders, signature, ordersToProcess);

        vm.stopPrank();

        // Verify Alice got the tokens
        assertEq(WrappedToken(token).balanceOf(_alice), burnAmount, "Alice should have correct initial tokens");

        // Setup Alice for burn
        vm.deal(_alice, burnFee);
        vm.startPrank(_alice);

        // Approve bridge to spend tokens
        WrappedToken(token).approve(address(_wrappedBridge), burnAmount);

        // Should succeed because burn doesn't require controller access
        uint32 operationId = _wrappedBridge.burn{ value: burnFee }(
            burnAmount, token, order.fromTokenID, abi.encodePacked(uint8(1)), bytes32(0)
        );

        vm.stopPrank();

        // Verify tokens were burned
        assertEq(WrappedToken(token).balanceOf(_alice), 0, "Alice's tokens should be burned");
        assertEq(WrappedToken(token).balanceOf(address(_wrappedBridge)), 0, "Bridge should not hold tokens");
    }

    function testBurnWrappedSideWithUnregisteredToken() public {
        bytes memory principal = abi.encodePacked(uint8(1), uint8(2), uint8(3));
        uint256 burnFee = _wrappedBridge.burnFeeInWei();

        // Create token and fund caller
        address erc20 = address(new WrappedToken("omar", "OMAR", 18, _owner));
        vm.deal(address(this), burnFee); // Fund test contract with burn fee

        bytes32 toTokenId = _createIdFromPrincipal(abi.encodePacked(uint8(1)));
        vm.expectRevert(bytes("Invalid from address; not registered in the bridge"));
        bytes32 memo = bytes32(abi.encodePacked(uint8(0)));

        // Include burn fee in the call
        _wrappedBridge.burn{ value: burnFee }(100, erc20, toTokenId, principal, memo);
    }

    function testBurnBaseSideWithUnregisteredToken() public {
        uint256 burnAmount = 1 ether;
        uint256 burnFee = _baseBridge.burnFeeInWei();

        vm.deal(_alice, burnAmount + burnFee);
        WrappedToken token = new WrappedToken("Test", "TST", 18, _owner);

        vm.startPrank(_alice);
        vm.expectRevert("Invalid operation on base side");
        _baseBridge.burn{ value: burnFee }(
            burnAmount, address(token), bytes32(0), abi.encodePacked(uint8(1)), bytes32(0)
        );
        vm.stopPrank();
    }

    function testMintBaseSideWithUnregisteredToken() public {
        WrappedToken erc20 = new WrappedToken("omar", "OMAR", 18, _owner);
        address erc20Address = address(erc20);

        vm.prank(address(_owner));
        erc20.transfer(address(_baseBridge), 1000);

        MintOrder memory order = _createMintOrder(_alice, erc20Address);

        MintOrder[] memory orders = new MintOrder[](1);
        orders[0] = order;

        bytes memory encodedOrders = _batchMintOrders(orders);
        bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);

        uint32[] memory ordersToProcess = new uint32[](0);

        _baseBridge.batchMint(encodedOrders, signature, ordersToProcess);

        assertEq(erc20.balanceOf(order.recipient), order.amount);
    }

    function testMintWrappedSideWithUnregisteredToken() public {
        WrappedToken erc20 = new WrappedToken("omar", "OMAR", 18, _owner);
        address erc20Address = address(erc20);

        vm.prank(address(_owner));
        erc20.transfer(address(_wrappedBridge), 1000);

        MintOrder memory order = _createMintOrder(_alice, erc20Address);

        MintOrder[] memory orders = new MintOrder[](1);
        orders[0] = order;

        bytes memory encodedOrders = _batchMintOrders(orders);
        bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);

        uint32[] memory ordersToProcess = new uint32[](0);

        vm.expectRevert(bytes("Invalid token pair"));
        _wrappedBridge.batchMint(encodedOrders, signature, ordersToProcess);
    }

    function testMintCallsAreRejectedWhenPaused() public {
        // Start as owner
        vm.startPrank(_owner);

        // Pause the bridge
        _wrappedBridge.pause();

        // Create the mint order
        MintOrder memory mintOrder = _createDefaultMintOrder();

        MintOrder[] memory orders = new MintOrder[](1);
        orders[0] = mintOrder;

        bytes memory encodedOrders = _batchMintOrders(orders);
        bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);

        uint32[] memory ordersToProcess = new uint32[](0);

        // Try minting while paused
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        _wrappedBridge.batchMint(encodedOrders, signature, ordersToProcess);

        // Unpause bridge
        _wrappedBridge.unpause();

        // Mint should succeed now
        _wrappedBridge.batchMint(encodedOrders, signature, ordersToProcess);

        // Verify mint succeeded
        assertEq(
            WrappedToken(mintOrder.toERC20).balanceOf(mintOrder.recipient),
            mintOrder.amount,
            "Mint should succeed after unpausing"
        );

        vm.stopPrank();
    }

    function testAddAllowedImplementation() public {
        vm.startPrank(_owner, _owner);

        BTFBridge _newImpl = new BTFBridge();

        newImplementation = address(_newImpl);

        _wrappedBridge.addAllowedImplementation(newImplementation.codehash);

        assertTrue(_wrappedBridge.allowedImplementations(newImplementation.codehash));

        vm.stopPrank();
    }

    function testAddAllowedImplementationOnlyOwner() public {
        vm.prank(address(10));

        vm.expectRevert();

        _wrappedBridge.addAllowedImplementation(newImplementation.codehash);
    }

    function testAddAllowedImplementationByAController() public {
        vm.startPrank(_owner);
        BTFBridge _newImpl = new BTFBridge();

        newImplementation = address(_newImpl);

        address controller = address(55);
        _wrappedBridge.addController(controller);

        vm.stopPrank();

        vm.prank(controller);

        _wrappedBridge.addAllowedImplementation(newImplementation.codehash);
    }

    /// Test that the bridge can be upgraded to a new implementation
    /// and the new implementation has been added to the list of allowed
    /// implementations
    function testUpgradeBridgeWithAllowedImplementation() public {
        vm.startPrank(_owner);

        BTFBridge _newImpl = new BTFBridge();

        newImplementation = address(_newImpl);

        _wrappedBridge.addAllowedImplementation(newImplementation.codehash);
        assertTrue(_wrappedBridge.allowedImplementations(newImplementation.codehash));

        // Wrap in ABI for easier testing
        BTFBridge proxy = BTFBridge(payable(wrappedProxy));

        // pass empty calldata to initialize
        bytes memory data = new bytes(0);

        proxy.upgradeToAndCall(address(_newImpl), data);

        vm.stopPrank();
    }

    function testUpgradeBridgeWithNotAllowedImplementation() public {
        vm.startPrank(_owner);
        BTFBridge _newImpl = new BTFBridge();
        newImplementation = address(_newImpl);
        // Wrap in ABI for easier testing

        BTFBridge proxy = BTFBridge(payable(wrappedProxy));
        // pass empty calldata to initialize
        bytes memory data = new bytes(0);
        vm.expectRevert();
        proxy.upgradeToAndCall(address(_newImpl), data);

        vm.stopPrank();
    }

    function testPauseByController() public {
        address controller = address(42);

        vm.prank(_owner);
        _wrappedBridge.addController(controller);

        vm.prank(controller);
        _wrappedBridge.pause();

        assertTrue(_wrappedBridge.paused());
    }

    function testPauseByNonController() public {
        address nonController = address(43);

        vm.prank(nonController);
        vm.expectRevert("Not a controller");
        _wrappedBridge.pause();
    }

    function testUnpauseByController() public {
        address controller = address(42);

        vm.prank(_owner);
        _wrappedBridge.addController(controller);

        vm.prank(controller);
        _wrappedBridge.pause();

        vm.prank(controller);
        _wrappedBridge.unpause();

        assertFalse(_wrappedBridge.paused());
    }

    function testUnpauseByNonController() public {
        address nonController = address(43);

        vm.prank(_owner);
        _wrappedBridge.pause();

        vm.prank(nonController);
        vm.expectRevert("Not a controller");
        _wrappedBridge.unpause();
    }

    function testAddAllowedImplementationByController() public {
        address controller = address(42);

        vm.prank(_owner);
        _wrappedBridge.addController(controller);

        bytes32 newImplementationHash = keccak256(abi.encodePacked("new implementation"));

        vm.prank(controller);
        _wrappedBridge.addAllowedImplementation(newImplementationHash);

        assertTrue(_wrappedBridge.allowedImplementations(newImplementationHash));
    }

    function testAddAllowedImplementationByNonController() public {
        address nonController = address(43);
        bytes32 newImplementationHash = keccak256(abi.encodePacked("new implementation"));

        vm.prank(nonController);
        vm.expectRevert("Not a controller");
        _wrappedBridge.addAllowedImplementation(newImplementationHash);
    }

    function testAddAllowedImplementationAlreadyAllowed() public {
        address controller = address(42);

        vm.prank(_owner);
        _wrappedBridge.addController(controller);

        bytes32 newImplementationHash = keccak256(abi.encodePacked("new implementation"));

        vm.prank(controller);
        _wrappedBridge.addAllowedImplementation(newImplementationHash);

        vm.prank(controller);
        vm.expectRevert("Implementation already allowed");
        _wrappedBridge.addAllowedImplementation(newImplementationHash);
    }

    function testAddAndRemoveController() public {
        address newController = address(44);

        vm.prank(_owner);
        _wrappedBridge.addController(newController);
        assertTrue(_wrappedBridge.controllerAccessList(newController));

        vm.prank(_owner);
        _wrappedBridge.removeController(newController);
        assertFalse(_wrappedBridge.controllerAccessList(newController));
    }

    function _createDefaultMintOrder() private returns (MintOrder memory order) {
        return _createDefaultMintOrder(0);
    }

    function _createDefaultMintOrder(
        uint32 nonce
    ) private returns (MintOrder memory order) {
        // Remove the vm.startPrank and vm.stopPrank from here
        bytes32 fromTokenId = _createIdFromPrincipal(abi.encodePacked(uint8(1), uint8(2), uint8(3), uint8(4)));
        address toErc20 = _wrappedBridge.deployERC20("Token", "TKN", 18, fromTokenId);
        return _createDefaultMintOrder(fromTokenId, toErc20, nonce);
    }

    function _createDefaultMintOrder(
        bytes32 fromTokenId,
        address toERC20,
        uint32 nonce
    ) private view returns (MintOrder memory order) {
        order.amount = 1000;
        order.senderID = _createIdFromPrincipal(abi.encodePacked(uint8(1), uint8(2), uint8(3)));
        order.fromTokenID = fromTokenId;
        order.recipient = _alice;
        order.toERC20 = toERC20;
        order.nonce = nonce;
        order.senderChainID = 0;
        order.recipientChainID = _CHAIN_ID;
        order.name = StringUtils.truncateUTF8("Token");
        order.symbol = bytes16(StringUtils.truncateUTF8("Token"));
        order.decimals = 18;
        order.approveSpender = address(0);
        order.approveAmount = 0;
        order.feePayer = address(0);
    }

    function _createSelfMintOrder() private returns (MintOrder memory order) {
        order.amount = 1000;
        order.senderID = _createIdFromPrincipal(abi.encodePacked(uint8(1), uint8(2), uint8(3)));
        order.fromTokenID = _createIdFromPrincipal(abi.encodePacked(uint8(1), uint8(2), uint8(3), uint8(4)));
        order.recipient = address(_owner);
        order.toERC20 = _wrappedBridge.deployERC20("Token", "TKN", 18, order.fromTokenID);
        order.nonce = 0;
        order.senderChainID = 0;
        order.recipientChainID = _CHAIN_ID;
        // order.name = _bridge.truncateUTF8("Token");
        order.name = StringUtils.truncateUTF8("Token");
        // order.symbol = bytes16(_bridge.truncateUTF8("Token"));
        order.symbol = bytes16(StringUtils.truncateUTF8("Token"));
        order.decimals = 18;
        order.approveSpender = address(0);
        order.approveAmount = 0;
        order.feePayer = address(0);
    }

    function _createMintOrder(address recipient, address toERC20) private pure returns (MintOrder memory order) {
        order.amount = 1000;
        order.senderID = _createIdFromPrincipal(abi.encodePacked(uint8(1), uint8(2), uint8(3)));
        order.fromTokenID = _createIdFromPrincipal(abi.encodePacked(uint8(1), uint8(2), uint8(3), uint8(4)));
        order.recipient = recipient;
        order.toERC20 = toERC20;
        order.nonce = 0;
        order.senderChainID = 0;
        order.recipientChainID = _CHAIN_ID;
        // order.name = _bridge.truncateUTF8("Token");
        order.name = StringUtils.truncateUTF8("Token");
        // order.symbol = bytes16(_bridge.truncateUTF8("Token"));
        order.symbol = bytes16(StringUtils.truncateUTF8("Token"));
        order.decimals = 18;
        order.approveSpender = address(0);
        order.approveAmount = 0;
        order.feePayer = address(0);
    }

    function _batchMintOrders(
        MintOrder[] memory orders
    ) private pure returns (bytes memory) {
        bytes memory encodedOrders;
        for (uint256 i = 0; i < orders.length; i += 1) {
            bytes memory orderData = _encodeOrder(orders[i]);
            encodedOrders = abi.encodePacked(encodedOrders, orderData);
        }

        return abi.encodePacked(encodedOrders);
    }

    function _encodeOrder(
        MintOrder memory order
    ) private pure returns (bytes memory) {
        return abi.encodePacked(
            order.amount,
            order.senderID,
            order.fromTokenID,
            order.recipient,
            order.toERC20,
            order.nonce,
            order.senderChainID,
            order.recipientChainID,
            order.name,
            order.symbol,
            order.decimals,
            order.approveSpender,
            order.approveAmount,
            address(0)
        );
    }

    function _batchMintOrdersSignature(
        bytes memory encodedOrders,
        uint256 privateKey
    ) private pure returns (bytes memory) {
        bytes32 hash = keccak256(encodedOrders);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        return abi.encodePacked(r, s, v);
    }

    function _createIdFromPrincipal(
        bytes memory principal
    ) private pure returns (bytes32) {
        return bytes32(abi.encodePacked(uint8(0), uint8(principal.length), principal));
    }

    function _createIdFromAddress(address addr, uint32 chainID) private pure returns (bytes32) {
        return bytes32(abi.encodePacked(uint8(1), chainID, addr));
    }

    //// tests for the native token
    function testBatchMintNativeToken() public {
        vm.startPrank(_owner);

        // Fund the bridge with ETH for minting
        vm.deal(address(_wrappedBridge), 10 ether);

        // Create native token mint order
        bytes32 base_token_id = _createIdFromPrincipal(abi.encodePacked(uint8(1)));
        MintOrder memory order = _createDefaultMintOrder();
        order.amount = 1 ether;
        order.toERC20 = _wrappedBridge.NATIVE_TOKEN_ADDRESS();
        order.recipient = payable(_alice);

        MintOrder[] memory orders = new MintOrder[](1);
        orders[0] = order;
        bytes memory encodedOrders = _batchMintOrders(orders);
        bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);

        uint32[] memory ordersToProcess = new uint32[](1);
        ordersToProcess[0] = 0;

        // Record initial balance
        uint256 initialBalance = _alice.balance;

        // Execute mint
        uint8[] memory processedOrders = _wrappedBridge.batchMint(encodedOrders, signature, ordersToProcess);

        assertEq(processedOrders[0], _wrappedBridge.MINT_ERROR_CODE_OK());
        assertEq(_alice.balance - initialBalance, order.amount);

        vm.stopPrank();
    }

    function testBurnNativeToken() public {
        vm.startPrank(_owner);
        uint256 burnAmount = 1 ether;
        uint256 burnFee = _baseBridge.burnFeeInWei();
        uint256 totalAmount = burnAmount + burnFee;

        vm.deal(_alice, totalAmount);

        bytes32 toTokenId = _createIdFromPrincipal(abi.encodePacked(uint8(1)));
        bytes memory recipientId = abi.encodePacked(uint8(1), uint8(2), uint8(3));

        // vm.startPrank(_alice);
        vm.stopPrank();
        vm.startPrank(_alice);

        uint256 initialBridgeBalance = address(_baseBridge).balance;
        uint256 initialAliceBalance = _alice.balance;

        uint32 operationId = _baseBridge.burn{ value: totalAmount }(
            burnAmount, _baseBridge.NATIVE_TOKEN_ADDRESS(), toTokenId, recipientId, bytes32(0)
        );

        vm.stopPrank();

        assertEq(address(_baseBridge).balance - initialBridgeBalance, totalAmount, "Bridge balance should increase");
        assertEq(_alice.balance, initialAliceBalance - totalAmount, "Alice balance should decrease");
    }

    function testBatchMintMixedTokens() public {
        vm.startPrank(_owner);

        // Fund bridge with ETH
        vm.deal(address(_wrappedBridge), 10 ether);

        // Setup ERC20
        bytes32 baseTokenId1 = _createIdFromPrincipal(abi.encodePacked(uint8(1)));
        address token1 = _wrappedBridge.deployERC20("Token1", "TK1", 18, baseTokenId1);
        MintOrder memory order1 = _createDefaultMintOrder(baseTokenId1, token1, 0);

        // Setup Native Token
        MintOrder memory order2 = _createDefaultMintOrder();
        order2.toERC20 = _wrappedBridge.NATIVE_TOKEN_ADDRESS();
        order2.amount = 1 ether;
        order2.nonce = 1;

        MintOrder[] memory orders = new MintOrder[](2);
        orders[0] = order1;
        orders[1] = order2;

        bytes memory encodedOrders = _batchMintOrders(orders);
        bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);

        uint32[] memory ordersToProcess = new uint32[](2);
        ordersToProcess[0] = 0;
        ordersToProcess[1] = 1;

        uint8[] memory processedOrders = _wrappedBridge.batchMint(encodedOrders, signature, ordersToProcess);
        vm.stopPrank();
    }

    // Add this helper function to ensure correct initialization
    function ensureBaseBridgeSetup() private {
        // Add any necessary setup for base bridge
        require(_baseBridge.isWrappedSide() == false, "Must use base side for native tokens");
    }
    // Add these helper functions to BTFBridgeTest

    function setupBaseBridge() internal {
        // Initialize base bridge data
        bytes[] memory data = new bytes[](0);
        address[] memory initialControllers = new address[](0);

        // Initialize base bridge with correct parameters
        bytes memory baseInitData = abi.encodeWithSelector(
            BTFBridge.initialize.selector,
            _owner, // minter address
            address(0), // fee charge address
            address(_wrappedTokenDeployer),
            false, // isWrappedSide = false for base bridge
            _owner, // owner
            initialControllers
        );

        BTFBridge baseImpl = new BTFBridge();
        UUPSProxy baseProxyContract = new UUPSProxy(address(baseImpl), baseInitData);
        baseProxy = payable(address(baseProxyContract));
        _baseBridge = BTFBridge(payable(baseProxy));
    }

    function testBatchMintInvalidAmount() public {
        // Single prank session
        vm.startPrank(_owner);
        // Create tokens and setup
        MintOrder memory order = _createDefaultMintOrder();
        address token = order.toERC20;

        order.amount = 0;
        MintOrder[] memory orders = new MintOrder[](1);
        orders[0] = order;

        bytes memory encodedOrders = _batchMintOrders(orders);
        bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);

        uint32[] memory ordersToProcess = new uint32[](1);
        ordersToProcess[0] = 0;

        uint8[] memory processedOrders = _wrappedBridge.batchMint(encodedOrders, signature, ordersToProcess);
        vm.stopPrank();

        assertEq(processedOrders[0], _wrappedBridge.MINT_ERROR_CODE_ZERO_AMOUNT());
    }

    function testBurnNativeTokenInsufficientBalance() public {
    uint256 burnAmount = 1 ether;
    uint256 burnFee = _baseBridge.burnFeeInWei();
    uint256 sentAmount = burnAmount;  // Only sending burn amount, not fee
    
    // Debug prints
    console.log("\nTest Configuration:");
    console.log("Burn amount:", burnAmount);
    console.log("Burn fee:", burnFee);
    console.log("Total required:", burnAmount + burnFee);
    console.log("Amount sending:", sentAmount);
    
    vm.deal(_alice, sentAmount);
    console.log("Alice balance:", _alice.balance);
    
    bytes32 toTokenId = _createIdFromPrincipal(abi.encodePacked(uint8(1)));
    bytes memory recipientId = abi.encodePacked(uint8(1));
    
    vm.startPrank(_alice);
    
    // Try the operation and capture the exact error
    bool hasError;
    string memory errorMessage;
    
    try _baseBridge.burn{value: sentAmount}(
        burnAmount,
        _baseBridge.NATIVE_TOKEN_ADDRESS(),
        toTokenId,
        recipientId,
        bytes32(0)
    ) {
        hasError = false;
    } catch Error(string memory reason) {
        hasError = true;
        errorMessage = reason;
        console.log("\nCaught revert with reason:", reason);
    } catch (bytes memory rawError) {
        hasError = true;
        console.log("\nCaught raw error:");
        console.logBytes(rawError);
    }
    
    assertTrue(hasError, "Should have reverted");
    if (bytes(errorMessage).length > 0) {
        assertEq(errorMessage, "Must send: amount + fee", "Wrong error message");
    }
    
    vm.stopPrank();
}

    function testValidateOrderWithNativeToken() public {
        vm.startPrank(_owner); // Start as owner/controller

        // Fund bridge with ETH
        vm.deal(address(_wrappedBridge), 10 ether);

        // Create a mint order for native token
        MintOrder memory order = _createDefaultMintOrder();
        order.toERC20 = _wrappedBridge.NATIVE_TOKEN_ADDRESS();
        order.fromTokenID = bytes32(0); // native token ID
        order.amount = 1 ether; // Set specific amount for easier checking

        // Record initial balance
        uint256 initialBalance = order.recipient.balance;

        MintOrder[] memory orders = new MintOrder[](1);
        orders[0] = order;
        bytes memory encodedOrders = _batchMintOrders(orders);
        bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);

        uint32[] memory ordersToProcess = new uint32[](1);
        ordersToProcess[0] = 0;

        // This should pass because we skip ERC20 validation for native token
        uint8[] memory processedOrders = _wrappedBridge.batchMint(encodedOrders, signature, ordersToProcess);

        // Verify mint was successful
        assertEq(processedOrders[0], _wrappedBridge.MINT_ERROR_CODE_OK(), "Native token mint should succeed");

        // Verify actual ETH transfer
        assertEq(order.recipient.balance - initialBalance, order.amount, "Native token transfer should succeed");

        vm.stopPrank();
    }

    function testBurnNativeTokenTransfers() public {
        // Get burn fee
        uint256 burnFee = _baseBridge.burnFeeInWei();
        uint256 burnAmount = 1 ether;
        uint256 totalAmount = burnAmount + burnFee; // Total needed is burn amount + fee

        // Fund accounts
        vm.deal(_alice, totalAmount); // Give Alice enough for amount + fee
        vm.deal(address(_baseBridge), 1 ether);

        bytes32 toTokenId = _createIdFromPrincipal(abi.encodePacked(uint8(1)));
        bytes memory recipientId = abi.encodePacked(uint8(1), uint8(2), uint8(3));

        uint256 initialBalance = _alice.balance;
        uint256 initialBridgeBalance = address(_baseBridge).balance;

        vm.startPrank(_alice);
        uint32 operationId = _baseBridge.burn{ value: totalAmount }( // Send total amount (burn + fee)
            burnAmount, // Amount to burn
            address(0), // Native token address
            toTokenId,
            recipientId,
            bytes32(0)
        );
        vm.stopPrank();

        // Verify balances changed correctly
        assertEq(_alice.balance, initialBalance - totalAmount, "Alice balance didn't decrease by correct amount");
        assertEq(
            address(_baseBridge).balance,
            initialBridgeBalance + totalAmount,
            "Bridge balance didn't increase by correct amount"
        );

        // Optional: verify the collected fees
        assertEq(_baseBridge.collectedBurnFees(), burnFee, "Burn fee wasn't collected correctly");
    }

    function testValidateOrderSkipsTokenPairCheckForNative() public {
        vm.startPrank(_owner); // Start as owner/controller

        // Setup the order for native ETH
        MintOrder memory order = _createDefaultMintOrder();
        order.toERC20 = address(0); // Native ETH
        order.amount = 1 ether;

        // Fund the bridge with ETH
        vm.deal(address(_wrappedBridge), 1 ether);

        // Use an unregistered token ID - this would fail for non-native tokens
        order.fromTokenID = bytes32(uint256(123)); // Random token ID

        // Setup the mint operation
        MintOrder[] memory orders = new MintOrder[](1);
        orders[0] = order;
        bytes memory encodedOrders = _batchMintOrders(orders);
        bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);

        uint32[] memory ordersToProcess = new uint32[](1);
        ordersToProcess[0] = 0;

        // Record initial balance
        uint256 initialBalance = order.recipient.balance;

        // Execute mint
        uint8[] memory processedOrders = _wrappedBridge.batchMint(encodedOrders, signature, ordersToProcess);

        // Verify mint was successful
        assertEq(processedOrders[0], _wrappedBridge.MINT_ERROR_CODE_OK(), "Mint should succeed for native token");
        assertEq(order.recipient.balance - initialBalance, order.amount, "Native token transfer should succeed");

        vm.stopPrank();
    }

    function testBytes32ZeroForNativeToken() public {
        vm.startPrank(_owner); // Start as owner (who is a controller)

        // Create order with native token (address(0))
        MintOrder memory order = _createDefaultMintOrder();
        order.toERC20 = address(0);
        order.fromTokenID = bytes32(0);
        order.amount = 1 ether;

        // Fund bridge with ETH for the transfer
        vm.deal(address(_wrappedBridge), 1 ether);

        // Setup mint order
        MintOrder[] memory orders = new MintOrder[](1);
        orders[0] = order;
        bytes memory encodedOrders = _batchMintOrders(orders);
        bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);

        uint32[] memory ordersToProcess = new uint32[](1);
        ordersToProcess[0] = 0;

        // Record initial balance
        uint256 initialBalance = order.recipient.balance;

        // Should pass even though bytes32(0) is used
        uint8[] memory processedOrders = _wrappedBridge.batchMint(encodedOrders, signature, ordersToProcess);

        // Verify mint was successful
        assertEq(processedOrders[0], _wrappedBridge.MINT_ERROR_CODE_OK());
        assertEq(order.recipient.balance - initialBalance, order.amount, "Native token transfer failed");

        vm.stopPrank();
    }


    function testBurnFeeCollection() public {
    // Start with owner to set up initial state
    vm.startPrank(_owner);
    
    // Set and verify burn fee
    uint256 burnFee = 0.01 ether;
    _baseBridge.updateBurnFee(burnFee);
    assertEq(_baseBridge.burnFeeInWei(), burnFee, "Burn fee not set");
    
    // Create token and mint to owner using batch mint
    bytes32 baseTokenId = _createIdFromPrincipal(abi.encodePacked(uint8(1)));
    address wrappedToken = _wrappedBridge.deployERC20("Test", "TST", 18, baseTokenId);
    
    // Create mint order for Alice
    uint256 burnAmount = 1 ether;
    MintOrder memory order = MintOrder({
        amount: burnAmount,
        senderID: baseTokenId,
        fromTokenID: baseTokenId,
        recipient: _alice,
        toERC20: wrappedToken,
        nonce: 0,
        senderChainID: 0,
        recipientChainID: _CHAIN_ID,
        name: StringUtils.truncateUTF8("Test"),
        symbol: bytes16(StringUtils.truncateUTF8("TST")),
        decimals: 18,
        approveSpender: address(0),
        approveAmount: 0,
        feePayer: address(0)
    });

    // Batch mint tokens to Alice
    MintOrder[] memory orders = new MintOrder[](1);
    orders[0] = order;
    bytes memory encodedOrders = _batchMintOrders(orders);
    bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);
    
    uint32[] memory ordersToProcess = new uint32[](1);
    ordersToProcess[0] = 0;
    _wrappedBridge.batchMint(encodedOrders, signature, ordersToProcess);
    
    vm.stopPrank();

    // Verify Alice received tokens
    assertEq(WrappedToken(wrappedToken).balanceOf(_alice), burnAmount, "Token mint failed");

    // Setup Alice for burn
    vm.startPrank(_alice);
    vm.deal(_alice, burnFee);  // Give Alice just the fee amount
    
    // Record initial states
    uint256 initialAliceBalance = _alice.balance;
    uint256 initialBridgeBalance = address(_baseBridge).balance;
    uint256 initialCollectedFees = _baseBridge.collectedBurnFees();
    
    // Approve bridge to spend tokens
    WrappedToken(wrappedToken).approve(address(_baseBridge), burnAmount);
    
    // Burn with fee
    _baseBridge.burn{value: burnFee}(
        burnAmount,
        wrappedToken,
        baseTokenId,
        abi.encodePacked(uint8(1)),
        bytes32(0)
    );
    
    // Verify state changes
    assertEq(_baseBridge.collectedBurnFees(), initialCollectedFees + burnFee, "Fee collection failed");
    assertEq(address(_baseBridge).balance, initialBridgeBalance + burnFee, "Bridge balance incorrect");
    assertEq(_alice.balance, initialAliceBalance - burnFee, "Alice balance incorrect");
    assertEq(WrappedToken(wrappedToken).balanceOf(_alice), 0, "Tokens not burned");
    
    vm.stopPrank();
}

function testNativeTokenBurnFeeCollection() public {
    vm.startPrank(_owner);
    
    // Set fee to 0.01 ETH
    uint256 burnFee = 0.01 ether;
    _baseBridge.updateBurnFee(burnFee);
    
    vm.stopPrank();
    
    // Test burning ETH
    uint256 burnAmount = 1 ether;
    uint256 totalRequired = burnAmount + burnFee;
    
    vm.deal(_alice, totalRequired);
    vm.startPrank(_alice);
    
    _baseBridge.burn{value: totalRequired}(
        burnAmount,
        _baseBridge.NATIVE_TOKEN_ADDRESS(),  // Use native token address
        bytes32(0),  // Native token ID
        abi.encodePacked(uint8(1)),
        bytes32(0)
    );
    
    assertEq(_baseBridge.collectedBurnFees(), burnFee, "Fee not collected");
    vm.stopPrank();
}

    function testBurnFeeWithdrawal() public {
    // Setup initial state
    vm.startPrank(_owner);
    uint256 burnFee = 0.01 ether;
    _baseBridge.updateBurnFee(burnFee);
    
    // Setup token for burn
    bytes32 baseTokenId = _createIdFromPrincipal(abi.encodePacked(uint8(1)));
    address wrappedToken = _wrappedBridge.deployERC20("Test", "TST", 18, baseTokenId);
    vm.stopPrank();
    
    // Setup and execute burn to collect fees
    vm.startPrank(_alice);
    vm.deal(_alice, burnFee);
    
    // Record initial balances
    uint256 initialBridgeBalance = address(_baseBridge).balance;
    uint256 initialCollectedFees = _baseBridge.collectedBurnFees();
    
    // Burn with fee
    _baseBridge.burn{value: burnFee}(
        0,  // Zero burn amount to test just fee
        wrappedToken,
        baseTokenId,
        abi.encodePacked(uint8(1)),
        bytes32(0)
    );
    
    // Verify fee collection
    assertEq(_baseBridge.collectedBurnFees(), initialCollectedFees + burnFee, "Fee not collected");
    assertEq(address(_baseBridge).balance, initialBridgeBalance + burnFee, "Bridge balance wrong");
    vm.stopPrank();
    
    // Test non-owner withdrawal
    vm.startPrank(_alice);
    vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", _alice));
    _baseBridge.withdrawBurnFees();
    vm.stopPrank();
    
    // Test owner withdrawal
    uint256 initialOwnerBalance = _owner.balance;
    vm.startPrank(_owner);
    _baseBridge.withdrawBurnFees();
    
    // Verify withdrawal
    assertEq(_owner.balance, initialOwnerBalance + burnFee, "Fee withdrawal failed");
    assertEq(_baseBridge.collectedBurnFees(), 0, "Collected fees not reset");
    vm.stopPrank();
}

    function testBurnWithoutFee() public {
    // 1. Owner setup
    vm.startPrank(_owner);
    
    // Set burn fee
    uint256 burnFee = 0.01 ether;
    _baseBridge.updateBurnFee(burnFee);
    
    // Create and deploy token
    bytes32 baseTokenId = _createIdFromPrincipal(abi.encodePacked(uint8(1)));
    address wrappedToken = _wrappedBridge.deployERC20("Test", "TST", 18, baseTokenId);
    
    // Create and mint tokens to Alice
    MintOrder memory order = _createDefaultMintOrder(baseTokenId, wrappedToken, 0);
    order.recipient = _alice;
    order.amount = 1 ether;
    
    // Batch mint
    MintOrder[] memory orders = new MintOrder[](1);
    orders[0] = order;
    bytes memory encodedOrders = _batchMintOrders(orders);
    bytes memory signature = _batchMintOrdersSignature(encodedOrders, _OWNER_KEY);
    _wrappedBridge.batchMint(encodedOrders, signature, new uint32[](0));
    
    vm.stopPrank();

    // Verify initial state
    assertEq(WrappedToken(wrappedToken).balanceOf(_alice), 1 ether, "Token mint failed");

    // Try burning without fee
    vm.startPrank(_alice);
    
    // Approve bridge
    WrappedToken(wrappedToken).approve(address(_baseBridge), 1 ether);
    
    // Try to burn without fee - should fail
    vm.expectRevert("Insufficient burn fee"); // Changed to match actual contract error
    _baseBridge.burn(
        1 ether,
        wrappedToken,
        baseTokenId,
        abi.encodePacked(uint8(1)),
        bytes32(0)
    );
    
    // Verify nothing changed
    assertEq(WrappedToken(wrappedToken).balanceOf(_alice), 1 ether, "Tokens should not be burned");
    
    vm.stopPrank();
}
function testBurnFeeUpdate() public {
    vm.startPrank(_owner);
    
    uint256 newFee = 0.02 ether;
    uint256 oldFee = _baseBridge.burnFeeInWei();
    
    // Expect event emission
    vm.expectEmit(true, true, false, true);
    emit BurnFeeUpdated(oldFee, newFee);
    
    // Update fee as owner
    _baseBridge.updateBurnFee(newFee);
    assertEq(_baseBridge.burnFeeInWei(), newFee, "Fee not updated");
    
    vm.stopPrank();
    
    // Test non-owner access
    vm.startPrank(_alice);
    // Use the correct error format for OpenZeppelin's Ownable
    vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", _alice));
    _baseBridge.updateBurnFee(0.03 ether);
    vm.stopPrank();
    
    // Verify fee didn't change
    assertEq(_baseBridge.burnFeeInWei(), newFee, "Fee should not change from non-owner");
}

    function testZeroFeeWithdrawal() public {
        vm.prank(_owner);
        vm.expectRevert("No fees to withdraw");
        _baseBridge.withdrawBurnFees();
    }

}
