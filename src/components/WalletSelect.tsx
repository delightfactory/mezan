import React from 'react';
import { Wallet } from '../types/models';

interface WalletSelectProps {
  wallets: Wallet[];
  value: string;
  onChange: (value: string) => void;
  required?: boolean;
  className?: string;
  filter?: 'ALL' | 'REAL' | 'ALLOCATED';
}

export const WalletSelect: React.FC<WalletSelectProps> = ({
  wallets,
  value,
  onChange,
  required = false,
  className = "w-full rounded-xl border border-gray-200 bg-white px-4 py-3 outline-none transition-all focus:border-primary-500 focus:ring-2 focus:ring-primary-100",
  filter = 'ALL'
}) => {
  const activeWallets = wallets.filter(w => !w.is_archived);

  const filteredWallets = filter === 'ALL' 
    ? activeWallets 
    : activeWallets.filter(w => w.type === filter);

  const realWallets = filteredWallets
    .filter(w => w.type === 'REAL')
    .sort((a, b) => {
      if (a.sort_order !== b.sort_order) {
        return (a.sort_order || 0) - (b.sort_order || 0);
      }
      return new Date(a.created_at).getTime() - new Date(b.created_at).getTime();
    });

  const allocatedWallets = filteredWallets
    .filter(w => w.type === 'ALLOCATED')
    .sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime());

  return (
    <select 
      value={value} 
      onChange={(e) => onChange(e.target.value)} 
      className={className} 
      required={required}
    >
      <option value="">اختر المحفظة...</option>
      
      {realWallets.length > 0 && (
        <optgroup label="المحافظ الأساسية">
          {realWallets.map(w => (
            <option key={w.id} value={w.id}>{w.name}</option>
          ))}
        </optgroup>
      )}

      {allocatedWallets.length > 0 && (
        <optgroup label="مخصصات وصناديق">
          {allocatedWallets.map(w => (
            <option key={w.id} value={w.id}>{w.name}</option>
          ))}
        </optgroup>
      )}
    </select>
  );
};
