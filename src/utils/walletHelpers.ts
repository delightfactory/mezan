import { Wallet } from '../types/models';

export function getDefaultWalletId(wallets: Wallet[], filter: 'ALL' | 'REAL' | 'ALLOCATED' = 'ALL'): string {
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

  if (realWallets.length > 0) {
    return realWallets[0].id;
  }

  const allocatedWallets = filteredWallets
    .filter(w => w.type === 'ALLOCATED')
    .sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime());

  if (allocatedWallets.length > 0) {
    return allocatedWallets[0].id;
  }

  return '';
}
