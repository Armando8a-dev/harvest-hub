import type { Metadata } from "next";
import { Providers } from "./providers";
import "./globals.css";

export const metadata: Metadata = {
  title: "HarvestHub — Multi-pool Yield Farm",
  description: "Stake different tokens across multiple pools and earn HRV rewards in real time. MasterChef-style accrual on Sepolia.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
