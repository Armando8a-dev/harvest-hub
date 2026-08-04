export const HARVEST_HUB_ADDRESS = "0xc11faB6eA199Ebd60207d5b8C3de2C3b0aB918d4" as const;
export const HRV_TOKEN_ADDRESS = "0xFE87a075F68626f2Ab49af547c6521Bf5325AD1e" as const;

// The two pools created at deploy time.
export const POOLS = [
  {
    id: "0x79004c100e7f5273b4b9ede0bd45511fa12029a2c28503e7d975153422c7d1cf" as const,
    name: "SEED Pool",
    stakeToken: "0x3eDc43FC2AF7BC6dAF554FE976299bA43807ce9C" as const,
    stakeSymbol: "SEED",
    rate: "0.001",
  },
  {
    id: "0xac4f28e39d948bc13bfdd5ffe8a13bc826038dd86dfa0bb667840fbc7a2bc864" as const,
    name: "CORN Pool",
    stakeToken: "0x23B9107fBC60e9ca8c994ca4483dB8B50BA4F3Fc" as const,
    stakeSymbol: "CORN",
    rate: "0.005",
  },
] as const;

export const HARVEST_HUB_ABI = [
  { type: "function", name: "pendingRewards", inputs: [{ type: "bytes32" }, { type: "address" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "pools", inputs: [{ type: "bytes32" }], outputs: [
      { name: "stakeToken", type: "address" },
      { name: "totalStaked", type: "uint256" },
      { name: "rewardRate", type: "uint256" },
      { name: "lastUpdateTime", type: "uint256" },
      { name: "accRewardPerShare", type: "uint256" },
      { name: "isActive", type: "bool" },
    ], stateMutability: "view" },
  { type: "function", name: "userInfo", inputs: [{ type: "bytes32" }, { type: "address" }], outputs: [
      { name: "amount", type: "uint256" },
      { name: "rewardDebt", type: "uint256" },
    ], stateMutability: "view" },
  { type: "function", name: "stake", inputs: [{ type: "bytes32" }, { type: "uint256" }], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "withdraw", inputs: [{ type: "bytes32" }, { type: "uint256" }], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "harvest", inputs: [{ type: "bytes32" }], outputs: [], stateMutability: "nonpayable" },
] as const;

export const ERC20_ABI = [
  { type: "function", name: "balanceOf", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "allowance", inputs: [{ type: "address" }, { type: "address" }], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "approve", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [{ type: "bool" }], stateMutability: "nonpayable" },
  { type: "function", name: "faucet", inputs: [], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "symbol", inputs: [], outputs: [{ type: "string" }], stateMutability: "view" },
] as const;
