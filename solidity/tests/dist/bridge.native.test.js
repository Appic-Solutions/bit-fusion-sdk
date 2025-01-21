"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
var __generator = (this && this.__generator) || function (thisArg, body) {
    var _ = { label: 0, sent: function() { if (t[0] & 1) throw t[1]; return t[1]; }, trys: [], ops: [] }, f, y, t, g;
    return g = { next: verb(0), "throw": verb(1), "return": verb(2) }, typeof Symbol === "function" && (g[Symbol.iterator] = function() { return this; }), g;
    function verb(n) { return function (v) { return step([n, v]); }; }
    function step(op) {
        if (f) throw new TypeError("Generator is already executing.");
        while (g && (g = 0, op[0] && (_ = 0)), _) try {
            if (f = 1, y && (t = op[0] & 2 ? y["return"] : op[0] ? y["throw"] || ((t = y["return"]) && t.call(y), 0) : y.next) && !(t = t.call(y, op[1])).done) return t;
            if (y = 0, t) op = [op[0] & 2, t.value];
            switch (op[0]) {
                case 0: case 1: t = op; break;
                case 4: _.label++; return { value: op[1], done: false };
                case 5: _.label++; y = op[1]; op = [0]; continue;
                case 7: op = _.ops.pop(); _.trys.pop(); continue;
                default:
                    if (!(t = _.trys, t = t.length > 0 && t[t.length - 1]) && (op[0] === 6 || op[0] === 2)) { _ = 0; continue; }
                    if (op[0] === 3 && (!t || (op[1] > t[0] && op[1] < t[3]))) { _.label = op[1]; break; }
                    if (op[0] === 6 && _.label < t[1]) { _.label = t[1]; t = op; break; }
                    if (t && _.label < t[2]) { _.label = t[2]; _.ops.push(op); break; }
                    if (t[2]) _.ops.pop();
                    _.trys.pop(); continue;
            }
            op = body.call(thisArg, _);
        } catch (e) { op = [6, e]; y = 0; } finally { f = t = 0; }
        if (op[0] & 5) throw op[1]; return { value: op[0] ? op[1] : void 0, done: true };
    }
};
exports.__esModule = true;
var chai_1 = require("chai");
var ethers_1 = require("ethers");
var chai_as_promised_1 = require("chai-as-promised");
// Enable chai-as-promised
var chai_2 = require("chai");
chai_2["default"].use(chai_as_promised_1["default"]);
var BRIDGE_ABI = [
    {
        "inputs": [],
        "name": "NATIVE_TOKEN_ADDRESS",
        "outputs": [{ "internalType": "address", "name": "", "type": "address" }],
        "stateMutability": "view",
        "type": "function"
    },
    {
        "inputs": [
            { "internalType": "uint256", "name": "amount", "type": "uint256" },
            { "internalType": "address", "name": "fromERC20", "type": "address" },
            { "internalType": "bytes32", "name": "toTokenID", "type": "bytes32" },
            { "internalType": "bytes", "name": "recipientID", "type": "bytes" },
            { "internalType": "bytes32", "name": "memo", "type": "bytes32" }
        ],
        "name": "burn",
        "outputs": [{ "internalType": "uint32", "name": "", "type": "uint32" }],
        "stateMutability": "payable",
        "type": "function"
    }
];
describe("BTF Bridge Native Token Tests", function () {
    var provider;
    var bridgeContract;
    var signer;
    var BRIDGE_ADDRESS = "0x0150B54605423F85d076Ea483De87e488fC266AE";
    before(function () { return __awaiter(void 0, void 0, void 0, function () {
        var contractBalance, privateKey, _a, _b, _c, code;
        return __generator(this, function (_d) {
            switch (_d.label) {
                case 0:
                    console.log("Setting up test environment...");
                    provider = new ethers_1.ethers.JsonRpcProvider('https://holesky.infura.io/v3/895d773d17f043008769af24d76f0ac1');
                    return [4 /*yield*/, provider.getBalance(BRIDGE_ADDRESS)];
                case 1:
                    contractBalance = _d.sent();
                    console.log("Bridge Contract ETH Balance:", ethers_1.ethers.formatEther(contractBalance));
                    privateKey = '0x388011f48124700b5c553b4b1c4b10b31e9c04fecb7b3b85a4231b8ede8d126e';
                    signer = new ethers_1.ethers.Wallet(privateKey, provider);
                    _b = (_a = console).log;
                    _c = ["Signer address:"];
                    return [4 /*yield*/, signer.getAddress()];
                case 2:
                    _b.apply(_a, _c.concat([_d.sent()]));
                    bridgeContract = new ethers_1.ethers.Contract(BRIDGE_ADDRESS, BRIDGE_ABI, signer);
                    return [4 /*yield*/, provider.getCode(BRIDGE_ADDRESS)];
                case 3:
                    code = _d.sent();
                    console.log("Contract code length:", code.length);
                    if (code === '0x')
                        throw new Error('Contract not found at address');
                    return [2 /*return*/];
            }
        });
    }); });
    describe("Native Token Operations", function () {
        it("should burn native ETH tokens successfully", function () {
            return __awaiter(this, void 0, void 0, function () {
                var amount, toTokenId, recipientId, _a, _b, memo, initialBalance, tx, receipt, finalBalance, error_1;
                return __generator(this, function (_c) {
                    switch (_c.label) {
                        case 0:
                            this.timeout(60000); // Increased timeout to 60s
                            amount = ethers_1.ethers.parseEther("0.01");
                            toTokenId = ethers_1.ethers.zeroPadBytes(ethers_1.ethers.toUtf8Bytes("NATIVE_TOKEN"), 32);
                            _b = (_a = ethers_1.ethers).toUtf8Bytes;
                            return [4 /*yield*/, signer.getAddress()];
                        case 1:
                            recipientId = _b.apply(_a, [_c.sent()]);
                            memo = ethers_1.ethers.ZeroHash;
                            console.log("Preparing burn transaction...");
                            console.log("Amount:", ethers_1.ethers.formatEther(amount), "ETH");
                            console.log("Recipient:", ethers_1.ethers.hexlify(recipientId));
                            _c.label = 2;
                        case 2:
                            _c.trys.push([2, 7, , 8]);
                            return [4 /*yield*/, provider.getBalance(signer.address)];
                        case 3:
                            initialBalance = _c.sent();
                            console.log("Initial balance:", ethers_1.ethers.formatEther(initialBalance));
                            return [4 /*yield*/, bridgeContract.burn(amount, ethers_1.ethers.ZeroAddress, toTokenId, recipientId, memo, { value: amount })];
                        case 4:
                            tx = _c.sent();
                            console.log("Transaction sent:", tx.hash);
                            return [4 /*yield*/, tx.wait()];
                        case 5:
                            receipt = _c.sent();
                            console.log("Transaction confirmed in block:", receipt.blockNumber);
                            return [4 /*yield*/, provider.getBalance(signer.address)];
                        case 6:
                            finalBalance = _c.sent();
                            console.log("Final balance:", ethers_1.ethers.formatEther(finalBalance));
                            (0, chai_1.expect)(initialBalance - finalBalance > amount).to.be["true"];
                            return [3 /*break*/, 8];
                        case 7:
                            error_1 = _c.sent();
                            console.error("Error burning native tokens:", error_1);
                            throw error_1;
                        case 8: return [2 /*return*/];
                    }
                });
            });
        });
        it("should fail if incorrect ETH amount is sent", function () {
            return __awaiter(this, void 0, void 0, function () {
                var amount, toTokenId, recipientId, _a, _b, memo;
                return __generator(this, function (_c) {
                    switch (_c.label) {
                        case 0:
                            this.timeout(30000);
                            amount = ethers_1.ethers.parseEther("0.01");
                            toTokenId = ethers_1.ethers.zeroPadBytes(ethers_1.ethers.toUtf8Bytes("NATIVE_TOKEN"), 32);
                            _b = (_a = ethers_1.ethers).toUtf8Bytes;
                            return [4 /*yield*/, signer.getAddress()];
                        case 1:
                            recipientId = _b.apply(_a, [_c.sent()]);
                            memo = ethers_1.ethers.ZeroHash;
                            console.log("Testing burn failure due to incorrect ETH amount...");
                            return [4 /*yield*/, (0, chai_1.expect)(bridgeContract.burn(amount, // Expecting 0.01 ETH burn
                                ethers_1.ethers.ZeroAddress, toTokenId, recipientId, memo, { value: ethers_1.ethers.parseEther("0.015") } // Sending 0.015 ETH instead
                                )).to.be.rejectedWith(Error)];
                        case 2:
                            _c.sent();
                            return [2 /*return*/];
                    }
                });
            });
        });
        it("should fail if user has insufficient ETH", function () {
            return __awaiter(this, void 0, void 0, function () {
                var amount, toTokenId, recipientId, _a, _b, memo;
                return __generator(this, function (_c) {
                    switch (_c.label) {
                        case 0:
                            this.timeout(30000);
                            amount = ethers_1.ethers.parseEther("1000");
                            toTokenId = ethers_1.ethers.zeroPadBytes(ethers_1.ethers.toUtf8Bytes("NATIVE_TOKEN"), 32);
                            _b = (_a = ethers_1.ethers).toUtf8Bytes;
                            return [4 /*yield*/, signer.getAddress()];
                        case 1:
                            recipientId = _b.apply(_a, [_c.sent()]);
                            memo = ethers_1.ethers.ZeroHash;
                            console.log("Testing burn failure due to insufficient ETH...");
                            return [4 /*yield*/, (0, chai_1.expect)(bridgeContract.burn(amount, ethers_1.ethers.ZeroAddress, toTokenId, recipientId, memo, { value: amount })).to.be.rejectedWith(Error)];
                        case 2:
                            _c.sent();
                            return [2 /*return*/];
                    }
                });
            });
        });
    });
});
