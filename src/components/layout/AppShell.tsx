import React from 'react';
import { Home, LogOut, PieChart, ShieldCheck, Users, Wallet } from 'lucide-react';
import { Link, Outlet, useLocation } from 'react-router-dom';
import { useAuth } from '../../contexts/AuthContext';

import { Logo } from '../common/Logo';

type NavItemProps = {
  to: string;
  icon: React.ComponentType<{ size?: number; strokeWidth?: number }>;
  label: string;
};

export const AppShell: React.FC = () => {
  const { signOut } = useAuth();
  const location = useLocation();

  const NavItem = ({ to, icon: Icon, label }: NavItemProps) => {
    const isActive = location.pathname === to;

    return (
      <Link
        to={to}
        className={`flex h-full w-full flex-col items-center justify-center gap-1 ${
          isActive ? 'text-primary-600' : 'text-gray-500 hover:text-gray-900'
        }`}
      >
        <Icon size={24} strokeWidth={isActive ? 2.5 : 2} />
        <span className="text-[10px] font-semibold">{label}</span>
      </Link>
    );
  };

  return (
    <div className="relative mx-auto flex min-h-screen max-w-md flex-col overflow-hidden bg-gray-50 shadow-xl">
      <header className="sticky top-0 z-10 flex items-center justify-between border-b border-gray-200 bg-white px-4 py-3 shadow-sm">
        <Logo variant="full" size="lg" />
        <div className="flex items-center gap-2">
          <Link
            to="/family/settings"
            className="flex h-10 w-10 items-center justify-center rounded-full bg-blue-50 text-blue-600 transition-colors hover:bg-blue-100"
            title="إدارة الأسرة"
          >
            <Users size={20} />
          </Link>
          <Link
            to="/account/security"
            className="flex h-10 w-10 items-center justify-center rounded-full bg-emerald-50 text-emerald-600 transition-colors hover:bg-emerald-100"
            title="أمان الحساب"
          >
            <ShieldCheck size={20} />
          </Link>
          <button
            onClick={signOut}
            className="flex h-10 w-10 items-center justify-center rounded-full bg-red-50 text-red-500 transition-colors hover:bg-red-100 hover:text-red-600"
            title="تسجيل الخروج"
            type="button"
          >
            <LogOut size={20} />
          </button>
        </div>
      </header>

      <main className="flex-1 overflow-y-auto p-4 pb-20">
        <Outlet />
      </main>

      <nav className="fixed bottom-0 h-16 w-full max-w-md border-t border-gray-200 bg-white sm:absolute">
        <div className="flex h-full items-center justify-around px-2">
          <NavItem to="/dashboard" icon={Home} label="الرئيسية" />
          <NavItem to="/wallets" icon={Wallet} label="المحافظ" />
          <NavItem to="/budgets" icon={PieChart} label="الميزانية" />
          <NavItem to="/family/settings" icon={Users} label="الأسرة" />
        </div>
      </nav>
    </div>
  );
};
