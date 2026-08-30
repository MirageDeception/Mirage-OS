import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { LayoutDashboard, BrainCircuit, Network, Settings, ShieldAlert } from "lucide-react";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: "MIRAGE | Enterprise Deception Fabric",
  description: "Automated deployment and management of deception security across AWS.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className={inter.className} suppressHydrationWarning>
        <div className="portal-container">
          <aside className="sidebar">
            <div className="sidebar-header">
              <h2 className="text-gradient">MIRAGE</h2>
            </div>
            <nav className="sidebar-nav">
              <a href="/" className="nav-link">
                <LayoutDashboard size={20} />
                <span>Dashboard</span>
              </a>
              <a href="/deploy-brain" className="nav-link">
                <BrainCircuit size={20} />
                <span>Deploy Brain</span>
              </a>
              <a href="/catalog" className="nav-link">
                <Network size={20} />
                <span>Deception Catalog</span>
              </a>
              <a href="/alerts" className="nav-link">
                <ShieldAlert size={20} />
                <span>Active Alerts</span>
              </a>
              <a href="/settings" className="nav-link">
                <Settings size={20} />
                <span>Settings</span>
              </a>
            </nav>
          </aside>
          <main className="main-content">
            {children}
          </main>
        </div>
      </body>
    </html>
  );
}
