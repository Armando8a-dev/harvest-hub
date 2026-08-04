"use client";

import { useState, useEffect } from "react";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { formatEther, parseEther } from "viem";
import {
  HARVEST_HUB_ADDRESS, HRV_TOKEN_ADDRESS, HARVEST_HUB_ABI, ERC20_ABI, POOLS,
} from "./abi";

export default function Home() {
  const { address, isConnected } = useAccount();
  const [poolIdx, setPoolIdx] = useState<number>(0);
  const [amount, setAmount] = useState<string>("");

  const pool = POOLS[poolIdx];
  const { writeContract, data: txHash, isPending, reset } = useWriteContract();
  const { isLoading: isMining, isSuccess } = useWaitForTransactionReceipt({ hash: txHash });

  // ─── reads ────────────────────────────────────────────────────────────
  const { data: hrvBalance, refetch: refetchHrv } = useReadContract({
    address: HRV_TOKEN_ADDRESS, abi: ERC20_ABI, functionName: "balanceOf",
    args: address ? [address] : undefined, query: { enabled: !!address },
  });
  const { data: stakeBalance, refetch: refetchStake } = useReadContract({
    address: pool.stakeToken, abi: ERC20_ABI, functionName: "balanceOf",
    args: address ? [address] : undefined, query: { enabled: !!address },
  });
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: pool.stakeToken, abi: ERC20_ABI, functionName: "allowance",
    args: address ? [address, HARVEST_HUB_ADDRESS] : undefined, query: { enabled: !!address },
  });
  const { data: poolData, refetch: refetchPool } = useReadContract({
    address: HARVEST_HUB_ADDRESS, abi: HARVEST_HUB_ABI, functionName: "pools", args: [pool.id],
  });
  const { data: userData, refetch: refetchUser } = useReadContract({
    address: HARVEST_HUB_ADDRESS, abi: HARVEST_HUB_ABI, functionName: "userInfo",
    args: address ? [pool.id, address] : undefined, query: { enabled: !!address },
  });
  const { data: pending, refetch: refetchPending } = useReadContract({
    address: HARVEST_HUB_ADDRESS, abi: HARVEST_HUB_ABI, functionName: "pendingRewards",
    args: address ? [pool.id, address] : undefined,
    query: { enabled: !!address, refetchInterval: 5000 }, // live, every 5s
  });

  const refetchAll = () => {
    refetchHrv(); refetchStake(); refetchAllowance(); refetchPool(); refetchUser(); refetchPending();
  };

  useEffect(() => {
    if (isSuccess) { refetchAll(); reset(); }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isSuccess]);

  // struct fields arrive as positional tuples in wagmi v2
  const totalStaked = poolData?.[1] as bigint | undefined;
  const staked = userData?.[0] as bigint | undefined;

  const amountWei = amount ? parseEther(amount) : 0n;
  const needsApproval = allowance !== undefined && amountWei > 0n && (allowance as bigint) < amountWei;

  // ─── actions ──────────────────────────────────────────────────────────
  const faucet = () => writeContract({ address: pool.stakeToken, abi: ERC20_ABI, functionName: "faucet" });
  const approve = () => writeContract({
    address: pool.stakeToken, abi: ERC20_ABI, functionName: "approve", args: [HARVEST_HUB_ADDRESS, amountWei],
  });
  const stake = () => writeContract({
    address: HARVEST_HUB_ADDRESS, abi: HARVEST_HUB_ABI, functionName: "stake", args: [pool.id, amountWei],
  });
  const withdraw = () => writeContract({
    address: HARVEST_HUB_ADDRESS, abi: HARVEST_HUB_ABI, functionName: "withdraw", args: [pool.id, amountWei],
  });
  const harvest = () => writeContract({
    address: HARVEST_HUB_ADDRESS, abi: HARVEST_HUB_ABI, functionName: "harvest", args: [pool.id],
  });

  const busy = isPending || isMining;
  const fmt = (v?: bigint) => (v !== undefined ? Number(formatEther(v)).toLocaleString(undefined, { maximumFractionDigits: 4 }) : "—");

  return (
    <main className="min-h-screen p-4 md:p-8 max-w-2xl mx-auto">
      {/* Header */}
      <div className="flex items-center justify-between mb-8">
        <div>
          <h1 className="text-2xl font-bold text-emerald-400">🌾 HarvestHub</h1>
          <p className="text-sm text-white/50">Multi-pool yield farm · Sepolia</p>
        </div>
        <ConnectButton />
      </div>

      {/* HRV balance */}
      {isConnected && (
        <div className="mb-6 rounded-2xl border border-emerald-400/20 bg-emerald-400/5 p-4 flex items-center justify-between">
          <span className="text-sm text-white/60">Your HRV rewards balance</span>
          <span className="text-xl font-bold text-emerald-400">{fmt(hrvBalance as bigint)} HRV</span>
        </div>
      )}

      {/* Pool selector */}
      <div className="flex gap-2 mb-4">
        {POOLS.map((p, i) => (
          <button
            key={p.id}
            onClick={() => { setPoolIdx(i); setAmount(""); }}
            className={`flex-1 rounded-xl px-4 py-3 border text-sm font-semibold transition-colors ${
              i === poolIdx
                ? "border-emerald-400 bg-emerald-400/10 text-emerald-400"
                : "border-white/10 bg-white/5 text-white/60 hover:border-white/20"
            }`}
          >
            {p.name}
            <span className="block text-xs font-normal text-white/40 mt-0.5">{p.rate} HRV/sec</span>
          </button>
        ))}
      </div>

      {/* Pool card */}
      <div className="rounded-2xl border border-white/10 bg-white/5 p-6 mb-4">
        <div className="grid grid-cols-2 gap-4 text-sm">
          <div>
            <p className="text-white/50">Total staked in pool</p>
            <p className="text-lg font-semibold">{fmt(totalStaked)} {pool.stakeSymbol}</p>
          </div>
          <div>
            <p className="text-white/50">Your stake</p>
            <p className="text-lg font-semibold">{fmt(staked)} {pool.stakeSymbol}</p>
          </div>
        </div>

        {isConnected && (
          <div className="mt-4 pt-4 border-t border-white/10">
            <p className="text-white/50 text-sm">Pending rewards (live)</p>
            <p className="text-3xl font-bold text-emerald-400 tabular-nums">{fmt(pending as bigint)} HRV</p>
            <button
              onClick={harvest}
              disabled={busy || !pending || (pending as bigint) === 0n}
              className="mt-3 w-full bg-emerald-500 hover:bg-emerald-400 disabled:opacity-40 text-black font-semibold py-2 rounded-xl transition-colors"
            >
              {busy ? "..." : "🚜 Harvest rewards"}
            </button>
          </div>
        )}
      </div>

      {!isConnected ? (
        <div className="rounded-2xl border border-white/10 bg-white/5 p-12 text-center">
          <p className="text-4xl mb-4">🌾</p>
          <p className="text-white/60">Connect your wallet to stake and earn HRV.</p>
        </div>
      ) : (
        <>
          {/* Faucet */}
          <div className="rounded-2xl border border-white/10 bg-white/5 p-6 mb-4 flex items-center justify-between">
            <div>
              <p className="font-semibold">Need {pool.stakeSymbol}?</p>
              <p className="text-xs text-white/50">Your balance: {fmt(stakeBalance as bigint)} {pool.stakeSymbol}</p>
            </div>
            <button
              onClick={faucet} disabled={busy}
              className="bg-white/10 hover:bg-white/20 disabled:opacity-40 px-4 py-2 rounded-xl text-sm font-semibold transition-colors"
            >
              {busy ? "..." : `Get 1000 ${pool.stakeSymbol}`}
            </button>
          </div>

          {/* Stake / Withdraw */}
          <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
            <h2 className="font-semibold mb-4 text-emerald-400">Stake / Withdraw</h2>
            <input
              type="number" min="0" step="0.01" value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder={`Amount of ${pool.stakeSymbol}`}
              className="w-full bg-white/10 border border-white/20 rounded-xl px-4 py-2 mb-3 text-white focus:outline-none focus:border-emerald-400"
            />
            <div className="flex gap-2">
              {needsApproval ? (
                <button
                  onClick={approve} disabled={busy || !amount}
                  className="flex-1 bg-amber-500 hover:bg-amber-400 disabled:opacity-40 text-black font-semibold py-2 rounded-xl transition-colors"
                >
                  {busy ? "..." : "1. Approve"}
                </button>
              ) : (
                <button
                  onClick={stake} disabled={busy || !amount || amountWei === 0n}
                  className="flex-1 bg-emerald-500 hover:bg-emerald-400 disabled:opacity-40 text-black font-semibold py-2 rounded-xl transition-colors"
                >
                  {busy ? "..." : "Stake"}
                </button>
              )}
              <button
                onClick={withdraw}
                disabled={busy || !amount || amountWei === 0n || !staked || staked === 0n}
                className="flex-1 border border-white/20 hover:bg-white/10 disabled:opacity-40 font-semibold py-2 rounded-xl transition-colors"
              >
                {busy ? "..." : "Withdraw"}
              </button>
            </div>
            <p className="text-xs text-white/40 mt-3">
              Staking or withdrawing automatically harvests your pending rewards.
            </p>
          </div>
        </>
      )}

      <p className="text-center text-xs text-white/30 mt-8">
        Hub:{" "}
        <a href={`https://sepolia.etherscan.io/address/${HARVEST_HUB_ADDRESS}`} target="_blank" rel="noreferrer" className="underline">
          {HARVEST_HUB_ADDRESS.slice(0, 6)}...{HARVEST_HUB_ADDRESS.slice(-4)}
        </a>
      </p>
    </main>
  );
}
