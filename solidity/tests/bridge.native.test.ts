import { expect } from 'chai';
import { ethers } from 'ethers';
import dotenv from 'dotenv';
import chai from 'chai';

// Updated ABI with more specific function definitions
const BRIDGE_ABI = [
    {
        "inputs": [],
        "name": "NATIVE_TOKEN_ADDRESS",
        "outputs": [{"internalType": "address", "name": "", "type": "address"}],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [
            {"internalType": "uint256", "name": "amount", "type": "uint256"},
            {"internalType": "address", "name": "fromERC20", "type": "address"},
            {"internalType": "bytes32", "name": "toTokenID", "type": "bytes32"},
            {"internalType": "bytes", "name": "recipientID", "type": "bytes"},
            {"internalType": "bytes32", "name": "memo", "type": "bytes32"}
        ],
        "name": "burn",
        "outputs": [{"internalType": "uint32", "name": "", "type": "uint32"}],
        "stateMutability": "payable",
        "type": "function"
    }
];

describe("BTF Bridge Native Token Tests", () => {
    let sepoliaProvider: ethers.JsonRpcProvider;
    let sepoliaBridge: ethers.Contract;
    let signer: ethers.Wallet;

    const SEPOLIA_BRIDGE = "0xfaE2d016F15F77354dFe85355c0640B657034EC4";

    before(async () => {
        console.log("Setting up test environment...");
        sepoliaProvider = new ethers.JsonRpcProvider('https://sepolia.infura.io/v3/895d773d17f043008769af24d76f0ac1');

        const privateKey = '0x388011f48124700b5c553b4b1c4b10b31e9c04fecb7b3b85a4231b8ede8d126e';
        signer = new ethers.Wallet(privateKey, sepoliaProvider);
        console.log("Signer address:", await signer.getAddress());

        sepoliaBridge = new ethers.Contract(
            SEPOLIA_BRIDGE,
            BRIDGE_ABI,
            signer
        );

        // Verify contract
        const code = await sepoliaProvider.getCode(SEPOLIA_BRIDGE);
        console.log("Contract code length:", code.length);
        if (code === '0x') throw new Error('Contract not found at address');
    });

    describe("Native Token Tests", () => {
        // it("should get NATIVE_TOKEN_ADDRESS", async function() {
        //     this.timeout(10000);
        //     try {
        //         const nativeTokenAddress = await sepoliaBridge.NATIVE_TOKEN_ADDRESS();
        //         console.log("Native token address:", nativeTokenAddress);
        //         expect(nativeTokenAddress.toLowerCase()).to.equal("0x0000000000000000000000000000000000000000");
        //     } catch (error) {
        //         console.error("Error getting NATIVE_TOKEN_ADDRESS:", error);
        //         throw error;
        //     }
        // });
        
        it("should burn native tokens", async function() {
            this.timeout(30000);
            
            const amount = ethers.parseEther("0.01");
            const toTokenId = ethers.zeroPadBytes(ethers.toUtf8Bytes("NATIVE_TOKEN"), 32);
            const recipientId = ethers.toUtf8Bytes(await signer.getAddress());
            const memo = ethers.ZeroHash;

            console.log("Preparing burn transaction...");
            console.log("Amount:", ethers.formatEther(amount), "ETH");
            console.log("Recipient:", ethers.hexlify(recipientId));

            try {
                // Check initial balances
                const initialBalance = await sepoliaProvider.getBalance(signer.address);
                console.log("Initial balance:", ethers.formatEther(initialBalance));

                // Estimate gas
                const gasEstimate = await sepoliaBridge.burn.estimateGas(
                    amount,
                    ethers.ZeroAddress,
                    toTokenId,
                    recipientId,
                    memo,
                    { value: amount }
                );
                console.log("Estimated gas:", gasEstimate.toString());

                // Send transaction
                const tx = await sepoliaBridge.burn(
                    amount,
                    ethers.ZeroAddress,
                    toTokenId,
                    recipientId,
                    memo,
                    { 
                        value: amount,
                        gasLimit: (gasEstimate * 12n) / 10n  // Add 20% buffer
                    }
                );

                console.log("Transaction sent:", tx.hash);
                const receipt = await tx.wait();
                console.log("Transaction confirmed in block:", receipt.blockNumber);

                const finalBalance = await sepoliaProvider.getBalance(signer.address);
                console.log("Final balance:", ethers.formatEther(finalBalance));

                expect(initialBalance - finalBalance > amount).to.be.true;
            } catch (error) {
                console.error("Error burning tokens:", error);
                throw error;
            }
        });
    });
});